import AppKit
import JellyCursorCore
import Testing
@testable import JellyCursorKit

// macOS の本物のカーソルの画像で、形の見分けを確かめる。
// 画面の仕組みにつながっていないと矢印と I 字の画像が空になるので、先にアプリとしてつないでおく
@MainActor
@Suite struct CursorShapeKitTests {
    init() {
        _ = NSApplication.shared
    }

    @Test func imagesAreNotEmpty() {
        for cursor in [NSCursor.arrow, .iBeam, .pointingHand] {
            #expect(!CursorShape(cursor).isEmpty)
        }
    }

    @Test func drawnKindsAreRecognized() {
        #expect(CursorShapeWatch.classify(.arrow) == .arrow)
        #expect(CursorShapeWatch.classify(.iBeam) == .iBeam)
        #expect(CursorShapeWatch.classify(.pointingHand) == .pointingHand)
    }

    // 自前で描かないカーソルを、矢印・I 字・指と取り違えない。
    // コピーやメニューの印がついた矢印を矢印として描くと、印が隠れてしまう
    @Test(arguments: ["crosshair", "openHand", "closedHand", "operationNotAllowed", "dragCopy", "dragLink",
                      "contextualMenu", "disappearingItem", "iBeamVertical"])
    func otherCursorsAreOther(name: String) throws {
        let cursor: NSCursor = switch name {
        case "crosshair": .crosshair
        case "openHand": .openHand
        case "closedHand": .closedHand
        case "operationNotAllowed": .operationNotAllowed
        case "dragCopy": .dragCopy
        case "dragLink": .dragLink
        case "contextualMenu": .contextualMenu
        case "disappearingItem": .disappearingItem
        default: .iBeamCursorForVerticalLayout
        }
        #expect(CursorShapeWatch.classify(cursor) == .other)
    }

    // 指の画像は、描く大きさとクリック位置が画像の中にある
    @Test func handImageHasHotSpotInside() {
        let image = CursorImage(.pointingHand)
        #expect(image.image != nil)
        #expect(image.size.width > 0 && image.size.height > 0)
        #expect((0...image.size.width).contains(image.hotSpot.x))
        #expect((0...image.size.height).contains(image.hotSpot.y))
    }

    // 止まっている指は回さず伸ばさない（画像のまま描く）
    @Test func restingHandIsIdentity() {
        let hand = PointingHand(scale: 1, motion: .standard, cursor: CursorImage(.pointingHand))
        hand.step(to: CGPoint(x: 100, y: 100), dt: 0)
        #expect(CATransform3DIsIdentity(hand.transform))
        #expect(hand.bounds.contains(CGPoint(x: 100, y: 100)))
    }
}
