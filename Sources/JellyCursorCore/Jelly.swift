import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

package final class Jelly: CursorFigure {
    private let shape: ArrowShape
    package private(set) var points: [CGPoint]
    private var trail: Trail
    private var heading: Heading
    private var length: CGFloat
    private var lastMouse = CGPoint.zero
    private var started = false
    package private(set) var isSettled = false
    private let stretchScale: CGFloat
    private let motion: MotionParameters
    // 道が折り返したときに、胴体をまっすぐにして先端のまわりで回している間の向き（先端から胴体への向き）
    private var pivot: Pivot?
    // 胴体を道に沿わせる度合い。回している間は 0 へ寄せ、回し終えたら 1 へ戻す
    private var pathFollow: CGFloat = 1
    // 前のフレームで描いた胴体の向き（先端から胴体の中ほどへ）。回し始めの向きと、クリックでつぶす向きにする
    private var bodyBack = CGVector(dx: 0, dy: -1)
    // 前のフレームで描いた胴体の、中ほどから見た尾の側（+ で左）。曲がった胴体をまっすぐにして回すとき、曲がっている側へ回す
    private var bodyCurl: CGFloat = 0
    private var squish: ClickSquish
    // 道に沿わせてよい度合い。道の向きがまっすぐな胴体の向きと逆のうちは下げ、向きが回ってそろうにつれて上げる
    private var pathGate: CGFloat = 1
    // 道に沿わせたい状態が続いている秒数
    private var engagedTime: CGFloat = 0
    // 折り返しで胴体を回した向きの合計（ラジアン。+ で左回り）。左右に振り続けたときに、同じ向きへ回り続けず
    // 巻き戻すよう、回す側を選ぶのに使う。しばらく折り返さなければ忘れる
    private var pivotTurns: CGFloat = 0
    private var sincePivot: CGFloat = 0
    // 回す側を決めかねたとき（止まったときの向きに沿って振ったとき）に回す側。毎回同じ側へ振れるように覚えておく
    private var tieSide: CGFloat = 1
    // 折り返したときに残す伸び（pt）。縮めてから回すと、折り返した直後のいちばん速く動いている間が短いままに見えるので、
    // 伸びを残したまま先端のまわりで振り回す（尾が勢いで回り込むように）。回している間は保ち、回し終えたら少しずつ減らす
    private var heldStretch: CGFloat = 0

    private struct Pivot {
        var angle: CGFloat
        var velocity: CGFloat = 0
        // 回る側（+1 で左回り）。先端が折り返しから離れて回す先が決まったときに決める
        var side: CGFloat?
        // 回る側を決めたときの回す先の向き。回している間にまた折り返して回す先が大きく変わったら、回る側を決め直す
        var sideTarget: CGFloat = 0
        // 回し始めたときに胴体が曲がっていた側（+1 で左、0 でまっすぐ）
        var curl: CGFloat = 0
        // 前のフレームの回す先の向き。折り返しが抜けたあと、回す先が回り続けても（円を描き続けても）遅れずに追うため
        var lastTarget: CGFloat?
        // 回す先までの残りの角度（ラジアン）。回す先が決まるまではほぼ逆向き
        var error: CGFloat = .pi
        // 先端が折り返しから離れて、回す先が決まっているか
        var aimed = false
    }

    package init(scale: CGFloat, motion: MotionParameters = .standard) {
        shape = ArrowShape(scale: scale)
        trail = Self.makeTrail(shape: shape, stretch: motion.stretch)
        heading = Heading(restAngle: shape.baseAngle, motion: motion)
        stretchScale = motion.stretch
        self.motion = motion
        squish = ClickSquish(motion: motion)
        length = shape.length
        points = Array(repeating: .zero, count: shape.vertices.count)
    }

    package func step(to mouse: CGPoint, dt: CGFloat, pressed: Bool) {
        if started, isJump(from: lastMouse, to: mouse, dt: dt) { restart(at: mouse) }
        if !started {
            started = true
        } else if dt > 0 {
            heading.turn(from: lastMouse, to: mouse, dt: dt)
        }
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        let previous = lastMouse
        lastMouse = mouse
        trail.record(mouse, dt: dt)
        // 少し動かしただけのときは、もともと道に沿わせていない
        let fold = heading.commitment > 0 ? trail.fold() : nil
        updatePivot(mouse: mouse, previous: previous, fold: fold, moved: moved, dt: dt)

        updatePathGate(mouse: mouse, dt: dt)
        let full = min(trail.length, Tuning.Trail.maxStretch) * stretchScale * heading.commitment
        let stretch: CGFloat
        if let p = pivot {
            // 回している間は、折り返したときの伸びを残したまま回し、新しい向きへ回るにつれて今の速さの伸びへ寄せる
            let aligned = (1 + cos(p.error)) / 2
            stretch = max(full * aligned * aligned, heldStretch)
        } else {
            // 回し終えたら、道に沿わせるのに合わせて伸ばす。道の向きが胴体の向きと逆で、まだ道に沿わせていないうちは
            // 伸ばさない（まっすぐなまま前へ伸びないように）。折り返しで残した伸びは、少しずつ減らす
            stretch = max(full * pathFollow * pathGate, heldStretch)
            heldStretch *= exp(-dt / Tuning.Fold.keepDecay)
        }
        var target = shape.length + stretch
        // 道が折り返したら、道に沿った胴体は折り返しより後ろへのばさない。伸びたぶんは道に沿って縮める（折り返しで重ならないように）。
        // 今の長さが折り返しに届いていなくても、伸びる途中で越えないよう、いつも抑える。回している間はまっすぐなので抑えない
        if let fold, pivot == nil {
            target = min(target, max(shape.length, fold.distance))
        }
        if dt > 0 {
            length += (target - length) * (1 - exp(-dt / Tuning.Trail.lengthSmoothing))
        }
        layOut(at: mouse)
        // クリックしたら、先端（クリック位置）を動かさずに、胴体の向きへつぶす
        squish.step(pressed: pressed, mouse: mouse, dt: dt)
        squish.apply(to: &points, anchor: mouse, axis: bodyBack)

        let worst = max(trail.length, abs(length - shape.length), heading.restError, squish.restError(size: shape.length))
        isSettled = worst < Tuning.Settle.threshold && pivot == nil && pathFollow == 1
    }

    // 胴体がいちばん伸びたときの長さまで、通った道を覚えておく
    private static func makeTrail(shape: ArrowShape, stretch: CGFloat) -> Trail {
        Trail(keep: shape.length + Tuning.Trail.maxStretch * stretch + 2 * Tuning.Trail.tangentWindow)
    }

    // ポインタが飛んだとき、動きを止まった状態から始め直す（クリックでつぶれている状態はそのまま）
    private func restart(at mouse: CGPoint) {
        squish.follow(jumpTo: mouse)
        trail = Self.makeTrail(shape: shape, stretch: stretchScale)
        heading = Heading(restAngle: shape.baseAngle, motion: motion)
        length = shape.length
        pivot = nil
        pathFollow = 1
        pathGate = 1
        engagedTime = 0
        pivotTurns = 0
        sincePivot = 0
        heldStretch = 0
        started = false
    }

    // 矢じり（先端から普段の長さのうち）で道が折り返したら、道に沿わせず、まっすぐにして先端のまわりで回す。
    // 道に沿わせたままだと、幅の広い矢じりが折り返しで自分と重なり、形が崩れて見える。
    // ほぼまっすぐ戻ったときは、速いと1フレームで矢じりより後ろまで戻ることがあるので、そのフレームで動いたぶんまでは
    // 矢じりの中とみなす（画面の書き換えの速さで、回すかどうかが変わらないように）。
    // 回し始めたら、折り返しが胴体より後ろへ抜けるまで続ける
    private func updatePivot(mouse: CGPoint, previous: CGPoint, fold: Trail.Fold?, moved: CGFloat, dt: CGFloat) {
        let span = min(length, trail.length)
        var folded = false
        if let fold {
            let head = shape.length + (fold.cosine < cos(Tuning.Fold.reversalAngle) ? moved : 0)
            // 回し始めたら、折り返しが胴体より後ろへ抜けるまで続ける。ゆっくり折り返したときは直近の道が短いので、
            // 回す先が決まる（先端が折り返しから minTurnTravel 離れる）までは抜けたとみなさない（回さないまま終わらないように）
            folded = fold.distance < (pivot == nil ? min(span, head) : max(span, Tuning.Fold.minTurnTravel + Tuning.Fold.reference))
        }
        if folded, pivot == nil {
            heldStretch = max(heldStretch, (length - shape.length) * Tuning.Fold.keepStretch)
            pivot = Pivot(angle: atan2(bodyBack.dy, bodyBack.dx),
                          curl: abs(bodyCurl) > Tuning.Fold.curlAngle ? (bodyCurl > 0 ? 1 : -1) : 0)
        }
        if var p = pivot {
            // 回す先は、先端から折り返し（無くなったら胴体の長さ）までの道の向き。新しく進む向きの後ろ。
            // 先端が折り返しから少し離れるまでは回さない（行き過ぎて少し戻したときに、くるっと向きを変えないように）
            // ゆっくり折り返したときは直近の道が短いので、覚えている道の形まで見る（回す先が先端の近くにとどまって回せないことがないように）
            let end = trail.point(at: min(max(fold?.distance ?? span, Tuning.Fold.reference), trail.pathLength))
            // ゆっくり折り返したときは、胴体の端もゆっくり回す（先端がゆっくり動いているのに、くるっと一瞬で回らないように）
            let tipSpeed = trail.length / Tuning.Trail.duration
            let tailSpeed = min(max(tipSpeed * Tuning.Fold.tailSpeedRatio, Tuning.Fold.minTailSpeed), Tuning.Fold.maxTailSpeed)
            let maxSpeed = tailSpeed / length
            var error: CGFloat = 0
            // 回す先が回る速さ。ばねはこの速さに合わせて回しながら追う（合わせないと、円を描き続ける間はいつまでも
            // 回す先に追いつけず、回し終わらない。回している間は伸びないので、短いままになる）
            var targetRate: CGFloat = 0
            let distance = hypot(end.x - mouse.x, end.y - mouse.y)
            let aimed = distance > Tuning.Fold.minTurnTravel
            var turning = dt
            if aimed {
                let target = atan2(end.y - mouse.y, end.x - mouse.x)
                // 折り返しを見ている間は、回す先が折り返しの位置で決まり、道の向きとは関係なく動くので合わせない
                if !folded, let last = p.lastTarget, dt > 0 {
                    targetRate = min(max(wrapAngle(target - last) / dt, -maxSpeed), maxSpeed)
                }
                p.lastTarget = folded ? nil : target
                // 回している間にまた折り返した（回す先が大きく変わった）ときは、新しく回し始めたのと同じに扱う
                if p.side != nil, abs(wrapAngle(target - p.sideTarget)) > .pi / 2 {
                    p.side = nil
                    p.aimed = false
                }
                // 回す先が決まったフレームでは、決まったあとの時間だけ回す。まるごと回すと、画面の書き換えが遅いほど
                // 早く回り始め、伸びを残した長い胴体では、書き換えの速さで尾の位置が大きく変わる
                if !p.aimed {
                    let gained = distance - hypot(end.x - previous.x, end.y - previous.y)
                    if gained > 0 { turning = dt * min(max((distance - Tuning.Fold.minTurnTravel) / gained, 0), 1) }
                }
                if p.side == nil {
                    p.side = turnSide(from: p.angle, to: target, curl: p.curl)
                    p.curl = 0
                    p.sideTarget = target
                }
                let side = p.side ?? 1
                error = wrapAngle(target - p.angle)
                if abs(error) > Tuning.Fold.oppositeTurn, error * side < 0 {
                    error += error > 0 ? -2 * .pi : 2 * .pi
                }
            } else {
                p.lastTarget = nil
            }
            p.aimed = aimed
            let spring = DampedSpring(omega: Tuning.Fold.omega, dampingRatio: 1)
            let n = substepCount(for: dt)
            let h = turning / CGFloat(n)
            let before = p.angle
            for _ in 0..<n {
                p.velocity += spring.velocityChange(error: error, velocity: p.velocity - targetRate, h: h)
                p.velocity = min(max(p.velocity, -maxSpeed), maxSpeed)
                p.angle += p.velocity * h
                error -= p.velocity * h
            }
            if aimed { p.error = error }
            pivotTurns += p.angle - before
            p.angle = wrapAngle(p.angle)
            // 回す先が回り続けていると、1フレームのうちに回す先が進むぶん、フレームの終わりには半分ほど遅れて見える。
            // その遅れを除いて、追いついたかを見る（画面の書き換えが遅いほど遅れが大きく、回し終われなくなるので）
            if !folded && abs(error + targetRate * dt / 2) < Tuning.Fold.finishAngle {
                // 回し終えた向きから、ふだんの向きの動き（進行方向へ向ける・止めたら左上へ戻す）を続ける
                heading.align(angle: p.angle + .pi, velocity: p.velocity)
                pivot = nil
            } else {
                pivot = p
            }
        }
        sincePivot = pivot == nil ? sincePivot + dt : 0
        if sincePivot > Tuning.Fold.turnMemory { pivotTurns = 0 }
        if dt > 0 {
            let target: CGFloat = pivot == nil ? 1 : 0
            let tau = target < pathFollow ? Tuning.Fold.followDrop : Tuning.Fold.followRecover
            pathFollow += (target - pathFollow) * (1 - exp(-dt / tau))
            if pathFollow > 0.999 { pathFollow = 1 }
        }
    }

    // 回る側（+1 で左回り、-1 で右回り）。ふつうは近い側へ回る。ほぼ逆向きへ回すときは:
    // - それまでの折り返しで回していたら、巻き戻す側へ回す。左右に振り続けても、同じ側へ回り続けず（プロペラのように回らず）、
    //   振り子のように行き来する
    // - 回し始めたときに胴体が大きく曲がっていたら（円を描いていて逆に回したときなど）、曲がっている側へ回す。
    //   まっすぐにするときに、胴体の後ろのほうが大きく跳ばないように
    // - それ以外は、止まったときの胴体の向き（右下）を通る側へ回す。ぶら下がるように振れる。
    //   その向きに沿って振ったとき（どちら側でも同じくらいのとき）は、前と同じ側へ回す
    // 道の少しの曲がり（画面の書き換えの速さで変わる）には頼らない
    private func turnSide(from angle: CGFloat, to target: CGFloat, curl: CGFloat) -> CGFloat {
        let error = wrapAngle(target - angle)
        guard abs(error) > Tuning.Fold.oppositeTurn else { return error >= 0 ? 1 : -1 }
        if abs(pivotTurns) > Tuning.Fold.unwindTurn { return pivotTurns > 0 ? -1 : 1 }
        if curl != 0 { return curl }
        let rest = shape.baseAngle + .pi
        if abs(wrapAngle(rest - angle)) < Tuning.Fold.restTie || abs(wrapAngle(rest - target)) < Tuning.Fold.restTie {
            return tieSide
        }
        func counterclockwise(_ a: CGFloat) -> CGFloat {
            let r = a.truncatingRemainder(dividingBy: 2 * .pi)
            return r < 0 ? r + 2 * .pi : r
        }
        tieSide = counterclockwise(rest - angle) < counterclockwise(target - angle) ? 1 : -1
        return tieSide
    }

    // まっすぐにしたときの胴体の向き（先端から胴体へ）
    private var restBack: CGVector {
        pivot.map { CGVector(dx: cos($0.angle), dy: sin($0.angle)) } ?? heading.axis.negated
    }

    // 道に沿わせたい度合い。道が胴体より短いうち・動き始めてあまり動いていないうち・回している間は、まっすぐな胴体に寄せる
    private var pathEngagement: CGFloat {
        min(trail.length / shape.length, 1) * heading.commitment * pathFollow
    }

    // 胴体は、まっすぐな形と道に沿った形を位置で混ぜて作る。逆を向いた2つの間で沿わせる度合いを増やすと、途中で胴体が
    // 先端へ縮んで小さな塊に見える（止まった矢印から右下へ動き出したとき・少し動かしたとき・行き過ぎて戻したときなど）。
    // そこで、道の向きがまっすぐな胴体の向きと逆のうちは道に沿わせず、向きが回ってそろうにつれて沿わせる。
    // すでに道に沿っているときは、向きが遅れても下げない。道に沿わせたい状態が続いているのに向きがそろわないとき
    // （速く円を描き始めて、向きが回る道に追いつけないときなど）は、少し待ってから沿わせる
    private func updatePathGate(mouse: CGPoint, dt: CGFloat) {
        guard dt > 0 else { return }
        var target: CGFloat = 1
        if trail.length > 0, let path = (trail.point(at: min(trail.length, shape.length / 2)) - mouse).normalized {
            let back = restBack
            let cosine = path.dx * back.dx + path.dy * back.dy
            let t = min(max((cosine - Tuning.Trail.opposingCosine) / (Tuning.Trail.opposedCosine - Tuning.Trail.opposingCosine), 0), 1)
            target = 1 - t * t * (3 - 2 * t)
        }
        if pathEngagement >= Tuning.Trail.gateHold {
            // 速く動き出して1フレームで沿わせたい状態になったときは、下げてから保つ（下げる前に保って、逆向きのまま沿わせないように）
            if engagedTime == 0 { pathGate = min(pathGate, target) }
            engagedTime += dt
            let forced = min(max((engagedTime - Tuning.Trail.gateForceDelay) / Tuning.Trail.gateForceTime, 0), 1)
            target = max(target, pathGate, forced)
        } else {
            engagedTime = 0
        }
        let tau = target < pathGate ? Tuning.Trail.gateCloseTime : Tuning.Trail.gateOpenTime
        pathGate += (target - pathGate) * (1 - exp(-dt / tau))
        if pathGate > 0.999 { pathGate = 1 }
    }

    // 矢印の軸を道筋に沿って曲げ、各頂点をその地点の向きに対して横へずらす
    private func layOut(at mouse: CGPoint) {
        let spine = Spine(mouse: mouse, trail: trail, restBack: restBack, blend: pathEngagement * pathGate)
        bodyBack = (spine.point(at: shape.length / 2) - mouse).normalized ?? restBack
        if let tail = (spine.point(at: length) - mouse).normalized {
            bodyCurl = wrapAngle(atan2(tail.dy, tail.dx) - atan2(bodyBack.dy, bodyBack.dx))
        }
        let stretch = length / shape.length
        let width = pow(1 / stretch, Tuning.Trail.thinning)
        let w = Tuning.Trail.tangentWindow
        for (i, v) in shape.vertices.enumerated() {
            let s = v.axial * stretch
            let c = spine.point(at: s)
            let back = (spine.point(at: s + w) - spine.point(at: max(s - w, 0))).normalized ?? spine.restBack
            // 前向き (-back) の左の法線は (back.dy, -back.dx)
            points[i] = CGPoint(x: c.x + back.dy * v.lateral * width,
                                y: c.y - back.dx * v.lateral * width)
        }
    }

    package var borderWidth: CGFloat { shape.borderWidth }
}

// 矢印の芯。先端から s px 後ろの位置を返す。
// 道が短いうちは手ぶれで向きがばたつくので、止まったときの向きのまっすぐな線に寄せる
private struct Spine {
    let mouse: CGPoint
    let trail: Trail
    let restBack: CGVector
    let blend: CGFloat
    private let pathBack: CGVector

    init(mouse: CGPoint, trail: Trail, restBack: CGVector, blend: CGFloat) {
        self.mouse = mouse
        self.trail = trail
        self.restBack = restBack
        self.blend = blend
        pathBack = trail.tailDirection(window: Tuning.Trail.tangentWindow) ?? restBack
    }

    func point(at s: CGFloat) -> CGPoint {
        let straight = CGPoint(x: mouse.x + restBack.dx * s, y: mouse.y + restBack.dy * s)
        guard blend > 0 else { return straight }
        let onPath: CGPoint
        if s <= trail.pathLength {
            onPath = trail.point(at: s)
        } else {
            let end = trail.point(at: trail.pathLength), extra = s - trail.pathLength
            onPath = CGPoint(x: end.x + pathBack.dx * extra, y: end.y + pathBack.dy * extra)
        }
        return CGPoint(x: straight.x + (onPath.x - straight.x) * blend,
                       y: straight.y + (onPath.y - straight.y) * blend)
    }
}

private extension CGPoint {
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}

private extension CGVector {
    var negated: CGVector { CGVector(dx: -dx, dy: -dy) }

    var normalized: CGVector? {
        let d = hypot(dx, dy)
        return d > 0.0001 ? CGVector(dx: dx / d, dy: dy / d) : nil
    }
}
