import AppKit

// システムの警告ダイアログなどは、層の数値に関係なく JellyCursor の窓より手前に出る。
// その上では自前の絵が隠れて見えなくなるので、手前にある窓の範囲を覚えておき、ポインタが入ったら本物に任せる。
// 調べる処理は1回0.1ms（まれに数ms）かかるので、描画とは別の流れで間隔をあけて調べる
@MainActor
final class CoverWatch {
    // 左下原点の画面座標
    private var rects: [CGRect] = []
    private var timer: Timer?
    private var inFlight = false
    private let ignoreUpTo = Tuning.Render.coverIgnoreSize * ArrowShape.systemPointerScale()

    func start(windows: @escaping () -> [CGWindowID]) {
        let t = Timer(timeInterval: Tuning.Render.coverCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(windows()) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        rects = []
    }

    func covers(_ point: CGPoint) -> Bool {
        rects.contains { $0.contains(point) }
    }

    private func refresh(_ ids: [CGWindowID]) {
        guard !inFlight, !ids.isEmpty else { return }
        inFlight = true
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ignoreUpTo = self.ignoreUpTo
        DispatchQueue.global(qos: .userInteractive).async {
            let infos = ids.flatMap { CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], $0) as? [[String: Any]] ?? [] }
            let found = Self.coveringRects(infos, ours: Set(ids), primaryHeight: primaryHeight, ignoreUpTo: ignoreUpTo)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.rects = found
                    self?.inFlight = false
                }
            }
        }
    }

    // 本物のカーソルが窓として手前に出ることがある（ダイアログが出てくる途中などに見えた）。
    // それを数えると、本物を出したとたん「手前に窓がある」ことになって戻れなくなるので、カーソルほどの小さな窓は数えない
    nonisolated static func coveringRects(_ infos: [[String: Any]], ours: Set<CGWindowID>,
                                          primaryHeight: CGFloat, ignoreUpTo: CGFloat) -> [CGRect] {
        infos.compactMap { w in
            guard let number = w[kCGWindowNumber as String] as? Int, !ours.contains(CGWindowID(number)),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > ignoreUpTo || rect.height > ignoreUpTo else { return nil }
            // 窓の一覧は左上原点なので、マウス位置と同じ左下原点に直す
            return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
    }
}
