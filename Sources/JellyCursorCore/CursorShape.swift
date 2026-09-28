import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

package enum CursorKind: Sendable {
    case arrow, iBeam, pointingHand, other
}

// カーソルの形（透明でない画素の並び）。カーソルの画像から作る部分は JellyCursorKit にある
package struct CursorShape: Sendable {
    // 画像を 1pt あたりこの画素数で描いて比べる
    package static let pixelsPerPoint = 2
    // 形の違う画素が、塗られた面積のこの割合より少なければ同じ形とみなす（縮小のにじみの分だけ許す）
    private static let tolerance = 0.05

    private let hotSpot: CGPoint
    private let size: CGSize
    private let opaque: [Bool]

    // grayAlpha はグレーと透明度の2バイトずつの並び。透明度だけを使う
    package init(hotSpot: CGPoint, size: CGSize, grayAlpha: [UInt8]) {
        self.hotSpot = hotSpot
        self.size = size
        opaque = stride(from: 1, to: grayAlpha.count, by: 2).map { grayAlpha[$0] > 127 }
    }

    package func matches(_ other: CursorShape) -> Bool {
        guard hotSpot == other.hotSpot, size == other.size, opaque.count == other.opaque.count else { return false }
        let filled = opaque.filter { $0 }.count
        guard filled > 0 else { return false }
        let differing = zip(opaque, other.opaque).filter { $0 != $1 }.count
        return Double(differing) / Double(filled) < Self.tolerance
    }

    // システム設定でポインタの色を変えると画像の色も変わるので、色ではなく形で見分ける
    package func classify(arrow: CursorShape, iBeam: CursorShape, pointingHand: CursorShape) -> CursorKind {
        if matches(arrow) { return .arrow }
        if matches(iBeam) { return .iBeam }
        if matches(pointingHand) { return .pointingHand }
        return .other
    }
}
