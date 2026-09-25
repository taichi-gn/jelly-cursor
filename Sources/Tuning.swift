import Foundation
import QuartzCore

enum Tuning {
    // 大きさはシステム設定の「ポインタの大きさ」に合わせる（ArrowShape.systemPointerScale）
    enum Arrow {
        static let vertexSpacing: CGFloat = 1.0
        // 標準の矢印の白い縁の太さ（倍率1のとき）
        static let borderWidth: CGFloat = 1.0
    }

    // 胴体はマウスが通った道の上に並ぶ。矢印の長さ ＝ 普段の長さ ＋ 直近 duration 秒に動いた距離
    enum Trail {
        static let duration: CGFloat = 0.07
        static let maxStretch: CGFloat = 60
        static let lengthSmoothing: CGFloat = 0.03
        // 伸びたぶん細くする度合い。0.5 なら長さ2倍で幅が約0.7倍、0 なら幅は変わらない
        static let thinning: CGFloat = 0.5
        // 道の向きを測るときに前後何pxの区間を使うか。短いと手ぶれで向きがばたつく
        static let tangentWindow: CGFloat = 3
    }

    // 進行方向へ先端を向ける。手ぶれで回らないよう、一定の速さを超えたときだけ向きを更新する
    enum Turn {
        static let omega: CGFloat = 18
        static let dampingRatio: CGFloat = 0.65
        static let minSpeed: CGFloat = 80
        // 少し動かしただけで回らないよう、動き始めてからこの距離(pt)動くまでは向きを変えない。
        // この秒数止まったら、動いた距離を数え直す
        static let minTravel: CGFloat = 30
        static let travelResetDelay: CGFloat = 0.15
        static let velocitySmoothing: CGFloat = 20
        // 角度のずれをピクセルに換算するときの尾の長さ
        static let armLength: CGFloat = 30
        // 位置が変わらない状態がこの秒数続いたら、元の向き（左上）へ戻す。
        // 振り子のように1回だけ行き過ぎ、折り返したら弾まずに収まる。
        // 行き過ぎの大きさは returnSwingDampingRatio で決まる（0.4 で約25%、1 で行き過ぎない）
        static let returnDelay: CGFloat = 0.2
        static let returnOmega: CGFloat = 18
        static let returnSwingDampingRatio: CGFloat = 0.4
        static let returnSettleDampingRatio: CGFloat = 1.0
    }

    // 文字の上の I 字。進行方向には回さず、速さで形だけ変える。値はすべて倍率1のときの比
    enum IBeam {
        // 横に速く動かすと縦棒が最大 1 + maxWiden 倍の太さになる。widenSpeed(pt/秒)でその約76%
        static let maxWiden: CGFloat = 2.4
        static let widenSpeed: CGFloat = 900
        // 上下の飾りは、縦棒の広がりのこの割合だけ広がる
        static let serifWiden: CGFloat = 0.35
        // 太くなったぶん高さを縮める割合
        static let squash: CGFloat = 0.12
        // 縦に速く動かすと高さが最大 1 + maxStretch 倍になり、そのぶん細くなる
        static let maxStretch: CGFloat = 0.5
        static let stretchSpeed: CGFloat = 1200
        // 斜めに動かすと、その向きの線に沿うように傾ける（右上・左下なら /、左上・右下なら \）。
        // 真横・真上下では傾けない。0.45 はおよそ24度。0 にすれば傾けない
        static let maxLean: CGFloat = 0.45
        static let leanSpeed: CGFloat = 900
        // 止めたとき1回小さく弾んで、約0.3秒で戻る
        static let omega: CGFloat = 26
        static let dampingRatio: CGFloat = 0.45
        static let velocitySmoothing: CGFloat = 20
        // 縦棒と飾りの境目（中心からの縦の距離）。標準の I 字は縦棒の直線部分が 5.5 まで続く
        static let stemHalfHeight: CGFloat = 5.5
        static let serifStart: CGFloat = 7.5
    }

    // リンクの上の指。回り方は矢印と同じ Turn の値を使う（少し動かしただけでは回らず、止めると上向きに戻る）
    enum Hand {
        // 速く動かすと、指差す向きに最大 1 + maxStretch 倍まで伸び、そのぶん細くなる。stretchSpeed(pt/秒)でその約76%
        static let maxStretch: CGFloat = 0.6
        static let stretchSpeed: CGFloat = 1500
        static let omega: CGFloat = 26
        static let dampingRatio: CGFloat = 0.45
        static let velocitySmoothing: CGFloat = 20
        // 指の向きをならす時間（秒）。長いほど手ぶれで震えにくいが、矢印より遅れる
        static let angleSmoothing: CGFloat = 0.01
        // 回る速さの上限（ラジアン/秒）。120Hzで1フレーム30度
        static let maxTurnRate: CGFloat = .pi / 6 * 120
        // 道の向きがばねの向きからこの角度より離れていたら、ほぼ逆とみなす
        static let oppositeTurn: CGFloat = .pi * 3 / 4
    }

    enum Settle {
        static let substeps = 4
        // すべてのずれがこのピクセル数を下回り、マウスも止まっていたら、更新を止めて眠る
        static let threshold: CGFloat = 0.05
        // 速度を「このあと何pxずれるか」に換算する係数
        static let velocityWeight: CGFloat = 0.02
    }

    enum Render {
        static let maxFrameStep: TimeInterval = 1.0 / 30
        // 眠っている間にマウス位置を見る頻度。動き出しの遅れは最大でこの1フレーム分
        static let idleFrameRate = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        // 隠し直しが効かず本物に任せたあと、隠れた状態がこの回数続いたら自前の絵に戻す
        // （動いている間の120Hzで約0.1秒、眠っている間の30〜60Hzで0.2〜0.4秒）
        static let overpowerRecoverChecks = 12
        // 他のアプリが本物のカーソルを隠しているかを調べるのは、マウスがこの秒数止まってから、この間隔ごと。
        // 調べる瞬間に本物が映っても重なるよう、矢印が元の形に戻りきってから調べる
        static let otherHideDelay: TimeInterval = 1
        static let otherHideInterval: TimeInterval = 0.5
        static let otherHideRecheckInterval: TimeInterval = 2
        static let otherHideInputSettle: TimeInterval = 0.3
        // 自分の分を戻してから、この秒数見えなければ他のアプリが隠していると判断する。
        // 他のアプリが隠している間は、調べるたびにこの秒数だけ待つ
        static let otherHideProbeTimeout: TimeInterval = 0.01
        // システム設定のポインタの色と大きさを読み直す間隔（秒）
        static let colorCheckInterval: TimeInterval = 1
        // JellyCursor の窓より手前にある窓（システムのダイアログなど）を調べる間隔（秒）
        static let coverCheckInterval: TimeInterval = 0.1
        // 手前の窓のうち、縦横ともこの大きさ（倍率1のとき、pt）以下のものは数えない（本物のカーソルが窓として出ることがあるため）
        static let coverIgnoreSize: CGFloat = 48
        static let shadowOpacity: Float = 0.35
        static let shadowRadius: CGFloat = 1.5
        static let shadowOffset = CGSize(width: 0, height: -1.5)
    }
}
