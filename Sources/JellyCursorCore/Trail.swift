import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 直近のマウス位置を時刻つきで覚え、「先端から s px 後ろ」の位置を返す
struct Trail {
    private struct Sample {
        let time: CGFloat
        let point: CGPoint
    }

    private var samples: [Sample] = []
    private var clock: CGFloat = 0
    // 新しい順の折れ線と、先端からの累積距離
    private var polyline: [CGPoint] = []
    private var distances: [CGFloat] = []

    private(set) var length: CGFloat = 0

    mutating func record(_ mouse: CGPoint, dt: CGFloat) {
        clock += dt
        if let last = samples.last, last.time == clock {
            samples[samples.count - 1] = Sample(time: clock, point: mouse)
        } else {
            samples.append(Sample(time: clock, point: mouse))
        }
        // 覚える時間より古いものは、補間に使う1つだけ残す
        let cutoff = clock - Tuning.Trail.duration
        while samples.count >= 2 && samples[1].time <= cutoff {
            samples.removeFirst()
        }
        rebuildPolyline(cutoff: cutoff)
    }

    func point(at s: CGFloat) -> CGPoint {
        guard let first = polyline.first else { return .zero }
        guard s > 0 else { return first }
        // 長さ0の区間は作らないので、区間の長さで割ってよい
        for i in 1..<polyline.count where s <= distances[i] {
            let a = polyline[i - 1], b = polyline[i]
            let t = (s - distances[i - 1]) / (distances[i] - distances[i - 1])
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return polyline[polyline.count - 1]
    }

    // 古い端での「さらに古い方へ」の向き。道が短すぎれば nil
    func tailDirection(window: CGFloat) -> CGVector? {
        guard length > 0.5 else { return nil }
        let a = point(at: max(length - window, 0)), b = point(at: length)
        let d = hypot(b.x - a.x, b.y - a.y)
        guard d > 0.0001 else { return nil }
        return CGVector(dx: (b.x - a.x) / d, dy: (b.y - a.y) / d)
    }

    private mutating func rebuildPolyline(cutoff: CGFloat) {
        polyline.removeAll(keepingCapacity: true)
        distances.removeAll(keepingCapacity: true)
        for i in stride(from: samples.count - 1, through: 0, by: -1) {
            var p = samples[i].point
            // 覚える時間ちょうどの位置を補間し、止めたときに長さがなめらかに縮むようにする
            if samples[i].time < cutoff && i + 1 < samples.count {
                let a = samples[i], b = samples[i + 1]
                let t = (cutoff - a.time) / (b.time - a.time)
                p = CGPoint(x: a.point.x + (b.point.x - a.point.x) * t, y: a.point.y + (b.point.y - a.point.y) * t)
            }
            if let last = polyline.last {
                let d = hypot(p.x - last.x, p.y - last.y)
                guard d > 0 else { continue }
                distances.append(distances[distances.count - 1] + d)
            } else {
                distances.append(0)
            }
            polyline.append(p)
        }
        length = distances.last ?? 0
    }
}
