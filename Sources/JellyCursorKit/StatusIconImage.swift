import AppKit
import JellyCursorCore

// メニューバーのアイコンの絵。記号は状態ごとに幅が違い、そのまま出すとアイコンの幅が変わって、まわりのアイコンが動く。
// そこで、どの状態も同じ大きさの絵にして、矢印の先が同じ位置に来るようにそろえる。
// 一時停止中などの印は、SF Symbols の印つきの記号と同じく、矢印の右下を少しくり抜いて重ねる
@MainActor
enum StatusIconImage {
    private static var cache: [StatusIcon: NSImage] = [:]
    private static var layout: Layout?
    // 印の直径（矢印の高さに対する割合）と、印のまわりをくり抜く幅（pt）
    private static let badgeRatio: CGFloat = 0.62
    private static let badgeGap: CGFloat = 1

    // すべての状態の絵を重ねたときの大きさと、それぞれの記号と印を置く範囲（左上から）
    private struct Layout {
        var size: CGSize
        var glyphRects: [String: CGRect]
        var badgeRects: [String: CGRect]
    }

    // 記号が使えないとき（古い macOS など）は nil
    static func image(for icon: StatusIcon) -> NSImage? {
        if let image = cache[icon] { return image }
        guard let layout = layout ?? makeLayout() else { return nil }
        self.layout = layout
        let symbol = icon.symbolName
        let glyphRect = layout.glyphRects[symbol] ?? .zero
        let badgeRect = layout.badgeRects[symbol] ?? .zero
        let badge = icon.badge?.symbolName
        let gap = badgeGap
        // 左上を原点にして描く。描く処理は、絵を描くスレッドで呼ばれることがあるので、主スレッドに縛らない。
        // 印のまわりのくり抜きが、描く先（メニューバーの背景など）まで消さないよう、透明な層の中で描いてから重ねる
        let image = NSImage(size: layout.size, flipped: true) { @Sendable _ in
            let context = NSGraphicsContext.current
            context?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.draw(in: glyphRect)
            if let badge {
                context?.compositingOperation = .destinationOut
                NSColor.black.setFill()
                NSBezierPath(ovalIn: badgeRect.insetBy(dx: -gap, dy: -gap)).fill()
                context?.compositingOperation = .sourceOver
                NSImage(systemSymbolName: badge, accessibilityDescription: nil)?.draw(in: badgeRect)
            }
            context?.cgContext.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = icon.accessibilityDescription
        cache[icon] = image
        return image
    }

    private static func makeLayout() -> Layout? {
        // 矢印の先を原点にそろえたときの、記号と印の範囲
        var glyphRects: [String: CGRect] = [:]
        var badgeRects: [String: CGRect] = [:]
        for name in Set(StatusIcon.allCases.map(\.symbolName)) {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
            // 半ポイント単位にそろえる（Retina の画素に合わせて、にじまないように）
            let found = tip(of: image) ?? CGPoint(x: image.size.width, y: 0)
            let tip = CGPoint(x: (found.x * 2).rounded() / 2, y: (found.y * 2).rounded() / 2)
            let rect = CGRect(x: -tip.x, y: -tip.y, width: image.size.width, height: image.size.height)
            glyphRects[name] = rect
            let d = (rect.height * badgeRatio).rounded()
            badgeRects[name] = CGRect(x: rect.maxX - d * 0.8, y: rect.maxY - d, width: d, height: d)
        }
        for badge in StatusIcon.allCases.compactMap(\.badge) {
            guard NSImage(systemSymbolName: badge.symbolName, accessibilityDescription: nil) != nil else { return nil }
        }
        var union = CGRect.null
        for icon in StatusIcon.allCases {
            union = union.union(glyphRects[icon.symbolName]!)
            if icon.badge != nil {
                union = union.union(badgeRects[icon.symbolName]!.insetBy(dx: -badgeGap, dy: -badgeGap))
            }
        }
        union = union.integral
        return Layout(size: union.size,
                      glyphRects: glyphRects.mapValues { $0.offsetBy(dx: -union.minX, dy: -union.minY) },
                      badgeRects: badgeRects.mapValues { $0.offsetBy(dx: -union.minX, dy: -union.minY) })
    }

    // 記号の絵で、いちばん上の段の左端の点（矢印の先）。左上から見た位置（pt）
    static func tip(of image: NSImage) -> CGPoint? {
        let scale: CGFloat = 4
        let width = Int((image.size.width * scale).rounded(.up))
        let height = Int((image.size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        // 画素の並びは上の段から
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 128 {
                return CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale)
            }
        }
        return nil
    }
}
