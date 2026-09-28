import AppKit
import JellyCursorCore

// リンクの上の指。本物の指カーソルの画像を、指先（クリック位置）を軸に回して伸ばす。
// 指の形は複雑で配色も矢印と逆なので、輪郭を描き直さず画像をそのまま使う。向きと伸びは HandMotion で決める
final class PointingHand: ImageFigure {
    private(set) var image: CGImage?
    private(set) var size = CGSize.zero
    private(set) var anchor = CGPoint(x: 0.5, y: 0.5)
    private(set) var position = CGPoint.zero
    var isSettled: Bool { motion.isSettled }

    private let scale: CGFloat
    private var motion: HandMotion

    init(scale: CGFloat, motion: MotionParameters, cursor: CursorImage) {
        self.scale = scale
        self.motion = HandMotion(scale: scale, motion: motion)
        use(cursor)
    }

    // ポインタの色の設定などで見た目が変わるので、実際に出ている指カーソルの画像に差し替える
    func use(_ cursor: CursorImage) {
        guard cursor.size.width > 0, cursor.size.height > 0 else { return }
        image = cursor.image
        size = CGSize(width: cursor.size.width * scale, height: cursor.size.height * scale)
        // ホットスポットは左上から、アンカーは左下から数える
        anchor = CGPoint(x: cursor.hotSpot.x / cursor.size.width, y: 1 - cursor.hotSpot.y / cursor.size.height)
    }

    func step(to mouse: CGPoint, dt: CGFloat) {
        motion.step(to: mouse, dt: dt, imageHeight: size.height)
        position = mouse
    }

    // 画像の上方向（指の向き）に伸ばしてから、動かした方向へ回す
    var transform: CATransform3D {
        let s = 1 + motion.stretch
        let stretched = CATransform3DMakeScale(1 / sqrt(s), s, 1)
        return CATransform3DConcat(stretched, CATransform3DMakeRotation(motion.angle - .pi / 2, 0, 0, 1))
    }
}
