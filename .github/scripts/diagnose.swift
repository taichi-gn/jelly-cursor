import CoreGraphics
import Foundation

// 使い方: diagnose <アプリ名>
// 画面を撮る許可があるか、本物のカーソルが見えているか、そのアプリの窓（層・範囲・透明度）を出す
let owner = CommandLine.arguments[1]
print("screen capture allowed: \(CGPreflightScreenCaptureAccess())")
typealias Int32Getter = @convention(c) () -> Int32
if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") {
    print("cursor visible: \(unsafeBitCast(symbol, to: Int32Getter.self)() != 0)")
}
let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for info in infos where info[kCGWindowOwnerName as String] as? String == owner {
    let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
    let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
    let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
        .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .null
    print("window layer=\(layer) alpha=\(alpha) bounds=\(bounds)")
}
