import Foundation

// オン・オフを切り替えるショートカット。keyCode は Carbon の仮想キーコード
package struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    package var keyCode: UInt16
    package var modifiers: KeyModifiers
    // キーの表示（記録したときのキーボード配列での文字）
    package var keyLabel: String

    package init(keyCode: UInt16, modifiers: KeyModifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    // characters は修飾キーを除いた入力文字（NSEvent.charactersIgnoringModifiers）
    package init(keyCode: UInt16, modifiers: KeyModifiers, characters: String?) {
        self.init(keyCode: keyCode, modifiers: modifiers, keyLabel: Self.label(keyCode: keyCode, characters: characters))
    }

    // メニューと同じ ⌃⌥⇧⌘ の順
    package var displayString: String { modifiers.symbols + keyLabel }

    // 文字入力とぶつからないよう、⌘・⌃・⌥のどれかを含むか、ファンクションキーであること
    package var isValid: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || Self.functionKeys[keyCode] != nil
    }

    // RegisterEventHotKey に渡す修飾キー（cmdKey・shiftKey・optionKey・controlKey）
    package var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= 1 << 8 }
        if modifiers.contains(.shift) { flags |= 1 << 9 }
        if modifiers.contains(.option) { flags |= 1 << 11 }
        if modifiers.contains(.control) { flags |= 1 << 12 }
        return flags
    }

    // メニューの項目にキーとして付けられる1文字（小文字）。記号で表すキーは nil。
    // ⇧と数字・記号の組み合わせは、記録した文字が⇧を押したあとの文字（1 なら !）になっていて、
    // メニューでは ⇧⌘! のように⇧が二重に効いた表示になるので付けない
    package var menuKeyEquivalent: String? {
        guard Self.specialKeys[keyCode] == nil, Self.functionKeys[keyCode] == nil,
              keyLabel.count == 1, let scalar = keyLabel.unicodeScalars.first else { return nil }
        if modifiers.contains(.shift) && !CharacterSet.letters.contains(scalar) { return nil }
        return keyLabel.lowercased()
    }

    package static func label(keyCode: UInt16, characters: String?) -> String {
        if let name = specialKeys[keyCode] ?? functionKeys[keyCode] { return name }
        let text = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return text.isEmpty ? "#\(keyCode)" : text
    }

    private static let specialKeys: [UInt16: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
    ]

    private static let functionKeys: [UInt16: String] = [
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]
}

package struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    package let rawValue: Int

    package init(rawValue: Int) {
        self.rawValue = rawValue
    }

    package static let control = KeyModifiers(rawValue: 1 << 0)
    package static let option = KeyModifiers(rawValue: 1 << 1)
    package static let shift = KeyModifiers(rawValue: 1 << 2)
    package static let command = KeyModifiers(rawValue: 1 << 3)

    package var symbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1).joined()
    }
}
