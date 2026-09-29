import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// クリックしたときの形の変化。押すとクリック位置へ向けてつぶれ、離すと少し伸びる側へ弾んでから戻る。
// value はつぶれの割合（正でつぶれ、負で伸びる）。押したまま動かす（ドラッグ）と、つぶれを戻してふつうの動きにする
struct ClickSquish {
    private(set) var value: CGFloat = 0
    private var velocity: CGFloat = 0
    private var target: CGFloat = 0
    private var isPressed = false
    // 押してから動いた道のり
    private var dragged: CGFloat = 0
    private var lastMouse: CGPoint?
    private let depth: CGFloat
    private let pressSpring: DampedSpring
    private let releaseSpring: DampedSpring

    init(motion: MotionParameters) {
        depth = motion.clickDepth
        pressSpring = DampedSpring(omega: Tuning.Click.pressOmega, dampingRatio: Tuning.Click.pressDampingRatio)
        releaseSpring = DampedSpring(omega: Tuning.Click.releaseOmega, dampingRatio: motion.clickReleaseDampingRatio)
    }

    // 元の形のまま止まっている。このときは形に手を加えない
    var isResting: Bool { value == 0 && velocity == 0 }

    // 今の目標からのずれを、形の大きさ size（px）に対するピクセル数で表したもの
    func restError(size: CGFloat) -> CGFloat {
        max(abs(value - target), abs(velocity) * Tuning.Settle.velocityWeight) * size
    }

    mutating func step(pressed: Bool, mouse: CGPoint, dt: CGFloat) {
        if pressed, !isPressed { dragged = 0 }
        if pressed, let lastMouse { dragged += hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) }
        isPressed = pressed
        lastMouse = mouse
        guard depth > 0 || !isResting else { return }

        target = pressed ? depth * max(0, 1 - dragged / Tuning.Click.dragRelease) : 0
        let spring = pressed ? pressSpring : releaseSpring
        let h = dt / CGFloat(Tuning.Settle.substeps)
        for _ in 0..<Tuning.Settle.substeps {
            velocity += spring.velocityChange(error: target - value, velocity: velocity, h: h)
            value += velocity * h
            // 形が裏返らないよう、つぶれと伸びに上限を設ける。上限に当たったらそちらへの速さは捨てる
            if value > Tuning.Click.maxSquash {
                value = Tuning.Click.maxSquash
                velocity = min(velocity, 0)
            } else if value < -Tuning.Click.maxStretch {
                value = -Tuning.Click.maxStretch
                velocity = max(velocity, 0)
            }
        }
        // 離して戻りきったら、ちょうど元の形にする
        if !pressed, abs(value) < Tuning.Click.restSnap, abs(velocity) < Tuning.Click.restSnap * 10 {
            value = 0
            velocity = 0
        }
    }

    // anchor（クリック位置）を中心に、axis（単位ベクトル）の向きに 1 - value 倍し、それと直角の向きに 1 / √(1 - value) 倍する
    func apply(to points: inout [CGPoint], anchor: CGPoint, axis: CGVector) {
        guard !isResting else { return }
        let along = 1 - value
        let across = 1 / along.squareRoot()
        for i in points.indices {
            let dx = points[i].x - anchor.x, dy = points[i].y - anchor.y
            let a = (dx * axis.dx + dy * axis.dy) * along
            let c = (dy * axis.dx - dx * axis.dy) * across
            points[i] = CGPoint(x: anchor.x + a * axis.dx - c * axis.dy, y: anchor.y + a * axis.dy + c * axis.dx)
        }
    }
}
