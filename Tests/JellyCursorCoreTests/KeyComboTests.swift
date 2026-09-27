import Foundation
import Testing
@testable import JellyCursorCore

@Suite struct KeyComboTests {
    @Test func displaysInMenuOrder() {
        let combo = KeyCombo(keyCode: 0x26, modifiers: [.command, .option, .control, .shift], characters: "j")
        #expect(combo.displayString == "⌃⌥⇧⌘J")
        #expect(combo.menuKeyEquivalent == "j")
    }

    @Test func carbonFlags() {
        #expect(KeyCombo(keyCode: 0, modifiers: .command, keyLabel: "A").carbonModifiers == 0x100)
        #expect(KeyCombo(keyCode: 0, modifiers: .shift, keyLabel: "A").carbonModifiers == 0x200)
        #expect(KeyCombo(keyCode: 0, modifiers: .option, keyLabel: "A").carbonModifiers == 0x800)
        #expect(KeyCombo(keyCode: 0, modifiers: .control, keyLabel: "A").carbonModifiers == 0x1000)
        #expect(KeyCombo(keyCode: 0, modifiers: [.control, .option, .command], keyLabel: "A").carbonModifiers == 0x1900)
    }

    @Test func validity() {
        #expect(!KeyCombo(keyCode: 0x26, modifiers: [], characters: "j").isValid)
        #expect(!KeyCombo(keyCode: 0x26, modifiers: .shift, characters: "j").isValid)
        #expect(KeyCombo(keyCode: 0x26, modifiers: .option, characters: "j").isValid)
        // ファンクションキーは修飾キーなしでもよい
        #expect(KeyCombo(keyCode: 0x60, modifiers: [], characters: nil).isValid)
    }

    @Test func labels() {
        #expect(KeyCombo.label(keyCode: 0x31, characters: " ") == "Space")
        #expect(KeyCombo.label(keyCode: 0x60, characters: "\u{F708}") == "F5")
        #expect(KeyCombo.label(keyCode: 0x7E, characters: nil) == "↑")
        #expect(KeyCombo.label(keyCode: 0x2C, characters: "/") == "/")
        #expect(KeyCombo.label(keyCode: 0x0B, characters: "") == "#11")
        #expect(KeyCombo(keyCode: 0x31, modifiers: .control, characters: " ").menuKeyEquivalent == nil)
        #expect(KeyCombo(keyCode: 0x12, modifiers: [.command, .shift], characters: "!").menuKeyEquivalent == nil)
        #expect(KeyCombo(keyCode: 0x12, modifiers: .command, characters: "1").menuKeyEquivalent == "1")
        #expect(KeyCombo(keyCode: 0x26, modifiers: [.command, .shift], characters: "J").menuKeyEquivalent == "j")
    }

    @Test func codableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 0x26, modifiers: [.control, .option], characters: "j")
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}
