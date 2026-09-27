import AppKit
import JellyCursorCore

// システム設定（アクセシビリティ → ディスプレイ → ポインタ）の大きさと色。
// 設定サーバーへの問い合わせで、まれに数msかかるので、毎フレームは呼ばない
enum SystemPointer {
    private static var domain: CFString { "com.apple.universalaccess" as CFString }

    // 「ポインタの大きさ」。動作中に変えたときも読めるよう、設定サーバーから読み直す
    static func scale() -> CGFloat {
        CFPreferencesAppSynchronize(domain)
        let value = (CFPreferencesCopyAppValue("mouseDriverCursorSize" as CFString, domain) as? NSNumber)?.doubleValue ?? 0
        return value >= 1 ? min(CGFloat(value), 4) : 1
    }

    // 「ポインタの枠線の色」「ポインタの塗りつぶしの色」
    static func colors() -> PointerColors {
        CFPreferencesAppSynchronize(domain)
        return PointerColors(fillValue: CFPreferencesCopyAppValue("cursorFill" as CFString, domain),
                             outlineValue: CFPreferencesCopyAppValue("cursorOutline" as CFString, domain))
    }
}

extension RGBA {
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
