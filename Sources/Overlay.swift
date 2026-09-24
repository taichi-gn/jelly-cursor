import AppKit

// 画面ごとの透明ウィンドウに、縁（影つき）と中身の2枚の図形の層と、画像の層を置き、形や向きだけを差し替える。
// 画面全体を毎フレーム描き直すと、Retina では1枚33MBの描画領域を書き換えることになり重い
final class Overlay {
    private struct Surface {
        let window: NSWindow
        let border: CAShapeLayer
        let fill: CAShapeLayer
        let picture: CALayer
    }

    private var surfaces: [Surface] = []
    private var isActive = false

    // nil のときは何も描かない（本物のカーソルに任せている間や、文字を打っている間）
    var figure: Figure? {
        didSet { if figure !== oldValue { render() } }
    }

    // システム設定のポインタの色
    var colors = PointerColors.standard {
        didSet { if colors != oldValue { applyColors() } }
    }

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    var windowNumbers: [CGWindowID] {
        surfaces.map { CGWindowID($0.window.windowNumber) }
    }

    func activate() {
        isActive = true
        rebuildWindows()
    }

    func deactivate() {
        isActive = false
        surfaces.forEach { $0.window.orderOut(nil) }
        surfaces = []
    }

    func render() {
        let outline = figure as? CursorFigure
        let picture = figure as? ImageFigure
        let bounds = outline?.bounds ?? .null
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for s in surfaces {
            let origin = s.window.frame.origin
            let path = outline.flatMap { f in
                s.window.frame.intersects(bounds) ? f.path(offsetBy: CGVector(dx: -origin.x, dy: -origin.y)) : nil
            }
            s.border.lineWidth = (outline?.borderWidth ?? 0) * 2
            s.border.path = path
            s.border.shadowPath = path
            s.fill.path = path

            if let picture, s.window.frame.contains(picture.position) {
                s.picture.contents = picture.image
                s.picture.bounds = CGRect(origin: .zero, size: picture.size)
                s.picture.anchorPoint = picture.anchor
                s.picture.position = CGPoint(x: picture.position.x - origin.x, y: picture.position.y - origin.y)
                s.picture.transform = picture.transform
                s.picture.isHidden = false
            } else {
                s.picture.isHidden = true
            }
        }
        CATransaction.commit()
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for s in surfaces {
            s.border.fillColor = colors.outline
            s.border.strokeColor = colors.outline
            s.fill.fillColor = colors.fill
        }
        CATransaction.commit()
    }

    @objc private func screensChanged() {
        if isActive { rebuildWindows() }
    }

    private func rebuildWindows() {
        surfaces.forEach { $0.window.orderOut(nil) }
        surfaces = NSScreen.screens.map(makeSurface)
        render()
    }

    private func makeSurface(for screen: NSScreen) -> Surface {
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        // 許可ダイアログなどのシステムの窓より手前に出すため、カーソル専用の層に置く
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .never
        w.contentView = view

        let border = CAShapeLayer()
        border.fillColor = colors.outline
        border.strokeColor = colors.outline
        border.lineJoin = .round
        border.shadowColor = NSColor.black.cgColor
        border.shadowOpacity = Tuning.Render.shadowOpacity
        border.shadowRadius = Tuning.Render.shadowRadius
        border.shadowOffset = Tuning.Render.shadowOffset

        let fill = CAShapeLayer()
        fill.fillColor = colors.fill

        // 画像はカーソル本来の色と影を含むので、色の設定は当てない
        let picture = CALayer()
        picture.contentsGravity = .resize
        picture.minificationFilter = .trilinear
        picture.isHidden = true

        for layer in [border, fill, picture] {
            layer.contentsScale = screen.backingScaleFactor
            view.layer?.addSublayer(layer)
        }
        w.orderFrontRegardless()
        return Surface(window: w, border: border, fill: fill, picture: picture)
    }
}
