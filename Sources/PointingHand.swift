import AppKit

// リンクの上の指。本物の指カーソルの画像を、指先（クリック位置）を軸に回して伸ばす。
// 指の形は複雑で配色も矢印と逆なので、輪郭を描き直さず画像をそのまま使う
final class PointingHand: ImageFigure {
    private(set) var image: CGImage?
    private(set) var size = CGSize.zero
    private(set) var anchor = CGPoint(x: 0.5, y: 0.5)
    private(set) var position = CGPoint.zero
    private(set) var isSettled = true

    private let scale: CGFloat
    // 指は上を向いている
    private var heading = Heading(restAngle: .pi / 2)
    private var trail = Trail()
    // 道の向きを測る区間。矢印の胴体と同じ長さにして、矢印と指で向きをそろえる
    private let pathSpan: CGFloat
    private var angle: CGFloat = .pi / 2
    private var lastTurn: CGFloat = 0
    private var stretch = SpringValue(omega: Tuning.Hand.omega, dampingRatio: Tuning.Hand.dampingRatio)
    private var smoothedVel = CGVector.zero
    private var lastMouse: CGPoint?

    init(scale: CGFloat = ArrowShape.systemPointerScale()) {
        self.scale = scale
        pathSpan = ArrowShape(scale: scale).length
        use(.pointingHand)
    }

    // ポインタの色の設定などで見た目が変わるので、実際に出ている指カーソルの画像に差し替える
    func use(_ cursor: NSCursor) {
        let imageSize = cursor.image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        var rect = CGRect(x: 0, y: 0, width: imageSize.width * 4, height: imageSize.height * 4)
        image = cursor.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        // ホットスポットは左上から、アンカーは左下から数える
        anchor = CGPoint(x: cursor.hotSpot.x / imageSize.width, y: 1 - cursor.hotSpot.y / imageSize.height)
    }

    func step(to mouse: CGPoint, dt: CGFloat) {
        if let lastMouse, dt > 0 {
            heading.turn(from: lastMouse, to: mouse, dt: dt)
            let k = 1 - exp(-Tuning.Hand.velocitySmoothing * dt)
            smoothedVel.dx += ((mouse.x - lastMouse.x) / dt - smoothedVel.dx) * k
            smoothedVel.dy += ((mouse.y - lastMouse.y) / dt - smoothedVel.dy) * k
            let speed = hypot(smoothedVel.dx, smoothedVel.dy)
            stretch.step(toward: Tuning.Hand.maxStretch * tanh(speed / Tuning.Hand.stretchSpeed) * heading.commitment,
                         dt: dt)
        }
        lastMouse = mouse
        trail.record(mouse, dt: dt)
        position = mouse
        // 速く動かし始めたときなどに、指が1フレームで大きく回って飛んだように見えないよう、回る速さに上限を設ける
        let maxTurn = Tuning.Hand.maxTurnRate * dt
        angle = wrapAngle(angle + min(max(wrapAngle(pathAngle(at: mouse) - angle), -maxTurn), maxTurn))
        isSettled = max(heading.restError, stretch.restError * size.height, trail.length) < Tuning.Settle.threshold
    }

    // 矢印の胴体と同じく、動いている間は実際に通った道の向きを指す。
    // 道が短いときや少し動かしただけのときは、ばねで回る向きに寄せる。
    // 折り返した道（道のりに比べて先端と後ろの点が近い）では、道の向きが一瞬で裏返るので、ばねの向きに寄せる
    private func pathAngle(at mouse: CGPoint) -> CGFloat {
        let span = min(trail.length, pathSpan)
        let behind = trail.point(at: span)
        let d = hypot(mouse.x - behind.x, mouse.y - behind.y)
        guard span > 0, d > 0.0001 else { return heading.angle }
        var turn = wrapAngle(atan2(mouse.y - behind.y, mouse.x - behind.x) - heading.angle)
        // ばねの向きとほぼ逆の道（止まった指から真下へ動き出したときなど）は、右回りと左回りのどちらでもほぼ同じ角度なので、
        // 手ぶれで回る側が入れ替わって指が行ったり来たりしないよう、前のフレームと同じ側へ回す
        if abs(turn) > Tuning.Hand.oppositeTurn, turn * lastTurn < 0 {
            turn += turn > 0 ? -2 * .pi : 2 * .pi
        }
        lastTurn = turn
        let blend = min(trail.length / pathSpan, 1) * heading.commitment * (d / span)
        return heading.angle + turn * blend
    }

    // 画像の上方向（指の向き）に伸ばしてから、動かした方向へ回す
    var transform: CATransform3D {
        let s = 1 + stretch.value
        let stretched = CATransform3DMakeScale(1 / sqrt(s), s, 1)
        return CATransform3DConcat(stretched, CATransform3DMakeRotation(angle - .pi / 2, 0, 0, 1))
    }
}
