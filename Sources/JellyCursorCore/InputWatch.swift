import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// macOS は文字を打つとマウスを動かすまでカーソルを消す。自前で描く I 字も同じように消すため、
// 最後の文字入力が最後のマウス移動より新しいかを見る（キー入力の時刻は権限なしで取れる）。
// ⌘・⌃を押しながらのキー（ショートカットやアプリの切り替え）は文字入力として数えない。
// アプリの切り替えは⌘を離したときに起きるので、カーソルが I 字でない間も毎回読んで、押された瞬間の⌘を捕まえる。
// 読む間隔より短く⌘を押して離したときは、キーより後に修飾キーが変わったことで見分ける
// （Shift や ⌥ を同じくらい短く押して打った文字も入力に数えなくなるが、次の文字で消える）
package struct TypingWatch {
    // 同じキー入力を、読むたびの時刻のずれで別の入力と数えないための幅（秒）
    private static let sameKeyTolerance: TimeInterval = 0.01
    private var lastMouse: CGPoint?
    private var lastMoveTime: TimeInterval
    private var lastKeyTime: TimeInterval?
    private var lastTypedTime = -TimeInterval.infinity

    package init(now: TimeInterval) {
        lastMoveTime = now
    }

    package var isTyping: Bool { lastTypedTime > lastMoveTime }

    package mutating func update(mouse: CGPoint, now: TimeInterval, secondsSinceKeyDown: TimeInterval,
                         secondsSinceFlagsChanged: @autoclosure () -> TimeInterval,
                         shortcutHeld: @autoclosure () -> Bool) {
        if mouse != lastMouse {
            lastMouse = mouse
            lastMoveTime = now
        }
        let keyTime = now - secondsSinceKeyDown
        if keyTime > (lastKeyTime ?? -.infinity) + Self.sameKeyTolerance {
            lastKeyTime = keyTime
            let modifierChangedAfter = now - secondsSinceFlagsChanged() > keyTime
            if !shortcutHeld() && !modifierChangedAfter { lastTypedTime = keyTime }
        }
    }
}

// 他のアプリが本物のカーソルを隠しているかを、マウスが止まっている間だけ間をあけて調べる。
// 他のアプリが隠すのは動画を放置したときや文字を打っているときで、マウスを動かせば表示に戻る
package struct OtherHideWatch {
    private var lastMouse: CGPoint?
    private var stillSince: TimeInterval
    private var lastProbe = -TimeInterval.infinity
    package private(set) var isHidden = false

    package init(now: TimeInterval) {
        stillSince = now
    }

    // lastInput は最後のキー入力かクリックの時刻
    package mutating func update(mouse: CGPoint, now: TimeInterval, lastInput: @autoclosure () -> TimeInterval, probe: () -> Bool) {
        if mouse != lastMouse {
            lastMouse = mouse
            stillSince = now
            isHidden = false
            return
        }
        guard now - stillSince >= Tuning.Render.otherHideDelay else { return }
        // 隠れていると分かったあとは、調べるたびに待たされるので間隔をあける。
        // ただし、キーやクリックに応じて他のアプリが表示に戻すことがある（動画の一時停止など）ので、
        // そのあとは相手が戻し終えるのを少し待ってから、いつもの間隔で確かめ直す
        var interval = Tuning.Render.otherHideInterval
        if isHidden {
            let input = lastInput()
            if input > lastProbe {
                // 相手が戻し終える前に確かめて、確かめ直しの機会を使い切らないよう待つ
                guard now - input >= Tuning.Render.otherHideInputSettle else { return }
            } else {
                interval = Tuning.Render.otherHideRecheckInterval
            }
        }
        guard now - lastProbe >= interval else { return }
        lastProbe = now
        isHidden = probe()
    }
}
