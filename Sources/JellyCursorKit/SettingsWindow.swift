import AppKit
import JellyCursorCore
import Observation
import SwiftUI

// 設定画面の窓。中身は SwiftUI で作り、窓は AppKit で持つ。
// SwiftUI の Settings と MenuBarExtra は、macOS 26 で設定画面が前面に出ない・開かないことがあるので使わない
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let state: AppState
    private let actions: AppActions
    private let navigation = SettingsNavigation()
    private let recorder: KeyRecorder
    // 設定画面を開く前に前面にあったアプリ。閉じたらそこへ戻す
    private let previousApp: () -> AppIdentity?
    private var window: NSWindow?

    init(settings: AppSettings, state: AppState, actions: AppActions, previousApp: @escaping () -> AppIdentity?) {
        self.settings = settings
        self.state = state
        self.actions = actions
        self.previousApp = previousApp
        recorder = KeyRecorder(onRecordingChange: actions.suspendShortcut)
    }

    // メニューバーだけのアプリ（.accessory）のままだと前面に出せないので、開いている間だけふつうのアプリにする
    // welcome が true なら、一般タブの上に、はじめて使う人向けの案内を出す
    func show(tab: SettingsTab? = nil, welcome: Bool = false) {
        if let tab { navigation.tab = tab }
        if welcome { navigation.showsWelcome = true }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        // Dock のアイコンは、ふつうのアプリになってから渡さないと空のアイコンのままになる（macOS 26 で確認）
        NSApp.applicationIconImage = AppIconImage.make()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // メニューバーだけのアプリに戻す。窓が無くても JellyCursor が前面に残ってキー入力を受け取れなくなるので、
    // 開く前に使っていたアプリへ前面を返す
    func windowWillClose(_ notification: Notification) {
        recorder.stop()
        // 案内は閉じるボタンで消さなくても、次に開いたときには出さない
        navigation.showsWelcome = false
        NSApp.setActivationPolicy(.accessory)
        guard let id = previousApp()?.bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { return }
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }

    // ほかのアプリへ移ったら、ショートカットの記録をやめて元に戻す
    func windowDidResignKey(_ notification: Notification) {
        recorder.stop()
    }

    // タブの切り替えは SwiftUI が作り直すことがあるので、前面になるたびに枠を消し直す
    func windowDidBecomeKey(_ notification: Notification) {
        if let view = window?.contentView { Self.hideTabFocusRing(in: view) }
    }

    // タブを選んだあとに少し遅れて出る、キーボード操作用の青い枠（フォーカスの枠）を出さない。
    // システム設定の「キーボードナビゲーション」がオンのときに出る。タブの中の項目の枠はそのまま残す
    private static func hideTabFocusRing(in view: NSView) {
        for subview in view.subviews {
            if subview is NSSegmentedControl || subview is NSTabView {
                subview.focusRingType = .none
            }
            hideTabFocusRing(in: subview)
        }
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(settings: settings, state: state, actions: actions, navigation: navigation,
                                recorder: recorder)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        // 中身の大きさが決まってから真ん中に置く。先に置くと、あとで広がったぶん画面の右や上にはみ出す
        window.setContentSize(controller.view.fittingSize)
        window.center()
        if let view = window.contentView { Self.hideTabFocusRing(in: view) }
        followTabTitle(of: window)
        return window
    }

    // 窓のタイトルを今開いているタブの名前にする（設定の窓のタイトルは、表示しているパネルに合わせる。Apple の HIG）
    private func followTabTitle(of window: NSWindow) {
        withObservationTracking {
            window.title = navigation.tab.title
        } onChange: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window else { return }
                self.followTabTitle(of: window)
            }
        }
    }
}
