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

    // ⌘・⌃・⌥のうち2つ以上か、ファンクションキー
    @Test func validity() {
        func combo(_ modifiers: KeyModifiers, key: UInt16 = 0x26) -> KeyCombo {
            KeyCombo(keyCode: key, modifiers: modifiers, characters: "j")
        }
        #expect(!combo([]).isValid)
        #expect(!combo(.shift).isValid)
        #expect(!combo(.option).isValid)
        #expect(!combo([.option, .shift]).isValid)
        #expect(!combo(.control).isValid)
        // ⌘W・⌘Q・⌘⇧S のようなアプリのショートカットは取らない
        #expect(!combo(.command, key: 0x0D).isValid)
        #expect(!combo([.command, .shift]).isValid)
        #expect(combo([.option, .command]).isValid)
        #expect(combo([.control, .option]).isValid)
        #expect(combo([.control, .command]).isValid)
        #expect(combo([.control, .option, .command]).isValid)
        // ファンクションキーは修飾キーなしでもよい
        #expect(KeyCombo(keyCode: 0x60, modifiers: [], characters: nil).isValid)
    }

    @Test func labels() {
        #expect(KeyCombo.label(keyCode: 0x31, characters: " ") == "スペース")
        #expect(KeyCombo.label(keyCode: 0x60, characters: "\u{F708}") == "F5")
        #expect(KeyCombo.label(keyCode: 0x7E, characters: nil) == "↑")
        #expect(KeyCombo.label(keyCode: 0x2C, characters: "/") == "/")
        #expect(KeyCombo.label(keyCode: 0x0B, characters: "") == "#11")
        // テンキーの Enter・Clear・Help と、見えない文字
        #expect(KeyCombo.label(keyCode: 0x4C, characters: "\u{03}") == "⌤")
        #expect(KeyCombo.label(keyCode: 0x47, characters: "\u{F739}") == "⌧")
        #expect(KeyCombo.label(keyCode: 0x72, characters: "\u{F746}") == "Help")
        #expect(KeyCombo.label(keyCode: 0x6E, characters: "\u{10}") == "#110")
        #expect(KeyCombo.label(keyCode: 0x69, characters: "\u{F710}") == "F13")
        #expect(KeyCombo(keyCode: 0x31, modifiers: .control, characters: " ").menuKeyEquivalent == nil)
        #expect(KeyCombo(keyCode: 0x12, modifiers: [.command, .shift], characters: "!").menuKeyEquivalent == nil)
        #expect(KeyCombo(keyCode: 0x12, modifiers: [.command, .shift], characters: "1").menuKeyEquivalent == "1")
        #expect(KeyCombo(keyCode: 0x12, modifiers: .command, characters: "1").menuKeyEquivalent == "1")
        #expect(KeyCombo(keyCode: 0x26, modifiers: [.command, .shift], characters: "J").menuKeyEquivalent == "j")
    }

    @Test func codableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 0x26, modifiers: [.control, .option], characters: "j")
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}
