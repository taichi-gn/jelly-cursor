import AppKit
import JellyCursorCore
import Testing
@testable import JellyCursorKit

// 設定画面のプレビュー。窓に載せなくても、大きさが決まれば描き、時間を進めると動くこと
@MainActor
@Suite struct MotionPreviewTests {
    private func makeView() -> MotionPreviewView {
        let view = MotionPreviewView()
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 170)
        return view
    }

    @Test func drawsBothFiguresInTheirLanes() throws {
        let view = makeView()
        let bounds = view.figureBounds
        #expect(bounds.count == 2)
        let arrow = try #require(bounds.first), iBeam = try #require(bounds.last)
        #expect(!arrow.isNull && !iBeam.isNull)
        // 上の段に矢印、下の段に I 字
        #expect(arrow.midY > view.bounds.midY)
        #expect(iBeam.midY < view.bounds.midY)
    }

    @Test func movesOverTimeAndStaysInside() {
        let view = makeView()
        let start = view.figureBounds
        // 道筋の半分ほど（右上へ動いて止まるところ）まで進める
        var moved = false
        for _ in 0..<Int(PreviewScript.period / 2 * 60) {
            view.advance(dt: 1.0 / 60)
            moved = moved || view.figureBounds != start
            for rect in view.figureBounds {
                #expect(view.bounds.contains(rect))
            }
        }
        #expect(moved)
    }

    @Test func changingTheStyleKeepsDrawing() {
        let view = makeView()
        view.style = MotionStyle(stretch: 2, wobble: 0)
        #expect(view.figureBounds.allSatisfy { !$0.isNull })
    }
}
