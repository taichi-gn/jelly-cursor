import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 動きの標準の値。設定の「伸び」「弾み」で変わる値は、MotionParameters がここから作る
package enum Tuning {
    // 大きさはシステム設定の「ポインタの大きさ」に合わせる（JellyCursorKit の SystemPointer.scale）
    enum Arrow {
        static let vertexSpacing: CGFloat = 1.0
        // 標準の矢印の白い縁の太さ（倍率1のとき）
        static let borderWidth: CGFloat = 1.0
    }

    // 胴体はマウスが通った道の上に並ぶ。矢印の長さ ＝ 普段の長さ ＋ 直近 duration 秒に動いた距離
    enum Trail {
        static let duration: CGFloat = 0.07
        // 胴体がその秒数に動いた道のりより長いとき、後ろのほうを沿わせる道を、何秒前まで覚えておくか
        static let keepTime: CGFloat = 0.5
        static let maxStretch: CGFloat = 60
        static let lengthSmoothing: CGFloat = 0.03
        // 今の速さのならしの時間（秒）。伸びは、今の速さでその秒数（duration）に進む道のりまでに抑える
        static let speedSmoothing: CGFloat = 0.008
        // 位置が変わらないフレームが、この秒数より短く続いただけなら、今の速さに数えない（マウスの報告が画面の書き換えより遅いときの抜け）
        static let stillHold: CGFloat = 0.02
        // 伸びたぶん細くする度合い。0.5 なら長さ2倍で幅が約0.7倍、0 なら幅は変わらない
        static let thinning: CGFloat = 0.5
        // 道の向きを測るときに前後何pxの区間を使うか。短いと手ぶれで向きがばたつく
        static let tangentWindow: CGFloat = 3
        // 道の向きとまっすぐな胴体の向きの cos が opposedCosine より小さい（100度より開いている）と、道に沿わせない。
        // opposingCosine（70度）までは沿わせる
        static let opposingCosine: CGFloat = 0.34
        static let opposedCosine: CGFloat = -0.17
        // 道に沿わせたい度合いがこれ以上のとき（すでに道に沿っているとき）は、向きがずれても沿わせる度合いを下げない
        static let gateHold: CGFloat = 0.9
        // 沿わせてよい度合いを下げる速さと上げる速さ（秒）。速く動かし始めたときに間に合うよう、下げるのは急ぐ
        static let gateCloseTime: CGFloat = 0.003
        static let gateOpenTime: CGFloat = 0.05
        // 道に沿わせたい状態がこの秒数続いても向きがそろわなければ、さらに gateForceTime 秒かけて沿わせる
        static let gateForceDelay: CGFloat = 0.15
        static let gateForceTime: CGFloat = 0.15
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
        // 手ぶれとみなす大きさ(pt)と、手ぶれの中心を求めるならしの時間（秒）。ならした点からこれより離れていなければ、
        // 動いた距離に数えず、向きも変えない（止めた手がふるえても、矢印が曲がったり指が首を振ったりしないように）
        static let tremorRadius: CGFloat = 4
        static let tremorSmoothing: CGFloat = 0.1
        // 角度のずれをピクセルに換算するときの尾の長さ
        static let armLength: CGFloat = 30
        // 位置が変わらない状態がこの秒数続いたら、元の向き（左上）へ戻す。
        // 振り子のように1回だけ行き過ぎ、折り返したら弾まずに収まる。
        // 行き過ぎの大きさは returnSwingDampingRatio で決まる（0.4 で約25%、1 で行き過ぎない）
        static let returnDelay: CGFloat = 0.2
        // 手ぶれだけの状態や、今の向きから外れた向きへゆっくり動かす状態がこの秒数続いたら、元の向きへ戻す。
        // 動いた向きと今の向きの cos が astrayCosine より小さい（60度より開いている）と、外れているとみなす
        static let slowReturnDelay: CGFloat = 0.4
        static let astrayCosine: CGFloat = 0.5
        static let returnOmega: CGFloat = 18
        static let returnSwingDampingRatio: CGFloat = 0.4
        static let returnSettleDampingRatio: CGFloat = 1.0
        // 向ける先が急に変わった大きさがこれ（ラジアン）より大きい（ほぼ逆向き）とき、それまでに unwindTurn より回っていたら、
        // 巻き戻す側へ回す
        static let oppositeTurn: CGFloat = 2.6
        static let unwindTurn: CGFloat = 0.5
    }

    // 道が胴体の長さのうちで折り返したとき（左右に振ったときなど）。道に沿わせると胴体が自分と重なって崩れて見えるので、
    // 伸びを戻しながら、胴体をまっすぐにして先端のまわりで新しい向きへ回す
    enum Fold {
        // 先端近くの道の向きから、この角度より大きく曲がっていたら折り返しとみなす。
        // 90度の曲がり角（上へ動いてから横へ）は、これまでどおり道に沿って曲げる
        static let angle: CGFloat = 100 * .pi / 180
        // 先端近くの道の向きを測る長さ（pt）。短いと手ぶれで折り返しと見てしまう
        static let reference: CGFloat = 3
        // 回すばね。行き過ぎず、速く振ったときは折り返してから約0.03〜0.05秒で向きがそろう
        static let omega: CGFloat = 120
        // 回している間に胴体の端が動く速さの上限（pt/秒）。長いうちはゆっくり、縮むにつれて速く回る。
        // 1フレームで端が飛びすぎない値
        static let maxTailSpeed: CGFloat = 2000
        // 先端近くの道の向きと、先端から折り返しへの向きの cos がこれより大きければ（約37度以内）、折り返しから先端までの道は
        // ほぼまっすぐとみなす
        static let straightCosine: CGFloat = 0.8
        // 回し始めて縮めるときの、長さのならしの時間（秒）。ふだん（Trail.lengthSmoothing）より早く縮める
        static let shrinkSmoothing: CGFloat = 0.02
        // 回し終えたときの伸びを減らす時間（秒）
        static let keepDecay: CGFloat = 0.1
        // ゆっくり折り返したときは、胴体の端が動く速さを、先端の速さのこの倍までにする（ただし minTailSpeed pt/秒 までは許す）
        static let tailSpeedRatio: CGFloat = 4
        static let minTailSpeed: CGFloat = 300
        // 回す先がこの角度より大きく離れていたら、ほぼ逆向きとみなし、決めた側へ回す（右回りと左回りが入れ替わらないように）
        static let oppositeTurn: CGFloat = 2.6
        // 折り返しで回した向きの合計がこれ（ラジアン）を超えていたら、ほぼ逆向きへ回すときは巻き戻す側へ回す
        static let unwindTurn: CGFloat = 0.5
        // まっすぐにして回し始めるとき、胴体の尾が中ほどからこの角度（ラジアン）より横にあれば、曲がっている側へ回す
        static let curlAngle: CGFloat = 0.2
        // 回す先か今の向きが、止まったときの向きからこの角度（ラジアン）以内なら、どちら側へ回しても同じくらいなので、前と同じ側へ回す
        static let restTie: CGFloat = 0.35
        // この秒数折り返さなければ、回した向きの合計を忘れる
        static let turnMemory: CGFloat = 1
        // 先端が折り返しからこの道のり(pt)離れるまでは回さない。行き過ぎて少し戻したときに、向きを変えないように
        static let minTurnTravel: CGFloat = 10
        // 折り返しが胴体より後ろへ抜け、回す先との差がこれ（ラジアン）より小さくなったら、道に沿わせるのに戻る
        static let finishAngle: CGFloat = 0.15
        // 道に沿わせるのをやめる速さと、戻す速さ（秒）
        static let followDrop: CGFloat = 0.008
        static let followRecover: CGFloat = 0.04
    }

    // クリックしたとき。押すとクリック位置へ向けてつぶれ、離すと少し伸びる側へ弾んでから戻る
    package enum Click {
        // 押したときにつぶれる割合（伸び 100% のとき）。横には 1/√(1 - つぶれ) 倍に太る
        static let depth: CGFloat = 0.16
        // つぶれと伸びの上限。形が裏返らないように
        static let maxSquash: CGFloat = 0.35
        static let maxStretch: CGFloat = 0.3
        // 押したとき。約0.05秒で、ほとんど行き過ぎずにつぶれる
        static let pressOmega: CGFloat = 45
        static let pressDampingRatio: CGFloat = 0.8
        // 離したとき。つぶれの約3割だけ伸びる側へ行き過ぎて、約0.4秒で戻る（弾み 100% のとき）
        static let releaseOmega: CGFloat = 30
        static let releaseDampingRatio: CGFloat = 0.35
        // 押した位置から dragDeadZone(pt) までは手のふるえとみなし、そこから dragRelease(pt) 離れるとつぶれを戻しきる
        // （ドラッグの間はふつうの動きにする）
        static let dragDeadZone: CGFloat = 4
        static let dragRelease: CGFloat = 12
        // これより短いクリック（トラックパッドのタップなど）も、この秒数は押したことにする。
        // ボタンを見に行く間（眠っている間は1/60秒）より短いクリックも見逃さず、つぶれて弾むのが見えるように
        package static let minimumPress: TimeInterval = 0.08
        // 戻りきったとみなす、つぶれの割合
        static let restSnap: CGFloat = 0.001
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
        // 幅と高さの倍率の下限。戻りの行き過ぎで形が裏返らないように
        static let minScale: CGFloat = 0.3
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

    // 1フレームでこの距離(pt)より遠く、この速さ(pt/秒)より速く移ったら、手で動かしたのではなく飛んだとみなす
    enum Jump {
        static let distance: CGFloat = 250
        static let speed: CGFloat = 15000
        // 表示が詰まったフレーム（経過時間が上限で切られたとき）で、飛んだとみなす距離(pt)
        static let stalledDistance: CGFloat = 1000
    }

    enum Settle {
        static let substeps = 4
        // ばねを1回に動かす時間の上限（秒）。フレームが 1/30 秒までなら substeps 回で足りる
        static let maxSubstep: CGFloat = 1.0 / 120
        // すべてのずれがこのピクセル数を下回り、マウスも止まっていたら、更新を止めて眠る
        static let threshold: CGFloat = 0.05
        // 速度を「このあと何pxずれるか」に換算する係数
        static let velocityWeight: CGFloat = 0.02
    }

    package enum Render {
        package static let maxFrameStep: TimeInterval = 1.0 / 30
        // 眠っている間にマウス位置を見る間隔（秒）。動き出しの遅れは最大でこの1回分
        package static let idlePollInterval: TimeInterval = 1.0 / 60
        // 隠し直しが効かず本物に任せたあと、隠れた状態がこの回数続いたら自前の絵に戻す
        // （動いている間の120Hzで約0.1秒、眠っている間の30〜60Hzで0.2〜0.4秒）
        package static let overpowerRecoverChecks = 12
        // 他のアプリが本物のカーソルを隠しているかを調べるのは、マウスがこの秒数止まってから、この間隔ごと。
        // 調べる瞬間に本物が映っても重なるよう、矢印が元の形に戻りきってから調べる
        package static let otherHideDelay: TimeInterval = 1
        package static let otherHideInterval: TimeInterval = 0.5
        package static let otherHideRecheckInterval: TimeInterval = 2
        package static let otherHideInputSettle: TimeInterval = 0.3
        // 自分の分を戻してから、この秒数見えなければ他のアプリが隠していると判断する。
        // 他のアプリが隠している間は、調べるたびにこの秒数だけ待つ
        package static let otherHideProbeTimeout: TimeInterval = 0.01
        // システム設定のポインタの色と大きさを読み直す間隔（秒）
        package static let colorCheckInterval: TimeInterval = 1
        // JellyCursor の窓より手前にある窓（システムのダイアログなど）を調べる間隔（秒）
        package static let coverCheckInterval: TimeInterval = 0.1
        // 手前の窓のうち、縦横ともこの大きさ（倍率1のとき、pt）以下のものは数えない（本物のカーソルが窓として出ることがあるため）
        package static let coverIgnoreSize: CGFloat = 48
        package static let shadowOpacity: Float = 0.35
        package static let shadowRadius: CGFloat = 1.5
        package static let shadowOffset = CGSize(width: 0, height: -1.5)
    }
}
