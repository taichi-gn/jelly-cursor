import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 画面に描くカーソル。毎フレーム動かし、落ち着いたかを返す。pressed はマウスのボタンを押しているか
package protocol Figure: AnyObject {
    var isSettled: Bool { get }
    func step(to mouse: CGPoint, dt: CGFloat, pressed: Bool)
}

extension Figure {
    package func step(to mouse: CGPoint, dt: CGFloat) {
        step(to: mouse, dt: dt, pressed: false)
    }
}

// 輪郭を変形させて描くもの。矢印（Jelly）と I 字（IBeam）
package protocol CursorFigure: Figure {
    var points: [CGPoint] { get }
    var borderWidth: CGFloat { get }
}

extension CursorFigure {
    package var bounds: CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .null
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
