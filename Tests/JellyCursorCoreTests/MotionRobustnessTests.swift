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

    // 1フレームのうちに、マウスの動き以上に形が大きく飛ばない。
    // 上限は、この試験を書いたときの3つの設定の最大値（画面の書き換えの速さとポインタの大きさごと）の約1.2倍
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func movesWithoutJumps(rate: CGFloat) {
        let limits: [CGFloat: (CGFloat, CGFloat)] = [60: (112, 108), 120: (88, 89), 240: (58, 55)]
        for style in [MotionStyle.standard, MotionPreset.subtle.style, MotionPreset.lively.style] {
            for scale in [1, 2] as [CGFloat] {
                let limit = scale == 1 ? limits[rate]!.0 : limits[rate]!.1
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
                #expect(beamJump < 3 * scale * max(CGFloat(style.stretch), 1) * 60 / rate, "\(label): \(beamJump) px")
            }
        }
    }

    // 指したところで少し行き過ぎて戻す（5〜8px）くらいでは、矢印の向きを変えない。大きく戻せば向きを変える
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func smallCorrectionsDoNotFlip(rate: CGFloat) {
        func turn(back: CGFloat, over seconds: CGFloat) -> CGFloat {
            let arrow = Jelly(scale: 1)
            let start = CGPoint(x: 100, y: 300)
            arrow.step(to: start, dt: 0)
            var mouse = start, t: CGFloat = 0
            while t < 0.4 {
                t += 1 / rate
                let u = min(t / 0.4, 1)
                mouse = CGPoint(x: start.x + 400 * (1 - (1 - u) * (1 - u)), y: start.y)
                arrow.step(to: mouse, dt: 1 / rate)
            }
            let before = bodyAngle(arrow, from: mouse), end = mouse
            var worst: CGFloat = 0, e: CGFloat = 0
            while e < seconds + 0.1 {
                e += 1 / rate
                mouse = CGPoint(x: end.x - back * min(e / seconds, 1), y: end.y)
                arrow.step(to: mouse, dt: 1 / rate)
                worst = max(worst, abs(wrapAngle(bodyAngle(arrow, from: mouse) - before)))
            }
            return worst
        }
        #expect(turn(back: 5, over: 0.08) < 0.1)
        #expect(turn(back: 8, over: 0.15) < 0.1)
        #expect(turn(back: 30, over: 0.2) > 2.5)
    }

    // まっすぐ速く動かして一瞬で逆向きに戻しても、画面の書き換えの速さによらず、矢じりが折り返しで崩れず、大きく飛ばない
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func sharpUTurnsStayWhole(rate: CGFloat) {
        for scale in [1, 2] as [CGFloat] {
            for speed in [500, 1000, 1500, 2500] as [CGFloat] {
                let arrow = Jelly(scale: scale)
                var mouse = CGPoint(x: 300, y: 300)
                arrow.step(to: mouse, dt: 0)
                var worstOverlap: CGFloat = 0, worstJump: CGFloat = 0, previous = arrow.points
                let turn = Int(0.3 * rate)
                for i in 0..<(2 * turn) {
                    let last = mouse
                    mouse.x += (i < turn ? 1 : -1) * speed / rate
                    mouse.y += 0.3
                    arrow.step(to: mouse, dt: 1 / rate)
                    worstOverlap = max(worstOverlap, overlapArea(arrow.points))
                    // 動き出し（止まった形から一気に速く動かしたとき）の動きは見ず、折り返してからを見る
                    if i >= turn {
                        worstJump = max(worstJump, frameJump(from: previous, to: arrow.points,
                                                             mouseMoved: CGVector(dx: mouse.x - last.x, dy: mouse.y - last.y)))
                    }
                    previous = arrow.points
                }
                let label = "大きさ \(scale) \(speed)pt/秒"
                #expect(worstOverlap < 1 * scale * scale, "\(label): \(worstOverlap)")
                #expect(worstJump < (12 * scale + 2400 / rate) * 1.2, "\(label): \(worstJump)")
            }
        }
    }

    // 円を描き続けると、矢印は道に沿って伸びたまま回る。途中で回る向きを逆にして（道が折り返して）胴体をまっすぐにしても、
    // すぐにまた伸びる（回し終わらずに、いつまでも短いままにならない）
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func keepsStretchingWhileCircling(rate: CGFloat) {
        let rest = ArrowShape(scale: 1).length
        // 速く回すほど、画面の書き換えが遅い（60Hz）ときに回し終わりにくい
        for (rx, ry, revolutions) in [(40, 40, 3), (80, 80, 2), (80, 30, 3), (80, 80, 2.5), (40, 40, 4)] as [(CGFloat, CGFloat, CGFloat)] {
            // 最後の1秒の、先端からいちばん遠い頂点までの距離の平均
            func reach(reverseAt: CGFloat) -> CGFloat {
                let arrow = Jelly(scale: 1)
                let script = MouseScript.circle(radiusX: rx, radiusY: ry, revolutions: revolutions, rate: rate, reverseAt: reverseAt)
                var sum: CGFloat = 0, count: CGFloat = 0
                for (i, frame) in script.enumerated() {
                    arrow.step(to: frame.mouse, dt: frame.dt)
                    guard i >= script.count - Int(rate) else { continue }
                    sum += arrow.points.map { hypot($0.x - frame.mouse.x, $0.y - frame.mouse.y) }.max() ?? 0
                    count += 1
                }
                return sum / count
            }
            let steady = reach(reverseAt: .infinity), reversed = reach(reverseAt: 1.2)
            let label = "\(rx)x\(ry) \(revolutions)回/秒"
            #expect(steady > 2.5 * rest, "\(label): \(steady)")
            #expect(reversed > 0.95 * steady, "\(label): 逆回しのあと \(reversed)、回し続けたとき \(steady)")
        }
    }

    // 左右に振ると、矢印は振り子のように行き来する。同じ向きへ回り続けない（プロペラのように回らない）
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func shakingWagsInsteadOfSpinning(rate: CGFloat) {
        for wobble in [0, 8] as [CGFloat] {
            let arrow = Jelly(scale: 1)
            arrow.step(to: CGPoint(x: 500, y: 500), dt: 0)
            var net: CGFloat = 0, total: CGFloat = 0, last: CGFloat?
            for frame in MouseScript.shake(amplitude: 100, frequency: 4, rate: rate, seconds: 2, drift: wobble) {
                arrow.step(to: frame.mouse, dt: frame.dt)
                let angle = bodyAngle(arrow, from: frame.mouse)
                if let last {
                    net += wrapAngle(angle - last)
                    total += abs(wrapAngle(angle - last))
                }
                last = angle
            }
            #expect(total > 20, "上下のゆれ \(wobble): 振っても向きが変わらない")
            #expect(abs(net) < .pi, "上下のゆれ \(wobble): \(net) ラジアン回り続けた")
        }
    }

    // 止まった矢印の胴体と逆向きへ動き出しても、胴体が先端へ縮んで小さな塊にならない。少しだけ動かしたとき・止まった矢印から
    // 速く動き出したとき・行き過ぎて一瞬止めてから戻したとき・ゆっくり折り返したときを見る
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func movingAgainstTheBodyDoesNotCollapse(rate: CGFloat) {
        let rest = ArrowShape(scale: 1).length
        func shortestReach(_ position: (CGFloat) -> CGPoint, seconds: CGFloat) -> CGFloat {
            let arrow = Jelly(scale: 1)
            arrow.step(to: position(0), dt: 0)
            var shortest = CGFloat.infinity
            for i in 1...Int((seconds * rate).rounded()) {
                let mouse = position(CGFloat(i) / rate)
                arrow.step(to: mouse, dt: 1 / rate)
                shortest = min(shortest, arrow.points.map { hypot($0.x - mouse.x, $0.y - mouse.y) }.max() ?? 0)
            }
            return shortest
        }
        // 胴体は右下（止まったときの向き）。そちらや真下・右へ動かす
        for degrees in [-67, -45, -90, 0] as [CGFloat] {
            let direction = CGVector(dx: cos(degrees * .pi / 180), dy: sin(degrees * .pi / 180))
            for speed in [150, 400, 1200, 3000] as [CGFloat] {
                // 25pt だけ動かして止める
                let nudge = shortestReach({ t in
                    let d = min(speed * t, 25)
                    return CGPoint(x: 300 + direction.dx * d, y: 300 + direction.dy * d)
                }, seconds: 0.8)
                // そのまま動き続ける
                let start = shortestReach({ t in CGPoint(x: 300 + direction.dx * speed * t, y: 300 + direction.dy * speed * t) }, seconds: 0.5)
                #expect(nudge > 0.7 * rest, "\(degrees)° \(speed)pt/秒で少し動かした: \(nudge)")
                #expect(start > 0.7 * rest, "\(degrees)° \(speed)pt/秒で動き出した: \(start)")
            }
        }
        for pause in [0.08, 0.12, 0.18] as [CGFloat] {
            let reach = shortestReach({ t in
                if t < 0.3 { return CGPoint(x: 300 + 800 * t, y: 300) }
                return CGPoint(x: 540 - 300 * max(t - 0.3 - pause, 0), y: 300)
            }, seconds: 1.2)
            #expect(reach > 0.7 * rest, "行き過ぎて \(pause) 秒止めてから戻した: \(reach)")
        }
        for speed in [60, 100, 140, 200] as [CGFloat] {
            let reach = shortestReach({ t in CGPoint(x: 300 + (t < 0.6 ? speed * t : speed * (1.2 - t)), y: 300 + 18 * t) }, seconds: 1.6)
            #expect(reach > 0.7 * rest, "\(speed)pt/秒でゆっくり折り返した: \(reach)")
        }
    }

    // 角を曲がっても、少しあとで胴体の後ろのほうが跳ねない（道の覚えている秒数から角が抜けたときに、
    // 後ろのほうの向きが一度に変わらない）。1フレームの動きは、マウスが1フレームに動く距離に比べて小さい
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func cornersDoNotSnapTheTail(rate: CGFloat) {
        for scale in [1, 2] as [CGFloat] {
            for style in [MotionStyle.standard, MotionStyle(stretch: 2, wobble: 2)] {
                for degrees in [45, 90, -90] as [CGFloat] {
                    for speed in [400, 700, 1000, 2000] as [CGFloat] {
                        let arrow = Jelly(scale: scale, motion: MotionParameters(style))
                        var mouse = CGPoint(x: 300, y: 300)
                        arrow.step(to: mouse, dt: 0)
                        var previous = arrow.points, worst: CGFloat = 0
                        let corner = Int(0.3 * rate)
                        let turned = CGVector(dx: cos(degrees * .pi / 180), dy: sin(degrees * .pi / 180))
                        for i in 1...(2 * corner) {
                            let last = mouse
                            let direction = i <= corner ? CGVector(dx: 1, dy: 0) : turned
                            mouse.x += direction.dx * speed / rate
                            mouse.y += direction.dy * speed / rate
                            arrow.step(to: mouse, dt: 1 / rate)
                            if i > corner + 1 {
                                worst = max(worst, frameJump(from: previous, to: arrow.points,
                                                             mouseMoved: CGVector(dx: mouse.x - last.x, dy: mouse.y - last.y)))
                            }
                            previous = arrow.points
                        }
                        let label = "大きさ \(scale) 伸び \(style.stretch) \(degrees)° \(speed)pt/秒"
                        #expect(worst < 6 * speed / rate + 3 * scale, "\(label): \(worst)")
                    }
                }
            }
        }
    }

    // どの向きに、どの速さで振っても、同じ向きへ回り続けない（止まったときの矢印の向きに沿って振ったときや、
    // 速く振って折り返しの途中でまた折り返したときも）。手ぶれほどの小さなゆれを混ぜる
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func shakingAnyWayDoesNotSpin(rate: CGFloat) {
        let arrowAxis = ArrowShape(scale: 1).baseAngle
        for axis in [0, .pi / 2, arrowAxis, .pi / 4, -.pi / 4] as [CGFloat] {
            for (amplitude, frequency) in [(30, 3), (50, 4), (100, 5), (40, 6), (20, 8)] as [(CGFloat, CGFloat)] {
                let arrow = Jelly(scale: 1)
                var random = SeededRandom(seed: 3)
                var net: CGFloat = 0, worst: CGFloat = 0, last: CGFloat?
                var t: CGFloat = 0
                arrow.step(to: CGPoint(x: 500, y: 500), dt: 0)
                while t < 3 {
                    t += 1 / rate
                    let u = amplitude * min(t / 0.2, 1) * sin(2 * .pi * frequency * t)
                    let jitter = (random.next() - 0.5) * 0.6
                    let mouse = CGPoint(x: 500 + u * cos(axis) - jitter * sin(axis), y: 500 + u * sin(axis) + jitter * cos(axis))
                    arrow.step(to: mouse, dt: 1 / rate)
                    let angle = bodyAngle(arrow, from: mouse)
                    if let last { net += wrapAngle(angle - last) }
                    last = angle
                    worst = max(worst, abs(net))
                }
                #expect(worst < 1.5 * .pi, "向き \(Int(axis * 180 / .pi))° \(amplitude)px \(frequency)回/秒: \(worst / (2 * .pi)) 回転")
            }
        }
    }

    // 指も、左右に振って同じ向きへ回り続けない（ゆっくり大きく振っても、1往復ごとに1回転しない）
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func handShakingDoesNotSpin(rate: CGFloat) {
        for axis in [0, .pi / 4, .pi / 2] as [CGFloat] {
            for (amplitude, frequency) in [(200, 2), (30, 3), (50, 4), (100, 4)] as [(CGFloat, CGFloat)] {
                var hand = HandMotion(scale: 1)
                var random = SeededRandom(seed: 3)
                var net: CGFloat = 0, worst: CGFloat = 0, last: CGFloat?
                var t: CGFloat = 0
                hand.step(to: CGPoint(x: 500, y: 500), dt: 0, imageHeight: 32)
                while t < 3 {
                    t += 1 / rate
                    let u = amplitude * min(t / 0.2, 1) * sin(2 * .pi * frequency * t)
                    let jitter = (random.next() - 0.5) * 0.6
                    let mouse = CGPoint(x: 500 + u * cos(axis) - jitter * sin(axis), y: 500 + u * sin(axis) + jitter * cos(axis))
                    hand.step(to: mouse, dt: 1 / rate, imageHeight: 32)
                    if let last { net += wrapAngle(hand.angle - last) }
                    last = hand.angle
                    worst = max(worst, abs(net))
                }
                #expect(worst < 5 * .pi, "向き \(Int(axis * 180 / .pi))° \(amplitude)px \(frequency)回/秒: \(worst / (2 * .pi)) 回転")
            }
        }
    }

    // 止めた手がふるえる（数pxの範囲で細かく行き来する）だけなら、矢印は伸びも曲がりもせず、指も首を振らない
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func tremorLeavesTheCursorAlone(rate: CGFloat) {
        let rest = ArrowShape(scale: 1).length
        for amplitude in [0.5, 1.5, 3] as [CGFloat] {
            let arrow = Jelly(scale: 1)
            var hand = HandMotion(scale: 1)
            var random = SeededRandom(seed: 11)
            let center = CGPoint(x: 600, y: 390)
            arrow.step(to: center, dt: 0)
            hand.step(to: center, dt: 0, imageHeight: 32)
            var shortest = CGFloat.infinity, longest: CGFloat = 0, handTurn: CGFloat = 0
            var t: CGFloat = 0
            while t < 3 {
                t += 1 / rate
                let dx = amplitude * (sin(2 * .pi * 10 * t + 1) * 0.7 + (random.next() - 0.5) * 0.6)
                let dy = amplitude * (sin(2 * .pi * 8.3 * t + 4) * 0.7 + (random.next() - 0.5) * 0.6)
                // 0.5pt ごとの位置（トラックパッドやマウスの細かさ）
                let mouse = CGPoint(x: ((center.x + dx) * 2).rounded() / 2, y: ((center.y + dy) * 2).rounded() / 2)
                arrow.step(to: mouse, dt: 1 / rate)
                hand.step(to: mouse, dt: 1 / rate, imageHeight: 32)
                let reach = arrow.points.map { hypot($0.x - mouse.x, $0.y - mouse.y) }.max() ?? 0
                shortest = min(shortest, reach)
                longest = max(longest, reach)
                handTurn = max(handTurn, abs(wrapAngle(hand.angle - .pi / 2)))
            }
            #expect(longest - shortest < 0.1 * rest, "±\(amplitude)pt: 矢印の長さ \(shortest)〜\(longest)")
            #expect(handTurn < 0.1, "±\(amplitude)pt: 指が \(handTurn) ラジアン回った")
        }
    }

    // 速く動かしたあと、ゆっくり動かし続けると、矢印も指も元の向きへ戻る（前の向きのまま後ろ向きに進まない）
    @Test(arguments: [60, 120, 240] as [CGFloat])
    func creepingReturnsToRest(rate: CGFloat) {
        let restBody = { () -> CGFloat in
            let arrow = Jelly(scale: 1)
            arrow.step(to: .zero, dt: 0)
            return bodyAngle(arrow, from: .zero)
        }()
        for (degrees, speed) in [(180, 30), (180, 60), (90, 60), (-90, 40)] as [(CGFloat, CGFloat)] {
            let arrow = Jelly(scale: 1)
            var hand = HandMotion(scale: 1)
            let direction = CGVector(dx: cos(degrees * .pi / 180), dy: sin(degrees * .pi / 180))
            var mouse = CGPoint(x: 300, y: 300)
            arrow.step(to: mouse, dt: 0)
            hand.step(to: mouse, dt: 0, imageHeight: 32)
            var t: CGFloat = 0
            while t < 2.4 {
                t += 1 / rate
                // 右へ速く 0.2 秒動かしてから、1pt ごとの位置でゆっくり動かす
                mouse = t < 0.2 ? CGPoint(x: 300 + 1500 * t, y: 300)
                    : CGPoint(x: (600 + direction.dx * speed * (t - 0.2)).rounded(), y: (300 + direction.dy * speed * (t - 0.2)).rounded())
                arrow.step(to: mouse, dt: 1 / rate)
                hand.step(to: mouse, dt: 1 / rate, imageHeight: 32)
            }
            let arrowOff = abs(wrapAngle(bodyAngle(arrow, from: mouse) - restBody))
            let handOff = abs(wrapAngle(hand.angle - .pi / 2))
            #expect(arrowOff < 0.15, "\(degrees)° \(speed)pt/秒: 矢印が元の向きから \(arrowOff) ラジアン")
            #expect(handOff < 0.15, "\(degrees)° \(speed)pt/秒: 指が上から \(handOff) ラジアン")
        }
    }

    // ほかのアプリがポインタを遠くへ動かした（1フレームで飛んだ）ときは、新しい位置で止まっている形から始め直す。
    // 飛んだ線に沿って伸びたり、飛んだ向きへ回ったりしない
    @Test func jumpsStartOverAtTheNewPosition() {
        for distance in [300, 1500] as [CGFloat] {
            let arrow = Jelly(scale: 1), beam = IBeam(scale: 1)
            var hand = HandMotion(scale: 1)
            let start = CGPoint(x: 300, y: 300), end = CGPoint(x: 300 + distance, y: 300 + distance * 0.3)
            for figure in [arrow, beam] as [CursorFigure] { figure.step(to: start, dt: 0) }
            hand.step(to: start, dt: 0, imageHeight: 32)
            for _ in 0..<30 {
                for figure in [arrow, beam] as [CursorFigure] { figure.step(to: start, dt: 1 / 120) }
                hand.step(to: start, dt: 1 / 120, imageHeight: 32)
            }
            let arrowAtRest = arrow.points.map { CGPoint(x: $0.x - start.x, y: $0.y - start.y) }
            let beamAtRest = beam.points.map { CGPoint(x: $0.x - start.x, y: $0.y - start.y) }
            var arrowMoved: CGFloat = 0, beamMoved: CGFloat = 0, handTurn: CGFloat = 0
            for _ in 0..<60 {
                for figure in [arrow, beam] as [CursorFigure] { figure.step(to: end, dt: 1 / 120) }
                hand.step(to: end, dt: 1 / 120, imageHeight: 32)
                for (p, q) in zip(arrow.points, arrowAtRest) { arrowMoved = max(arrowMoved, hypot(p.x - end.x - q.x, p.y - end.y - q.y)) }
                for (p, q) in zip(beam.points, beamAtRest) { beamMoved = max(beamMoved, hypot(p.x - end.x - q.x, p.y - end.y - q.y)) }
                handTurn = max(handTurn, abs(wrapAngle(hand.angle - .pi / 2)))
            }
            #expect(arrowMoved < 0.5, "\(distance)pt 飛んだ: 矢印が形を変えた \(arrowMoved)")
            #expect(beamMoved < 0.5, "\(distance)pt 飛んだ: I 字が形を変えた \(beamMoved)")
            #expect(handTurn < 0.01, "\(distance)pt 飛んだ: 指が \(handTurn) ラジアン回った")
            #expect(arrow.isSettled && beam.isSettled && hand.isSettled)
        }
    }

    // 表示が詰まって1フレームが長くなっても（0.1〜0.5 秒）、ばねが暴れず、形はマウスの近くに収まる
    @Test func longFramesStayCalm() {
        for dt in [0.1, 0.3, 0.5] as [CGFloat] {
            let arrow = Jelly(scale: 1), beam = IBeam(scale: 1)
            var hand = HandMotion(scale: 1)
            var mouse = CGPoint(x: 300, y: 300)
            for figure in [arrow, beam] as [CursorFigure] { figure.step(to: mouse, dt: 0) }
            hand.step(to: mouse, dt: 0, imageHeight: 32)
            for i in 1...36 {
                mouse = CGPoint(x: 300 + 1500 * CGFloat(i) / 120, y: 300)
                for figure in [arrow, beam] as [CursorFigure] { figure.step(to: mouse, dt: 1 / 120) }
                hand.step(to: mouse, dt: 1 / 120, imageHeight: 32)
            }
            var beamReach: CGFloat = 0, handScale: CGFloat = 0, finite = true
            for _ in 0..<60 {
                for figure in [arrow, beam] as [CursorFigure] { figure.step(to: mouse, dt: dt) }
                hand.step(to: mouse, dt: dt, imageHeight: 32)
                finite = finite && (arrow.points + beam.points).allSatisfy { $0.x.isFinite && $0.y.isFinite }
                beamReach = max(beamReach, beam.points.map { hypot($0.x - mouse.x, $0.y - mouse.y) }.max() ?? 0)
                handScale = max(handScale, hand.lengthScale)
            }
            #expect(finite, "\(dt) 秒のフレーム: 形が数でなくなった")
            #expect(beamReach < 20, "\(dt) 秒のフレーム: I 字が \(beamReach)pt まで広がった")
            #expect(handScale < 2, "\(dt) 秒のフレーム: 指が \(handScale) 倍に伸びた")
            #expect(arrow.isSettled && beam.isSettled && hand.isSettled, "\(dt) 秒のフレーム: 落ち着かない")
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
        // 振ったり、速く折り返したりしても（胴体を先端のまわりで回すときも）、画面の書き換えの速さでほとんど変わらない。
        // 回し始めるフレームが1つずれることはあるので、9割のフレームで比べる
        func shake(_ t: CGFloat) -> CGPoint {
            let x: CGFloat = 500 + 100 * min(t / 0.2, 1) * sin(2 * .pi * 4 * t)
            return CGPoint(x: x, y: 500 + 8 * sin(2 * .pi * 1.3 * t))
        }
        func uTurn(_ t: CGFloat) -> CGPoint {
            CGPoint(x: 300 + (t < 0.3 ? 1500 * t : max(450 - 1500 * (t - 0.3), 0)), y: 300 + 20 * t)
        }
        func typicalDifference(_ path: (CGFloat) -> CGPoint, rate: CGFloat, scale: CGFloat) -> CGFloat {
            func shapes(_ r: CGFloat) -> [[CGPoint]] {
                let arrow = Jelly(scale: scale)
                arrow.step(to: path(0), dt: 0)
                var out: [[CGPoint]] = []
                for i in 1...Int(2 * r) {
                    arrow.step(to: path(CGFloat(i) / r), dt: 1 / r)
                    if i % Int(r / 60) == 0 { out.append(arrow.points) }
                }
                return out
            }
            let differences = zip(shapes(240), shapes(rate)).map { a, b in
                zip(a, b).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
            }.sorted()
            return differences[differences.count * 9 / 10]
        }
        for scale in [1, 2] as [CGFloat] {
            #expect(typicalDifference(shake, rate: 120, scale: scale) < 10 * scale)
            #expect(typicalDifference(shake, rate: 60, scale: scale) < 18 * scale)
            #expect(typicalDifference(uTurn, rate: 120, scale: scale) < 5 * scale)
            #expect(typicalDifference(uTurn, rate: 60, scale: scale) < 8 * scale)
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
