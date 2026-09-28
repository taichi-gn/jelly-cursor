import AppKit
import JellyCursorKit

MainActor.assumeIsolated {
    // make app から呼ばれたときは、アイコンの画像を書き出して終わる（JellyCursor --write-iconset <フォルダ>）
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--write-iconset") {
        guard index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("使い方: JellyCursor --write-iconset <フォルダ>\n".utf8))
            exit(2)
        }
        exit(AppIconImage.writeIconset(to: arguments[index + 1]) ? 0 : 1)
    }

    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
}
