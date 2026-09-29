import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

func wrapAngle(_ a: CGFloat) -> CGFloat { atan2(sin(a), cos(a)) }

// 1フレームを何回に分けてばねを動かすか。ふつうは Tuning.Settle.substeps 回。表示が詰まってフレームが長くなっても、
// 1回ぶんが Tuning.Settle.maxSubstep 秒を超えないように増やす（刻みが粗すぎると、ばねが発散する）
func substepCount(for dt: CGFloat) -> Int {
    // ちょうど割り切れる長さ（1/30 秒など）が、割り算の誤差で1回多くならないよう、わずかに引いてから切り上げる
    max(Tuning.Settle.substeps, Int((dt / Tuning.Settle.maxSubstep - 1e-6).rounded(.up)))
}

struct DampedSpring {
    let stiffness: CGFloat
    let damping: CGFloat

    init(omega: CGFloat, dampingRatio: CGFloat) {
        stiffness = omega * omega
        damping = 2 * dampingRatio * omega
    }

    func velocityChange(error: CGFloat, velocity: CGFloat, h: CGFloat) -> CGFloat {
        (stiffness * error - damping * velocity) * h
    }
}

struct SpringValue {
    private let spring: DampedSpring
    private(set) var value: CGFloat = 0
    private var velocity: CGFloat = 0

    init(omega: CGFloat, dampingRatio: CGFloat) {
        spring = DampedSpring(omega: omega, dampingRatio: dampingRatio)
    }

    mutating func step(toward target: CGFloat, dt: CGFloat) {
        let n = substepCount(for: dt)
        let h = dt / CGFloat(n)
        for _ in 0..<n {
            velocity += spring.velocityChange(error: target - value, velocity: velocity, h: h)
            value += velocity * h
        }
    }

    var restError: CGFloat { max(abs(value), abs(velocity) * Tuning.Settle.velocityWeight) }
}
