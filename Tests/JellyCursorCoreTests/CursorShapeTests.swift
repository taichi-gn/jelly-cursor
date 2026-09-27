import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

@Suite struct CursorShapeTests {
    // w×h の画素に、fill が true の所を不透明に塗った形
    private func shape(_ w: Int, _ h: Int, hotSpot: CGPoint = .zero, fill: (Int, Int) -> Bool) -> CursorShape {
        var bytes: [UInt8] = []
        for y in 0..<h {
            for x in 0..<w { bytes += [0, fill(x, y) ? 255 : 0] }
        }
        return CursorShape(hotSpot: hotSpot, size: CGSize(width: w / 2, height: h / 2), grayAlpha: bytes)
    }

    private var arrow: CursorShape { shape(20, 20) { x, y in x <= y } }
    private var bar: CursorShape { shape(20, 20, hotSpot: CGPoint(x: 5, y: 5)) { x, _ in (9...10).contains(x) } }
    private var blob: CursorShape { shape(20, 20, hotSpot: CGPoint(x: 1, y: 1)) { x, y in x + y < 12 } }

    @Test func matchesDespiteSmallBlur() {
        // 塗られた面積（210画素）の5%未満の違いは同じ形
        let blurred = shape(20, 20) { x, y in x <= y || (x == y + 1 && x < 8) }
        #expect(blurred.matches(arrow))
        let different = shape(20, 20) { x, y in x <= y + 2 }
        #expect(!different.matches(arrow))
    }

    @Test func hotSpotAndSizeMustAgree() {
        let moved = shape(20, 20, hotSpot: CGPoint(x: 1, y: 0)) { x, y in x <= y }
        #expect(!moved.matches(arrow))
        let bigger = shape(22, 22) { x, y in x <= y }
        #expect(!bigger.matches(arrow))
    }

    @Test func emptyNeverMatches() {
        let empty = shape(20, 20) { _, _ in false }
        #expect(!empty.matches(empty))
    }

    @Test func classifies() {
        #expect(arrow.classify(arrow: arrow, iBeam: bar, pointingHand: blob) == .arrow)
        #expect(bar.classify(arrow: arrow, iBeam: bar, pointingHand: blob) == .iBeam)
        #expect(blob.classify(arrow: arrow, iBeam: bar, pointingHand: blob) == .pointingHand)
        let other = shape(20, 20) { x, _ in x < 3 }
        #expect(other.classify(arrow: arrow, iBeam: bar, pointingHand: blob) == .other)
    }
}
