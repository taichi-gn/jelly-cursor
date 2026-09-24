import CoreGraphics
import Foundation

// システム設定の「ポインタの枠線の色」「ポインタの塗りつぶしの色」。未設定なら白い縁・黒い中身
struct PointerColors: Equatable {
    var fill: CGColor
    var outline: CGColor

    static let standard = PointerColors(fill: CGColor(gray: 0, alpha: 1), outline: CGColor(gray: 1, alpha: 1))

    // 設定サーバーに問い合わせるので、毎フレームは呼ばない
    static func current() -> PointerColors {
        let domain = "com.apple.universalaccess" as CFString
        CFPreferencesAppSynchronize(domain)
        return PointerColors(
            fill: color(from: CFPreferencesCopyAppValue("cursorFill" as CFString, domain)) ?? standard.fill,
            outline: color(from: CFPreferencesCopyAppValue("cursorOutline" as CFString, domain)) ?? standard.outline)
    }

    // 書式は公式に書かれていないので、数値の並び（赤・緑・青・透明度）と名前つき（red・green・blue・alpha）の
    // 両方を受け付ける。0〜1 の範囲外や数が足りないものは読めなかった扱いにする
    static func color(from value: Any?) -> CGColor? {
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
        return CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
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
