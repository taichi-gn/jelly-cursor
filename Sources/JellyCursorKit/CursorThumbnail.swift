import AppKit
import JellyCursorCore

// 設定画面に並べるカーソルの絵。カーソルの画像は、クリックする点（ホットスポット）に合わせた余白を含み、
// 矢印は左上に寄せて描かれている。そのまま並べると矢印だけ左上に寄って見えるので、描かれている範囲だけを
// 切り出して、枠の真ん中に置けるようにする
@MainActor
enum CursorThumbnail {
    // 描かれているとみなす不透明さ（0〜255）。薄い影は含めない（含めると、影のぶん左上に寄って見える）
    private static let opaque: UInt8 = 128
    // 1pt を何ピクセルで描くか（範囲を調べるときと、切り出した絵）
    private static let pixelsPerPoint = 4

    private static var cache: [CursorKind: NSImage] = [:]

    static func image(for kind: CursorKind) -> NSImage {
        if let image = cache[kind] { return image }
        let source = cursor(for: kind).image
        let image = drawnBounds(of: source).flatMap { crop(source, to: $0) } ?? source
        cache[kind] = image
        return image
    }

    private static func cursor(for kind: CursorKind) -> NSCursor {
        switch kind {
        case .arrow, .other: .arrow
        case .iBeam: .iBeam
        case .pointingHand: .pointingHand
        }
    }

    // 描かれている範囲（pt。左下原点）。何も描かれていなければ nil
    static func drawnBounds(of image: NSImage) -> NSRect? {
        guard let rep = render(image, from: NSRect(origin: .zero, size: image.size)), let data = rep.bitmapData else {
            return nil
        }
        // 画素は上の行から並ぶ
        var minX = rep.pixelsWide, maxX = -1, minRow = rep.pixelsHigh, maxRow = -1
        for row in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where data[row * rep.bytesPerRow + x * 4 + 3] >= opaque {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard maxX >= minX, maxRow >= minRow else { return nil }
        let scale = CGFloat(pixelsPerPoint)
        return NSRect(x: CGFloat(minX) / scale, y: CGFloat(rep.pixelsHigh - 1 - maxRow) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxRow - minRow + 1) / scale)
    }

    // 範囲だけを、1pt を pixelsPerPoint ピクセルで描いた絵（Retina でもぼやけない）
    private static func crop(_ image: NSImage, to rect: NSRect) -> NSImage? {
        guard let rep = render(image, from: rect) else { return nil }
        let cropped = NSImage(size: rect.size)
        cropped.addRepresentation(rep)
        return cropped
    }

    // image の rect の部分を、1pt を pixelsPerPoint ピクセルで描く
    private static func render(_ image: NSImage, from rect: NSRect) -> NSBitmapImageRep? {
        let width = Int((rect.width * CGFloat(pixelsPerPoint)).rounded())
        let height = Int((rect.height * CGFloat(pixelsPerPoint)).rounded())
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
        else { return nil }
        rep.size = rect.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: rect.size), from: rect, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
