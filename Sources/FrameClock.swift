import AppKit

// マウスがある画面の書き換えに合わせて onFrame を呼ぶ。onFrame が true を返したら浅く眠る。
// 眠っている間は表示リンクを止め、タイマーでマウス位置だけを見て、動いたらすぐ起きる。
// 表示リンクは何もしなくても1回85µsほどかかり、タイマーは30µsほどで済む。
// マウス移動のグローバル監視は、前面のアプリがマウス移動を求めていないと届かないので、起こす用途には使えない
@MainActor
final class FrameClock {
    private let onFrame: (CGFloat) -> Bool
    private let onIdle: () -> Void
    private let mouseLocation: () -> CGPoint
    private var link: CADisplayLink?
    private var linkScreen: NSScreen?
    private var idleTimer: Timer?
    // 表示リンクの時刻と同じ時計（CACurrentMediaTime）で、最後に動かした・見た時刻
    private var lastTimestamp: CFTimeInterval?
    private var sleepingAt: CGPoint?

    init(onFrame: @escaping (CGFloat) -> Bool, onIdle: @escaping () -> Void,
         mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.onFrame = onFrame
        self.onIdle = onIdle
        self.mouseLocation = mouseLocation
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func start() {
        attach(to: screenUnderMouse())
    }

    func stop() {
        link?.invalidate()
        link = nil
        linkScreen = nil
        idleTimer?.invalidate()
        idleTimer = nil
        lastTimestamp = nil
        sleepingAt = nil
    }

    @objc private func frame(_ current: CADisplayLink) {
        // 止める前に予定されていた1回が、眠ったあとに届くことがある
        guard sleepingAt == nil else { return }
        if let screen = screenUnderMouse(), screen !== linkScreen {
            attach(to: screen)
        }
        let dt = lastTimestamp.map { step(since: $0, now: current.timestamp) }
            ?? (current.targetTimestamp - current.timestamp)
        lastTimestamp = current.timestamp
        advance(dt: dt)
    }

    // 眠っている間にマウスが動いたら、次の表示リンクを待たずにここで1フレーム進める（起きるまでの遅れを増やさない）
    private func poll() {
        let now = CACurrentMediaTime()
        let dt = lastTimestamp.map { step(since: $0, now: now) } ?? Tuning.Render.idlePollInterval
        lastTimestamp = now
        guard mouseLocation() != sleepingAt else {
            onIdle()
            return
        }
        wake()
        if let screen = screenUnderMouse(), screen !== linkScreen {
            attach(to: screen)
        }
        advance(dt: dt)
    }

    private func advance(dt: CFTimeInterval) {
        let mouse = mouseLocation()
        if onFrame(CGFloat(dt)) {
            sleep(at: mouse)
        }
    }

    // 起きた直後の表示リンクの時刻は、最後にタイマーで見た時刻より前のことがあるので、負にしない
    private func step(since last: CFTimeInterval, now: CFTimeInterval) -> CFTimeInterval {
        min(max(now - last, 0), Tuning.Render.maxFrameStep)
    }

    // マウスがある画面が外されると、その画面の表示リンクが呼ばれなくなって、frame での付け替えも起きなくなりうる
    @objc private func screensChanged() {
        if link != nil { attach(to: screenUnderMouse()) }
    }

    private func sleep(at mouse: CGPoint) {
        sleepingAt = mouse
        link?.isPaused = true
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: Tuning.Render.idlePollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func wake() {
        sleepingAt = nil
        idleTimer?.invalidate()
        idleTimer = nil
        link?.isPaused = false
    }

    private func attach(to screen: NSScreen?) {
        guard let screen else { return }
        link?.invalidate()
        let newLink = screen.displayLink(target: self, selector: #selector(frame(_:)))
        newLink.isPaused = sleepingAt != nil
        newLink.add(to: .main, forMode: .common)
        link = newLink
        linkScreen = screen
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = mouseLocation()
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
