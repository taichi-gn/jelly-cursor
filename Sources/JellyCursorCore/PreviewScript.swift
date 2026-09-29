import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 設定画面のプレビューで動かすマウスの道筋。period 秒ごとに繰り返す。
// 弧を描いて右上へ動かして止め（戻る揺れを見せる）、クリックし、別の弧で左下へ戻して、また止めてクリックする
package enum PreviewScript {
    package static let period: Double = 4.4

    private static let start = CGPoint(x: 0.15, y: 0.3)
    private static let end = CGPoint(x: 0.85, y: 0.7)
    private static let moveDuration = 0.6
    private static let arcHeight = 0.25
    // 右上へ動き始める時刻と、左下へ戻り始める時刻
    private static let outbound = 0.0
    private static let inbound = period / 2

    // 止まって向きが戻ったあと、それぞれ1回クリックする（押す時刻と離す時刻）
    private static let clicks: [ClosedRange<Double>] = [1.35...1.5, 3.55...3.7]

    // その時刻にボタンを押しているか
    package static func isPressed(at time: Double) -> Bool {
        let t = time.truncatingRemainder(dividingBy: period) + (time < 0 ? period : 0)
        return clicks.contains { $0.contains(t) }
    }

    // 0〜1 の四角の中の位置（左下原点）。描く側で枠の大きさに合わせる
    package static func position(at time: Double) -> CGPoint {
        let t = time.truncatingRemainder(dividingBy: period) + (time < 0 ? period : 0)
        if t < inbound {
            return point(from: start, to: end, arc: arcHeight, progress: (t - outbound) / moveDuration)
        }
        return point(from: end, to: start, arc: -arcHeight, progress: (t - inbound) / moveDuration)
    }

    private static func point(from a: CGPoint, to b: CGPoint, arc: Double, progress: Double) -> CGPoint {
        let u = min(max(progress, 0), 1)
        let e = u * u * (3 - 2 * u)
        return CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e + arc * sin(.pi * u))
    }
}
