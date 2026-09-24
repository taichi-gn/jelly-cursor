import AppKit

// 本物のカーソルは、前面にいないアプリからは公開APIで隠せない。
// "SetsCursorInBackground" は非公開APIで、存在しなければ隠さずに動く。
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

    static func show() {
        guard isHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        isHidden = false
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

enum CursorKind {
    case arrow, iBeam, pointingHand, other
}

// 他のアプリが今出しているカーソルが、矢印・I 字・それ以外のどれかを追う。
// 形の画像を取るのは1回0.5msほどかかるので、通し番号が変わったときだけ調べる
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

    // システム設定でポインタの色を変えると画像の色も変わるので、色ではなく形で見分ける
    static func classify(_ cursor: NSCursor) -> CursorKind {
        let shape = CursorShape(cursor)
        if shape.matches(arrowShape) { return .arrow }
        if shape.matches(iBeamShape) { return .iBeam }
        if shape.matches(handShape) { return .pointingHand }
        return .other
    }
}

// カーソルの形（透明でない画素の並び）
struct CursorShape {
    private static let pixelsPerPoint = 2
    // 形の違う画素が、塗られた面積のこの割合より少なければ同じ形とみなす（縮小のにじみの分だけ許す）
    private static let tolerance = 0.05

    private let hotSpot: NSPoint
    private let size: NSSize
    private let opaque: [Bool]

    init(_ cursor: NSCursor) {
        hotSpot = cursor.hotSpot
        size = cursor.image.size
        let w = Int(size.width) * Self.pixelsPerPoint, h = Int(size.height) * Self.pixelsPerPoint
        // グレーと透明度の2バイトで描き、透明度だけを使う
        var pixels = [UInt8](repeating: 0, count: max(w * h * 2, 0))
        if w > 0, h > 0, let image = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pixels.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 2,
                                        space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        opaque = stride(from: 1, to: pixels.count, by: 2).map { pixels[$0] > 127 }
    }

    func matches(_ other: CursorShape) -> Bool {
        guard hotSpot == other.hotSpot, size == other.size, opaque.count == other.opaque.count else { return false }
        let filled = opaque.filter { $0 }.count
        guard filled > 0 else { return false }
        let differing = zip(opaque, other.opaque).filter { $0 != $1 }.count
        return Double(differing) / Double(filled) < Self.tolerance
    }
}

// macOS は文字を打つとマウスを動かすまでカーソルを消す。自前で描く I 字も同じように消すため、
// 最後の文字入力が最後のマウス移動より新しいかを見る（キー入力の時刻は権限なしで取れる）。
// ⌘・⌃を押しながらのキー（ショートカットやアプリの切り替え）は文字入力として数えない。
// アプリの切り替えは⌘を離したときに起きるので、カーソルが I 字でない間も毎回読んで、押された瞬間の⌘を捕まえる
struct TypingWatch {
    // 同じキー入力を、読むたびの時刻のずれで別の入力と数えないための幅（秒）
    private static let sameKeyTolerance: TimeInterval = 0.01
    private var lastMouse: CGPoint?
    private var lastMoveTime: TimeInterval
    private var lastKeyTime: TimeInterval?
    private var lastTypedTime = -TimeInterval.infinity

    init(now: TimeInterval) {
        lastMoveTime = now
    }

    var isTyping: Bool { lastTypedTime > lastMoveTime }

    mutating func update(mouse: CGPoint, now: TimeInterval, secondsSinceKeyDown: TimeInterval,
                         shortcutHeld: @autoclosure () -> Bool) {
        if mouse != lastMouse {
            lastMouse = mouse
            lastMoveTime = now
        }
        let keyTime = now - secondsSinceKeyDown
        if keyTime > (lastKeyTime ?? -.infinity) + Self.sameKeyTolerance {
            lastKeyTime = keyTime
            if !shortcutHeld() { lastTypedTime = keyTime }
        }
    }
}
