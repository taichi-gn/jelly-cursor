import AppKit
import JellyCursorKit

MainActor.assumeIsolated {
    // make app から呼ばれたときは、アイコンの画像を書き出して終わる（JellyCursor --write-iconset <フォルダ>）
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--write-iconset"), index + 1 < arguments.count {
        exit(AppIconImage.writeIconset(to: arguments[index + 1]) ? 0 : 1)
    }

    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
}
