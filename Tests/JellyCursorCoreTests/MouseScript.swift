import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import JellyCursorCore

// 動きの丈夫さを確かめるための、決まったマウスの動き。フレームごとの位置と、前のフレームからの秒数
struct ScriptFrame {
    let mouse: CGPoint
    let dt: CGFloat
}

// 種を決めると毎回同じ列になる乱数
struct SeededRandom {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1
    }

    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(state >> 11) / CGFloat(1 << 53)
    }
}

enum MouseScript {
    // 左右に振る。振り始めの 0.2 秒で大きくし、上下にも drift だけゆれる
    static func shake(amplitude: CGFloat, frequency: CGFloat, rate: CGFloat, seconds: CGFloat = 1.5,
                      drift: CGFloat = 8) -> [ScriptFrame] {
        var frames = [ScriptFrame(mouse: CGPoint(x: 500, y: 500), dt: 0)]
        let dt = 1 / rate
        var t: CGFloat = 0
        while t < seconds {
            t += dt
            let x = amplitude * min(t / 0.2, 1) * sin(2 * .pi * frequency * t)
            frames.append(ScriptFrame(mouse: CGPoint(x: 500 + x, y: 500 + drift * sin(2 * .pi * 1.3 * t)), dt: dt))
        }
        return frames
    }

    // 手で動かすような、でたらめな動き。止まる・ゆっくり・速い（最大 6000pt/秒）を混ぜ、
    // 速さはなめらかに（約0.03秒で）変わる
    static func wander(seed: Int, rate: CGFloat, seconds: CGFloat = 4) -> [ScriptFrame] {
        var random = SeededRandom(seed: seed)
        var mouse = CGPoint(x: 500, y: 500), velocity = CGVector.zero, target = CGVector.zero
        var frames = [ScriptFrame(mouse: mouse, dt: 0)]
        let dt = 1 / rate
        var t: CGFloat = 0, retarget: CGFloat = 0
        while t < seconds {
            t += dt
            if t >= retarget {
                let speed = random.next() < 0.25 ? 0 : random.next() < 0.3 ? 2500 + random.next() * 3500 : random.next() * 2000
                let angle = random.next() * 2 * .pi
                target = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
                retarget = t + 0.08 + random.next() * 0.5
            }
            let k = 1 - exp(-dt / 0.03)
            velocity.dx += (target.dx - velocity.dx) * k
            velocity.dy += (target.dy - velocity.dy) * k
            mouse.x += velocity.dx * dt
            mouse.y += velocity.dy * dt
            frames.append(ScriptFrame(mouse: mouse, dt: dt))
        }
        return frames
    }

    // ふつうの手では起きない乱暴な動き。向きと速さ（最大 8000pt/秒）が一瞬で変わり、ときどき画面の端まで飛ぶ。
    // フレームの間隔もばらつき、0 秒や、表示が詰まったときの 1/30 秒も混ぜる
    static func erratic(seed: Int, rate: CGFloat, segments: Int = 30) -> [ScriptFrame] {
        var random = SeededRandom(seed: seed)
        var mouse = CGPoint(x: 500, y: 500)
        var frames = [ScriptFrame(mouse: mouse, dt: 0)]
        for _ in 0..<segments {
            let still = random.next() < 0.3
            let duration = 0.05 + random.next() * 0.5
            let speed = random.next() < 0.3 ? 3000 + random.next() * 5000 : random.next() * 2500
            let angle = random.next() * 2 * .pi, curve = (random.next() - 0.5) * 14
            if random.next() < 0.1 {
                mouse = CGPoint(x: random.next() * 5000, y: random.next() * 3000)
            }
            var elapsed: CGFloat = 0
            while elapsed < duration {
                var dt = (0.8 + 0.4 * random.next()) / rate
                let roll = random.next()
                if roll < 0.03 { dt = 0 } else if roll < 0.06 { dt = 1.0 / 30 }
                elapsed += dt
                if !still {
                    let a = angle + curve * elapsed
                    mouse.x += cos(a) * speed * dt
                    mouse.y += sin(a) * speed * dt
                }
                frames.append(ScriptFrame(mouse: mouse, dt: dt))
            }
        }
        return frames
    }
}

// 輪郭が自分と交差してできた輪のうち、いちばん大きいものの面積（px²）。
// 交差した2辺で輪郭を2つに分け、小さいほうの面積を見る。重なっていなければ 0
func overlapArea(_ points: [CGPoint]) -> CGFloat {
    let n = points.count
    func side(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
    func area(_ loop: ArraySlice<CGPoint>) -> CGFloat {
        let q = Array(loop)
        var sum: CGFloat = 0
        for k in q.indices {
            let u = q[k], w = q[(k + 1) % q.count]
            sum += u.x * w.y - w.x * u.y
        }
        return abs(sum) / 2
    }
    // 辺を囲む四角が重ならない組は、交わらないので先に外す（試験を速くするため）
    let boxes = (0..<n).map { i -> (CGFloat, CGFloat, CGFloat, CGFloat) in
        let a = points[i], b = points[(i + 1) % n]
        return (min(a.x, b.x), max(a.x, b.x), min(a.y, b.y), max(a.y, b.y))
    }
    var worst: CGFloat = 0
    for i in 0..<n {
        let a = points[i], b = points[(i + 1) % n]
        for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
            guard boxes[i].0 <= boxes[j].1, boxes[j].0 <= boxes[i].1, boxes[i].2 <= boxes[j].3, boxes[j].2 <= boxes[i].3 else {
                continue
            }
            let c = points[j], d = points[(j + 1) % n]
            let d1 = side(c, d, a), d2 = side(c, d, b), d3 = side(a, b, c), d4 = side(a, b, d)
            guard (d1 > 0) != (d2 > 0), d1 != 0, d2 != 0, (d3 > 0) != (d4 > 0), d3 != 0, d4 != 0 else { continue }
            let inner = area(points[(i + 1)...j])
            let outer = area(points[(j + 1)...] + points[...i])
            worst = max(worst, min(inner, outer))
        }
    }
    return worst
}

// 1フレームのうちに、マウスの動きを差し引いて、頂点がいちばん大きく動いた距離（px）
func frameJump(from previous: [CGPoint], to current: [CGPoint], mouseMoved: CGVector) -> CGFloat {
    var worst: CGFloat = 0
    for (p, q) in zip(previous, current) {
        let dx: CGFloat = q.x - p.x - mouseMoved.dx
        let dy: CGFloat = q.y - p.y - mouseMoved.dy
        worst = max(worst, hypot(dx, dy))
    }
    return worst
}
