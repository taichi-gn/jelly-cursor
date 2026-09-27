import AppKit
import JellyCursorCore
import SwiftUI

// 設定画面のプレビュー。決まった道筋（PreviewScript）でマウスを動かしたときの矢印と I 字を、今の設定の動きで描く
struct MotionPreview: View {
    let style: MotionStyle
    @State private var model = PreviewModel()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { graphics, size in
                model.draw(in: &graphics, size: size, date: context.date, style: style)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("動きのプレビュー")
    }
}

// 描くたびに動かす。SwiftUI に変化を知らせない（知らせると描き直しが止まらなくなる）ので、Observable にはしない
@MainActor
private final class PreviewModel {
    // 見やすいよう、ポインタの大きさ2のときの大きさで描く
    private static let scale: CGFloat = 2
    private static let margin: CGFloat = 26

    private var style: MotionStyle?
    private var arrow = Jelly(scale: PreviewModel.scale)
    private var iBeam = IBeam(scale: PreviewModel.scale)
    private var time: Double = 0
    private var lastDate: Date?
    private let colors = SystemPointer.colors()

    func draw(in graphics: inout GraphicsContext, size: CGSize, date: Date, style: MotionStyle) {
        if style != self.style {
            self.style = style
            let motion = MotionParameters(style)
            arrow = Jelly(scale: Self.scale, motion: motion)
            iBeam = IBeam(scale: Self.scale, motion: motion)
            lastDate = nil
        }
        // 窓を隠していた間などに時間が飛んでも、1フレームで大きく動かさない
        let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), Tuning.Render.maxFrameStep) } ?? 0
        lastDate = date
        time += dt

        let lanes = [
            CGRect(x: 0, y: 0, width: size.width, height: size.height / 2),
            CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2),
        ]
        let figures: [CursorFigure] = [arrow, iBeam]
        let position = PreviewScript.position(at: time)
        for (lane, figure) in zip(lanes, figures) {
            // 枠の中の位置（左下原点）。描くときに上下を返す
            let mouse = CGPoint(x: Self.margin + position.x * (lane.width - 2 * Self.margin),
                                y: Self.margin + position.y * (lane.height - 2 * Self.margin))
            figure.step(to: mouse, dt: CGFloat(dt))
            draw(figure, in: lane, graphics: &graphics)
        }
    }

    // Overlay と同じく、縁（影つき）を太く塗ってから中身を塗る
    private func draw(_ figure: CursorFigure, in lane: CGRect, graphics: inout GraphicsContext) {
        var path = Path()
        path.addLines(figure.points.map { CGPoint(x: lane.minX + $0.x, y: lane.maxY - $0.y) })
        path.closeSubpath()
        let outline = Color(cgColor: colors.outline.cgColor)
        graphics.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(Double(Tuning.Render.shadowOpacity)),
                                    radius: Tuning.Render.shadowRadius * Self.scale, x: 0,
                                    y: -Tuning.Render.shadowOffset.height * Self.scale))
            layer.fill(path, with: .color(outline))
            layer.stroke(path, with: .color(outline),
                         style: StrokeStyle(lineWidth: figure.borderWidth * 2, lineJoin: .round))
        }
        graphics.fill(path, with: .color(Color(cgColor: colors.fill.cgColor)))
    }
}
