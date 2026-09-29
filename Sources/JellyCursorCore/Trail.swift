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

    // 先端から道をたどり、先端近くの向きから Fold.angle より大きく曲がった（折り返した）ところまでの道のり。
    // 先端近くの向きは、先端から Fold.reference px 後ろの点への向き。手ぶれで折り返しと見ないよう、
    // それより短い道や、先端のすぐ後ろで向きが定まらない道では nil
    func foldDistance() -> CGFloat? {
        let reference = Tuning.Fold.reference
        guard polyline.count >= 3, length > reference else { return nil }
        let tip = polyline[0], ref = point(at: reference)
        let rx = ref.x - tip.x, ry = ref.y - tip.y
        let rl = hypot(rx, ry)
        guard rl > reference / 2 else { return nil }
        let limit = cos(Tuning.Fold.angle)
        for i in 1..<polyline.count where distances[i] > reference {
            let sx = polyline[i].x - polyline[i - 1].x, sy = polyline[i].y - polyline[i - 1].y
            // 長さ0の区間は作らないので、区間の長さで割ってよい
            if (sx * rx + sy * ry) / (hypot(sx, sy) * rl) < limit { return distances[i - 1] }
        }
        return nil
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
