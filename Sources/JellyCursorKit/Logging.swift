import Foundation
import os

// 起動や状態が変わったときなどの記録。あとから log show で見られるよう、残る重さ（notice 以上）で書く
// （ターミナルで log show --last 1h --predicate 'subsystem == "local.jellycursor"'）。
// 診断情報に入れるため、この起動のあいだの新しいものを手元にも残しておく
@MainActor
enum AppLog {
    private static let logger = Logger(subsystem: "local.jellycursor", category: "app")
    private static let limit = 30
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // 新しいもの limit 件を古い順に
    private(set) static var recent: [String] = []

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        remember(message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        remember("エラー: \(message)")
    }

    private static func remember(_ message: String) {
        recent.append("\(time.string(from: Date())) \(message)")
        if recent.count > limit { recent.removeFirst(recent.count - limit) }
    }
}
