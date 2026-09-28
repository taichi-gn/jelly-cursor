import AppKit
import CoreGraphics
import Foundation

// 使い方: diagnose <アプリ名>
// 画面を撮る許可があるか、本物のカーソルが見えているか、前面のアプリ、そのアプリの窓（層・範囲・透明度）を出す
let owner = CommandLine.arguments[1]
print("screen capture allowed: \(CGPreflightScreenCaptureAccess())")
typealias Int32Getter = @convention(c) () -> Int32
if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") {
    print("cursor visible: \(unsafeBitCast(symbol, to: Int32Getter.self)() != 0)")
}
print("frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "なし")")
let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
print("regular apps: \(regular.map { $0.localizedName ?? "?" }.joined(separator: ", "))")
if let screen = NSScreen.screens.first {
    print("screen size: \(Int(screen.frame.width)) \(Int(screen.frame.height))")
}
// 2つ目の引数に .app の場所を渡すと、Finder などが使うアイコンの真ん中の色を出す（JellyCursor のアイコンなら紫がかる）
if CommandLine.arguments.count > 2 {
    let icon = NSWorkspace.shared.icon(forFile: CommandLine.arguments[2])
    var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
    if let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let c = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh * 3 / 4)?.usingColorSpace(.sRGB)
        print(String(format: "bundle icon color: r=%.2f g=%.2f b=%.2f", c?.redComponent ?? -1, c?.greenComponent ?? -1,
                     c?.blueComponent ?? -1))
    }
}
let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for info in infos where info[kCGWindowOwnerName as String] as? String == owner {
    let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
    let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
    let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
        .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .null
    print("window layer=\(layer) alpha=\(alpha) bounds=\(bounds)")
}
