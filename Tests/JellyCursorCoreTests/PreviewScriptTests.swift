import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

@Suite struct PreviewScriptTests {
    @Test func staysInsideUnitSquareAndLoops() {
        for i in 0...880 {
            let t = Double(i) * 0.01
            let p = PreviewScript.position(at: t)
            #expect((0...1).contains(p.x) && (0...1).contains(p.y))
            let q = PreviewScript.position(at: t + PreviewScript.period)
            #expect(abs(p.x - q.x) < 1e-9 && abs(p.y - q.y) < 1e-9)
        }
    }

    // 飛ばずに動く（1フレームの移動が小さい）
    @Test func isContinuous() {
        var last = PreviewScript.position(at: 0)
        for i in 1...1056 {
            let p = PreviewScript.position(at: Double(i) / 120)
            #expect(hypot(p.x - last.x, p.y - last.y) < 0.03)
            last = p
        }
    }

    // クリックは止まっている間だけ、往きと帰りに1回ずつ。押している間にマウスは動かない
    @Test func clicksWhileStill() {
        var presses = 0, wasPressed = false
        for i in 0..<Int(PreviewScript.period * 120) {
            let t = Double(i) / 120
            let pressed = PreviewScript.isPressed(at: t)
            if pressed && !wasPressed { presses += 1 }
            if pressed { #expect(PreviewScript.position(at: t) == PreviewScript.position(at: t + 1.0 / 120)) }
            wasPressed = pressed
        }
        #expect(presses == 2)
        #expect(PreviewScript.isPressed(at: 1.4) == PreviewScript.isPressed(at: 1.4 + PreviewScript.period))
    }

    // 動いたあとに止まる時間がある（戻る揺れを見せる）
    @Test func holdsStill() {
        let a = PreviewScript.position(at: 1.0), b = PreviewScript.position(at: 2.1)
        #expect(a == b)
        #expect(PreviewScript.position(at: -0.5) == PreviewScript.position(at: PreviewScript.period - 0.5))
    }
}
