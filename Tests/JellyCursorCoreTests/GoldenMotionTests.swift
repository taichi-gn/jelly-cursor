import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

// 標準の動きが、パッケージに分ける前（main の efbc96a）と同じであることを確かめる。
// golden-motion.json は、分ける前のコードで GoldenScenario を動かし、4フレームごとに記録したもの
@Suite struct GoldenMotionTests {
    private static let golden: [String: [[Double]]] = {
        let url = Bundle.module.url(forResource: "golden-motion", withExtension: "json")!
        return try! JSONDecoder().decode([String: [[Double]]].self, from: Data(contentsOf: url))
    }()

    private static let frames = GoldenScenario.frames()

    @Test(arguments: [("arrow@1", 1.0), ("arrow@2", 2.0)])
    func arrow(name: String, scale: Double) {
        compareOutline(name) { Jelly(scale: CGFloat(scale), motion: MotionParameters(.standard)) }
    }

    @Test(arguments: [("ibeam@1", 1.0), ("ibeam@1.5", 1.5)])
    func iBeam(name: String, scale: Double) {
        compareOutline(name) { IBeam(scale: CGFloat(scale), motion: MotionParameters(.standard)) }
    }

    @Test(arguments: [("hand@1", 1.0), ("hand@2", 2.0)])
    func hand(name: String, scale: Double) throws {
        let expected = try #require(Self.golden[name])
        var hand = HandMotion(scale: CGFloat(scale), motion: MotionParameters(.standard))
        var rows: [[Double]] = []
        for (i, frame) in Self.frames.enumerated() {
            hand.step(to: frame.mouse, dt: frame.dt, imageHeight: 32 * CGFloat(scale))
            if i % 4 == 0 { rows.append([Double(hand.angle), Double(hand.stretch), hand.isSettled ? 1 : 0]) }
        }
        compare(rows, expected, name: name)
    }

    @Test func standardStyleUsesTuningValues() {
        let p = MotionParameters.standard
        #expect(p.stretch == 1)
        #expect(p.turnDampingRatio == Tuning.Turn.dampingRatio)
        #expect(p.returnSwingDampingRatio == Tuning.Turn.returnSwingDampingRatio)
        #expect(p.iBeamDampingRatio == Tuning.IBeam.dampingRatio)
        #expect(p.handDampingRatio == Tuning.Hand.dampingRatio)
    }

    private func compareOutline(_ name: String, _ make: () -> CursorFigure) {
        guard let expected = Self.golden[name] else {
            Issue.record("記録が無い: \(name)")
            return
        }
        let figure = make()
        var rows: [[Double]] = []
        for (i, frame) in Self.frames.enumerated() {
            figure.step(to: frame.mouse, dt: frame.dt)
            if i % 4 == 0 { rows.append(Self.summary(figure.points, mouse: frame.mouse) + [figure.isSettled ? 1 : 0]) }
        }
        compare(rows, expected, name: name)
    }

    private func compare(_ actual: [[Double]], _ expected: [[Double]], name: String) {
        #expect(actual.count == expected.count, "\(name): 行の数")
        for (row, (a, e)) in zip(actual, expected).enumerated() {
            let same = a.count == e.count && zip(a, e).allSatisfy { abs($0 - $1) <= 1e-6 * max(1, abs($0), abs($1)) }
            if !same {
                Issue.record("\(name): \(row * 4) フレーム目が違う\n  今: \(a)\n  元: \(e)")
                return
            }
        }
    }

    // 頂点の位置（マウスからのずれ）の和と、頂点の順番で重みをつけた和
    private static func summary(_ points: [CGPoint], mouse: CGPoint) -> [Double] {
        var sx = 0.0, sy = 0.0, wx = 0.0, wy = 0.0
        for (i, p) in points.enumerated() {
            sx += Double(p.x - mouse.x); sy += Double(p.y - mouse.y)
            wx += Double(i + 1) * Double(p.x - mouse.x); wy += Double(i + 1) * Double(p.y - mouse.y)
        }
        return [sx, sy, wx, wy]
    }
}
