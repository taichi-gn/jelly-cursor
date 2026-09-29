import CoreGraphics
import Foundation

// 使い方: click <x> <y> [押している秒数]
// 左ボタンで1回クリックする（左上原点の画面座標）。秒数を渡すと、その間押したままにする。
// イベントを送る許可が無ければ何もせず 2 で終わる
let args = CommandLine.arguments.dropFirst().compactMap(Double.init)
let point = CGPoint(x: args[0], y: args[1])
let hold = args.count > 2 ? args[2] : 0.05
guard CGPreflightPostEventAccess() else {
    print("post events allowed: false")
    exit(2)
}
for (type, wait) in [(CGEventType.leftMouseDown, hold), (.leftMouseUp, 0.05)] {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
    event.post(tap: .cghidEventTap)
    usleep(useconds_t(wait * 1_000_000))
}
