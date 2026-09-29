import AppKit
import JellyCursorCore
import SwiftUI

// 設定画面のプレビュー。決まった道筋（PreviewScript）でマウスを動かし、クリックしたときの矢印と I 字を、今の設定の動きで描く。
// SwiftUI の TimelineView は、macOS 26 で書き換えが届かず何も描かれないことがあったので、
// 実際のカーソルと同じく、層（CAShapeLayer）を画面の書き換えに合わせて動かす
struct MotionPreview: NSViewRepresentable {
    let motion: MotionParameters

    func makeNSView(context: Context) -> MotionPreviewView {
        MotionPreviewView()
    }

    func updateNSView(_ view: MotionPreviewView, context: Context) {
        view.motion = motion
    }
}

final class MotionPreviewView: NSView {
    // 見やすいよう、ポインタの大きさ2のときの大きさで描く
    private static let scale: CGFloat = 2
    private static let margin: CGFloat = 26

    var motion = MotionParameters.standard {
        didSet {
            guard motion != oldValue else { return }
            figures = [Jelly(scale: Self.scale, motion: motion), IBeam(scale: Self.scale, motion: motion)]
            advance(dt: 0)
        }
    }

    // 上の段に矢印、下の段に I 字
    private var figures: [CursorFigure] = [Jelly(scale: MotionPreviewView.scale), IBeam(scale: MotionPreviewView.scale)]
    private var layers: [(border: CAShapeLayer, fill: CAShapeLayer)] = []
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var time: Double = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("動きのプレビュー")
        // Overlay と同じく、縁（影つき）を太く塗ってから中身を塗る
        let colors = SystemPointer.colors()
        layers = figures.map { _ in
            let border = CAShapeLayer()
            border.fillColor = colors.outline.cgColor
            border.strokeColor = colors.outline.cgColor
            border.lineJoin = .round
            border.shadowColor = NSColor.black.cgColor
            border.shadowOpacity = Tuning.Render.shadowOpacity
            border.shadowRadius = Tuning.Render.shadowRadius * Self.scale
            border.shadowOffset = CGSize(width: Tuning.Render.shadowOffset.width * Self.scale,
                                         height: Tuning.Render.shadowOffset.height * Self.scale)
            let fill = CAShapeLayer()
            fill.fillColor = colors.fill.cgColor
            layer?.addSublayer(border)
            layer?.addSublayer(fill)
            return (border, fill)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        updateScale()
        updateLink()
    }

    @objc private func occlusionChanged() {
        updateLink()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    // 大きさが決まったら、動かし始める前の形をすぐ描く
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        advance(dt: 0)
    }

    // 窓が画面に見えている間だけ、画面の書き換えに合わせて動かす。
    // 窓を閉じた・しまった・ほかの窓に隠れた・ほかのタブを開いた間は止める
    private func updateLink() {
        let running = window?.occlusionState.contains(.visible) == true
        if running, link == nil {
            let newLink = displayLink(target: self, selector: #selector(tick(_:)))
            newLink.add(to: .main, forMode: .common)
            link = newLink
        } else if !running, let link {
            link.invalidate()
            self.link = nil
            // 次に動かし始めたとき、止めていた間の時間を1フレームで進めない
            lastTimestamp = nil
        }
    }

    private func updateScale() {
        let scale = window?.backingScaleFactor ?? 2
        for (border, fill) in layers {
            border.contentsScale = scale
            fill.contentsScale = scale
        }
    }

    // 描いている矢印と I 字の範囲（試験用）
    var figureBounds: [CGRect] {
        layers.map { $0.fill.path?.boundingBoxOfPath ?? .null }
    }

    @objc private func tick(_ current: CADisplayLink) {
        let dt = lastTimestamp.map { min(max(current.timestamp - $0, 0), Tuning.Render.maxFrameStep) } ?? 0
        lastTimestamp = current.timestamp
        advance(dt: dt)
    }

    // dt 秒進めて描き直す
    func advance(dt: Double) {
        guard bounds.width > 2 * Self.margin, bounds.height > 4 * Self.margin else { return }
        time += dt
        let position = PreviewScript.position(at: time)
        let laneHeight = bounds.height / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, (figure, shapes)) in zip(figures, layers).enumerated() {
            // 段の中の位置（左下原点）。上の段が index 0
            let laneBottom = bounds.height - laneHeight * CGFloat(index + 1)
            let mouse = CGPoint(x: Self.margin + position.x * (bounds.width - 2 * Self.margin),
                                y: laneBottom + Self.margin + position.y * (laneHeight - 2 * Self.margin))
            figure.step(to: mouse, dt: CGFloat(dt), pressed: PreviewScript.isPressed(at: time))
            let path = figure.path(offsetBy: CGVector(dx: 0, dy: 0))
            shapes.border.path = path
            shapes.border.shadowPath = path
            shapes.border.lineWidth = figure.borderWidth * 2
            shapes.fill.path = path
        }
        CATransaction.commit()
    }
}
