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

    // CI のログで絵を細かく確かめられるよう、8倍の大きさで白地に描いた PNG を base64 で出す
    @Test func printsEnlargedImages() throws {
        let scale: CGFloat = 8
        for icon in StatusIcon.allCases {
            let image = try #require(StatusIconImage.image(for: icon))
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.white.setFill()
            CGRect(origin: .zero, size: image.size).fill()
            image.draw(in: CGRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            let png = try #require(rep.representation(using: .png, properties: [:]))
            let text = png.base64EncodedString()
            print("BEGIN-IMAGE status-icon-\(icon).png")
            var start = text.startIndex
            while start < text.endIndex {
                let end = text.index(start, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
                print(text[start..<end])
                start = end
            }
            print("END-IMAGE")
        }
    }
}
