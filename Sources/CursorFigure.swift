import CoreGraphics
import QuartzCore

// 画面に描くカーソル。毎フレーム動かし、落ち着いたかを返す
protocol Figure: AnyObject {
    var isSettled: Bool { get }
    func step(to mouse: CGPoint, dt: CGFloat)
}

// 輪郭を変形させて描くもの。矢印（Jelly）と I 字（IBeam）
protocol CursorFigure: Figure {
    var points: [CGPoint] { get }
    var borderWidth: CGFloat { get }
}

extension CursorFigure {
    var bounds: CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .null
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

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
