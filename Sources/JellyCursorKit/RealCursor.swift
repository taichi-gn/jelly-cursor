import AppKit
import JellyCursorCore

// 本物のカーソルは、前面にいないアプリからは公開APIで隠せない。
// "SetsCursorInBackground" は非公開APIで、存在しなければ隠さずに動く。
@MainActor
enum RealCursor {
    private(set) static var isHidden = false
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    static func allowBackgroundControl() -> Bool {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let d = dlsym(rtldDefault, "_CGSDefaultConnection"),
              let s = dlsym(rtldDefault, "CGSSetConnectionProperty") else { return false }
        let conn = unsafeBitCast(d, to: DefaultConnection.self)()
        let set = unsafeBitCast(s, to: SetProperty.self)
        return set(conn, conn, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }

    static func hide() {
        guard !isHidden else { return }
        CGDisplayHideCursor(CGMainDisplayID())
        isHidden = true
    }

    // 隠せない状態の判定も捨てる。オフにしたときなどに持ち越すと、次に隠したとき本物に任せたままになる
    static func show() {
        guard isHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        isHidden = false
        isOverpowered = false
        rehidLastCheck = false
        hiddenStreak = 0
    }

    // 本物のカーソルが見えなくなったときの逃げ道。自分が隠した回数の数え違いがあっても見えるよう、見えるまで重ねて戻す。
    // 他のアプリが隠している分（動画の再生中など）は戻せないので、回数に上限を設ける
    static func forceShow() {
        show()
        guard let isVisible else { return }
        for _ in 0..<8 where isVisible() == 0 {
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }

    // 動画の再生中や文字入力中に、他のアプリが本物のカーソルを隠しているか。
    // 隠れているのが自分のせいだけかは直接は分からないので、自分の分だけ戻して、見えるようになるかを見る。
    // 戻したことは少し遅れて反映される（測ると多くは0.1ms以内、まれに2ms台）ので、見えるまで待ってすぐ隠し直す
    static func isHiddenByOthers() -> Bool {
        guard isHidden, let isVisible, isVisible() == 0 else { return false }
        CGDisplayShowCursor(CGMainDisplayID())
        let deadline = ProcessInfo.processInfo.systemUptime + Tuning.Render.otherHideProbeTimeout
        var hidden = true
        // 休まずに確かめ続けると、待つ間ずっとCPUを使うので、合間に少し休む
        while ProcessInfo.processInfo.systemUptime < deadline {
            if isVisible() != 0 {
                hidden = false
                break
            }
            usleep(50)
        }
        CGDisplayHideCursor(CGMainDisplayID())
        return hidden
    }

    // 隠し直しても効かない状態（Dock が出ている間など）。この間は自前の絵を消して本物に任せる。
    // 隠れた状態がしばらく続くまで解除しないので、出たり消えたりのちらつきは起きない
    private(set) static var isOverpowered = false
    private static var rehidLastCheck = false
    private static var hiddenStreak = 0

    // 他のアプリのきっかけで表示に戻されても、こちらの隠した回数は1のまま残る。
    // その状態で隠す処理を重ねても効かないので、一度0に戻してから隠し直す
    static func rehideIfShown() {
        guard isHidden, let isVisible else {
            isOverpowered = false
            rehidLastCheck = false
            return
        }
        guard isVisible() != 0 else {
            hiddenStreak += 1
            if hiddenStreak >= Tuning.Render.overpowerRecoverChecks { isOverpowered = false }
            rehidLastCheck = false
            return
        }
        hiddenStreak = 0
        if rehidLastCheck { isOverpowered = true }
        CGDisplayShowCursor(CGMainDisplayID())
        CGDisplayHideCursor(CGMainDisplayID())
        rehidLastCheck = true
    }

    fileprivate typealias Int32Getter = @convention(c) () -> Int32
    private static let isVisible: Int32Getter? = dlsym(rtldDefault, "CGCursorIsVisible")
        .map { unsafeBitCast($0, to: Int32Getter.self) }
    // カーソルの形が変わるたびに増える通し番号。1回0.01µsほどで読める
    fileprivate static let shapeSeed: Int32Getter? = dlsym(rtldDefault, "CGSCurrentCursorSeed")
        .map { unsafeBitCast($0, to: Int32Getter.self) }
}

// 他のアプリが今出しているカーソルが、矢印・I 字・指・それ以外のどれかを追う。
// 形の画像を取るのは1回0.5msほどかかるので、通し番号が変わったときだけ調べる
@MainActor
struct CursorShapeWatch {
    private var lastSeed: Int32?
    private(set) var kind = CursorKind.arrow
    // 今出ているカーソル。指は画像をそのまま描くので、差し替えに使う
    private(set) var cursor: NSCursor?
    private static let arrowShape = CursorShape(NSCursor.arrow)
    private static let iBeamShape = CursorShape(NSCursor.iBeam)
    private static let handShape = CursorShape(NSCursor.pointingHand)

    // カーソルが変わったら true
    mutating func update() -> Bool {
        guard let seed = RealCursor.shapeSeed?(), seed != lastSeed else { return false }
        lastSeed = seed
        cursor = NSCursor.currentSystem
        kind = cursor.map(Self.classify) ?? .arrow
        return true
    }

    static func classify(_ cursor: NSCursor) -> CursorKind {
        CursorShape(cursor).classify(arrow: arrowShape, iBeam: iBeamShape, pointingHand: handShape)
    }
}

extension CursorShape {
    // カーソルの画像を 1pt あたり pixelsPerPoint 画素で、グレーと透明度の2バイトずつに描いて作る
    @MainActor
    init(_ cursor: NSCursor) {
        let size = cursor.image.size
        let w = Int(size.width) * Self.pixelsPerPoint, h = Int(size.height) * Self.pixelsPerPoint
        var pixels = [UInt8](repeating: 0, count: max(w * h * 2, 0))
        if w > 0, h > 0, let image = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pixels.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 2,
                                        space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        self.init(hotSpot: cursor.hotSpot, size: size, grayAlpha: pixels)
    }
}
