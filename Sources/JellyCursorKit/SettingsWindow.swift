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
    private var window: NSWindow?

    init(settings: AppSettings, state: AppState, actions: AppActions) {
        self.settings = settings
        self.state = state
        self.actions = actions
    }

    // メニューバーだけのアプリ（.accessory）のままだと前面に出せないので、開いている間だけふつうのアプリにする
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(settings: settings, state: state, actions: actions)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "JellyCursor の設定"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}
