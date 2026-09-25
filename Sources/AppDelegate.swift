import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var arrow = Jelly()
    private var iBeam = IBeam()
    private var hand = PointingHand()
    private var figures: [Figure] { [arrow, iBeam, hand] }
    private let overlay = Overlay()
    private let cover = CoverWatch()
    private lazy var clock = FrameClock(
        onFrame: { [unowned self] dt in self.frame(dt: dt) },
        onIdle: { [unowned self] in self.followCursorState(mouse: NSEvent.mouseLocation) })
    private var cursorShape = CursorShapeWatch()
    private var typing = TypingWatch(now: ProcessInfo.processInfo.systemUptime)
    private var otherHide = OtherHideWatch(now: ProcessInfo.processInfo.systemUptime)
    private var lastMouse: CGPoint?
    private var pointerScale: CGFloat = 1
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
        let mouse = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        rebuildFigures(scale: ArrowShape.systemPointerScale(), at: mouse)
        overlay.colors = PointerColors.current()
        lastColorCheck = now
        overlay.activate()
        cursorShape = CursorShapeWatch()
        typing = TypingWatch(now: now)
        otherHide = OtherHideWatch(now: now)
        followCursorState(mouse: mouse)
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

    // オンにしたときは、オフの間の移動を1フレームで動いたものとして伸ばさないよう、
    // ポインタの大きさを変えたときは、その大きさで描くよう、作り直して今の位置に置く
    private func rebuildFigures(scale: CGFloat, at mouse: CGPoint) {
        pointerScale = scale
        cover.pointerScale = scale
        arrow = Jelly(scale: scale)
        iBeam = IBeam(scale: scale)
        hand = PointingHand(scale: scale)
        if cursorShape.kind == .pointingHand, let cursor = cursorShape.cursor { hand.use(cursor) }
        figures.forEach { $0.step(to: mouse, dt: 0) }
    }

    // 眠ってよいなら true を返す。矢印・I 字・指はすべて動かし続け、切り替えた瞬間に形が飛ばないようにする
    private func frame(dt: CGFloat) -> Bool {
        let mouse = NSEvent.mouseLocation
        let figures = self.figures
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
    // 他のアプリが本物を隠している間（動画の放置・文字入力）は、自前の絵も消す
    private func followCursorState(mouse: CGPoint) {
        refreshSettingsIfDue()
        watchTyping(mouse: mouse)
        // 眠っている間は描き直しが走らないので、指の画像を差し替えたらここで描く
        if cursorShape.update(), cursorShape.kind == .pointingHand, let cursor = cursorShape.cursor {
            hand.use(cursor)
            overlay.render()
        }
        let covered = cover.covers(mouse)
        let hideReal = canHideCursor && cursorShape.kind != .other && !covered
        if hideReal { RealCursor.hide() } else { RealCursor.show() }
        RealCursor.rehideIfShown()
        let now = ProcessInfo.processInfo.systemUptime
        otherHide.update(mouse: mouse, now: now, lastInput: now - Self.secondsSinceKeyOrClick()) { RealCursor.isHiddenByOthers() }
        if RealCursor.isOverpowered || covered || otherHide.isHidden {
            overlay.figure = nil
            return
        }
        switch cursorShape.kind {
        case .arrow: overlay.figure = arrow
        case .iBeam: overlay.figure = hideReal && !typing.isTyping ? iBeam : nil
        case .pointingHand: overlay.figure = hideReal ? hand : nil
        case .other: overlay.figure = nil
        }
    }

    // システム設定でポインタの色や大きさを変えたら追従する。設定の読み直しは設定サーバーへの問い合わせで、
    // まれに数msかかるので、間隔をあけたうえで描画とは別の流れで読む
    private func refreshSettingsIfDue() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastColorCheck >= Tuning.Render.colorCheckInterval else { return }
        lastColorCheck = now
        DispatchQueue.global(qos: .utility).async {
            let colors = PointerColors.current()
            let scale = ArrowShape.systemPointerScale()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.overlay.colors = colors
                if scale != self.pointerScale { self.rebuildFigures(scale: scale, at: NSEvent.mouseLocation) }
            }
        }
    }

    private static func secondsSinceKeyOrClick() -> TimeInterval {
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    private func watchTyping(mouse: CGPoint) {
        typing.update(
            mouse: mouse, now: ProcessInfo.processInfo.systemUptime,
            secondsSinceKeyDown: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            secondsSinceFlagsChanged: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .flagsChanged),
            shortcutHeld: !CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: [.maskCommand, .maskControl]))
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
