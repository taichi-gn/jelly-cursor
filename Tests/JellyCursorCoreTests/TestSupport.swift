import Foundation
@testable import JellyCursorCore

// 120Hz で直線に動かしてから止める。止めたあとのフレーム数も指定する
func drive(_ figure: Figure, from a: CGPoint, to b: CGPoint, seconds: CGFloat, holdFrames: Int = 0) {
    let dt: CGFloat = 1.0 / 120
    figure.step(to: a, dt: 0)
    let n = Int((seconds / dt).rounded())
    for i in 1...n {
        let u = CGFloat(i) / CGFloat(n)
        figure.step(to: CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u), dt: dt)
    }
    for _ in 0..<holdFrames { figure.step(to: b, dt: dt) }
}

// 矢印の先端（マウス位置）からいちばん遠い頂点までの距離
func reach(_ figure: CursorFigure, from mouse: CGPoint) -> CGFloat {
    figure.points.map { hypot($0.x - mouse.x, $0.y - mouse.y) }.max() ?? 0
}

// 頂点の重心がマウスから見てどの向きにあるか（ラジアン）
func bodyAngle(_ figure: CursorFigure, from mouse: CGPoint) -> CGFloat {
    let n = CGFloat(figure.points.count)
    let cx = figure.points.map(\.x).reduce(0, +) / n - mouse.x
    let cy = figure.points.map(\.y).reduce(0, +) / n - mouse.y
    return atan2(cy, cx)
}
