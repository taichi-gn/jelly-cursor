import Foundation

// 画面に出ている窓1つの情報（CGWindowListCopyWindowInfo の1件）。bounds は窓の一覧と同じ左上原点の座標
package struct WindowInfo: Equatable, Sendable {
    package var number: UInt32
    package var ownerPID: Int32
    package var layer: Int
    package var alpha: Double
    package var bounds: CGRect

    package init(number: UInt32, ownerPID: Int32 = 0, layer: Int = 0, alpha: Double = 1, bounds: CGRect) {
        self.number = number
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }

    // 窓の一覧は左上原点なので、マウス位置や NSScreen と同じ左下原点に直す。primaryHeight は1枚目の画面の高さ
    package func appKitBounds(primaryHeight: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    // JellyCursor の窓より手前にある窓の範囲（左下原点）。
    // 本物のカーソルが窓として手前に出ることがある（ダイアログが出てくる途中などに見えた）。
    // それを数えると、本物を出したとたん「手前に窓がある」ことになって戻れなくなるので、カーソルほどの小さな窓は数えない
    package static func coveringRects(_ windows: [WindowInfo], ours: Set<UInt32>,
                                      primaryHeight: CGFloat, ignoreUpTo: CGFloat) -> [CGRect] {
        windows.compactMap { w in
            guard !ours.contains(w.number), w.alpha > 0,
                  w.bounds.width > ignoreUpTo || w.bounds.height > ignoreUpTo else { return nil }
            return w.appKitBounds(primaryHeight: primaryHeight)
        }
    }

    // 前面のアプリ（pid）が全画面で動いているか。
    // そのアプリのふつうの層の窓が、どれかの画面いっぱい（ノッチのある画面ではノッチの下から下端まで）を覆っていて、
    // その画面にメニューバーが出ていなければ全画面とみなす。メニューバーを見るのは、
    // メニューバーを隠す設定で最大化した窓と見分けるため
    package static func isFullScreen(_ windows: [WindowInfo], pid: Int32, screens: [ScreenInfo],
                                     primaryHeight: CGFloat, menuBarLayer: Int) -> Bool {
        screens.contains { screen in
            let full = screen.frame
            var belowNotch = full
            belowNotch.size.height -= screen.safeAreaTop
            let covered = windows.contains { w in
                guard w.ownerPID == pid, w.layer == 0, w.alpha > 0 else { return false }
                let r = w.appKitBounds(primaryHeight: primaryHeight)
                return r.isClose(to: full) || (screen.safeAreaTop > 0 && r.isClose(to: belowNotch))
            }
            guard covered else { return false }
            // 上端の帯。隣の画面のメニューバーと縁が接しただけで重なった扱いにならないよう、左右を 1pt 内側にする
            let topEdge = CGRect(x: full.minX + 1, y: full.maxY - 1, width: full.width - 2, height: 1)
            let menuBarShown = windows.contains { w in
                w.layer == menuBarLayer && w.alpha > 0 && w.appKitBounds(primaryHeight: primaryHeight).intersects(topEdge)
            }
            return !menuBarShown
        }
    }
}

// 画面1枚。frame は左下原点、safeAreaTop はノッチの分の高さ（無ければ 0）
package struct ScreenInfo: Equatable, Sendable {
    package var frame: CGRect
    package var safeAreaTop: CGFloat

    package init(frame: CGRect, safeAreaTop: CGFloat = 0) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
    }
}

private extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
