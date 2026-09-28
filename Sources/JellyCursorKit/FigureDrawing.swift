import AppKit
import JellyCursorCore

extension CursorFigure {
    func path(offsetBy offset: CGVector) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.x + offset.dx, y: $0.y + offset.dy) })
        path.closeSubpath()
        return path
    }
}

// 本物のカーソルの画像を、クリック位置を軸に回したり伸ばしたりして描くもの。指（PointingHand）
protocol ImageFigure: Figure {
    var image: CGImage? { get }
    var size: CGSize { get }
    // クリック位置。画像の左下を (0,0)、右上を (1,1) とした位置
    var anchor: CGPoint { get }
    var position: CGPoint { get }
    var transform: CATransform3D { get }
}

extension ImageFigure {
    // 回して伸ばしたあとの画像を囲む範囲
    var bounds: CGRect {
        CGRect(x: -anchor.x * size.width, y: -anchor.y * size.height, width: size.width, height: size.height)
            .applying(CATransform3DGetAffineTransform(transform))
            .offsetBy(dx: position.x, dy: position.y)
    }
}

// カーソルの画像とクリック位置。NSCursor は主スレッドで読むので、読んだ結果をこの形で渡す
struct CursorImage {
    let image: CGImage?
    // ポイント単位の大きさ
    let size: CGSize
    // 左上から数えたクリック位置
    let hotSpot: CGPoint

    @MainActor
    init(_ cursor: NSCursor) {
        size = cursor.image.size
        hotSpot = cursor.hotSpot
        guard size.width > 0, size.height > 0 else {
            image = nil
            return
        }
        // 大きく描いても粗くならないよう、4倍の解像度で取る
        var rect = CGRect(x: 0, y: 0, width: size.width * 4, height: size.height * 4)
        image = cursor.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
