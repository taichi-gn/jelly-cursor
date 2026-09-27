import Foundation
import Testing
@testable import JellyCursorCore

@Suite struct PointerColorsTests {
    @Test func readsArraysAndDictionaries() {
        #expect(PointerColors.color(from: [1, 0, 0, 1]) == RGBA(red: 1, green: 0, blue: 0))
        #expect(PointerColors.color(from: [0.2, 0.4, 0.6]) == RGBA(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        #expect(PointerColors.color(from: ["0.5", "0.5", "0.5", "0.5"]) == RGBA(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5))
        let dict: [String: Any] = ["red": 0.1, "green": 0.2, "blue": 0.3]
        #expect(PointerColors.color(from: dict) == RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        let withAlpha: [String: Any] = ["red": 0, "green": 0, "blue": 1, "alpha": 0.25]
        #expect(PointerColors.color(from: withAlpha) == RGBA(red: 0, green: 0, blue: 1, alpha: 0.25))
    }

    @Test func rejectsBrokenValues() {
        #expect(PointerColors.color(from: nil) == nil)
        #expect(PointerColors.color(from: "red") == nil)
        #expect(PointerColors.color(from: [1, 0]) == nil)
        #expect(PointerColors.color(from: [1, 0, 0, 1, 1]) == nil)
        #expect(PointerColors.color(from: [2, 0, 0]) == nil)
        #expect(PointerColors.color(from: [1, "x", 0]) == nil)
        let missing: [String: Any] = ["red": 1, "green": 1]
        #expect(PointerColors.color(from: missing) == nil)
    }

    @Test func fallsBackToStandardPerColor() {
        let colors = PointerColors(fillValue: [0, 0, 1], outlineValue: "broken")
        #expect(colors.fill == RGBA(red: 0, green: 0, blue: 1))
        #expect(colors.outline == PointerColors.standard.outline)
        #expect(PointerColors(fillValue: nil, outlineValue: nil) == .standard)
    }
}
