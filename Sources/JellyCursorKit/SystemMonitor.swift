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
    private var distributedObserver: DistributedObserver?
    private var frontPID: pid_t?
    // 本体と画面は別々に眠って起きるので、どちらかが眠っている間は止める
    private var sleeping: Set<Sleeper> = []
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
        observe(workspace, NSWorkspace.willSleepNotification) { $0.sleep(.system) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.wake(.system) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.sleep(.displays) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.wake(.displays) }
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

        // ロックとスクリーンセーバーは、ほかのプロセスからの知らせ（分散通知）で届く
        distributedObserver = DistributedObserver([
            Notification.Name("com.apple.screenIsLocked"): { [weak self] in self?.conditions.screenLocked = true },
            Notification.Name("com.apple.screenIsUnlocked"): { [weak self] in
                self?.conditions.screenLocked = false
                self?.requestRebuild()
            },
            Notification.Name("com.apple.screensaver.didstart"): { [weak self] in self?.conditions.screenSaverRunning = true },
            Notification.Name("com.apple.screensaver.didstop"): { [weak self] in self?.conditions.screenSaverRunning = false },
        ]) { [weak self] in self?.onChange?() }

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

    private func sleep(_ sleeper: Sleeper) {
        wakeWork?.cancel()
        wakeWork = nil
        sleeping.insert(sleeper)
        conditions.asleep = true
    }

    // 本体と画面の両方が起きたら、画面の準備ができるのを少し待ってから、作り直して動かす
    private func wake(_ sleeper: Sleeper) {
        sleeping.remove(sleeper)
        // 画面が眠ったという知らせを取りこぼしていても、本体が起きたときに画面が点いていれば起きた扱いにする
        if sleeper == .system && CGDisplayIsAsleep(CGMainDisplayID()) == 0 {
            sleeping.remove(.displays)
        }
        guard sleeping.isEmpty else { return }
        wakeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.sleeping.isEmpty else { return }
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
        // 前のアプリについての問い合わせの結果は捨てて、調べ直す。結果が出るまでは前の値のままにして、
        // 全画面のアプリどうしを切り替えたときに、一瞬だけ動き出して本物のカーソルを隠さないようにする
        fullScreenGeneration += 1
        fullScreenInFlight = false
        checkFullScreen()
        onChange?()
    }

    private func updateFullScreenTimer() {
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        fullScreenGeneration += 1
        fullScreenInFlight = false
        // 見ないときは全画面かどうかを使わないので、知らせずに戻しておく
        guard watchesFullScreen, Self.current === self else {
            conditions.frontAppFullScreen = false
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

private enum Sleeper {
    case system, displays
}

// ほかのプロセスからの知らせ（分散通知）を受け取る。ふつうの受け取り方では、アプリが前面にいない間
// （JellyCursor はほとんどいつもそう）は届くのを止められ、前面に来たときにまとめて届くことがあるので、すぐ届けるよう頼む
@MainActor
private final class DistributedObserver: NSObject {
    private let handlers: [Notification.Name: () -> Void]
    private let afterEach: () -> Void

    init(_ handlers: [Notification.Name: () -> Void], afterEach: @escaping () -> Void) {
        self.handlers = handlers
        self.afterEach = afterEach
        super.init()
        let center = DistributedNotificationCenter.default()
        for name in handlers.keys {
            center.addObserver(self, selector: #selector(receive(_:)), name: name, object: nil,
                               suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func receive(_ notification: Notification) {
        handlers[notification.name]?()
        afterEach()
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
