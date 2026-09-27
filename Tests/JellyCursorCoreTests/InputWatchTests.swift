import Foundation
import Testing
@testable import JellyCursorCore

@Suite struct TypingWatchTests {
    private let mouse = CGPoint(x: 10, y: 10)

    @Test func typingHidesUntilMouseMoves() {
        var w = TypingWatch(now: 0)
        w.update(mouse: mouse, now: 1, secondsSinceKeyDown: 5, secondsSinceFlagsChanged: 5, shortcutHeld: false)
        #expect(!w.isTyping)
        // 2秒の時点で 0.1秒前にキー入力
        w.update(mouse: mouse, now: 2, secondsSinceKeyDown: 0.1, secondsSinceFlagsChanged: 5, shortcutHeld: false)
        #expect(w.isTyping)
        w.update(mouse: CGPoint(x: 11, y: 10), now: 2.5, secondsSinceKeyDown: 0.6, secondsSinceFlagsChanged: 5,
                 shortcutHeld: false)
        #expect(!w.isTyping)
    }

    @Test func shortcutsAreNotTyping() {
        var w = TypingWatch(now: 0)
        w.update(mouse: mouse, now: 1, secondsSinceKeyDown: 0.05, secondsSinceFlagsChanged: 5, shortcutHeld: true)
        #expect(!w.isTyping)
    }

    // 読む間隔より短く⌘を押して離したとき（キーより後に修飾キーが変わった）も入力に数えない
    @Test func shortCommandPressIsNotTyping() {
        var w = TypingWatch(now: 0)
        w.update(mouse: mouse, now: 1, secondsSinceKeyDown: 0.05, secondsSinceFlagsChanged: 0.02, shortcutHeld: false)
        #expect(!w.isTyping)
    }

    // 同じキー入力を、読むたびの時刻のずれで何度も数えない
    @Test func sameKeyCountsOnce() {
        var w = TypingWatch(now: 0)
        w.update(mouse: mouse, now: 0.5, secondsSinceKeyDown: 5, secondsSinceFlagsChanged: 5, shortcutHeld: false)
        w.update(mouse: mouse, now: 1, secondsSinceKeyDown: 0.2, secondsSinceFlagsChanged: 5, shortcutHeld: false)
        #expect(w.isTyping)
        // 0.8秒のキー入力を 0.795秒と読んでも同じ入力。そのあとマウスを動かしたので入力中ではない
        w.update(mouse: CGPoint(x: 12, y: 10), now: 1.2, secondsSinceKeyDown: 0.405, secondsSinceFlagsChanged: 5,
                 shortcutHeld: false)
        #expect(!w.isTyping)
    }
}

@Suite struct OtherHideWatchTests {
    private let mouse = CGPoint(x: 10, y: 10)

    @Test func probesOnlyAfterMouseRests() {
        var w = OtherHideWatch(now: 0)
        var probes = 0
        let probe = { () -> Bool in probes += 1; return true }
        w.update(mouse: mouse, now: 0, lastInput: -10, probe: probe)
        w.update(mouse: mouse, now: 0.5, lastInput: -10, probe: probe)
        #expect(probes == 0)
        w.update(mouse: mouse, now: 1.0, lastInput: -10, probe: probe)
        #expect(probes == 1)
        #expect(w.isHidden)
        // 隠れていると分かったあとは、2秒あけて確かめ直す
        w.update(mouse: mouse, now: 1.6, lastInput: -10, probe: probe)
        #expect(probes == 1)
        w.update(mouse: mouse, now: 3.0, lastInput: -10, probe: probe)
        #expect(probes == 2)
        // 動かしたらすぐ隠れていない扱いに戻る
        w.update(mouse: CGPoint(x: 11, y: 10), now: 3.1, lastInput: -10, probe: probe)
        #expect(!w.isHidden)
    }

    // キーやクリックのあとは、相手が戻し終えるのを少し待ってから、いつもの間隔で確かめ直す
    @Test func rechecksSoonAfterInput() {
        var w = OtherHideWatch(now: 0)
        var answer = true
        var probes = 0
        let probe = { () -> Bool in probes += 1; return answer }
        w.update(mouse: mouse, now: 0, lastInput: -10, probe: probe)
        w.update(mouse: mouse, now: 1.0, lastInput: -10, probe: probe)
        #expect(w.isHidden)
        answer = false
        w.update(mouse: mouse, now: 1.6, lastInput: 1.5, probe: probe)
        #expect(probes == 1)
        w.update(mouse: mouse, now: 1.85, lastInput: 1.5, probe: probe)
        #expect(probes == 2)
        #expect(!w.isHidden)
    }
}
