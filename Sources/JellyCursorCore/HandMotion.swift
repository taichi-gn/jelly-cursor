import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// リンクの上の指の向きと伸び。画像を回して描く部分は JellyCursorKit の PointingHand にある
package struct HandMotion {
    // 指差す向き（ラジアン）。上向きが π/2
    package private(set) var angle: CGFloat = .pi / 2
    package private(set) var isSettled = true
    package var stretch: CGFloat { stretchSpring.value }
    // クリックでつぶれる割合（正でつぶれ、負で伸びる）。指先へ向けてつぶす
    package var squash: CGFloat { squish.value }
    // 指の向きの長さの倍率（伸びとつぶれを合わせたもの）。戻りの行き過ぎで 0 以下になって裏返らないよう、下限を設ける
    package var lengthScale: CGFloat { max((1 + stretch) * (1 - squash), Tuning.IBeam.minScale) }

    // 指は上を向いている
    private var heading: Heading
    private var trail = Trail()
    // 道の向きを測る区間。矢印の胴体と同じ長さにして、矢印と指で向きをそろえる
    private let pathSpan: CGFloat
    private var lastTurn: CGFloat = 0
    private var stretchSpring: SpringValue
    private let maxStretch: CGFloat
    private var smoothedVel = CGVector.zero
    private var lastMouse: CGPoint?
    private var squish: ClickSquish

    package init(scale: CGFloat, motion: MotionParameters = .standard) {
        heading = Heading(restAngle: .pi / 2, motion: motion)
        pathSpan = ArrowShape(scale: scale).length
        stretchSpring = SpringValue(omega: Tuning.Hand.omega, dampingRatio: motion.handDampingRatio)
        maxStretch = Tuning.Hand.maxStretch * motion.stretch
        squish = ClickSquish(motion: motion)
    }

    // imageHeight は描く画像の高さ。伸びのずれをピクセルに直して、落ち着いたかを決めるのに使う
    package mutating func step(to mouse: CGPoint, dt: CGFloat, imageHeight: CGFloat, pressed: Bool = false) {
        squish.step(pressed: pressed, mouse: mouse, dt: dt)
        if let lastMouse, dt > 0 {
            heading.turn(from: lastMouse, to: mouse, dt: dt)
            let k = 1 - exp(-Tuning.Hand.velocitySmoothing * dt)
            smoothedVel.dx += ((mouse.x - lastMouse.x) / dt - smoothedVel.dx) * k
            smoothedVel.dy += ((mouse.y - lastMouse.y) / dt - smoothedVel.dy) * k
            let speed = hypot(smoothedVel.dx, smoothedVel.dy)
            stretchSpring.step(toward: maxStretch * tanh(speed / Tuning.Hand.stretchSpeed) * heading.commitment, dt: dt)
        }
        lastMouse = mouse
        trail.record(mouse, dt: dt)
        // 道の向きは手ぶれで毎フレーム少しずつ揺れるので、ならしてから向ける。
        // 速く動かし始めたときなどに、指が1フレームで大きく回って飛んだように見えないよう、回る速さに上限を設ける
        let smoothed = wrapAngle(pathAngle(at: mouse) - angle) * (1 - exp(-dt / Tuning.Hand.angleSmoothing))
        let maxTurn = Tuning.Hand.maxTurnRate * dt
        angle = wrapAngle(angle + min(max(smoothed, -maxTurn), maxTurn))
        let lag = abs(wrapAngle(heading.angle - angle)) * Tuning.Turn.armLength
        isSettled = max(heading.restError, stretchSpring.restError * imageHeight, trail.length, lag,
                        squish.restError(size: imageHeight)) < Tuning.Settle.threshold
    }

    // 矢印の胴体と同じく、動いている間は実際に通った道の向きを指す。
    // 道が短いときや少し動かしただけのときは、ばねで回る向きに寄せる。
    // 折り返した道（道のりに比べて先端と後ろの点が近い）では、道の向きが一瞬で裏返るので、ばねの向きに寄せる
    private mutating func pathAngle(at mouse: CGPoint) -> CGFloat {
        let span = min(trail.length, pathSpan)
        let behind = trail.point(at: span)
        let d = hypot(mouse.x - behind.x, mouse.y - behind.y)
        // 止まって道が消えたら、前の動きで回した側は忘れる。次の動き出しを、前の動きの側に引きずらない
        guard span > 0, d > 0.0001 else {
            lastTurn = 0
            return heading.angle
        }
        var turn = wrapAngle(atan2(mouse.y - behind.y, mouse.x - behind.x) - heading.angle)
        // ばねの向きとほぼ逆の道（止まった指から真下へ動き出したときなど）は、右回りと左回りのどちらでもほぼ同じ角度なので、
        // 手ぶれで回る側が入れ替わって指が行ったり来たりしないよう、前のフレームと同じ側へ回す。
        // 前のフレームもほぼ逆だったときだけにする（前のフレームで少し遅れていただけなら、近い側へ回す。
        // そうしないと、左右に振るたびに遠回りして、同じ向きへ回り続ける）
        if abs(turn) > Tuning.Hand.oppositeTurn, abs(lastTurn) > Tuning.Hand.oppositeTurn, turn * lastTurn < 0 {
            turn += turn > 0 ? -2 * .pi : 2 * .pi
        }
        lastTurn = turn
        let blend = min(trail.length / pathSpan, 1) * heading.commitment * (d / span)
        return heading.angle + turn * blend
    }
}
