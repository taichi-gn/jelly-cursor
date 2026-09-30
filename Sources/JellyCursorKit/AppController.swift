import AppKit
import JellyCursorCore
import ServiceManagement

// アプリ全体の流れ。設定と Mac の状態から描くかどうかを決め（Activity）、描くのは CursorEngine に任せる
@MainActor
package final class AppController: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let state = AppState()
    private let system = SystemMonitor()
    private let hotKey = HotKey()
    private var engine: CursorEngine?
    private var statusMenu: StatusMenu?
    private var signalSources: [DispatchSourceSignal] = []
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, state: state, actions: actions, previousApp: { [weak self] in self?.system.lastOtherApp })

    package override init() {
        super.init()
    }

    private var actions: AppActions {
        AppActions(
            setEnabled: { [weak self] in self?.setEnabled($0) },
            suspendShortcut: { [weak self] in self?.suspendShortcut($0) })
    }

    package func applicationDidFinishLaunching(_ notification: Notification) {
        quitOtherInstances()
        // Shift を押しながら起動したら、何も隠さずに止めた状態で始める（おかしくなったときの逃げ道）
        state.safeMode = NSEvent.modifierFlags.contains(.shift)
        state.canHideCursor = RealCursor.allowBackgroundControl()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "開発版"
        AppLog.notice("起動 \(version) セーフモード=\(state.safeMode) 本物を隠せる=\(state.canHideCursor)")
        engine = CursorEngine(canHideCursor: state.canHideCursor, motion: settings.values.motionParameters,
                              cursorKinds: settings.values.cursorKinds)
        setUpSignalHandlers()
        NSApp.mainMenu = makeMainMenu()
        // .app に入れたアイコンを macOS が読み込めていないと「JellyCursor について」に空のアイコンが出るので、
        // 自分でも描いて渡す（Dock のぶんは、設定画面を開いてふつうのアプリになったときに渡す）
        NSApp.applicationIconImage = AppIconImage.make()
        statusMenu = StatusMenu(
            settings: settings, state: state,
            actions: StatusMenu.Actions(
                toggleEnabled: { [weak self] in self?.toggleEnabled() },
                applyPreset: { [weak self] in self?.settings.values.motion = $0.style },
                openSettings: { [weak self] in self?.openSettings() }))
        statusMenu?.isVisible = settings.values.showsMenuBarIcon || state.safeMode

        settings.onChange = { [weak self] old in self?.settingsChanged(from: old) }
        system.onChange = { [weak self] in self?.update() }
        system.onNeedsRebuild = { [weak self] in
            AppLog.notice("スリープ復帰・ロック解除・画面構成の変化のあとで作り直す")
            self?.engine?.restart()
        }
        system.start()
        registerShortcut()
        update()
        // アイコンを隠していると、セーフモードで起動したことに気づけないので設定画面を開く
        if state.safeMode && !settings.values.showsMenuBarIcon { openSettings() }
        welcomeOnFirstLaunch()
        // 起動時に -OpenSettings <タブ> を渡すと、そのタブで設定画面を開く（open JellyCursor.app --args -OpenSettings motion）
        if let name = UserDefaults.standard.string(forKey: "OpenSettings") {
            openSettings(tab: SettingsTab(rawValue: name))
        }
        // 起動時に -OpenMenu YES を渡すと、メニューバーのメニューを開く（見た目を撮るため）
        if UserDefaults.standard.bool(forKey: "OpenMenu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { self.statusMenu?.open() }
            }
        }
    }

    // はじめて起動したときは、メニューバーのアイコンに気づけるよう、案内つきで設定画面を開く。
    // 「初期状態に戻す」で消えないよう、設定とは別に覚えておく。
    // 案内が無かった版から上げた人（設定を変えたことがある・ログイン時に起動している）には出さない
    private func welcomeOnFirstLaunch() {
        let defaults = UserDefaults.standard
        let key = "welcomed"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        let usedBefore = defaults.object(forKey: AppSettings.defaultsKey) != nil
            || [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
        guard !usedBefore else { return }
        settingsWindow.show(tab: .general, welcome: true)
    }

    // 別の場所に置いた JellyCursor（作り直したものと、アプリケーションフォルダに入れたものなど）が動いていたら終わらせ、
    // 今開いたほうで動く。2つ動くと、どちらも本物のカーソルを隠して絵を描くので、重なって見える
    private func quitOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: id) where other.processIdentifier != me {
            AppLog.notice("先に動いていた JellyCursor（pid \(other.processIdentifier)）を終わらせる")
            other.terminate()
        }
    }

    package func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
        RealCursor.show()
    }

    // アイコンを隠しているときは、アプリをもう一度開くと設定画面を出す
    package func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // 設定と Mac の状態から、描くかどうかを決め直す
    private func update() {
        guard let engine else { return }
        // 全画面かどうかは窓の一覧を1秒ごとに調べるので、使う設定のときだけ見る
        system.watchesFullScreen = settings.values.pauseInFullScreen && state.isEnabled(in: settings)
        let activity = Activity(settings: settings.values, conditions: system.conditions, safeMode: state.safeMode)
        if activity != state.activity {
            AppLog.notice("状態: \(activity.summary)")
        }
        if activity.isRunning {
            engine.start()
        } else {
            engine.stop()
        }
        state.activity = activity
        statusMenu?.update()
    }

    private func settingsChanged(from old: SettingsValues) {
        let new = settings.values
        if new.motionParameters != old.motionParameters { engine?.apply(motion: new.motionParameters) }
        if new.cursorKinds != old.cursorKinds { engine?.apply(cursorKinds: new.cursorKinds) }
        if new.shortcut != old.shortcut { registerShortcut() }
        if new.showsMenuBarIcon != old.showsMenuBarIcon {
            statusMenu?.isVisible = new.showsMenuBarIcon || state.safeMode
        }
        update()
    }

    // オンにしたらセーフモードも終える。オフにしたら、本物のカーソルが見えるところまで確かに戻す
    // （隠した回数の数え違いなどで見えなくなっていても、オフにすれば戻るように）
    private func setEnabled(_ enabled: Bool) {
        if enabled { state.safeMode = false }
        settings.values.isEnabled = enabled
        statusMenu?.isVisible = settings.values.showsMenuBarIcon || state.safeMode
        update()
        if !enabled { RealCursor.forceShow() }
    }

    private func toggleEnabled() {
        setEnabled(!state.isEnabled(in: settings))
    }

    private func openSettings(tab: SettingsTab? = nil) {
        settingsWindow.show(tab: tab)
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    private func registerShortcut() {
        let shortcut = settings.values.shortcut
        state.shortcutFailed = !hotKey.register(shortcut) { [weak self] in self?.toggleEnabled() }
        if state.shortcutFailed, let shortcut {
            AppLog.error("ショートカット \(shortcut.displayString) を登録できない")
        }
        statusMenu?.update()
    }

    private func suspendShortcut(_ suspended: Bool) {
        if suspended {
            hotKey.unregister()
        } else {
            registerShortcut()
        }
    }

    // 設定画面を開いている間（ふつうのアプリとして前面にいる間）だけ見えるメニュー
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "JellyCursor について",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "設定…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "JellyCursor を隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "ほかを隠す",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "JellyCursor を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowMenu = NSMenu(title: "ウインドウ")
        windowMenu.addItem(withTitle: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }

    // kill などで止められたときも、本物のカーソルを戻してから終わる
    private func setUpSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { RealCursor.show() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
