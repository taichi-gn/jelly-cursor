import AppKit
import ApplicationServices

// 使い方: dock-tile <アプリ名>
// Dock にあるそのアプリのアイコンの範囲を、screencapture -R の形（x,y,幅,高さ）で出す。
// Dock の中身はアクセシビリティの API で読むので、その許可が無いときは 2 で終わる
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
