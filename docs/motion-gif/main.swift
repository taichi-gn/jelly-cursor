import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// README の見本のアニメーション用に、矢印と I 字を決まった道筋で動かし、フレームごとの頂点を JSON で出す（60fps）。
// 使い方は make.sh
func smooth(_ u: Double) -> Double { let t = min(max(u, 0), 1); return t * t * (3 - 2 * t) }

struct Segment {
    let duration: Double
    var pressed = false
    let path: (Double) -> CGPoint
}

// フレームごとの頂点（最後にマウス位置）と、ボタンを押しているか
func run(_ figure: CursorFigure, start: CGPoint, segments: [Segment]) -> (frames: [[[Double]]], pressed: [Bool]) {
    var frames: [[[Double]]] = [], pressed: [Bool] = []
    figure.step(to: start, dt: 0)
    let dt = 1.0 / 60
    for seg in segments {
        let n = Int((seg.duration / dt).rounded())
        for i in 1...n {
            let p = seg.path(Double(i) / Double(n))
            figure.step(to: p, dt: CGFloat(dt), pressed: seg.pressed)
            frames.append(figure.points.map { [Double($0.x), Double($0.y)] } + [[Double(p.x), Double(p.y)]])
            pressed.append(seg.pressed)
        }
    }
    return (frames, pressed)
}

func hold(_ p: CGPoint, _ seconds: Double) -> Segment { Segment(duration: seconds) { _ in p } }
func press(_ p: CGPoint, _ seconds: Double) -> Segment { Segment(duration: seconds, pressed: true) { _ in p } }

// 矢印: 右上へ弧を描いて速く動かし、止める（揺れて戻る）→ クリック → 左下へ戻して止める → クリック
let a0 = CGPoint(x: 70, y: 70), a1 = CGPoint(x: 290, y: 190)
let arrowSegments = [
    hold(a0, 0.5),
    Segment(duration: 0.55) { u in let e = smooth(u); return CGPoint(x: a0.x + (a1.x - a0.x) * e, y: a0.y + (a1.y - a0.y) * e + 45 * sin(.pi * u)) },
    hold(a1, 0.55), press(a1, 0.15), hold(a1, 0.4),
    Segment(duration: 0.55) { u in let e = smooth(u); return CGPoint(x: a1.x + (a0.x - a1.x) * e, y: a1.y + (a0.y - a1.y) * e - 45 * sin(.pi * u)) },
    hold(a0, 0.6), press(a0, 0.15), hold(a0, 0.55),
]
// I 字: 横に速く（太る）→ 止める（弾む）→ 斜めに（傾く）→ 縦に（伸びる）→ 止める → クリック
let b0 = CGPoint(x: 70, y: 130), b1 = CGPoint(x: 290, y: 130), b2 = CGPoint(x: 180, y: 50), b3 = CGPoint(x: 180, y: 200)
let beamSegments = [
    hold(b0, 0.5),
    Segment(duration: 0.4) { u in let e = smooth(u); return CGPoint(x: b0.x + (b1.x - b0.x) * e, y: b0.y) },
    hold(b1, 0.6),
    Segment(duration: 0.4) { u in let e = smooth(u); return CGPoint(x: b1.x + (b2.x - b1.x) * e, y: b1.y + (b2.y - b1.y) * e) },
    hold(b2, 0.5),
    Segment(duration: 0.35) { u in let e = smooth(u); return CGPoint(x: b2.x, y: b2.y + (b3.y - b2.y) * e) },
    Segment(duration: 0.55) { u in let e = smooth(u); return CGPoint(x: b3.x + (b0.x - b3.x) * e, y: b3.y + (b0.y - b3.y) * e) },
    hold(b0, 0.15), press(b0, 0.15), hold(b0, 0.4),
]
let scale: CGFloat = 2
let arrow = run(Jelly(scale: scale), start: a0, segments: arrowSegments)
let beam = run(IBeam(scale: scale), start: b0, segments: beamSegments)
let result: [String: Any] = [
    "arrow": arrow.frames, "arrowPressed": arrow.pressed,
    "ibeam": beam.frames, "ibeamPressed": beam.pressed,
    "border": Double(1 * scale),
]
let data = try JSONSerialization.data(withJSONObject: result)
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("arrow frames", (result["arrow"] as! [Any]).count, "ibeam frames", (result["ibeam"] as! [Any]).count)
