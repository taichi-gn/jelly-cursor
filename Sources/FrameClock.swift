import AppKit

// マウスがある画面の書き換えに合わせて onFrame を呼ぶ。onFrame が true を返したら浅く眠る。
// 眠っている間は低い頻度でマウス位置だけを見て、動いたらすぐ起きる。
// マウス移動のグローバル監視は、前面のアプリがマウス移動を求めていないと届かないので、起こす用途には使えない
@MainActor
final class FrameClock {
    private let onFrame: (CGFloat) -> Bool
    private let onIdle: () -> Void
    private var link: CADisplayLink?
    private var linkScreen: NSScreen?
    private var lastTimestamp: CFTimeInterval?
    private var sleepingAt: CGPoint?

    init(onFrame: @escaping (CGFloat) -> Bool, onIdle: @escaping () -> Void) {
        self.onFrame = onFrame
        self.onIdle = onIdle
    }

    func start() {
        attach(to: Self.screenUnderMouse())
    }

    func stop() {
        link?.invalidate()
        link = nil
        linkScreen = nil
        lastTimestamp = nil
        sleepingAt = nil
    }

    @objc private func frame(_ current: CADisplayLink) {
        let mouse = NSEvent.mouseLocation
        if let screen = Self.screenUnderMouse(), screen !== linkScreen {
            attach(to: screen)
        }
        let dt = lastTimestamp.map { min(current.timestamp - $0, Tuning.Render.maxFrameStep) }
            ?? (current.targetTimestamp - current.timestamp)
        lastTimestamp = current.timestamp

        if let sleepingAt {
            guard mouse != sleepingAt else {
                onIdle()
                return
            }
            wake()
        }
        if onFrame(CGFloat(dt)) {
            sleep(at: mouse)
        }
    }

    private func sleep(at mouse: CGPoint) {
        sleepingAt = mouse
        link?.preferredFrameRateRange = Tuning.Render.idleFrameRate
    }

    private func wake() {
        sleepingAt = nil
        link?.preferredFrameRateRange = .default
    }

    private func attach(to screen: NSScreen?) {
        guard let screen else { return }
        link?.invalidate()
        let newLink = screen.displayLink(target: self, selector: #selector(frame(_:)))
        if sleepingAt != nil {
            newLink.preferredFrameRateRange = Tuning.Render.idleFrameRate
        }
        newLink.add(to: .main, forMode: .common)
        link = newLink
        linkScreen = screen
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
