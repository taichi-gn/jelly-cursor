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
    private var travel: CGFloat = 0
    private var returnPhase = ReturnPhase.none
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
        self.angle = wrapAngle(angle)
        targetAngle = self.angle
        angularVel = velocity
        returnPhase = .none
    }

    mutating func turn(from last: CGPoint, to mouse: CGPoint, dt: CGFloat) {
        let k = 1 - exp(-Tuning.Turn.velocitySmoothing * dt)
        smoothedVel.dx += ((mouse.x - last.x) / dt - smoothedVel.dx) * k
        smoothedVel.dy += ((mouse.y - last.y) / dt - smoothedVel.dy) * k
        if mouse == last {
            idleTime += dt
            if idleTime >= Tuning.Turn.travelResetDelay { travel = 0 }
        } else {
            idleTime = 0
            travel += hypot(mouse.x - last.x, mouse.y - last.y)
        }

        let returning = idleTime >= Tuning.Turn.returnDelay
        if returning {
            targetAngle = restAngle
        } else {
            returnPhase = .none
            if travel >= Tuning.Turn.minTravel && hypot(smoothedVel.dx, smoothedVel.dy) > Tuning.Turn.minSpeed {
                targetAngle = atan2(smoothedVel.dy, smoothedVel.dx)
            }
        }
        let h = dt / CGFloat(Tuning.Settle.substeps)
        for _ in 0..<Tuning.Settle.substeps {
            let error = wrapAngle(targetAngle - angle)
            let spring = returning ? returnSpring(error: error) : turnSpring
            angularVel += spring.velocityChange(error: error, velocity: angularVel, h: h)
            angle += angularVel * h
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
