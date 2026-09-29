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
    // 胴体を道に沿わせる度合い。回している間は 0 へ寄せ、回し終えたら 1 へ戻す
    private var pathFollow: CGFloat = 1
    // 前のフレームで描いた胴体の向き（先端から胴体の中ほどへ）。回し始めの向きと、クリックでつぶす向きにする
    private var bodyBack = CGVector(dx: 0, dy: -1)
    private var squish: ClickSquish
    // 折り返しで胴体を回した向きの合計（ラジアン。+ で左回り）。左右に振り続けたときに、同じ向きへ回り続けず
    // 巻き戻すよう、回す側を選ぶのに使う。しばらく折り返さなければ忘れる
    private var pivotTurns: CGFloat = 0
    private var sincePivot: CGFloat = 0
    // 回す側を決めかねたとき（止まったときの向きに沿って振ったとき）に回す側。毎回同じ側へ振れるように覚えておく
    private var tieSide: CGFloat = 1

    private struct Pivot {
        var angle: CGFloat
        var velocity: CGFloat = 0
        // 回る側（+1 で左回り）。先端が折り返しから離れて回す先が決まったときに決める
        var side: CGFloat?
        // 回る側を決めたときの回す先の向き。回している間にまた折り返して回す先が大きく変わったら、回る側を決め直す
        var sideTarget: CGFloat = 0
        // 前のフレームの回す先の向き。折り返しが抜けたあと、回す先が回り続けても（円を描き続けても）遅れずに追うため
        var lastTarget: CGFloat?
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
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        lastMouse = mouse
        trail.record(mouse, dt: dt)
        // 少し動かしただけのときは、もともと道に沿わせていない
        let fold = heading.commitment > 0 ? trail.fold() : nil
        updatePivot(mouse: mouse, fold: fold, moved: moved, dt: dt)

        // 回している間は伸びを戻し、短くしてから回す。回し終えたら、道に沿わせるのに合わせて少しずつ伸ばす（一度に伸ばすと跳ねて見える）
        let stretch = pivot == nil ? min(trail.length, Tuning.Trail.maxStretch) * pathFollow : 0
        var target = shape.length + stretch * stretchScale * heading.commitment
        // 道が折り返したら、胴体は折り返しより後ろへのばさない。伸びたぶんは道に沿って縮める（折り返しで重ならないように）。
        // 今の長さが折り返しに届いていなくても、伸びる途中で越えないよう、いつも抑える
        if let fold {
            target = min(target, max(shape.length, fold.distance))
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
    // ほぼまっすぐ戻ったときは、速いと1フレームで矢じりより後ろまで戻ることがあるので、そのフレームで動いたぶんまでは
    // 矢じりの中とみなす（画面の書き換えの速さで、回すかどうかが変わらないように）。
    // 回し始めたら、折り返しが胴体より後ろへ抜けるまで続ける
    private func updatePivot(mouse: CGPoint, fold: Trail.Fold?, moved: CGFloat, dt: CGFloat) {
        let span = min(length, trail.length)
        var folded = false
        if let fold {
            let head = shape.length + (fold.cosine < cos(Tuning.Fold.reversalAngle) ? moved : 0)
            folded = fold.distance < (pivot == nil ? min(span, head) : span)
        }
        if folded, pivot == nil {
            pivot = Pivot(angle: atan2(bodyBack.dy, bodyBack.dx))
        }
        if var p = pivot {
            // 回す先は、先端から折り返し（無くなったら胴体の長さ）までの道の向き。新しく進む向きの後ろ。
            // 先端が折り返しから少し離れるまでは回さない（行き過ぎて少し戻したときに、くるっと向きを変えないように）
            let end = trail.point(at: min(max(fold?.distance ?? span, Tuning.Fold.reference), trail.length))
            let maxSpeed = Tuning.Fold.maxTailSpeed / length
            var error: CGFloat = 0
            // 回す先が回る速さ。ばねはこの速さに合わせて回しながら追う（合わせないと、円を描き続ける間はいつまでも
            // 回す先に追いつけず、回し終わらない。回している間は伸びないので、短いままになる）
            var targetRate: CGFloat = 0
            if hypot(end.x - mouse.x, end.y - mouse.y) > Tuning.Fold.minTurnTravel {
                let target = atan2(end.y - mouse.y, end.x - mouse.x)
                // 折り返しを見ている間は、回す先が折り返しの位置で決まり、道の向きとは関係なく動くので合わせない
                if !folded, let last = p.lastTarget, dt > 0 {
                    targetRate = min(max(wrapAngle(target - last) / dt, -maxSpeed), maxSpeed)
                }
                p.lastTarget = folded ? nil : target
                if p.side != nil, abs(wrapAngle(target - p.sideTarget)) > .pi / 2 { p.side = nil }
                if p.side == nil {
                    p.side = turnSide(from: p.angle, to: target)
                    p.sideTarget = target
                }
                let side = p.side ?? 1
                error = wrapAngle(target - p.angle)
                if abs(error) > Tuning.Fold.oppositeTurn, error * side < 0 {
                    error += error > 0 ? -2 * .pi : 2 * .pi
                }
            } else {
                p.lastTarget = nil
            }
            let spring = DampedSpring(omega: Tuning.Fold.omega, dampingRatio: 1)
            let h = dt / CGFloat(Tuning.Settle.substeps)
            let before = p.angle
            for _ in 0..<Tuning.Settle.substeps {
                p.velocity += spring.velocityChange(error: error, velocity: p.velocity - targetRate, h: h)
                p.velocity = min(max(p.velocity, -maxSpeed), maxSpeed)
                p.angle += p.velocity * h
                error -= p.velocity * h
            }
            pivotTurns += p.angle - before
            p.angle = wrapAngle(p.angle)
            // 回す先が回り続けていると、1フレームのうちに回す先が進むぶん、フレームの終わりには半分ほど遅れて見える。
            // その遅れを除いて、追いついたかを見る（画面の書き換えが遅いほど遅れが大きく、回し終われなくなるので）
            if !folded && abs(error + targetRate * dt / 2) < Tuning.Fold.finishAngle {
                // 回し終えた向きから、ふだんの向きの動き（進行方向へ向ける・止めたら左上へ戻す）を続ける
                heading.align(angle: p.angle + .pi, velocity: p.velocity)
                pivot = nil
            } else {
                pivot = p
            }
        }
        sincePivot = pivot == nil ? sincePivot + dt : 0
        if sincePivot > Tuning.Fold.turnMemory { pivotTurns = 0 }
        if dt > 0 {
            let target: CGFloat = pivot == nil ? 1 : 0
            let tau = target < pathFollow ? Tuning.Fold.followDrop : Tuning.Fold.followRecover
            pathFollow += (target - pathFollow) * (1 - exp(-dt / tau))
            if pathFollow > 0.999 { pathFollow = 1 }
        }
    }

    // 回る側（+1 で左回り、-1 で右回り）。ふつうは近い側へ回る。ほぼ逆向きへ回すときは:
    // - それまでの折り返しで回していたら、巻き戻す側へ回す。左右に振り続けても、同じ側へ回り続けず（プロペラのように回らず）、
    //   振り子のように行き来する
    // - 回していなければ、止まったときの胴体の向き（右下）を通る側へ回す。ぶら下がるように振れる。
    //   その向きに沿って振ったとき（どちら側でも同じくらいのとき）は、前と同じ側へ回す
    // 道の見かけの曲がり（画面の書き換えの速さで変わる）には頼らない
    private func turnSide(from angle: CGFloat, to target: CGFloat) -> CGFloat {
        let error = wrapAngle(target - angle)
        guard abs(error) > Tuning.Fold.oppositeTurn else { return error >= 0 ? 1 : -1 }
        if abs(pivotTurns) > Tuning.Fold.unwindTurn { return pivotTurns > 0 ? -1 : 1 }
        let rest = shape.baseAngle + .pi
        if abs(wrapAngle(rest - angle)) < Tuning.Fold.restTie || abs(wrapAngle(rest - target)) < Tuning.Fold.restTie {
            return tieSide
        }
        func counterclockwise(_ a: CGFloat) -> CGFloat {
            let r = a.truncatingRemainder(dividingBy: 2 * .pi)
            return r < 0 ? r + 2 * .pi : r
        }
        tieSide = counterclockwise(rest - angle) < counterclockwise(target - angle) ? 1 : -1
        return tieSide
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
