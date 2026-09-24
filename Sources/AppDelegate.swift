import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arrow = Jelly()
    private let iBeam = IBeam()
    private let hand = PointingHand()
    private let overlay = Overlay()
    private let cover = CoverWatch()
    private lazy var clock = FrameClock(
        onFrame: { [unowned self] dt in self.frame(dt: dt) },
        onIdle: { [unowned self] in self.followCursorState(mouse: NSEvent.mouseLocation) })
    private var cursorShape = CursorShapeWatch()
    private var typing = TypingWatch(now: ProcessInfo.processInfo.systemUptime)
    private var lastMouse: CGPoint?
    private var lastColorCheck: TimeInterval = 0
    private var isRunning = false
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var signalSources: [DispatchSourceSignal] = []
    private var canHideCursor = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        canHideCursor = RealCursor.allowBackgroundControl()
        setUpStatusItem()
        setUpSignalHandlers()
        start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        RealCursor.show()
    }

    private func start() {
        isRunning = true
        overlay.colors = PointerColors.current()
        lastColorCheck = ProcessInfo.processInfo.systemUptime
        overlay.activate()
        cursorShape = CursorShapeWatch()
        typing = TypingWatch(now: ProcessInfo.processInfo.systemUptime)
        followCursorState(mouse: NSEvent.mouseLocation)
        clock.start()
        cover.start { [unowned self] in self.overlay.windowNumbers }
        toggleItem?.title = "ぐにゃぐにゃ: オン"
    }

    private func stop() {
        isRunning = false
        clock.stop()
        cover.stop()
        overlay.deactivate()
        RealCursor.show()
        toggleItem?.title = "ぐにゃぐにゃ: オフ"
    }

    // 眠ってよいなら true を返す。矢印・I 字・指はすべて動かし続け、切り替えた瞬間に形が飛ばないようにする
    private func frame(dt: CGFloat) -> Bool {
        let mouse = NSEvent.mouseLocation
        let figures: [Figure] = [arrow, iBeam, hand]
        figures.forEach { $0.step(to: mouse, dt: dt) }
        followCursorState(mouse: mouse)
        overlay.render()
        defer { lastMouse = mouse }
        return figures.allSatisfy(\.isSettled) && mouse == lastMouse
    }

    // カーソルの種類と入力中かどうかで、描くものと本物の出し入れを決める。眠っている間も呼ぶ。
    // 次のときは自前の絵を消して本物に任せる:
    // - リサイズなど、矢印・I 字・指以外のカーソル
    // - システムのダイアログなど、JellyCursor の窓より手前にある窓の上（自前の絵がその奥に隠れる）
    // - 隠し直しても本物が消えない間（Dock が出ている間など。2つ見えないように）
    private func followCursorState(mouse: CGPoint) {
        refreshColorsIfDue()
        if cursorShape.update(), cursorShape.kind == .pointingHand, let cursor = cursorShape.cursor {
            hand.use(cursor)
        }
        let covered = cover.covers(mouse)
        let hideReal = canHideCursor && cursorShape.kind != .other && !covered
        if hideReal { RealCursor.hide() } else { RealCursor.show() }
        RealCursor.rehideIfShown()
        if RealCursor.isOverpowered || covered {
            overlay.figure = nil
            return
        }
        switch cursorShape.kind {
        case .arrow: overlay.figure = arrow
        case .iBeam: overlay.figure = hideReal && !isTyping(mouse: mouse) ? iBeam : nil
        case .pointingHand: overlay.figure = hideReal ? hand : nil
        case .other: overlay.figure = nil
        }
    }

    // システム設定でポインタの色を変えたら追従する。設定の読み直しは設定サーバーへの問い合わせで、
    // まれに数msかかるので、間隔をあけたうえで描画とは別の流れで読む
    private func refreshColorsIfDue() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastColorCheck >= Tuning.Render.colorCheckInterval else { return }
        lastColorCheck = now
        DispatchQueue.global(qos: .utility).async {
            let colors = PointerColors.current()
            DispatchQueue.main.async { [weak self] in self?.overlay.colors = colors }
        }
    }

    private func isTyping(mouse: CGPoint) -> Bool {
        typing.isTyping(
            mouse: mouse, now: ProcessInfo.processInfo.systemUptime,
            secondsSinceKeyDown: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown))
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "Jelly Cursor") {
            item.button?.image = image
        } else {
            item.button?.title = "J"
        }
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        if !canHideCursor {
            menu.addItem(NSMenuItem(title: "本物のカーソルを隠せませんでした", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        toggleItem = toggle
    }

    @objc private func toggleEnabled() {
        if isRunning { stop() } else { start() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setUpSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                RealCursor.show()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
