import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

@Suite struct MotionStyleTests {
    @Test func clampsIntoRange() {
        var style = MotionStyle(stretch: 5, wobble: -1)
        #expect(style.stretch == 2)
        #expect(style.wobble == 0)
        style.stretch = -3
        style.wobble = .nan
        #expect(style.stretch == 0)
        #expect(style.wobble == 1)
    }

    @Test func decodesBrokenValuesSafely() throws {
        let json = #"{"stretch": 9, "wobble": "x"}"#
        let style = try JSONDecoder().decode(MotionStyle.self, from: Data(json.utf8))
        #expect(style == MotionStyle(stretch: 2, wobble: 1))
    }

    @Test func presetsRoundTrip() {
        for preset in MotionPreset.allCases {
            #expect(MotionPreset(matching: preset.style) == preset)
        }
        #expect(MotionPreset(matching: MotionStyle(stretch: 1.2, wobble: 1)) == nil)
        // スライダーの刻みで生じる小さなずれは同じとみなす
        #expect(MotionPreset(matching: MotionStyle(stretch: 1.001, wobble: 0.999)) == .standard)
    }

    @Test func wobbleMapsToDamping() {
        let standard: CGFloat = 0.4
        #expect(MotionParameters.dampingRatio(standard, wobble: 0) == 1)
        #expect(MotionParameters.dampingRatio(standard, wobble: 1) == standard)
        #expect(MotionParameters.dampingRatio(standard, wobble: 2) == standard / 2)
        // 弾みを強くするほど減衰は小さくなる
        var last = CGFloat.infinity
        for w in stride(from: 0.0, through: 2.0, by: 0.1) {
            let d = MotionParameters.dampingRatio(standard, wobble: CGFloat(w))
            #expect(d < last)
            #expect(d > 0)
            last = d
        }
    }
}

@Suite struct MotionEffectTests {
    private let a = CGPoint(x: 100, y: 100)
    private let b = CGPoint(x: 700, y: 100)

    @Test func stretchScalesArrowLength() {
        func reachWhileMoving(_ stretch: Double) -> CGFloat {
            let jelly = Jelly(scale: 1, motion: MotionParameters(MotionStyle(stretch: stretch, wobble: 1)))
            drive(jelly, from: a, to: b, seconds: 0.4)
            return reach(jelly, from: b)
        }
        let rest = ArrowShape(scale: 1).length
        let none = reachWhileMoving(0), standard = reachWhileMoving(1), double = reachWhileMoving(2)
        // 伸び 0 では止まっているときの長さのまま（向きだけ変わる）
        #expect(abs(none - rest) < 1.5)
        #expect(standard > none + 20)
        #expect(double > standard + 20)
    }

    @Test func stretchZeroKeepsIBeamShape() {
        let still = IBeam(scale: 1)
        still.step(to: a, dt: 0)
        let moving = IBeam(scale: 1, motion: MotionParameters(MotionStyle(stretch: 0, wobble: 1)))
        drive(moving, from: a, to: CGPoint(x: 700, y: 500), seconds: 0.3)
        let offsets = { (f: IBeam, m: CGPoint) in f.points.map { CGPoint(x: $0.x - m.x, y: $0.y - m.y) } }
        for (p, q) in zip(offsets(still, a), offsets(moving, CGPoint(x: 700, y: 500))) {
            #expect(abs(p.x - q.x) < 1e-9 && abs(p.y - q.y) < 1e-9)
        }
    }

    // 止めたあと元の向きへ戻るとき、弾み 0 では行き過ぎず、弾みを強くするほど大きく行き過ぎる
    @Test func wobbleControlsReturnOvershoot() {
        func overshoot(_ wobble: Double) -> CGFloat {
            let jelly = Jelly(scale: 1, motion: MotionParameters(MotionStyle(stretch: 1, wobble: wobble)))
            // 右へ動かして右を向かせてから止める。元の向き（左上）へ戻る途中で反対側へ渡った最大の角度
            drive(jelly, from: a, to: b, seconds: 0.4)
            let restAngle = ArrowShape(scale: 1).baseAngle
            let restBody = atan2(-sin(restAngle), -cos(restAngle))
            let startSide = wrapAngle(bodyAngle(jelly, from: b) - restBody)
            var worst: CGFloat = 0
            for _ in 0..<240 {
                jelly.step(to: b, dt: 1.0 / 120)
                let side = wrapAngle(bodyAngle(jelly, from: b) - restBody)
                if side * startSide < 0 { worst = max(worst, abs(side)) }
            }
            return worst
        }
        let none = overshoot(0), standard = overshoot(1), strong = overshoot(2)
        #expect(none < 0.01)
        #expect(standard > 0.05)
        #expect(strong > standard * 1.3)
    }

    // 弾みを変えても、止めれば必ず落ち着く（眠れる）
    @Test(arguments: [0.0, 0.5, 1.0, 1.5, 2.0])
    func settlesForAnyWobble(wobble: Double) {
        let motion = MotionParameters(MotionStyle(stretch: 2, wobble: wobble))
        let figures: [Figure] = [Jelly(scale: 1, motion: motion), IBeam(scale: 1, motion: motion)]
        for f in figures {
            drive(f, from: a, to: CGPoint(x: 600, y: 450), seconds: 0.3, holdFrames: 600)
            #expect(f.isSettled)
        }
        var hand = HandMotion(scale: 1, motion: motion)
        hand.step(to: a, dt: 0, imageHeight: 32)
        for i in 1...36 {
            hand.step(to: CGPoint(x: 100 + CGFloat(i) * 14, y: 100 + CGFloat(i) * 9), dt: 1.0 / 120, imageHeight: 32)
        }
        for _ in 0..<600 { hand.step(to: CGPoint(x: 604, y: 424), dt: 1.0 / 120, imageHeight: 32) }
        #expect(hand.isSettled)
    }
}
