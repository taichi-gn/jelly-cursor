import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

// クリックしたときの形の変化
@Suite struct ClickTests {
    private let mouse = CGPoint(x: 400, y: 300)

    // 止まったまま、押して離す。フレームごとに fn を呼ぶ
    private func click(_ figure: Figure, press: Int = 30, release: Int = 120, rate: CGFloat = 120,
                       each fn: (Int, Bool) -> Void = { _, _ in }) {
        figure.step(to: mouse, dt: 0)
        for i in 0..<(press + release) {
            let pressed = i < press
            figure.step(to: mouse, dt: 1 / rate, pressed: pressed)
            fn(i, pressed)
        }
    }

    // 押すと先端（クリック位置）を動かさずに胴体の向きへつぶれ、離すと少し伸びて、ちょうど元の形に戻る
    @Test func arrowSquashesTowardItsTipAndRebounds() {
        let arrow = Jelly(scale: 1)
        let rest = reach(Jelly(scale: 1).then { $0.step(to: mouse, dt: 0) }, from: mouse)
        var pressedReach = CGFloat.infinity, longest: CGFloat = 0, tipMoved = false
        click(arrow) { _, pressed in
            if arrow.points[0] != mouse { tipMoved = true }
            let r = reach(arrow, from: mouse)
            if pressed { pressedReach = min(pressedReach, r) } else { longest = max(longest, r) }
        }
        #expect(!tipMoved)
        // 押している間は約16%短くなる（ばねで少し行き過ぎてもよい）
        #expect(pressedReach < rest * 0.88 && pressedReach > rest * 0.78)
        // 離すと少し伸びる側へ行き過ぎる
        #expect(longest > rest * 1.02 && longest < rest * 1.15)
        #expect(arrow.isSettled)
        let fresh = Jelly(scale: 1)
        fresh.step(to: mouse, dt: 0)
        #expect(arrow.points == fresh.points)
    }

    // I 字は中心（クリック位置）へ向けて縦につぶれ、横に太る
    @Test func iBeamSquashesAroundItsCenter() {
        let beam = IBeam(scale: 1)
        let fresh = IBeam(scale: 1)
        fresh.step(to: mouse, dt: 0)
        func height(_ b: IBeam) -> CGFloat { (b.points.map(\.y).max() ?? 0) - (b.points.map(\.y).min() ?? 0) }
        func width(_ b: IBeam) -> CGFloat { (b.points.map(\.x).max() ?? 0) - (b.points.map(\.x).min() ?? 0) }
        var squashed = false
        click(beam) { i, _ in
            guard i == 29 else { return }
            squashed = height(beam) < height(fresh) * 0.88 && width(beam) > width(fresh) * 1.03
            // 上下は中心から同じだけ縮む
            let top = (beam.points.map(\.y).max() ?? 0) - mouse.y, bottom = mouse.y - (beam.points.map(\.y).min() ?? 0)
            #expect(abs(top - bottom) < 0.05)
        }
        #expect(squashed)
        #expect(beam.isSettled)
        #expect(beam.points == fresh.points)
    }

    @Test func handSquashesAndReturns() {
        var hand = HandMotion(scale: 1)
        hand.step(to: mouse, dt: 0, imageHeight: 32)
        for _ in 0..<30 { hand.step(to: mouse, dt: 1.0 / 120, imageHeight: 32, pressed: true) }
        #expect(hand.squash > 0.13 && hand.squash < 0.2)
        var lowest: CGFloat = 0
        for _ in 0..<120 {
            hand.step(to: mouse, dt: 1.0 / 120, imageHeight: 32)
            lowest = min(lowest, hand.squash)
        }
        #expect(lowest < -0.02)
        #expect(hand.squash == 0 && hand.isSettled)
    }

    // 押したまま止めていれば、つぶれたまま落ち着く（眠れる）
    @Test func settlesWhileHeld() {
        let arrow = Jelly(scale: 1)
        arrow.step(to: mouse, dt: 0)
        for _ in 0..<120 { arrow.step(to: mouse, dt: 1.0 / 120, pressed: true) }
        #expect(arrow.isSettled)
    }

    // 押したまま動かす（ドラッグ）と、つぶれを戻してふつうの動きにする
    @Test func draggingReleasesTheSquash() {
        let pressedDrag = Jelly(scale: 1), plainDrag = Jelly(scale: 1)
        for figure in [pressedDrag, plainDrag] { figure.step(to: mouse, dt: 0) }
        for _ in 0..<30 { pressedDrag.step(to: mouse, dt: 1.0 / 120, pressed: true) }
        for i in 1...60 {
            let p = CGPoint(x: mouse.x + CGFloat(i) * 2, y: mouse.y)
            pressedDrag.step(to: p, dt: 1.0 / 120, pressed: true)
            plainDrag.step(to: p, dt: 1.0 / 120)
        }
        let end = CGPoint(x: mouse.x + 120, y: mouse.y)
        #expect(abs(reach(pressedDrag, from: end) - reach(plainDrag, from: end)) < 1)
    }

    // 設定で「クリックで弾む」を切ったとき、伸び 0 のときはつぶれない。弾み 0 なら離しても行き過ぎない
    @Test func settingsControlTheSquash() {
        for motion in [MotionParameters(.standard, clickBounce: false), MotionParameters(MotionStyle(stretch: 0, wobble: 1))] {
            let arrow = Jelly(scale: 1, motion: motion)
            let fresh = Jelly(scale: 1, motion: motion)
            fresh.step(to: mouse, dt: 0)
            var changed = false
            click(arrow) { _, _ in if arrow.points != fresh.points { changed = true } }
            #expect(!changed)
        }
        let calm = Jelly(scale: 1, motion: MotionParameters(MotionStyle(stretch: 1, wobble: 0)))
        let rest = reach(Jelly(scale: 1).then { $0.step(to: mouse, dt: 0) }, from: mouse)
        var longest: CGFloat = 0
        click(calm) { _, pressed in if !pressed { longest = max(longest, reach(calm, from: mouse)) } }
        #expect(longest < rest + 0.01)
    }

    // 速く何度も押したり離したりしても、つぶれと伸びは上限の中に収まり、止めれば元に戻る
    @Test func rapidClicksStayInRange() {
        for style in [MotionStyle.standard, MotionStyle(stretch: 2, wobble: 2)] {
            var hand = HandMotion(scale: 1, motion: MotionParameters(style))
            var random = SeededRandom(seed: 7)
            var pressed = false
            for _ in 0..<2000 {
                if random.next() < 0.15 { pressed.toggle() }
                hand.step(to: mouse, dt: 1.0 / 120, imageHeight: 32, pressed: pressed)
                #expect(hand.squash <= Tuning.Click.maxSquash && hand.squash >= -Tuning.Click.maxStretch)
            }
            for _ in 0..<240 { hand.step(to: mouse, dt: 1.0 / 120, imageHeight: 32) }
            #expect(hand.squash == 0 && hand.isSettled)
        }
    }

    // 押しているときと離したときの動きは、画面の書き換えの速さによらずほぼ同じ
    @Test func sameSquashAtAnyRefreshRate() {
        func squashes(rate: CGFloat) -> [CGFloat] {
            var hand = HandMotion(scale: 1)
            hand.step(to: mouse, dt: 0, imageHeight: 32)
            var out: [CGFloat] = []
            let perSample = Int(rate / 60)
            for i in 1...Int(0.6 * rate) {
                hand.step(to: mouse, dt: 1 / rate, imageHeight: 32, pressed: CGFloat(i) / rate <= 0.2)
                if i % perSample == 0 { out.append(hand.squash) }
            }
            return out
        }
        let reference = squashes(rate: 240)
        for rate in [120, 60] as [CGFloat] {
            let worst = zip(reference, squashes(rate: rate)).map { abs($0 - $1) }.max() ?? 1
            #expect(worst < 0.02, "\(rate)Hz: \(worst)")
        }
    }
}

extension Jelly {
    fileprivate func then(_ fn: (Jelly) -> Void) -> Jelly {
        fn(self)
        return self
    }
}
