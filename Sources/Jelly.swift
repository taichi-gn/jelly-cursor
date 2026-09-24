import CoreGraphics
import Foundation

final class Jelly: CursorFigure {
    private let shape = ArrowShape()
    private(set) var points: [CGPoint]
    private var trail = Trail()
    private var heading: Heading
    private var length: CGFloat
    private var lastMouse = CGPoint.zero
    private var started = false
    private(set) var isSettled = false

    init() {
        heading = Heading(restAngle: shape.baseAngle)
        length = shape.length
        points = Array(repeating: .zero, count: shape.vertices.count)
    }

    func step(to mouse: CGPoint, dt: CGFloat) {
        if !started {
            started = true
        } else if dt > 0 {
            heading.turn(from: lastMouse, to: mouse, dt: dt)
        }
        lastMouse = mouse
        trail.record(mouse, dt: dt)

        let target = shape.length + min(trail.length, Tuning.Trail.maxStretch) * heading.commitment
        if dt > 0 {
            length += (target - length) * (1 - exp(-dt / Tuning.Trail.lengthSmoothing))
        }
        layOut(at: mouse)

        let worst = max(trail.length, abs(length - shape.length), heading.restError)
        isSettled = worst < Tuning.Settle.threshold
    }

    // 矢印の軸を道筋に沿って曲げ、各頂点をその地点の向きに対して横へずらす
    private func layOut(at mouse: CGPoint) {
        let spine = Spine(mouse: mouse, trail: trail, restBack: heading.axis.negated,
                          blend: min(trail.length / shape.length, 1) * heading.commitment)
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

    var borderWidth: CGFloat { shape.borderWidth }
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
