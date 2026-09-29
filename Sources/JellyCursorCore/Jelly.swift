import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

package final class Jelly: CursorFigure {
    private let shape: ArrowShape
    package private(set) var points: [CGPoint]
    private var trail = Trail()
    private var heading: Heading
    private var length: CGFloat
    private var lastMouse = CGPoint.zero
    private var started = false
    package private(set) var isSettled = false
    private let stretchScale: CGFloat
    // 道が折り返したときに、胴体をまっすぐにして先端のまわりで回している間の向き（先端から胴体への向き）
    private var pivot: Pivot?
    // ほぼ逆向きへ回すときに回る側。前に回した側を覚えておく
    private var pivotSide: CGFloat = 1
    // 胴体を道に沿わせる度合い。回している間は 0 へ寄せ、回し終えたら 1 へ戻す
    private var pathFollow: CGFloat = 1
    // 前のフレームで描いた胴体の向き（先端から胴体の中ほどへ）。回し始めの向きと、クリックでつぶす向きにする
    private var bodyBack = CGVector(dx: 0, dy: -1)
    private var squish: ClickSquish

    private struct Pivot {
        var angle: CGFloat
        var velocity: CGFloat = 0
    }

    package init(scale: CGFloat, motion: MotionParameters = .standard) {
        shape = ArrowShape(scale: scale)
        heading = Heading(restAngle: shape.baseAngle, motion: motion)
        stretchScale = motion.stretch
        squish = ClickSquish(motion: motion)
        length = shape.length
        points = Array(repeating: .zero, count: shape.vertices.count)
    }

    package func step(to mouse: CGPoint, dt: CGFloat, pressed: Bool) {
        if !started {
            started = true
        } else if dt > 0 {
            heading.turn(from: lastMouse, to: mouse, dt: dt)
        }
        lastMouse = mouse
        trail.record(mouse, dt: dt)
        // 少し動かしただけのときは、もともと道に沿わせていない
        let fold = heading.commitment > 0 ? trail.foldDistance() : nil
        updatePivot(mouse: mouse, fold: fold, dt: dt)

        // 回している間は伸びを戻し、短くしてから回す
        let stretch = pivot == nil ? min(trail.length, Tuning.Trail.maxStretch) : 0
        var target = shape.length + stretch * stretchScale * heading.commitment
        // 道が折り返したら、胴体は折り返しより後ろへのばさない。伸びたぶんは道に沿って縮める（折り返しで重ならないように）
        if let fold, fold < min(length, trail.length) {
            target = min(target, max(shape.length, fold))
        }
        if dt > 0 {
            length += (target - length) * (1 - exp(-dt / Tuning.Trail.lengthSmoothing))
        }
        layOut(at: mouse)
        // クリックしたら、先端（クリック位置）を動かさずに、胴体の向きへつぶす
        squish.step(pressed: pressed, mouse: mouse, dt: dt)
        squish.apply(to: &points, anchor: mouse, axis: bodyBack)

        let worst = max(trail.length, abs(length - shape.length), heading.restError, squish.restError(size: shape.length))
        isSettled = worst < Tuning.Settle.threshold && pivot == nil && pathFollow == 1
    }

    // 矢じり（先端から普段の長さのうち）で道が折り返したら、道に沿わせず、まっすぐにして先端のまわりで回す。
    // 道に沿わせたままだと、幅の広い矢じりが折り返しで自分と重なり、形が崩れて見える。
    // 回し始めたら、折り返しが胴体より後ろへ抜けるまで回し続ける
    private func updatePivot(mouse: CGPoint, fold: CGFloat?, dt: CGFloat) {
        let span = min(length, trail.length)
        let folded = fold.map { $0 < (pivot == nil ? min(span, shape.length) : span) } ?? false
        if folded, pivot == nil {
            pivot = Pivot(angle: atan2(bodyBack.dy, bodyBack.dx))
            // 回す先（先端から折り返しまでの向き）が今の向きのどちら側にあるかで、回る側を決める。
            // まっすぐ折り返したときは、前と同じ側
            let near = trail.point(at: Tuning.Fold.reference)
            let cross = bodyBack.dx * (near.y - mouse.y) - bodyBack.dy * (near.x - mouse.x)
            if abs(cross) > 0.5 { pivotSide = cross > 0 ? 1 : -1 }
        }
        if var p = pivot {
            // 回す先は、先端から折り返し（無くなったら胴体の長さ）までの道の向き。新しく進む向きの後ろ
            let end = trail.point(at: min(max(fold ?? span, Tuning.Fold.reference), trail.length))
            var error: CGFloat = 0
            if hypot(end.x - mouse.x, end.y - mouse.y) > 1 {
                error = wrapAngle(atan2(end.y - mouse.y, end.x - mouse.x) - p.angle)
                if abs(error) > Tuning.Fold.oppositeTurn, error * pivotSide < 0 {
                    error += error > 0 ? -2 * .pi : 2 * .pi
                }
            }
            let spring = DampedSpring(omega: Tuning.Fold.omega, dampingRatio: 1)
            let maxSpeed = Tuning.Fold.maxTailSpeed / length
            let h = dt / CGFloat(Tuning.Settle.substeps)
            for _ in 0..<Tuning.Settle.substeps {
                p.velocity += spring.velocityChange(error: error, velocity: p.velocity, h: h)
                p.velocity = min(max(p.velocity, -maxSpeed), maxSpeed)
                p.angle += p.velocity * h
                error -= p.velocity * h
            }
            p.angle = wrapAngle(p.angle)
            if !folded && abs(error) < Tuning.Fold.finishAngle {
                // 回し終えた向きから、ふだんの向きの動き（進行方向へ向ける・止めたら左上へ戻す）を続ける
                heading.align(angle: p.angle + .pi, velocity: p.velocity)
                pivot = nil
            } else {
                pivot = p
            }
        }
        if dt > 0 {
            let target: CGFloat = pivot == nil ? 1 : 0
            let tau = target < pathFollow ? Tuning.Fold.followDrop : Tuning.Fold.followRecover
            pathFollow += (target - pathFollow) * (1 - exp(-dt / tau))
            if pathFollow > 0.999 { pathFollow = 1 }
        }
    }

    // 矢印の軸を道筋に沿って曲げ、各頂点をその地点の向きに対して横へずらす
    private func layOut(at mouse: CGPoint) {
        let restBack = pivot.map { CGVector(dx: cos($0.angle), dy: sin($0.angle)) } ?? heading.axis.negated
        let spine = Spine(mouse: mouse, trail: trail, restBack: restBack,
                          blend: min(trail.length / shape.length, 1) * heading.commitment * pathFollow)
        bodyBack = (spine.point(at: shape.length / 2) - mouse).normalized ?? restBack
        let stretch = length / shape.length
        let width = pow(1 / stretch, Tuning.Trail.thinning)
        let w = Tuning.Trail.tangentWindow
        for (i, v) in shape.vertices.enumerated() {
            let s = v.axial * stretch
            let c = spine.point(at: s)
            let back = (spine.point(at: s + w) - spine.point(at: max(s - w, 0))).normalized ?? spine.restBack
            // 前向き (-back) の左の法線は (back.dy, -back.dx)
            points[i] = CGPoint(x: c.x + back.dy * v.lateral * width,
                                y: c.y - back.dx * v.lateral * width)
        }
    }

    package var borderWidth: CGFloat { shape.borderWidth }
}

// 矢印の芯。先端から s px 後ろの位置を返す。
// 道が短いうちは手ぶれで向きがばたつくので、止まったときの向きのまっすぐな線に寄せる
private struct Spine {
    let mouse: CGPoint
    let trail: Trail
    let restBack: CGVector
    let blend: CGFloat
    private let pathBack: CGVector

    init(mouse: CGPoint, trail: Trail, restBack: CGVector, blend: CGFloat) {
        self.mouse = mouse
        self.trail = trail
        self.restBack = restBack
        self.blend = blend
        pathBack = trail.tailDirection(window: Tuning.Trail.tangentWindow) ?? restBack
    }

    func point(at s: CGFloat) -> CGPoint {
        let straight = CGPoint(x: mouse.x + restBack.dx * s, y: mouse.y + restBack.dy * s)
        guard blend > 0 else { return straight }
        let onPath: CGPoint
        if s <= trail.length {
            onPath = trail.point(at: s)
        } else {
            let end = trail.point(at: trail.length), extra = s - trail.length
            onPath = CGPoint(x: end.x + pathBack.dx * extra, y: end.y + pathBack.dy * extra)
        }
        return CGPoint(x: straight.x + (onPath.x - straight.x) * blend,
                       y: straight.y + (onPath.y - straight.y) * blend)
    }
}

private extension CGPoint {
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}

private extension CGVector {
    var negated: CGVector { CGVector(dx: -dx, dy: -dy) }

    var normalized: CGVector? {
        let d = hypot(dx, dy)
        return d > 0.0001 ? CGVector(dx: dx / d, dy: dy / d) : nil
    }
}
