import Foundation
import OSLog

// 起動や状態が変わったときなどの記録。あとから log show で見られるよう、残る重さ（notice 以上）で書く。
// ターミナルで log show --last 1h --predicate 'subsystem == "local.jellycursor"'
private let subsystem = "local.jellycursor"
let logger = Logger(subsystem: subsystem, category: "app")

// この起動のあいだに書いた記録のうち、新しいもの limit 件を古い順に返す（診断情報に入れる）。読めなければ空
func recentLogLines(limit: Int = 30) -> [String] {
    guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
          let entries = try? store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
    else { return [] }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let lines = entries.compactMap { $0 as? OSLogEntryLog }
        .map { "\(formatter.string(from: $0.date)) \($0.composedMessage)" }
    return Array(lines.suffix(limit))
}
