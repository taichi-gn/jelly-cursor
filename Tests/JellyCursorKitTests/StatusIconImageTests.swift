import AppKit
import JellyCursorCore
import Testing
@testable import JellyCursorKit

// メニューバーのアイコンは、どの状態でも同じ大きさで、矢印の先が同じ位置にあること（状態が変わっても幅や位置が動かない）
@MainActor
@Suite struct StatusIconImageTests {
    init() {
        _ = NSApplication.shared
    }

    @Test func allStatesShareSizeAndTip() throws {
        let images = try StatusIcon.allCases.map { try #require(StatusIconImage.image(for: $0)) }
        let size = images[0].size
        #expect(size.width > 0 && size.height > 0)
        let tips = try images.map { try #require(StatusIconImage.tip(of: $0)) }
        for (image, tip) in zip(images, tips) {
            #expect(image.size == size)
            #expect(image.isTemplate)
            #expect(abs(tip.x - tips[0].x) <= 0.5 && abs(tip.y - tips[0].y) <= 0.5)
        }
    }
}
