import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

// 標準の動きが、記録と同じであることを確かめる（意図しない変化に気づくため）。
// golden-motion.json は、GoldenScenario を動かし、4フレームごとに記録したもの。最初はパッケージに分ける前（main の efbc96a）の
// コードで記録し、矢印が胴体と逆向きへ動き出したときに胴体をつぶさず先に向きを回すようにしたときに、矢印を記録し直した。
// 動きの標準を意図して変えたときは、RECORD_GOLDEN=1 swift test --filter GoldenMotionTests で記録し直す
@Suite struct GoldenMotionTests {
    private static let isRecording = ProcessInfo.processInfo.environment["RECORD_GOLDEN"] != nil
    private static let recordedURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Resources/golden-motion.json")

    private static let golden: [String: [[Double]]] = {
        guard let url = Bundle.module.url(forResource: "golden-motion", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([String: [[Double]]].self, from: data) else { return [:] }
        return rows
    }()

    private static let frames = GoldenScenario.frames()

    // 記録の名前と、その記録を作る動かし方
    private static let cases: [(name: String, run: @Sendable () -> [[Double]])] = [
        ("arrow@1", { outlineRows(Jelly(scale: 1, motion: MotionParameters(.standard))) }),
        ("arrow@2", { outlineRows(Jelly(scale: 2, motion: MotionParameters(.standard))) }),
        ("ibeam@1", { outlineRows(IBeam(scale: 1, motion: MotionParameters(.standard))) }),
        ("ibeam@1.5", { outlineRows(IBeam(scale: 1.5, motion: MotionParameters(.standard))) }),
        ("hand@1", { handRows(scale: 1) }),
        ("hand@2", { handRows(scale: 2) }),
    ]

    @Test(.disabled(if: GoldenMotionTests.isRecording), arguments: GoldenMotionTests.cases.map(\.name))
    func matchesRecording(name: String) throws {
        let expected = try #require(Self.golden[name], "記録が無い: \(name)")
        let actual = try #require(Self.cases.first { $0.name == name }).run()
        #expect(actual.count == expected.count, "\(name): 行の数")
        for (row, (a, e)) in zip(actual, expected).enumerated() {
            let same = a.count == e.count && zip(a, e).allSatisfy { abs($0 - $1) <= 1e-6 * max(1, abs($0), abs($1)) }
            if !same {
                Issue.record("\(name): \(row * 4) フレーム目が違う\n  今: \(a)\n  記録: \(e)")
                return
            }
        }
    }

    @Test(.enabled(if: GoldenMotionTests.isRecording))
    func record() throws {
        var text = "{\n"
        for (k, c) in Self.cases.sorted(by: { $0.name < $1.name }).enumerated() {
            let rows = c.run()
            text += "  \"\(c.name)\": [\n"
            for (i, row) in rows.enumerated() {
                text += "    [" + row.map { String(format: "%.9g", $0) }.joined(separator: ", ") + "]"
                text += i + 1 < rows.count ? ",\n" : "\n"
            }
            text += "  ]" + (k + 1 < Self.cases.count ? ",\n" : "\n")
        }
        text += "}\n"
        try Data(text.utf8).write(to: Self.recordedURL)
    }

    @Test func standardStyleUsesTuningValues() {
        let p = MotionParameters.standard
        #expect(p.stretch == 1)
        #expect(p.turnDampingRatio == Tuning.Turn.dampingRatio)
        #expect(p.returnSwingDampingRatio == Tuning.Turn.returnSwingDampingRatio)
        #expect(p.iBeamDampingRatio == Tuning.IBeam.dampingRatio)
        #expect(p.handDampingRatio == Tuning.Hand.dampingRatio)
    }

    // 4フレームごとに、頂点の位置（マウスからのずれ）の和と、頂点の順番で重みをつけた和、落ち着いたか
    private static func outlineRows(_ figure: CursorFigure) -> [[Double]] {
        var rows: [[Double]] = []
        for (i, frame) in frames.enumerated() {
            figure.step(to: frame.mouse, dt: frame.dt)
            guard i % 4 == 0 else { continue }
            var sx = 0.0, sy = 0.0, wx = 0.0, wy = 0.0
            for (j, p) in figure.points.enumerated() {
                let dx = Double(p.x - frame.mouse.x), dy = Double(p.y - frame.mouse.y)
                sx += dx; sy += dy
                wx += Double(j + 1) * dx; wy += Double(j + 1) * dy
            }
            rows.append([sx, sy, wx, wy, figure.isSettled ? 1 : 0])
        }
        return rows
    }

    // 4フレームごとに、指の向き・伸び・落ち着いたか。画像は 32pt 四方とする
    private static func handRows(scale: CGFloat) -> [[Double]] {
        var hand = HandMotion(scale: scale, motion: MotionParameters(.standard))
        var rows: [[Double]] = []
        for (i, frame) in frames.enumerated() {
            hand.step(to: frame.mouse, dt: frame.dt, imageHeight: 32 * scale)
            if i % 4 == 0 { rows.append([Double(hand.angle), Double(hand.stretch), hand.isSettled ? 1 : 0]) }
        }
        return rows
    }
}
