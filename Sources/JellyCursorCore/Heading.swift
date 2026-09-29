import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct Heading {
    // 元の向きへの戻り方。弾むばねで戻り、1回行き過ぎて折り返したら、弾まないばねに切り替える
    private enum ReturnPhase {
        case none
        // sign は戻り始めたときのずれの向き
        case swinging(sign: CGFloat)
        case settling
    }

    private let restAngle: CGFloat
    private(set) var angle: CGFloat
    private var targetAngle: CGFloat
    private var angularVel: CGFloat = 0
    private var smoothedVel = CGVector.zero
    private var idleTime: CGFloat = 0
    // 手ぶれしかしていない（止まっているときも含む）状態が続いている秒数
    private var quietTime: CGFloat = 0
    // 手ぶれだけか、今の向きとは違う向きへゆっくり動いている状態が続いている秒数
    private var slowTime: CGFloat = 0
    // 前のフレームで、手ぶれより大きく動いていたか
    private var wasMoving = false
    // マウス位置をならした点。手ぶれならこの点のまわりにとどまり、動かしていればこの点から離れていく
    private var calm: CGPoint?
    private var travel: CGFloat = 0
    private var returnPhase = ReturnPhase.none
    // 止まったときの向きから回った向きの合計（ラジアン。+ で左回り）。動いている間の分だけ数え、止まって戻り始めたら数え直す
    private var turned: CGFloat = 0
    // 向ける先が急にほぼ逆へ変わったときに回る側（+1 で左回り）。回った分を巻き戻す側。近い側でよいときは nil
    private var forcedSide: CGFloat?
    private let turnSpring: DampedSpring
    private let swingSpring: DampedSpring
    private let settleSpring = DampedSpring(omega: Tuning.Turn.returnOmega,
                                            dampingRatio: Tuning.Turn.returnSettleDampingRatio)

    init(restAngle: CGFloat, motion: MotionParameters = .standard) {
        self.restAngle = restAngle
        angle = restAngle
        targetAngle = restAngle
        turnSpring = DampedSpring(omega: Tuning.Turn.omega, dampingRatio: motion.turnDampingRatio)
        swingSpring = DampedSpring(omega: Tuning.Turn.returnOmega, dampingRatio: motion.returnSwingDampingRatio)
    }

    var axis: CGVector { CGVector(dx: cos(angle), dy: sin(angle)) }

    // 動き始めてからの距離で 0→1 になる。少し動かしただけのときは胴体を曲げたり伸ばしたりしない
    var commitment: CGFloat {
        let start = Tuning.Turn.minTravel * 0.6
        let t = min(max((travel - start) / (Tuning.Turn.minTravel - start), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // 左上に戻りきるまでは落ち着いていない扱いにする。更新を止めても戻り損ねないように
    var restError: CGFloat {
        max(abs(wrapAngle(restAngle - angle)), abs(angularVel) * Tuning.Settle.velocityWeight)
            * Tuning.Turn.armLength
    }

    // 胴体を先端のまわりで回し終えたあと、その向きと回る速さから続ける（向きが飛ばないように）
    mutating func align(angle: CGFloat, velocity: CGFloat) {
        turned += wrapAngle(angle - self.angle)
        forcedSide = nil
        self.angle = wrapAngle(angle)
        targetAngle = self.angle
        angularVel = velocity
        returnPhase = .none
    }

    mutating func turn(from last: CGPoint, to mouse: CGPoint, dt: CGFloat) {
        let k = 1 - exp(-Tuning.Turn.velocitySmoothing * dt)
        smoothedVel.dx += ((mouse.x - last.x) / dt - smoothedVel.dx) * k
        smoothedVel.dy += ((mouse.y - last.y) / dt - smoothedVel.dy) * k
        let center = calm ?? last
        let kc = 1 - exp(-dt / Tuning.Turn.tremorSmoothing)
        let settled = CGPoint(x: center.x + (mouse.x - center.x) * kc, y: center.y + (mouse.y - center.y) * kc)
        calm = settled
        // 手ぶれ（ならした点のまわりで小さく行き来するだけ）は、動いた距離に数えず、向きも変えない
        let lag = hypot(mouse.x - settled.x, mouse.y - settled.y)
        let moving = lag > Tuning.Turn.tremorRadius
        let speed = hypot(smoothedVel.dx, smoothedVel.dy)
        let fast = moving && speed > Tuning.Turn.minSpeed
        if mouse == last {
            idleTime += dt
        } else {
            idleTime = 0
            // 動き出したと分かったフレームでは、それまで手ぶれとして数えずにいたぶん（ならした点からの遅れ）も数える。
            // 画面の書き換えが速いほど細かく刻まれて、数えずにいるぶんが変わらないように
            if moving { travel += wasMoving ? hypot(mouse.x - last.x, mouse.y - last.y) : lag }
        }
        wasMoving = moving
        // 止まっているか手ぶれだけの状態が続いたら、動いた距離を数え直す（次に少し動かしただけで向きを変えないように）
        quietTime = moving ? 0 : quietTime + dt
        if quietTime >= Tuning.Turn.travelResetDelay { travel = 0 }
        // 手ぶれだけの状態や、今の向きから大きく外れた向きへゆっくり動かす状態が続いたら、止めたときと同じく元の向きへ戻す。
        // 速く動かしたあとにゆっくり戻すと、前の向きのまま後ろ向きに進むように見えないように。
        // 今の向きのままゆっくり動かしているとき（速さが向きを変える速さの前後で揺れるドラッグなど）は、向きを保つ。
        // 指したところで少し行き過ぎて戻すくらいの間は、向きを変えない
        let astray = speed > 0 && (smoothedVel.dx * cos(angle) + smoothedVel.dy * sin(angle)) / speed < Tuning.Turn.astrayCosine
        slowTime = !moving || (!fast && astray) ? slowTime + dt : 0

        let returning = idleTime >= Tuning.Turn.returnDelay || slowTime >= Tuning.Turn.slowReturnDelay
        if returning {
            targetAngle = restAngle
            // 元の向きへは近い側から戻るので、それまでに回った分は忘れる
            turned = wrapAngle(angle - restAngle)
            forcedSide = nil
        } else {
            returnPhase = .none
            if travel >= Tuning.Turn.minTravel && fast {
                let target = atan2(smoothedVel.dy, smoothedVel.dx)
                // 左右に振ったときなど、向ける先が急にほぼ逆へ変わったら、それまでに回った分を巻き戻す側へ回す。
                // 近い側へ回すと、ばねの行き過ぎのぶん毎回同じ側が近くなり、同じ向きへ回り続ける
                if abs(wrapAngle(target - targetAngle)) > .pi / 2 {
                    let error = wrapAngle(target - angle)
                    forcedSide = abs(error) > Tuning.Turn.oppositeTurn && abs(turned) > Tuning.Turn.unwindTurn
                        ? (turned > 0 ? -1 : 1) : nil
                }
                targetAngle = target
            }
        }
        let n = substepCount(for: dt)
        let h = dt / CGFloat(n)
        for _ in 0..<n {
            var error = wrapAngle(targetAngle - angle)
            if let side = forcedSide {
                if error * side < 0 { error += side * 2 * .pi }
                if abs(error) < .pi / 2 { forcedSide = nil }
            }
            let spring = returning ? returnSpring(error: error) : turnSpring
            angularVel += spring.velocityChange(error: error, velocity: angularVel, h: h)
            angle += angularVel * h
            turned += angularVel * h
        }
        angle = wrapAngle(angle)
    }

    private mutating func returnSpring(error: CGFloat) -> DampedSpring {
        switch returnPhase {
        case .none:
            returnPhase = .swinging(sign: error >= 0 ? 1 : -1)
            return swingSpring
        case .swinging(let sign):
            // 反対側へ渡ったあと、また元の向きへ動き始めたら折り返した
            guard error * sign < 0 && angularVel * error > 0 else { return swingSpring }
            returnPhase = .settling
            return settleSpring
        case .settling:
            return settleSpring
        }
    }
}
