import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 色の成分（sRGB、0〜1）
package struct RGBA: Equatable, Sendable {
    package var red: CGFloat
    package var green: CGFloat
    package var blue: CGFloat
    package var alpha: CGFloat

    package init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

// システム設定の「ポインタの枠線の色」「ポインタの塗りつぶしの色」。未設定なら白い縁・黒い中身。
// 設定の読み出しは JellyCursorKit の PointerColors.current()
package struct PointerColors: Equatable, Sendable {
    package var fill: RGBA
    package var outline: RGBA

    package static let standard = PointerColors(fill: RGBA(red: 0, green: 0, blue: 0),
                                                outline: RGBA(red: 1, green: 1, blue: 1))

    package init(fill: RGBA, outline: RGBA) {
        self.fill = fill
        self.outline = outline
    }

    // 設定の値から作る。読めなかった色は標準の色にする
    package init(fillValue: Any?, outlineValue: Any?) {
        self.init(fill: Self.color(from: fillValue) ?? Self.standard.fill,
                  outline: Self.color(from: outlineValue) ?? Self.standard.outline)
    }

    // 書式は公式に書かれていないので、数値の並び（赤・緑・青・透明度）と名前つき（red・green・blue・alpha）の
    // 両方を受け付ける。0〜1 の範囲外や数が足りないものは読めなかった扱いにする
    package static func color(from value: Any?) -> RGBA? {
        let components: [CGFloat]?
        if let array = value as? [Any] {
            components = numbers(array)
        } else if let dict = value as? [String: Any] {
            components = numbers(["red", "green", "blue"].map { dict[$0] as Any } + [dict["alpha"] ?? 1])
        } else {
            components = nil
        }
        guard var c = components, (3...4).contains(c.count), c.allSatisfy({ (0...1).contains($0) }) else {
            return nil
        }
        if c.count == 3 { c.append(1) }
        return RGBA(red: c[0], green: c[1], blue: c[2], alpha: c[3])
    }

    private static func numbers(_ values: [Any]) -> [CGFloat]? {
        let parsed = values.map { v -> CGFloat? in
            if let n = v as? NSNumber { return CGFloat(n.doubleValue) }
            if let s = v as? String, let d = Double(s) { return CGFloat(d) }
            return nil
        }
        return parsed.contains { $0 == nil } ? nil : parsed.compactMap { $0 }
    }
}
