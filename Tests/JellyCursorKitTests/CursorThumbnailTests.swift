import AppKit
import JellyCursorCore
import Testing
@testable import JellyCursorKit

// 設定画面に並べるカーソルの絵は、描かれている範囲だけを切り出してあり、枠の真ん中に置ける
// （カーソルの画像のままだと、ホットスポットに合わせた余白のぶん、矢印が左上に寄って見えた）
@MainActor
@Suite struct CursorThumbnailTests {
    init() {
        _ = NSApplication.shared
    }

    @Test(arguments: [CursorKind.arrow, .iBeam, .pointingHand])
    func thumbnailsAreTrimmedToTheDrawing(kind: CursorKind) throws {
        let image = CursorThumbnail.image(for: kind)
        let drawn = try #require(CursorThumbnail.drawnBounds(of: image), "\(kind): 何も描かれていない")
        #expect(abs(drawn.minX) <= 0.5 && abs(drawn.minY) <= 0.5, "\(kind): \(drawn) / \(image.size)")
        #expect(abs(drawn.maxX - image.size.width) <= 0.5 && abs(drawn.maxY - image.size.height) <= 0.5,
                "\(kind): \(drawn) / \(image.size)")
    }
}
