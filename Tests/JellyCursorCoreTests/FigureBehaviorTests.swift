import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import JellyCursorCore

// 動きの性質（PR #1・#2 で確かめたもの）
@Suite struct FigureBehaviorTests {
    // 少し動かしただけ（動き始めてから minTravel の6割の 18pt 未満）では回らず、伸びも曲がりもしない
    @Test func smallMovesDoNotTurn() {
        let jelly = Jelly(scale: 1)
        let start = CGPoint(x: 300, y: 300), end = CGPoint(x: 314, y: 297)
        jelly.step(to: start, dt: 0)
        let before = bodyAngle(jelly, from: start)
        drive(jelly, from: start, to: end, seconds: 0.08)
        #expect(abs(wrapAngle(bodyAngle(jelly, from: end) - before)) < 0.05)
        #expect(reach(jelly, from: end) < ArrowShape(scale: 1).length + 1.5)
    }

    // 速く動かすと進行方向を向き、止めると元の向きへ戻って眠る
    @Test func turnsTowardMotionAndReturns() {
        let jelly = Jelly(scale: 1)
        let a = CGPoint(x: 100, y: 400), b = CGPoint(x: 700, y: 400)
        drive(jelly, from: a, to: b, seconds: 0.4)
        // 右へ動いているので、胴体は先端の左（π の向き）にある
        #expect(abs(wrapAngle(bodyAngle(jelly, from: b) - .pi)) < 0.2)
        for _ in 0..<240 { jelly.step(to: b, dt: 1.0 / 120) }
        #expect(jelly.isSettled)
        let rest = Jelly(scale: 1)
        rest.step(to: b, dt: 0)
        #expect(abs(wrapAngle(bodyAngle(jelly, from: b) - bodyAngle(rest, from: b))) < 0.01)
    }

    // 斜めに動かすと、その向きの線に沿って傾く（右上・左下なら /、左上・右下なら \）
    @Test(arguments: [(1.0, 1.0, 1.0), (-1.0, -1.0, 1.0), (-1.0, 1.0, -1.0), (1.0, -1.0, -1.0)])
    func iBeamLeansAlongDiagonal(dx: Double, dy: Double, sign: Double) {
        let beam = IBeam(scale: 1)
        let a = CGPoint(x: 400, y: 400)
        let b = CGPoint(x: a.x + 250 * dx, y: a.y + 250 * dy)
        drive(beam, from: a, to: b, seconds: 0.25)
        // 上端の頂点の平均の x が、下端の平均より右なら /
        let top = beam.points.filter { $0.y > b.y + 5 }.map(\.x)
        let bottom = beam.points.filter { $0.y < b.y - 5 }.map(\.x)
        let lean = top.reduce(0, +) / CGFloat(top.count) - bottom.reduce(0, +) / CGFloat(bottom.count)
        #expect(lean * sign > 2)
    }

    // 指は、動いている間は矢印の胴体と同じ向き（通った道の向き）を指す
    @Test func handPointsAlongPathLikeArrow() {
        let jelly = Jelly(scale: 1)
        var hand = HandMotion(scale: 1)
        let points = (0...60).map { i -> CGPoint in
            let t = CGFloat(i) / 60
            return CGPoint(x: 200 + 500 * t, y: 300 + 200 * sin(.pi * t))
        }
        jelly.step(to: points[0], dt: 0)
        hand.step(to: points[0], dt: 0, imageHeight: 32)
        var worst: CGFloat = 0
        for (i, p) in points.enumerated().dropFirst() {
            jelly.step(to: p, dt: 1.0 / 120)
            hand.step(to: p, dt: 1.0 / 120, imageHeight: 32)
            guard i > 20 else { continue }
            // 矢印の胴体は先端の後ろにあるので、指の向きはその逆
            let arrowHeading = wrapAngle(bodyAngle(jelly, from: p) + .pi)
            worst = max(worst, abs(wrapAngle(hand.angle - arrowHeading)))
        }
        #expect(worst < 0.35)
    }

    @Test func handReturnsUpright() {
        var hand = HandMotion(scale: 1)
        hand.step(to: CGPoint(x: 100, y: 100), dt: 0, imageHeight: 32)
        for i in 1...40 { hand.step(to: CGPoint(x: 100 + CGFloat(i) * 15, y: 100), dt: 1.0 / 120, imageHeight: 32) }
        #expect(abs(wrapAngle(hand.angle)) < 0.3)
        for _ in 0..<300 { hand.step(to: CGPoint(x: 700, y: 100), dt: 1.0 / 120, imageHeight: 32) }
        #expect(abs(wrapAngle(hand.angle - .pi / 2)) < 0.01)
        #expect(hand.isSettled)
    }

    @Test func boundsCoverPoints() {
        let jelly = Jelly(scale: 2)
        jelly.step(to: CGPoint(x: 50, y: 60), dt: 0)
        let b = jelly.bounds
        #expect(jelly.points.allSatisfy { b.insetBy(dx: -0.001, dy: -0.001).contains($0) })
        #expect(b.maxX <= 50.001 + 20 && b.maxY <= 60.001)
    }
}
