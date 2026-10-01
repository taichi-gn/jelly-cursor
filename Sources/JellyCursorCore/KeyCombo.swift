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

    // どのアプリでも効くショートカットにするので、ほかの操作とぶつからないよう、⌘・⌃・⌥のうち2つ以上を含むか、
    // ファンクションキーであること。⌘だけ（⌘W・⌘Q など）はアプリのメニューと、⌃だけ（⌃A・⌃E など）は文字の編集と、
    // ⌥だけ（⌥E など）は é や © などの文字の入力とぶつかる
    package var isValid: Bool {
        Self.functionKeys[keyCode] != nil
            || [KeyModifiers.command, .control, .option].filter { modifiers.contains($0) }.count >= 2
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
    // ⇧と記号の組み合わせは、⇧を押したあとの文字（! など）で記録したものだと、メニューでは ⇧⌘! のように
    // ⇧が二重に効いた表示になるので付けない
    package var menuKeyEquivalent: String? {
        guard Self.specialKeys[keyCode] == nil, Self.functionKeys[keyCode] == nil,
              keyLabel.count == 1, let scalar = keyLabel.unicodeScalars.first else { return nil }
        if modifiers.contains(.shift) && !CharacterSet.alphanumerics.contains(scalar) { return nil }
        return keyLabel.lowercased()
    }

    // characters は修飾キーを除いたときの文字。見えない文字（制御文字や、矢印などの特殊キーの私用領域の文字）は、
    // キーコードで表す
    package static func label(keyCode: UInt16, characters: String?) -> String {
        if let name = specialKeys[keyCode] ?? functionKeys[keyCode] { return name }
        let text = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let visible = text.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F && !(0xE000...0xF8FF).contains($0.value) }
        return text.isEmpty || !visible ? "#\(keyCode)" : text
    }

    private static let specialKeys: [UInt16: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "スペース", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x4C: "⌤", 0x47: "⌧", 0x72: "Help",
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
