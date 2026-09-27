import AppKit
import JellyCursorCore

// 自動で止めるために、Mac の状態を見張る。ロック・ユーザーの切り替え・スクリーンセーバー・スリープ・
// 「視差効果を減らす」・低電力モード・前面のアプリ・全画面。
// スリープからの復帰や画面構成の変化のあとは、描く窓などを作り直すよう onNeedsRebuild で知らせる
@MainActor
final class SystemMonitor {
    private(set) var conditions = SystemConditions()
    // 前面に来た、JellyCursor 以外の最後のアプリ。メニューの「〜では無効」に使う
    private(set) var lastOtherApp: AppIdentity?
    var onChange: (() -> Void)?
    var onNeedsRebuild: (() -> Void)?
    // 全画面かどうかは窓の一覧を調べるので、設定でオンのときだけ見る
    var watchesFullScreen = false {
        didSet { if watchesFullScreen != oldValue { updateFullScreenTimer() } }
    }

    // 画面構成が変わったと CoreGraphics から呼び戻す先
    fileprivate static weak var current: SystemMonitor?
    // 起きた直後や画面構成が変わった直後は画面の準備ができていないことがあるので、少し待ってから作り直す
    private static let settleDelay: TimeInterval = 1
    private static let fullScreenCheckInterval: TimeInterval = 1

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var frontPID: pid_t?
    private var wakeWork: DispatchWorkItem?
    private var rebuildWork: DispatchWorkItem?
    private var fullScreenTimer: Timer?
    private var fullScreenInFlight = false
    // 前面のアプリが変わったり見るのをやめたりしたら増やし、その前に出した問い合わせの結果を捨てる
    private var fullScreenGeneration = 0

    func start() {
        guard Self.current == nil else { return }
        Self.current = self
        conditions.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        conditions.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        frontAppChanged(NSWorkspace.shared.frontmostApplication.map(RunningApp.init))

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.conditions.sessionActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) {
            $0.conditions.sessionActive = true
            $0.requestRebuild()
        }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.setAsleep(true) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.setAsleep(false) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.setAsleep(true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.setAsleep(false) }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
            $0.conditions.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.checkFullScreen() }
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication).map(RunningApp.init)
            MainActor.assumeIsolated { self?.frontAppChanged(app) }
        }))

        // 低電力モードの知らせは主スレッド以外で届くことがある
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) {
            $0.conditions.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.conditions.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
            $0.conditions.screenLocked = false
            $0.requestRebuild()
        }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { $0.conditions.screenSaverRunning = true }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.conditions.screenSaverRunning = false }

        CGDisplayRegisterReconfigurationCallback(displaysReconfigured, nil)
        updateFullScreenTimer()
    }

    // 知らせを主スレッドで受け取り、状態を変えてから onChange を呼ぶ
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ update: @escaping @MainActor @Sendable (SystemMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.onChange?()
            }
        }
        observers.append((center, token))
    }

    private func setAsleep(_ asleep: Bool) {
        wakeWork?.cancel()
        wakeWork = nil
        guard !asleep else {
            conditions.asleep = true
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.conditions.asleep = false
                self.onNeedsRebuild?()
                self.onChange?()
            }
        }
        wakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    // 画面をつないだり外したり、解像度を変えたりしたあと。続けて何度も届くので、落ち着いてから1回だけ作り直す
    fileprivate func requestRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onNeedsRebuild?()
                self.checkFullScreen()
            }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func frontAppChanged(_ app: RunningApp?) {
        frontPID = app?.pid
        conditions.frontApp = app?.identity
        if let app, app.pid != ProcessInfo.processInfo.processIdentifier, let identity = app.identity {
            lastOtherApp = identity
        }
        // 前のアプリについての問い合わせの結果は捨てて、調べ直す
        fullScreenGeneration += 1
        fullScreenInFlight = false
        conditions.frontAppFullScreen = false
        checkFullScreen()
        onChange?()
    }

    private func updateFullScreenTimer() {
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        fullScreenGeneration += 1
        fullScreenInFlight = false
        guard watchesFullScreen, Self.current === self else {
            setFullScreen(false)
            return
        }
        let timer = Timer(timeInterval: Self.fullScreenCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFullScreen() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fullScreenTimer = timer
        checkFullScreen()
    }

    // 窓の一覧を調べるのは数msかかることがあるので、主スレッドとは別の流れで調べる
    private func checkFullScreen() {
        guard watchesFullScreen, !fullScreenInFlight else { return }
        guard let pid = frontPID, pid != ProcessInfo.processInfo.processIdentifier else {
            setFullScreen(false)
            return
        }
        let screens = NSScreen.screens.map { ScreenInfo(frame: $0.frame, safeAreaTop: $0.safeAreaInsets.top) }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
        let generation = fullScreenGeneration
        fullScreenInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let windows = WindowInfo.list([.optionOnScreenOnly, .excludeDesktopElements], relativeTo: kCGNullWindowID)
            let fullScreen = WindowInfo.isFullScreen(windows, pid: pid, screens: screens, primaryHeight: primaryHeight,
                                                     menuBarLayer: menuBarLayer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.fullScreenGeneration == generation else { return }
                    self.fullScreenInFlight = false
                    self.setFullScreen(fullScreen)
                }
            }
        }
    }

    private func setFullScreen(_ fullScreen: Bool) {
        guard conditions.frontAppFullScreen != fullScreen else { return }
        conditions.frontAppFullScreen = fullScreen
        onChange?()
    }
}

// NSRunningApplication から必要なものだけを写した値（主スレッドへそのまま渡せる）
private struct RunningApp: Sendable {
    let pid: pid_t
    let identity: AppIdentity?

    init(_ app: NSRunningApplication) {
        pid = app.processIdentifier
        identity = app.bundleIdentifier.map {
            AppIdentity(bundleID: $0, name: app.localizedName ?? $0)
        }
    }
}

// 画面をつないだり外したり、解像度を変えたりしたときに CoreGraphics から呼ばれる。変わり始めの知らせは無視する
private func displaysReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                  _ userInfo: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag) else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated { SystemMonitor.current?.requestRebuild() }
    }
}
