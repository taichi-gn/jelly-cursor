import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

// 動きがカクついたり形が崩れたりしないこと。設定の組み合わせ・ポインタの大きさ・画面の書き換えの速さを変えて確かめる。
// 数値の上限は、この試験を書いたときの測り値に余裕を持たせたもの
@Suite struct MotionRobustnessTests {
    static let styles: [MotionStyle] = [.standard, MotionPreset.subtle.style, MotionPreset.lively.style,
                                        MotionStyle(stretch: 2, wobble: 2), MotionStyle(stretch: 0, wobble: 0)]
    static let shakes: [(amplitude: CGFloat, frequency: CGFloat)] = [(30, 3), (50, 4), (80, 2), (100, 5), (150, 6)]

    // 左右に振ると道が何度も折り返す。矢じりが折り返しで自分と重なって崩れず、I 字も裏返らない
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func shakingKeepsShapesWhole(rate: CGFloat) {
        for style in Self.styles {
            for scale in [1, 2] as [CGFloat] {
                var arrowOverlap: CGFloat = 0, beamOverlap: CGFloat = 0
                for shake in Self.shakes {
                    let script = MouseScript.shake(amplitude: shake.amplitude, frequency: shake.frequency, rate: rate)
                    let arrow = Jelly(scale: scale, motion: MotionParameters(style))
                    let beam = IBeam(scale: scale, motion: MotionParameters(style))
                    for frame in script {
                        arrow.step(to: frame.mouse, dt: frame.dt)
                        beam.step(to: frame.mouse, dt: frame.dt)
                        arrowOverlap = max(arrowOverlap, overlapArea(arrow.points))
                        beamOverlap = max(beamOverlap, overlapArea(beam.points))
                    }
                }
                #expect(arrowOverlap < 0.5 * scale * scale, "伸び \(style.stretch) 弾み \(style.wobble) 大きさ \(scale)")
                #expect(beamOverlap == 0, "伸び \(style.stretch) 弾み \(style.wobble) 大きさ \(scale)")
            }
        }
    }

    // 手で動かすようなでたらめな動きでも、矢印の重なりはごく小さくまれで、I 字は裏返らない
    @Test(arguments: [60, 120] as [CGFloat])
    func wanderingRarelyOverlaps(rate: CGFloat) {
        for style in Self.styles {
            for scale in [1, 2] as [CGFloat] {
                var worst: CGFloat = 0, overlapping = 0, frames = 0, beamOverlap: CGFloat = 0
                for seed in 0..<8 {
                    let arrow = Jelly(scale: scale, motion: MotionParameters(style))
                    let beam = IBeam(scale: scale, motion: MotionParameters(style))
                    for frame in MouseScript.wander(seed: seed, rate: rate) {
                        arrow.step(to: frame.mouse, dt: frame.dt)
                        beam.step(to: frame.mouse, dt: frame.dt)
                        let area = overlapArea(arrow.points)
                        worst = max(worst, area)
                        if area > 10 * scale * scale { overlapping += 1 }
                        beamOverlap = max(beamOverlap, overlapArea(beam.points))
                        frames += 1
                    }
                }
                let label = "伸び \(style.stretch) 弾み \(style.wobble) 大きさ \(scale)"
                #expect(worst < 60 * scale * scale, "\(label)")
                #expect(overlapping * 100 <= frames, "\(label): \(overlapping)/\(frames) フレーム")
                #expect(beamOverlap == 0, "\(label)")
            }
        }
    }

    // 1フレームのうちに、マウスの動き以上に形が大きく飛ばない
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func movesWithoutJumps(rate: CGFloat) {
        for style in [MotionStyle.standard, MotionPreset.subtle.style, MotionPreset.lively.style] {
            for scale in [1, 2] as [CGFloat] {
                // 胴体が長いほど、画面の書き換えが遅いほど、1フレームの動きは大きくなる
                let limit = 1.25 * (20 * scale + 3600 / rate) * (0.5 + 0.5 * max(CGFloat(style.stretch), 1))
                var arrowJump: CGFloat = 0, beamJump: CGFloat = 0
                let scripts = Self.shakes.map { MouseScript.shake(amplitude: $0.amplitude, frequency: $0.frequency, rate: rate) }
                    + (0..<8).map { MouseScript.wander(seed: $0, rate: rate) }
                for script in scripts {
                    let arrow = Jelly(scale: scale, motion: MotionParameters(style))
                    let beam = IBeam(scale: scale, motion: MotionParameters(style))
                    var last = script[0].mouse
                    var arrowPoints: [CGPoint]?, beamPoints: [CGPoint]?
                    for frame in script {
                        arrow.step(to: frame.mouse, dt: frame.dt)
                        beam.step(to: frame.mouse, dt: frame.dt)
                        let moved = CGVector(dx: frame.mouse.x - last.x, dy: frame.mouse.y - last.y)
                        if let arrowPoints { arrowJump = max(arrowJump, frameJump(from: arrowPoints, to: arrow.points, mouseMoved: moved)) }
                        if let beamPoints { beamJump = max(beamJump, frameJump(from: beamPoints, to: beam.points, mouseMoved: moved)) }
                        arrowPoints = arrow.points
                        beamPoints = beam.points
                        last = frame.mouse
                    }
                }
                let label = "伸び \(style.stretch) 大きさ \(scale)"
                #expect(arrowJump < limit, "\(label): \(arrowJump) px")
                #expect(beamJump < 8 * scale * max(CGFloat(style.stretch), 1) * 60 / rate, "\(label): \(beamJump) px")
            }
        }
    }

    // ふつうの手では起きない乱暴な入力（向きと速さが一瞬で変わる・画面の端まで飛ぶ・0 秒や 1/30 秒のフレーム）でも、
    // 形は有限で、マウスの近くにあり、指の伸びとつぶれも範囲に収まる。クリックも混ぜる
    @Test func erraticInputStaysFiniteAndNearTheMouse() {
        for style in Self.styles {
            let motion = MotionParameters(style)
            let stretch = CGFloat(style.stretch)
            for scale in [1, 2] as [CGFloat] {
                // 伸びきった長さに、クリックを離したときの伸び（最大 maxStretch）と、矢じりの幅のぶんを足す
                let arrowReach = (ArrowShape(scale: scale).length + Tuning.Trail.maxStretch * stretch) * (1 + Tuning.Click.maxStretch)
                    + 10 * scale
                let beamReach = 8.3 * scale * (1 + Tuning.IBeam.maxStretch * stretch * 2) * (1 + Tuning.IBeam.maxLean * stretch * 2)
                    + 3.3 * scale * (1 + Tuning.IBeam.maxWiden * stretch * 2)
                for seed in 0..<4 {
                    for rate in [60, 120] as [CGFloat] {
                        let arrow = Jelly(scale: scale, motion: motion)
                        let beam = IBeam(scale: scale, motion: motion)
                        var hand = HandMotion(scale: scale, motion: motion)
                        var worstArrow: CGFloat = 0, worstBeam: CGFloat = 0, finite = true, handInRange = true
                        for (i, frame) in MouseScript.erratic(seed: seed, rate: rate).enumerated() {
                            let pressed = (i / 17) % 3 == 1
                            arrow.step(to: frame.mouse, dt: frame.dt, pressed: pressed)
                            beam.step(to: frame.mouse, dt: frame.dt, pressed: pressed)
                            hand.step(to: frame.mouse, dt: frame.dt, imageHeight: 32 * scale, pressed: pressed)
                            for p in arrow.points + beam.points where !p.x.isFinite || !p.y.isFinite { finite = false }
                            worstArrow = max(worstArrow, arrow.points.map { hypot($0.x - frame.mouse.x, $0.y - frame.mouse.y) }.max() ?? 0)
                            worstBeam = max(worstBeam, beam.points.map { hypot($0.x - frame.mouse.x, $0.y - frame.mouse.y) }.max() ?? 0)
                            if !hand.angle.isFinite || hand.stretch < -Tuning.Hand.maxStretch * stretch - 0.01
                                || hand.stretch > 1.6 * Tuning.Hand.maxStretch * stretch + 0.01
                                || hand.squash < -Tuning.Click.maxStretch || hand.squash > Tuning.Click.maxSquash {
                                handInRange = false
                            }
                        }
                        let label = "伸び \(style.stretch) 弾み \(style.wobble) 大きさ \(scale) 種 \(seed) \(rate)Hz"
                        #expect(finite, "\(label)")
                        #expect(worstArrow <= arrowReach, "\(label): \(worstArrow) > \(arrowReach)")
                        #expect(worstBeam <= beamReach, "\(label): \(worstBeam) > \(beamReach)")
                        #expect(handInRange, "\(label)")
                    }
                }
            }
        }
    }

    // どう動かしても、止めれば落ち着いて（眠れて）、ちょうど元の形・向きに戻る
    @Test func settlesBackToRest() {
        for style in Self.styles {
            let motion = MotionParameters(style)
            for scale in [1, 2] as [CGFloat] {
                for seed in 0..<4 {
                    let script = MouseScript.erratic(seed: seed, rate: 120, segments: 12)
                    let arrow = Jelly(scale: scale, motion: motion)
                    let beam = IBeam(scale: scale, motion: motion)
                    var hand = HandMotion(scale: scale, motion: motion)
                    for (i, frame) in script.enumerated() {
                        let pressed = (i / 13) % 4 == 2
                        arrow.step(to: frame.mouse, dt: frame.dt, pressed: pressed)
                        beam.step(to: frame.mouse, dt: frame.dt, pressed: pressed)
                        hand.step(to: frame.mouse, dt: frame.dt, imageHeight: 32 * scale, pressed: pressed)
                    }
                    let end = script[script.count - 1].mouse
                    for _ in 0..<360 {
                        arrow.step(to: end, dt: 1.0 / 120)
                        beam.step(to: end, dt: 1.0 / 120)
                        hand.step(to: end, dt: 1.0 / 120, imageHeight: 32 * scale)
                    }
                    let label = "伸び \(style.stretch) 弾み \(style.wobble) 大きさ \(scale) 種 \(seed)"
                    #expect(arrow.isSettled && beam.isSettled && hand.isSettled, "\(label)")
                    let restArrow = Jelly(scale: scale, motion: motion), restBeam = IBeam(scale: scale, motion: motion)
                    restArrow.step(to: end, dt: 0)
                    restBeam.step(to: end, dt: 0)
                    let arrowOff = zip(arrow.points, restArrow.points).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
                    let beamOff = zip(beam.points, restBeam.points).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
                    #expect(arrowOff < 0.1 && beamOff < 0.1, "\(label): \(arrowOff) \(beamOff)")
                    #expect(abs(wrapAngle(hand.angle - .pi / 2)) < 0.01 && abs(hand.stretch) < 0.01 && hand.squash == 0, "\(label)")
                }
            }
        }
    }

    // 画面の書き換えの速さ（60・120・240Hz）が違っても、同じ動かし方ならほとんど同じ動きになる
    @Test func sameMotionAtAnyRefreshRate() {
        func path(_ t: CGFloat) -> CGPoint {
            func ease(_ u: CGFloat) -> CGFloat { let x = min(max(u, 0), 1); return x * x * (3 - 2 * x) }
            var p = CGPoint(x: 200, y: 300)
            if t > 0 { let u = min(t / 0.5, 1); p = CGPoint(x: 200 + 600 * ease(u), y: 300 + 150 * sin(.pi * u)) }
            if t > 1.4 { let u = min((t - 1.4) / 0.3, 1); p = CGPoint(x: 800 - 500 * u, y: 300 - 20 * u) }
            if t > 1.7 { let u = min((t - 1.7) / 0.2, 1); p = CGPoint(x: 300 + 30 * u, y: 280 + 260 * u) }
            if t > 2.8 {
                let u = min((t - 2.8) / 0.5, 1)
                p = CGPoint(x: 330 + 40 * sin(u * 4 * .pi), y: 500 + 40 * cos(u * 4 * .pi))
            }
            return p
        }
        // 1/60 秒ごとの形
        func run<F>(_ rate: CGFloat, make: () -> F, step: (inout F, CGPoint, CGFloat) -> Void, read: (F) -> [CGFloat]) -> [[CGFloat]] {
            var figure = make()
            step(&figure, path(0), 0)
            let perSample = Int(rate / 60)
            var samples: [[CGFloat]] = []
            for i in 1...Int(4 * rate) {
                step(&figure, path(CGFloat(i) / rate), 1 / rate)
                if i % perSample == 0 { samples.append(read(figure)) }
            }
            return samples
        }
        // 同じ時刻の形どうしで、いちばん離れた頂点の距離
        func worstDifference(_ a: [[CGFloat]], _ b: [[CGFloat]]) -> CGFloat {
            var worst: CGFloat = 0
            for (x, y) in zip(a, b) {
                for k in stride(from: 0, to: x.count, by: 2) {
                    let dx: CGFloat = x[k] - y[k], dy: CGFloat = x[k + 1] - y[k + 1]
                    worst = max(worst, hypot(dx, dy))
                }
            }
            return worst
        }
        for scale in [1, 2] as [CGFloat] {
            for style in [MotionStyle.standard, MotionPreset.lively.style] {
                let motion = MotionParameters(style)
                let size = scale * max(CGFloat(style.stretch), 1)
                for (kind, make) in [("矢印", { Jelly(scale: scale, motion: motion) as CursorFigure }),
                                     ("I 字", { IBeam(scale: scale, motion: motion) as CursorFigure })] {
                    let shapes = [240, 120, 60].map { rate in
                        run(CGFloat(rate), make: make, step: { $0.step(to: $1, dt: $2) }, read: { $0.points.flatMap { [$0.x, $0.y] } })
                    }
                    let limits: (CGFloat, CGFloat) = kind == "矢印" ? (5 * size, 12 * size) : (0.5 * size, 1 * size)
                    let label = "\(kind) 伸び \(style.stretch) 大きさ \(scale)"
                    #expect(worstDifference(shapes[0], shapes[1]) < limits.0, "\(label) 120Hz")
                    #expect(worstDifference(shapes[0], shapes[2]) < limits.1, "\(label) 60Hz")
                }
            }
        }
        let angles = [240, 120, 60].map { rate in
            run(CGFloat(rate), make: { HandMotion(scale: 1) }, step: { $0.step(to: $1, dt: $2, imageHeight: 32) }, read: { [$0.angle] })
        }
        func worstAngle(_ a: [[CGFloat]], _ b: [[CGFloat]]) -> CGFloat { zip(a, b).map { abs(wrapAngle($0[0] - $1[0])) }.max() ?? 0 }
        // 指は回る速さに上限（60Hz で1フレーム60度）があるので、60Hz では1フレームぶん遅れて回ることがある
        #expect(worstAngle(angles[0], angles[1]) < 0.25)
        #expect(worstAngle(angles[0], angles[2]) < 0.8)
    }
}
