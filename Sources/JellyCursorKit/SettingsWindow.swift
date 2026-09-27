import AppKit
import JellyCursorCore
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
    private var window: NSWindow?

    init(settings: AppSettings, state: AppState, actions: AppActions) {
        self.settings = settings
        self.state = state
        self.actions = actions
        recorder = KeyRecorder(onRecordingChange: actions.suspendShortcut)
    }

    // メニューバーだけのアプリ（.accessory）のままだと前面に出せないので、開いている間だけふつうのアプリにする
    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stop()
        NSApp.setActivationPolicy(.accessory)
    }

    // ほかのアプリへ移ったら、ショートカットの記録をやめて元に戻す
    func windowDidResignKey(_ notification: Notification) {
        recorder.stop()
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(settings: settings, state: state, actions: actions, navigation: navigation,
                                recorder: recorder)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "JellyCursor の設定"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        // 中身の大きさが決まってから真ん中に置く。先に置くと、あとで広がったぶん画面の右や上にはみ出す
        window.setContentSize(controller.view.fittingSize)
        window.center()
        return window
    }
}
