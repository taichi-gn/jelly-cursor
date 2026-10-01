import Foundation

// 情報タブの「診断情報をコピー」で渡す文面。困ったときに状態をまとめて伝えられるようにする
package struct Diagnostics: Sendable {
    package var appVersion: String
    package var osVersion: String
    package var activity: Activity
    package var canHideCursor: Bool
    package var safeMode: Bool
    package var pointerScale: Double
    // 画面ごとの「幅×高さ@倍率」
    package var screens: [String]
    package var settings: SettingsValues
    package var shortcutFailed: Bool
    // この起動のあいだの最近の記録（起動・状態の変化など）。古い順
    package var recentLog: [String]

    package init(appVersion: String, osVersion: String, activity: Activity, canHideCursor: Bool, safeMode: Bool,
                 pointerScale: Double, screens: [String], settings: SettingsValues, shortcutFailed: Bool,
                 recentLog: [String] = []) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.activity = activity
        self.canHideCursor = canHideCursor
        self.safeMode = safeMode
        self.pointerScale = pointerScale
        self.screens = screens
        self.settings = settings
        self.shortcutFailed = shortcutFailed
        self.recentLog = recentLog
    }

    package var text: String {
        let shortcut = settings.shortcut.map { $0.displayString + (shortcutFailed ? "（登録できない）" : "") } ?? "なし"
        var lines = [
            "JellyCursor \(appVersion)",
            "macOS \(osVersion)",
            "状態: \(activity.summary)",
            "macOS のカーソルを隠す: \(canHideCursor ? "できる" : "できない")",
            "セーフモード: \(safeMode ? "はい" : "いいえ")",
            "ポインタのサイズ: \(String(format: "%.2f", pointerScale))",
            "画面: \(screens.isEmpty ? "なし" : screens.joined(separator: ", "))",
            "ショートカット: \(shortcut)",
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(settings), let json = String(data: data, encoding: .utf8) {
            lines.append("設定: \(json)")
        }
        if !recentLog.isEmpty {
            lines.append("最近の記録:")
            lines += recentLog.map { "  " + $0 }
        }
        return lines.joined(separator: "\n")
    }
}

extension Activity {
    // 情報タブと診断情報に出す、今の状態のひとこと
    package var summary: String {
        switch self {
        case .running: "オン"
        case .off: "オフ"
        case .safeMode: "セーフモード"
        case .paused: statusLine ?? ""
        }
    }
}
