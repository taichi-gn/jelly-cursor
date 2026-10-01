import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 直近のマウス位置を時刻つきで覚え、「先端から s px 後ろ」の位置を返す。
// length は直近 Tuning.Trail.duration 秒に動いた道のり（伸びの量に使う）。道の形は、それより古いところも
// 先端から keep px まで（ただし Tuning.Trail.keepTime 秒まで）覚えておく（胴体がその秒数に動いた道のりより長いときに、
// 後ろのほうも実際に通った道に沿わせるため）
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
    // 覚えている道の形の長さ（length 以上、keep 付近まで）
    private(set) var pathLength: CGFloat = 0
    private let keep: CGFloat

    init(keep: CGFloat = 0) {
        self.keep = keep
    }

    mutating func record(_ mouse: CGPoint, dt: CGFloat) {
        clock += dt
        if let last = samples.last, last.time == clock {
            samples[samples.count - 1] = Sample(time: clock, point: mouse)
        } else {
            samples.append(Sample(time: clock, point: mouse))
        }
        let cutoff = clock - Tuning.Trail.duration
        let used = rebuildPolyline(cutoff: cutoff)
        // 覚える時間より古く、道の形にも使わないものは捨てる（時間の境の補間に使う1つは残す）
        let drop = min(used, samples.lastIndex { $0.time <= cutoff } ?? 0)
        if drop > 0 { samples.removeFirst(drop) }
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

    // 覚えている道の古い端での「さらに古い方へ」の向き。道が短すぎれば nil
    func tailDirection(window: CGFloat) -> CGVector? {
        guard pathLength > 0.5 else { return nil }
        let a = point(at: max(pathLength - window, 0)), b = point(at: pathLength)
        let d = hypot(b.x - a.x, b.y - a.y)
        guard d > 0.0001 else { return nil }
        return CGVector(dx: (b.x - a.x) / d, dy: (b.y - a.y) / d)
    }

    // 道の折り返し。先端からの道のり
    struct Fold {
        let distance: CGFloat
    }

    // 先端から道をたどり、先端近くの向きから Fold.angle より大きく曲がった（折り返した）ところ。
    // 先端近くの向きは、先端から Fold.reference px 後ろの点への向き。手ぶれで折り返しと見ないよう、
    // それより短い道や、先端のすぐ後ろで向きが定まらない道では nil
    func fold() -> Fold? {
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
            let cosine = (sx * rx + sy * ry) / (hypot(sx, sy) * rl)
            guard cosine < limit else { continue }
            // 曲がった角度は、折り返しから reference px 先までの向きで測り直す。折り返した瞬間にできるごく短い区間の
            // 向きはでたらめなので、それだけで見ると、折り返していないのに折り返したとみなしたり、角度を見誤ったりする
            let a = polyline[i - 1], b = point(at: distances[i - 1] + reference)
            let bx = b.x - a.x, by = b.y - a.y, bl = hypot(bx, by)
            let measured = bl > reference / 2 ? (bx * rx + by * ry) / (bl * rl) : cosine
            if measured < limit { return Fold(distance: distances[i - 1]) }
        }
        return nil
    }

    // 新しい順の折れ線を作り直す。時間の境（cutoff）の位置を補間して入れ、そこまでの道のりを length にする。
    // その先は、keep px に届くまで古い点を足す。返すのは、使ったいちばん古い点の番号
    private mutating func rebuildPolyline(cutoff: CGFloat) -> Int {
        polyline.removeAll(keepingCapacity: true)
        distances.removeAll(keepingCapacity: true)
        var windowLength: CGFloat?
        var oldest = samples.count - 1
        func append(_ p: CGPoint) {
            if let last = polyline.last {
                let d = hypot(p.x - last.x, p.y - last.y)
                guard d > 0 else { return }
                distances.append(distances[distances.count - 1] + d)
            } else {
                distances.append(0)
            }
            polyline.append(p)
        }
        for i in stride(from: samples.count - 1, through: 0, by: -1) {
            if windowLength == nil && samples[i].time < cutoff {
                // 覚える時間ちょうどの位置を補間し、止めたときに長さがなめらかに縮むようにする
                if i + 1 < samples.count {
                    let a = samples[i], b = samples[i + 1]
                    let t = (cutoff - a.time) / (b.time - a.time)
                    append(CGPoint(x: a.point.x + (b.point.x - a.point.x) * t, y: a.point.y + (b.point.y - a.point.y) * t))
                }
                windowLength = distances.last ?? 0
                if (distances.last ?? 0) >= keep && !polyline.isEmpty { break }
            }
            if windowLength != nil && samples[i].time < clock - Tuning.Trail.keepTime && !polyline.isEmpty { break }
            append(samples[i].point)
            oldest = i
            if windowLength != nil && (distances.last ?? 0) >= keep { break }
        }
        length = windowLength ?? distances.last ?? 0
        pathLength = distances.last ?? 0
        return oldest
    }
}
