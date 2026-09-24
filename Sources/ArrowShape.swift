import Foundation

struct ArrowShape {
    // 矢印の軸に沿った座標。axial は先端から後ろへの距離、lateral は軸から左への距離
    struct Vertex {
        let axial: CGFloat
        let lateral: CGFloat
    }

    // macOS 標準の矢印（倍率1）の黒い中身の輪郭。NSCursor.arrow の最高解像度の画像から読み取った。
    // 先端（ホットスポット）が原点で y は下向き
    private static let outline: [CGPoint] = [
        .init(x: 0, y: 0), .init(x: 8.25, y: 7.95), .init(x: 8.25, y: 8.65), .init(x: 7.85, y: 8.95),
        .init(x: 4.95, y: 9.05), .init(x: 6.85, y: 13.65), .init(x: 6.65, y: 14.25), .init(x: 6.15, y: 14.65),
        .init(x: 5.45, y: 14.65), .init(x: 4.85, y: 14.15), .init(x: 2.95, y: 9.75), .init(x: 0.85, y: 11.55),
        .init(x: 0.55, y: 11.55), .init(x: 0.05, y: 11.15),
    ]

    let vertices: [Vertex]
    // 元の矢印が向いている角度（重心から先端へ）
    let baseAngle: CGFloat
    // 先端からいちばん後ろの頂点までの軸方向の長さ
    let length: CGFloat
    let borderWidth: CGFloat

    init(scale: CGFloat = ArrowShape.systemPointerScale()) {
        let offsets = Self.subdividedOffsets(scale: scale)
        let cx = offsets.map(\.dx).reduce(0, +) / CGFloat(offsets.count)
        let cy = offsets.map(\.dy).reduce(0, +) / CGFloat(offsets.count)
        baseAngle = atan2(-cy, -cx)

        let axis = CGVector(dx: cos(baseAngle), dy: sin(baseAngle))
        vertices = offsets.map { o in
            Vertex(axial: -(o.dx * axis.dx + o.dy * axis.dy),
                   lateral: o.dx * -axis.dy + o.dy * axis.dx)
        }
        length = vertices.map(\.axial).max() ?? 1
        borderWidth = Tuning.Arrow.borderWidth * scale
    }

    // システム設定の「ポインタの大きさ」。起動時に読むだけなので、変えたらアプリの再起動が要る
    static func systemPointerScale() -> CGFloat {
        let value = UserDefaults(suiteName: "com.apple.universalaccess")?.double(forKey: "mouseDriverCursorSize") ?? 0
        return value >= 1 ? min(value, 4) : 1
    }

    // 辺を細かく区切り、曲げたときに折れ線の角が目立たないようにする
    private static func subdividedOffsets(scale: CGFloat) -> [CGVector] {
        var offsets: [CGVector] = []
        for i in outline.indices {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let n = max(1, Int((hypot(b.x - a.x, b.y - a.y) / Tuning.Arrow.vertexSpacing).rounded()))
            for j in 0..<n {
                let t = CGFloat(j) / CGFloat(n)
                offsets.append(CGVector(dx: (a.x + (b.x - a.x) * t) * scale,
                                        dy: -(a.y + (b.y - a.y) * t) * scale))
            }
        }
        return offsets
    }
}
