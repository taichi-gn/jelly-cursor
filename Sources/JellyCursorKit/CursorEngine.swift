import AppKit
import JellyCursorCore

// 自前のカーソルを描く。start から stop までの間、マウスに合わせて毎フレーム動かし、本物のカーソルを出し入れする
@MainActor
final class CursorEngine {
    private(set) var isRunning = false
    private let canHideCursor: Bool
    private var motion: MotionParameters
    private var cursorKinds: CursorKinds
    private var arrow: Jelly
    private var iBeam: IBeam
    private var hand: PointingHand
    private var figures: [Figure] { [arrow, iBeam, hand] }
    private let overlay = Overlay()
    private let cover = CoverWatch()
    private lazy var clock = FrameClock(
        onFrame: { [unowned self] dt in self.frame(dt: dt) },
        onIdle: { [unowned self] in self.followCursorState(mouse: NSEvent.mouseLocation) },
        isPressed: { [unowned self] in self.isPressed() })
    private var clickWatch = ClickWatch()
    private var cursorShape = CursorShapeWatch()
    private var typing = TypingWatch(now: ProcessInfo.processInfo.systemUptime)
    private var otherHide = OtherHideWatch(now: ProcessInfo.processInfo.systemUptime)
    private var lastMouse: CGPoint?
    private var lastPressed = false
    private var pointerScale: CGFloat = 1
    private var lastColorCheck: TimeInterval = 0

    // 大きさは start で読み直して作り直す
    init(canHideCursor: Bool, motion: MotionParameters, cursorKinds: CursorKinds) {
        self.canHideCursor = canHideCursor
        self.motion = motion
        self.cursorKinds = cursorKinds
        arrow = Jelly(scale: 1, motion: motion)
        iBeam = IBeam(scale: 1, motion: motion)
        hand = PointingHand(scale: 1, motion: motion, cursor: CursorImage(.pointingHand))
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let mouse = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        rebuildFigures(scale: SystemPointer.scale(), at: mouse)
        overlay.colors = SystemPointer.colors()
        lastColorCheck = now
        overlay.activate()
        cursorShape = CursorShapeWatch()
        typing = TypingWatch(now: now)
        otherHide = OtherHideWatch(now: now)
        followCursorState(mouse: mouse)
        clock.start()
        cover.start { [unowned self] in self.overlay.windowNumbers }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        clock.stop()
        cover.stop()
        overlay.deactivate()
        RealCursor.show()
    }

    // スリープからの復帰や画面構成の変化のあと、窓・表示リンク・本物のカーソルの隠し方を作り直す
    func restart() {
        guard isRunning else { return }
        stop()
        start()
    }

    // 設定の「伸び」「弾み」を変えたら、その値で作り直す
    func apply(motion: MotionParameters) {
        guard motion != self.motion else { return }
        self.motion = motion
        if isRunning { rebuildFigures(scale: pointerScale, at: NSEvent.mouseLocation) }
    }

    // 自前で描くカーソルの種類を変えたら、今のカーソルに当てはめ直す
    func apply(cursorKinds: CursorKinds) {
        guard cursorKinds != self.cursorKinds else { return }
        self.cursorKinds = cursorKinds
        if isRunning { followCursorState(mouse: NSEvent.mouseLocation) }
    }

    // オンにしたときは、オフの間の移動を1フレームで動いたものとして伸ばさないよう、
    // ポインタの大きさや動きの設定を変えたときは、その値で描くよう、作り直して今の位置に置く
    private func rebuildFigures(scale: CGFloat, at mouse: CGPoint) {
        pointerScale = scale
        cover.pointerScale = scale
        arrow = Jelly(scale: scale, motion: motion)
        iBeam = IBeam(scale: scale, motion: motion)
        let handCursor = cursorShape.kind == .pointingHand ? cursorShape.cursor ?? .pointingHand : .pointingHand
        hand = PointingHand(scale: scale, motion: motion, cursor: CursorImage(handCursor))
        figures.forEach { $0.step(to: mouse, dt: 0) }
    }

    // 眠ってよいなら true を返す。矢印・I 字・指はすべて動かし続け、切り替えた瞬間に形が飛ばないようにする。
    // マウスのボタン（どれでも）を押している間は、クリックの形の変化を描く
    private func frame(dt: CGFloat) -> Bool {
        let mouse = NSEvent.mouseLocation
        let pressed = isPressed()
        let figures = self.figures
        figures.forEach { $0.step(to: mouse, dt: dt, pressed: pressed) }
        followCursorState(mouse: mouse)
        overlay.render()
        defer {
            lastMouse = mouse
            lastPressed = pressed
        }
        return figures.allSatisfy(\.isSettled) && mouse == lastMouse && pressed == lastPressed
    }

    // カーソルの種類と入力中かどうかで、描くものと本物の出し入れを決める。眠っている間も呼ぶ。
    // 次のときは自前の絵を消して本物に任せる:
    // - リサイズなど、矢印・I 字・指以外のカーソルと、設定で描かないことにした種類
    // - システムのダイアログなど、JellyCursor の窓より手前にある窓の上（自前の絵がその奥に隠れる）
    // - 隠し直しても本物が消えない間（Dock が出ている間など。2つ見えないように）
    // 他のアプリが本物を隠している間（動画の放置・文字入力）は、自前の絵も消す
    private func followCursorState(mouse: CGPoint) {
        refreshSettingsIfDue()
        watchTyping(mouse: mouse)
        // 眠っている間は描き直しが走らないので、指の画像を差し替えたらここで描く
        if cursorShape.update(), cursorShape.kind == .pointingHand, let cursor = cursorShape.cursor {
            hand.use(CursorImage(cursor))
            overlay.render()
        }
        let drawn = cursorKinds.contains(cursorShape.kind)
        let covered = cover.covers(mouse)
        let hideReal = canHideCursor && drawn && !covered
        if hideReal { RealCursor.hide() } else { RealCursor.show() }
        RealCursor.rehideIfShown()
        let now = ProcessInfo.processInfo.systemUptime
        otherHide.update(mouse: mouse, now: now, lastInput: now - Self.secondsSinceKeyOrClick()) { RealCursor.isHiddenByOthers() }
        if !drawn || RealCursor.isOverpowered || covered || otherHide.isHidden {
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let colors = SystemPointer.colors()
            let scale = SystemPointer.scale()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else { return }
                    self.overlay.colors = colors
                    if scale != self.pointerScale { self.rebuildFigures(scale: scale, at: NSEvent.mouseLocation) }
                }
            }
        }
    }

    // マウスのボタン（どれでも）を押しているか。ボタンを見に行く間より短いタップも、少しの間押したことにする
    private func isPressed() -> Bool {
        let secondsSinceLastPress = [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
        return clickWatch.isPressed(buttonsDown: NSEvent.pressedMouseButtons != 0,
                                    secondsSinceLastPress: secondsSinceLastPress,
                                    now: ProcessInfo.processInfo.systemUptime)
    }

    private static func secondsSinceKeyOrClick() -> TimeInterval {
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
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
}
