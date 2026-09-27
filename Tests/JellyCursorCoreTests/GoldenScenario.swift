import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 動きの記録に使う、決まったマウスの動き。フレームごとに (マウス位置, 前のフレームからの秒数) を返す
enum GoldenScenario {
    struct Frame {
        let mouse: CGPoint
        let dt: CGFloat
    }

    static func frames() -> [Frame] {
        var frames: [Frame] = [Frame(mouse: CGPoint(x: 200, y: 300), dt: 0)]
        var t: CGFloat = 0
        var mouse = CGPoint(x: 200, y: 300)
        func hold(_ seconds: CGFloat, dt: CGFloat = 1.0 / 120) {
            var elapsed: CGFloat = 0
            while elapsed < seconds - 1e-9 {
                elapsed += dt; t += dt
                frames.append(Frame(mouse: mouse, dt: dt))
            }
        }
        func move(_ seconds: CGFloat, dt: CGFloat = 1.0 / 120, _ path: (CGFloat) -> CGPoint) {
            var elapsed: CGFloat = 0
            while elapsed < seconds - 1e-9 {
                elapsed += dt; t += dt
                mouse = path(min(elapsed / seconds, 1))
                frames.append(Frame(mouse: mouse, dt: dt))
            }
        }
        // 右上へ弧を描いて速く動かし、止める（1回行き過ぎて戻る）
        let a = mouse
        move(0.5) { u in
            let e = u * u * (3 - 2 * u)
            return CGPoint(x: a.x + 600 * e, y: a.y + 150 * sin(.pi * u))
        }
        hold(0.9)
        // 眠っている間のタイマーの間隔で見た小さな手ぶれ（回らない）
        let b = mouse
        move(0.2, dt: 1.0 / 60) { u in CGPoint(x: b.x + 2 * sin(u * 12), y: b.y + 1.5 * cos(u * 9) - 1.5) }
        hold(0.5)
        // 左へ速く動かしてすぐ上へ折り返し、途中で1回だけ間延びしたフレームを挟む
        let c = mouse
        move(0.3) { u in CGPoint(x: c.x - 500 * u, y: c.y - 20 * u) }
        frames.append(Frame(mouse: mouse, dt: 1.0 / 30))
        let d = mouse
        move(0.2) { u in CGPoint(x: d.x + 30 * u, y: d.y + 260 * u) }
        hold(0.8)
        // 真下へ動き出す（指は上向きなので、ほぼ逆向き）
        let e = mouse
        move(0.35) { u in CGPoint(x: e.x + 3 * sin(u * 20), y: e.y - 400 * u) }
        hold(0.8)
        // 斜め（右上・左下）と縦にゆっくり
        let f = mouse
        move(0.4) { u in CGPoint(x: f.x + 300 * u, y: f.y + 300 * u) }
        hold(0.4)
        let g = mouse
        move(0.6) { u in CGPoint(x: g.x - 80 * u, y: g.y - 90 * u * u) }
        hold(0.7)
        return frames
    }
}
