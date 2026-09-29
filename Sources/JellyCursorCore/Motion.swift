import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 設定画面で選ぶ動きの強さ。どちらも 1 が標準（これまでの動き）で、0〜2 の範囲
// - stretch（伸び）: 矢印と指の伸び、I 字の太り・伸び・傾きの大きさ。0 なら形を変えず向きだけ変える
// - wobble（弾み）: 止めたときや向きを変えたときの弾み。0 なら行き過ぎずに収まり、2 なら標準より大きく弾む
package struct MotionStyle: Codable, Equatable, Sendable {
    package static let range: ClosedRange<Double> = 0...2
    package static let standard = MotionStyle(stretch: 1, wobble: 1)

    package var stretch: Double {
        didSet { stretch = Self.clamp(stretch) }
    }
    package var wobble: Double {
        didSet { wobble = Self.clamp(wobble) }
    }

    package init(stretch: Double, wobble: Double) {
        self.stretch = Self.clamp(stretch)
        self.wobble = Self.clamp(wobble)
    }

    // 保存した値が壊れていても範囲に収める
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(stretch: (try? c.decode(Double.self, forKey: .stretch)) ?? 1,
                  wobble: (try? c.decode(Double.self, forKey: .wobble)) ?? 1)
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : 1
    }
}

package enum MotionPreset: String, CaseIterable, Sendable {
    case subtle, standard, lively

    package var style: MotionStyle {
        switch self {
        case .subtle: MotionStyle(stretch: 0.5, wobble: 0.3)
        case .standard: .standard
        case .lively: MotionStyle(stretch: 1.6, wobble: 1.5)
        }
    }

    package var title: String {
        switch self {
        case .subtle: "控えめ"
        case .standard: "標準"
        case .lively: "大きめ"
        }
    }

    // 値がどのプリセットとも違えば nil（カスタム）。スライダーの刻みのずれは同じとみなす
    package init?(matching style: MotionStyle) {
        guard let preset = Self.allCases.first(where: {
            abs($0.style.stretch - style.stretch) < 0.005 && abs($0.style.wobble - style.wobble) < 0.005
        }) else { return nil }
        self = preset
    }
}

// MotionStyle から作る、描く側が使う値。標準のときは Tuning の値そのものになる
package struct MotionParameters: Equatable, Sendable {
    package static let standard = MotionParameters(.standard)

    // 伸び・太り・傾きの最大値にかける倍率
    package let stretch: CGFloat
    // 動いている間に進行方向へ回るときの減衰
    package let turnDampingRatio: CGFloat
    // 止めたあと元の向きへ戻るときの、1回目の行き過ぎの減衰
    package let returnSwingDampingRatio: CGFloat
    package let iBeamDampingRatio: CGFloat
    package let handDampingRatio: CGFloat
    // クリックでつぶれる割合（0 ならつぶれない）と、離したときの戻りの減衰
    package let clickDepth: CGFloat
    package let clickReleaseDampingRatio: CGFloat

    // clickBounce は設定の「クリックで弾む」。つぶれる深さは「伸び」、離したときの弾みは「弾み」に合わせる
    package init(_ style: MotionStyle, clickBounce: Bool = true) {
        stretch = CGFloat(style.stretch)
        let wobble = CGFloat(style.wobble)
        turnDampingRatio = Self.dampingRatio(Tuning.Turn.dampingRatio, wobble: wobble)
        returnSwingDampingRatio = Self.dampingRatio(Tuning.Turn.returnSwingDampingRatio, wobble: wobble)
        iBeamDampingRatio = Self.dampingRatio(Tuning.IBeam.dampingRatio, wobble: wobble)
        handDampingRatio = Self.dampingRatio(Tuning.Hand.dampingRatio, wobble: wobble)
        clickDepth = clickBounce ? min(Tuning.Click.depth * stretch, Tuning.Click.maxSquash) : 0
        clickReleaseDampingRatio = Self.dampingRatio(Tuning.Click.releaseDampingRatio, wobble: wobble)
    }

    // 弾みから減衰の度合いを決める。0 で 1（行き過ぎない）、1 で標準の値、2 で標準の半分（よく弾む）
    static func dampingRatio(_ standard: CGFloat, wobble: CGFloat) -> CGFloat {
        wobble <= 1 ? standard + (1 - standard) * (1 - wobble) : standard * (1 - (wobble - 1) / 2)
    }
}
