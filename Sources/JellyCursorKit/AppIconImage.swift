import AppKit

// Dock（設定画面を開いている間）と「JellyCursor について」に出すアイコン。画像ファイルを持たずに描く
enum AppIconImage {
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
}
