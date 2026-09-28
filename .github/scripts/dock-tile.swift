import AppKit
import ApplicationServices

// 使い方: dock-tile <アプリ名>        Dock にあるそのアプリのアイコンの範囲を、screencapture -R の形で出す
//         dock-tile --color <PNG>     画像の真ん中あたりの平均の色と、色の鮮やかさ（最大と最小の差）を出す
// Dock の中身はアクセシビリティの API で読むので、その許可が無いと失敗する
if CommandLine.arguments[1] == "--color" {
    guard let image = NSImage(contentsOfFile: CommandLine.arguments[2]),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write(Data("画像を読めない\n".utf8))
        exit(1)
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    var sum = (r: 0.0, g: 0.0, b: 0.0), count = 0.0
    let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
    for y in stride(from: h / 4, to: h * 3 / 4, by: 1) {
        for x in stride(from: w / 4, to: w * 3 / 4, by: 1) {
            guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            sum.r += c.redComponent
            sum.g += c.greenComponent
            sum.b += c.blueComponent
            count += 1
        }
    }
    let r = sum.r / count, g = sum.g / count, b = sum.b / count
    print(String(format: "r=%.2f g=%.2f b=%.2f 鮮やかさ=%.2f", r, g, b, max(r, g, b) - min(r, g, b)))
    exit(0)
}

let name = CommandLine.arguments[1]
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("アクセシビリティの許可が無い\n".utf8))
    exit(2)
}
guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { exit(1) }

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    return value as? [AXUIElement] ?? []
}

func attribute<T>(_ element: AXUIElement, _ name: String, as type: AXValueType, _ empty: T) -> T {
    var value: CFTypeRef?
    var result = empty
    if AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
       CFGetTypeID(value) == AXValueGetTypeID() {
        AXValueGetValue(value as! AXValue, type, &result)
    }
    return result
}

for list in children(AXUIElementCreateApplication(dock.processIdentifier)) {
    for item in children(list) {
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &title)
        guard title as? String == name else { continue }
        let origin = attribute(item, kAXPositionAttribute, as: .cgPoint, CGPoint.zero)
        let size = attribute(item, kAXSizeAttribute, as: .cgSize, CGSize.zero)
        print("\(Int(origin.x)),\(Int(origin.y)),\(Int(size.width)),\(Int(size.height))")
        exit(0)
    }
}
FileHandle.standardError.write(Data("Dock に \(name) が無い\n".utf8))
exit(1)
