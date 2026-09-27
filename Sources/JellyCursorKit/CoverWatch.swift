import AppKit
import JellyCursorCore

// システムの警告ダイアログなどは、層の数値に関係なく JellyCursor の窓より手前に出る。
// その上では自前の絵が隠れて見えなくなるので、手前にある窓の範囲を覚えておき、ポインタが入ったら本物に任せる。
// 調べる処理は1回0.1ms（まれに数ms）かかるので、描画とは別の流れで間隔をあけて調べる
@MainActor
final class CoverWatch {
    // 左下原点の画面座標
    private var rects: [CGRect] = []
    private var timer: Timer?
    private var inFlight = false
    // 止めたときに増やし、止める前に出した問い合わせの結果を捨てる
    private var generation = 0
    var pointerScale: CGFloat = 1
    // JellyCursor の窓の番号。手前にある窓を調べる基準にする
    private var ourWindows: () -> [CGWindowID] = { [] }

    func start(windows: @escaping () -> [CGWindowID]) {
        ourWindows = windows
        let t = Timer(timeInterval: Tuning.Render.coverCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        rects = []
        inFlight = false
        generation += 1
    }

    func covers(_ point: CGPoint) -> Bool {
        rects.contains { $0.contains(point) }
    }

    private func refresh() {
        let ids = ourWindows()
        guard !inFlight, !ids.isEmpty else { return }
        inFlight = true
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ignoreUpTo = Tuning.Render.coverIgnoreSize * pointerScale
        let generation = self.generation
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let windows = ids.flatMap { WindowInfo.list([.optionOnScreenAboveWindow], relativeTo: $0) }
            let found = WindowInfo.coveringRects(windows, ours: Set(ids), primaryHeight: primaryHeight, ignoreUpTo: ignoreUpTo)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.rects = found
                    self.inFlight = false
                }
            }
        }
    }
}

extension WindowInfo {
    // CGWindowListCopyWindowInfo の1件から作る。窓番号や範囲が読めないものは nil
    init?(_ info: [String: Any]) {
        guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        self.init(number: number,
                  ownerPID: (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0,
                  layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                  alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                  bounds: rect)
    }

    // 窓の一覧を取る。1回0.1ms（まれに数ms）かかるので、主スレッドでは呼ばない
    static func list(_ option: CGWindowListOption, relativeTo window: CGWindowID) -> [WindowInfo] {
        let infos = CGWindowListCopyWindowInfo(option, window) as? [[String: Any]] ?? []
        return infos.compactMap(WindowInfo.init)
    }
}
