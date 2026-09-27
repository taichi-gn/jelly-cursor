import Foundation

func wrapAngle(_ a: CGFloat) -> CGFloat { atan2(sin(a), cos(a)) }

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
        let h = dt / CGFloat(Tuning.Settle.substeps)
        for _ in 0..<Tuning.Settle.substeps {
            velocity += spring.velocityChange(error: target - value, velocity: velocity, h: h)
            value += velocity * h
        }
    }

    var restError: CGFloat { max(abs(value), abs(velocity) * Tuning.Settle.velocityWeight) }
}
