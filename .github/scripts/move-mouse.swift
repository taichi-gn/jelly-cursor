import CoreGraphics
import Foundation

// 使い方: move-mouse <中心x> <中心y> <半径> <秒>
// 120Hz で円を描くようにマウスを動かす（左上原点の画面座標）
let args = CommandLine.arguments.dropFirst().compactMap(Double.init)
let (cx, cy, radius, seconds) = (args[0], args[1], args[2], args[3])
let start = Date()
while case let t = Date().timeIntervalSince(start), t < seconds {
    let angle = t * 2 * .pi * 1.2
    CGWarpMouseCursorPosition(CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle)))
    usleep(8_333)
}
