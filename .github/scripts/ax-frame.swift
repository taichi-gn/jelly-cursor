import AppKit
import ApplicationServices

// 使い方: ax-frame <バンドル ID> <名前>
// そのアプリの画面の部品のうち、題（AXTitle）か説明（AXDescription）が <名前> のものの範囲を、
// screencapture -R の形（x,y,幅,高さ）で出す。Dock のアイコンなら ax-frame com.apple.dock <アプリ名>。
// アクセシビリティの API で読むので、その許可が無いときは 2、アプリの中身を読めないときは 3、見つからないときは 1 で終わる
let bundleID = CommandLine.arguments[1]
let name = CommandLine.arguments[2]

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

guard AXIsProcessTrusted() else { fail("アクセシビリティの許可が無い", 2) }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fail("\(bundleID) が動いていない", 1)
}

// 読めなかった部品があったか（無い属性を読んだときは数えない）。見つからなかったとき、忙しかっただけなら 3 で終わる
var unreadable = false

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if ![.success, .noValue, .attributeUnsupported].contains(result) { unreadable = true }
    return result == .success ? value : nil
}

func geometry<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType, _ empty: T) -> T {
    var result = empty
    if let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() {
        AXValueGetValue(value as! AXValue, type, &result)
    }
    return result
}

func search(_ element: AXUIElement, depth: Int) -> AXUIElement? {
    for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] where value(element, attribute) as? String == name {
        return element
    }
    guard depth < 16, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
    for child in children {
        if let found = search(child, depth: depth + 1) { return found }
    }
    return nil
}

let root = AXUIElementCreateApplication(app.processIdentifier)
guard value(root, kAXChildrenAttribute) != nil else { fail("\(bundleID) の中身を読めない", 3) }
guard let element = search(root, depth: 0) else {
    fail("「\(name)」が見つからない", unreadable ? 3 : 1)
}
let origin = geometry(element, kAXPositionAttribute, .cgPoint, CGPoint.zero)
let size = geometry(element, kAXSizeAttribute, .cgSize, CGSize.zero)
print("\(Int(origin.x)),\(Int(origin.y)),\(Int(size.width)),\(Int(size.height))")
