import CoreGraphics
import Foundation

// 使い方: press-key <キーコード> [control,option,shift,command]
// キーを1回押して離す。キー入力を送る許可が無ければ何もせず 2 で終わる
let keyCode = CGKeyCode(CommandLine.arguments[1])!
var flags: CGEventFlags = []
for name in (CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "").split(separator: ",") {
    switch name {
    case "control": flags.insert(.maskControl)
    case "option": flags.insert(.maskAlternate)
    case "shift": flags.insert(.maskShift)
    case "command": flags.insert(.maskCommand)
    default: break
    }
}
guard CGPreflightPostEventAccess() else {
    print("post events allowed: false")
    exit(2)
}
print("post events allowed: true")
let source = CGEventSource(stateID: .hidSystemState)
for keyDown in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)!
    event.flags = flags
    event.post(tap: .cghidEventTap)
    usleep(30_000)
}
