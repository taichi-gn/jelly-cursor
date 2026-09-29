import Foundation

// マウスのボタンを押しているかを決める。ボタンの今の状態だけでなく、最後に押された時刻も見て、
// 見に行く間より短いクリック（トラックパッドのタップなど）も、少しの間押したことにする
package struct ClickWatch {
    // 最後に押された時刻と、押したことにしておく時刻
    private var lastPress: TimeInterval?
    private var heldUntil: TimeInterval = -.infinity

    package init() {}

    // buttonsDown: 今どれかのボタンを押しているか。secondsSinceLastPress: 最後にボタンが押されてからの秒数
    package mutating func isPressed(buttonsDown: Bool, secondsSinceLastPress: TimeInterval, now: TimeInterval) -> Bool {
        let pressTime = now - secondsSinceLastPress
        // 最初に見たときより前のクリックは数えない
        if let lastPress, pressTime > lastPress + 0.001 {
            heldUntil = max(heldUntil, pressTime + Tuning.Click.minimumPress)
        }
        if lastPress.map({ pressTime > $0 }) ?? true { lastPress = pressTime }
        return buttonsDown || now < heldUntil
    }
}
