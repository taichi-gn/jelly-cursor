import CoreGraphics
import Foundation

// 使い方: click <x> <y>
// 左ボタンで1回クリックする（左上原点の画面座標）。イベントを送る許可が無ければ何もせず 2 で終わる
let args = CommandLine.arguments.dropFirst().compactMap(Double.init)
let point = CGPoint(x: args[0], y: args[1])
guard CGPreflightPostEventAccess() else {
    print("post events allowed: false")
    exit(2)
}
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
    event.post(tap: .cghidEventTap)
    usleep(50_000)
}
