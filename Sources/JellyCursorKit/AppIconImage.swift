import AppKit

// アプリのアイコン。画像ファイルを持たずに描き、make app のときに .icns にして .app に入れる
package enum AppIconImage {
    static func make() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            // macOS のアイコンと同じく、角の丸い四角の周りに少し余白をとる
            let plate = rect.insetBy(dx: 50, dy: 50)
            let path = NSBezierPath(roundedRect: plate, xRadius: 92, yRadius: 92)
            let gradient = NSGradient(colors: [
                NSColor(srgbRed: 1.0, green: 0.52, blue: 0.72, alpha: 1),
                NSColor(srgbRed: 0.52, green: 0.36, blue: 0.96, alpha: 1),
            ])
            gradient?.draw(in: path, angle: -90)
            let configuration = NSImage.SymbolConfiguration(pointSize: 230, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            guard let symbol = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return true }
            let size = symbol.size
            symbol.draw(in: NSRect(x: plate.midX - size.width / 2, y: plate.midY - size.height / 2,
                                   width: size.width, height: size.height))
            return true
        }
    }

    // iconutil に渡す AppIcon.iconset の中身（16〜1024 ピクセルの PNG）を書き出す。書けたら true
    @MainActor
    package static func writeIconset(to path: String) -> Bool {
        let folder = URL(fileURLWithPath: path)
        let image = make()
        let sizes = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                     ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, pixels) in sizes {
                guard let data = png(image, pixels: pixels) else { return false }
                try data.write(to: folder.appendingPathComponent("icon_\(name).png"))
            }
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func png(_ image: NSImage, pixels: Int) -> Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        // 1pt を 1 ピクセルとして描く
        bitmap.size = NSSize(width: pixels, height: pixels)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
