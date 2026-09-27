import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

@Suite struct WindowInfoTests {
    // 1枚目の画面は 1440×900
    private let primaryHeight: CGFloat = 900

    @Test func coveringRectsSkipOursTransparentAndCursorSized() {
        let windows = [
            WindowInfo(number: 1, bounds: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            WindowInfo(number: 2, alpha: 0, bounds: CGRect(x: 100, y: 100, width: 300, height: 200)),
            WindowInfo(number: 3, bounds: CGRect(x: 500, y: 100, width: 40, height: 40)),
            WindowInfo(number: 4, bounds: CGRect(x: 600, y: 100, width: 300, height: 200)),
            WindowInfo(number: 5, bounds: CGRect(x: 700, y: 50, width: 10, height: 60)),
        ]
        let rects = WindowInfo.coveringRects(windows, ours: [1], primaryHeight: primaryHeight, ignoreUpTo: 48)
        // 左上原点の y=100・高さ200 は、左下原点では y=600
        #expect(rects == [CGRect(x: 600, y: 600, width: 300, height: 200), CGRect(x: 700, y: 790, width: 10, height: 60)])
    }

    @Test func cursorSizedWindowsScaleWithPointer() {
        let windows = [WindowInfo(number: 3, bounds: CGRect(x: 500, y: 100, width: 80, height: 80))]
        #expect(WindowInfo.coveringRects(windows, ours: [], primaryHeight: primaryHeight, ignoreUpTo: 48).count == 1)
        #expect(WindowInfo.coveringRects(windows, ours: [], primaryHeight: primaryHeight, ignoreUpTo: 96).isEmpty)
    }

    private let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    private let menuBar = WindowInfo(number: 90, layer: 24, bounds: CGRect(x: 0, y: 0, width: 1440, height: 24))

    @Test func detectsFullScreenWindow() {
        let full = WindowInfo(number: 10, ownerPID: 42, bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(WindowInfo.isFullScreen([full], pid: 42, screens: [screen], primaryHeight: 900, menuBarLayer: 24))
        // 別のアプリの窓や、ふつうの層でない窓は数えない
        #expect(!WindowInfo.isFullScreen([full], pid: 7, screens: [screen], primaryHeight: 900, menuBarLayer: 24))
        var floating = full
        floating.layer = 3
        #expect(!WindowInfo.isFullScreen([floating], pid: 42, screens: [screen], primaryHeight: 900, menuBarLayer: 24))
    }

    @Test func menuBarMeansNotFullScreen() {
        let full = WindowInfo(number: 10, ownerPID: 42, bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(!WindowInfo.isFullScreen([full, menuBar], pid: 42, screens: [screen], primaryHeight: 900, menuBarLayer: 24))
    }

    @Test func zoomedWindowIsNotFullScreen() {
        let zoomed = WindowInfo(number: 10, ownerPID: 42, bounds: CGRect(x: 0, y: 24, width: 1440, height: 876))
        #expect(!WindowInfo.isFullScreen([zoomed, menuBar], pid: 42, screens: [screen], primaryHeight: 900, menuBarLayer: 24))
        #expect(!WindowInfo.isFullScreen([zoomed], pid: 42, screens: [screen], primaryHeight: 900, menuBarLayer: 24))
    }

    // ノッチのある画面では、全画面の窓はノッチの下から下端まで
    @Test func notchedScreen() {
        let notched = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 38)
        let below = WindowInfo(number: 10, ownerPID: 42, bounds: CGRect(x: 0, y: 38, width: 1512, height: 944))
        #expect(WindowInfo.isFullScreen([below], pid: 42, screens: [notched], primaryHeight: 982, menuBarLayer: 24))
        let bar = WindowInfo(number: 90, layer: 24, bounds: CGRect(x: 0, y: 0, width: 1512, height: 38))
        #expect(!WindowInfo.isFullScreen([below, bar], pid: 42, screens: [notched], primaryHeight: 982, menuBarLayer: 24))
    }

    // 2枚目の画面（1枚目の右、上端をそろえて置いた 1920×1080）での全画面
    @Test func secondScreen() {
        let second = ScreenInfo(frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080))
        let full = WindowInfo(number: 10, ownerPID: 42, bounds: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        let firstBar = menuBar
        #expect(WindowInfo.isFullScreen([full, firstBar], pid: 42, screens: [screen, second], primaryHeight: 900,
                                        menuBarLayer: 24))
    }
}
