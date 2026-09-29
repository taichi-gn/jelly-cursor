import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 文字の上の I 字。変形はいつも中心（クリック位置）を基準にするので、文字を選ぶ位置はずれない
package final class IBeam: CursorFigure {
    // macOS 標準の I 字（倍率1）の黒い中身の輪郭。NSCursor.iBeam の最高解像度の画像を4倍に拡大してから読み取った
    // （縦棒が細いので、そのままだと縁が内側に寄って1割ほど細くなる）。中心（ホットスポット）が原点で y は下向き
    private static let outline: [CGPoint] = [
        .init(x: -0.01, y: -0.01), .init(x: -0.01, y: 5.49), .init(x: 0.09, y: 5.86), .init(x: 0.29, y: 6.29),
        .init(x: 0.74, y: 6.81), .init(x: 1.41, y: 7.21), .init(x: 2.14, y: 7.41), .init(x: 2.29, y: 7.61),
        .init(x: 2.29, y: 8.01), .init(x: 1.99, y: 8.29), .init(x: 1.59, y: 8.29), .init(x: 0.94, y: 8.09),
        .init(x: 0.01, y: 7.49), .init(x: -0.39, y: 6.96), .init(x: -0.56, y: 6.89), .init(x: -0.91, y: 7.39),
        .init(x: -1.74, y: 7.99), .init(x: -2.59, y: 8.29), .init(x: -3.06, y: 8.26), .init(x: -3.29, y: 8.06),
        .init(x: -3.26, y: 7.54), .init(x: -2.99, y: 7.31), .init(x: -2.41, y: 7.21), .init(x: -1.76, y: 6.81),
        .init(x: -1.29, y: 6.26), .init(x: -0.99, y: 5.46), .init(x: -0.99, y: -5.46), .init(x: -1.19, y: -6.09),
        .init(x: -1.61, y: -6.69), .init(x: -2.41, y: -7.21), .init(x: -3.16, y: -7.41), .init(x: -3.29, y: -7.59),
        .init(x: -3.29, y: -8.04), .init(x: -2.99, y: -8.29), .init(x: -2.59, y: -8.29), .init(x: -1.94, y: -8.09),
        .init(x: -1.14, y: -7.59), .init(x: -0.56, y: -6.89), .init(x: -0.41, y: -6.91), .init(x: -0.19, y: -7.29),
        .init(x: 0.14, y: -7.59), .init(x: 0.94, y: -8.09), .init(x: 1.59, y: -8.29), .init(x: 1.99, y: -8.29),
        .init(x: 2.29, y: -8.01), .init(x: 2.29, y: -7.61), .init(x: 2.16, y: -7.41), .init(x: 1.01, y: -7.01),
        .init(x: 0.59, y: -6.66), .init(x: 0.09, y: -5.86), .init(x: -0.01, y: -5.49),
    ]

    private struct Vertex {
        let offset: CGVector
        // 縦棒なら1、上下の飾りなら serifWiden。太くなる度合いに使う
        let widenWeight: CGFloat
    }

    private let vertices: [Vertex]
    package private(set) var points: [CGPoint]
    package let borderWidth: CGFloat
    package private(set) var isSettled = true

    private var widen: SpringValue
    private var stretch: SpringValue
    private var lean: SpringValue
    // 太り・伸び・傾きの最大値。設定の「伸び」を掛けたもの
    private let maxWiden: CGFloat
    private let maxStretch: CGFloat
    private let maxLean: CGFloat
    private var smoothedVel = CGVector.zero
    private var lastMouse: CGPoint?
    private var squish: ClickSquish
    private let motion: MotionParameters
    private let height: CGFloat
    // 縦棒の中心線。クリック位置より少し左にあるので、ここを基準に広げて縦棒が横にずれないようにする
    private let stemCenterX: CGFloat

    package init(scale: CGFloat, motion: MotionParameters = .standard) {
        widen = SpringValue(omega: Tuning.IBeam.omega, dampingRatio: motion.iBeamDampingRatio)
        stretch = SpringValue(omega: Tuning.IBeam.omega, dampingRatio: motion.iBeamDampingRatio)
        lean = SpringValue(omega: Tuning.IBeam.omega, dampingRatio: motion.iBeamDampingRatio)
        maxWiden = Tuning.IBeam.maxWiden * motion.stretch
        maxStretch = Tuning.IBeam.maxStretch * motion.stretch
        maxLean = Tuning.IBeam.maxLean * motion.stretch
        squish = ClickSquish(motion: motion)
        self.motion = motion
        vertices = Self.outline.map { p in
            let t = Self.smoothstep(Tuning.IBeam.stemHalfHeight, Tuning.IBeam.serifStart, abs(p.y))
            return Vertex(offset: CGVector(dx: p.x * scale, dy: -p.y * scale),
                          widenWeight: 1 + (Tuning.IBeam.serifWiden - 1) * t)
        }
        points = Array(repeating: .zero, count: vertices.count)
        borderWidth = Tuning.Arrow.borderWidth * scale
        height = (Self.outline.map(\.y).max() ?? 1) * 2 * scale
        let stemXs = Self.outline.filter { abs($0.y) <= Tuning.IBeam.stemHalfHeight }.map(\.x)
        stemCenterX = ((stemXs.min() ?? 0) + (stemXs.max() ?? 0)) / 2 * scale
    }

    package func step(to mouse: CGPoint, dt: CGFloat, pressed: Bool) {
        // ポインタが飛んだら、新しい位置で止まっている状態から始め直す（飛んだ速さで大きく伸びないように）
        if let lastMouse, isJump(from: lastMouse, to: mouse, dt: dt) {
            squish.follow(jumpTo: mouse)
            widen = SpringValue(omega: Tuning.IBeam.omega, dampingRatio: motion.iBeamDampingRatio)
            stretch = SpringValue(omega: Tuning.IBeam.omega, dampingRatio: motion.iBeamDampingRatio)
            lean = SpringValue(omega: Tuning.IBeam.omega, dampingRatio: motion.iBeamDampingRatio)
            smoothedVel = .zero
            self.lastMouse = nil
        }
        if let lastMouse, dt > 0 {
            let k = 1 - exp(-Tuning.IBeam.velocitySmoothing * dt)
            smoothedVel.dx += ((mouse.x - lastMouse.x) / dt - smoothedVel.dx) * k
            smoothedVel.dy += ((mouse.y - lastMouse.y) / dt - smoothedVel.dy) * k
            widen.step(toward: maxWiden * tanh(abs(smoothedVel.dx) / Tuning.IBeam.widenSpeed), dt: dt)
            stretch.step(toward: maxStretch * tanh(abs(smoothedVel.dy) / Tuning.IBeam.stretchSpeed), dt: dt)
            // 動いた方向の線に沿うように傾ける。sin 2θ は右上・左下で正（/）、左上・右下で負（\）、
            // 真横・真上下で 0（傾けない）
            let speed = hypot(smoothedVel.dx, smoothedVel.dy)
            // 動いた向きの角度から求める（速さで割ると、止まって速さがごく小さくなったときに2乗が 0 になり、割れなくなる）
            let diagonal = sin(2 * atan2(smoothedVel.dy, smoothedVel.dx))
            lean.step(toward: maxLean * diagonal * tanh(speed / Tuning.IBeam.leanSpeed), dt: dt)
        }
        lastMouse = mouse
        layOut(at: mouse)
        // クリックしたら、中心（クリック位置）へ向けて縦につぶし、そのぶん横に太らせる
        squish.step(pressed: pressed, mouse: mouse, dt: dt)
        squish.apply(to: &points, anchor: CGPoint(x: mouse.x + stemCenterX, y: mouse.y), axis: CGVector(dx: 0, dy: 1))
        // 形の変化を、I 字の高さに対するピクセル数に直して比べる
        let worst = max(max(widen.restError, stretch.restError, lean.restError) * height, squish.restError(size: height))
        isSettled = worst < Tuning.Settle.threshold
    }

    // 太り・伸びのばねは、戻るときに反対側へ行き過ぎる。伸び・弾みを大きくしたときに幅や高さが 0 以下になって
    // 形が裏返らないよう、倍率に下限を設ける（標準の設定では下限まで行かない）
    private func layOut(at mouse: CGPoint) {
        let minScale = Tuning.IBeam.minScale
        let heightScale = max(1 + stretch.value - Tuning.IBeam.squash * widen.value, minScale)
        let thinning = 1 / sqrt(max(1 + stretch.value, minScale))
        for (i, v) in vertices.enumerated() {
            let y = v.offset.dy * heightScale
            // y は上向き。lean が正なら上側を右へずらして / にする
            let x = stemCenterX + (v.offset.dx - stemCenterX) * max(1 + widen.value * v.widenWeight, minScale) * thinning
                + lean.value * y
            points[i] = CGPoint(x: mouse.x + x, y: mouse.y + y)
        }
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
