import Foundation

package enum InstallLocation {
    // アプリがアプリケーションフォルダ（/Applications か ~/Applications）の中にあるか。
    // ログイン時に起動する設定はアプリの場所を覚えるので、作ったその場のアプリで登録しないようにする
    package static func isInApplicationsFolder(_ appPath: String, home: String) -> Bool {
        let path = URL(fileURLWithPath: appPath).standardizedFileURL.path
        let folders = ["/Applications", URL(fileURLWithPath: home).appendingPathComponent("Applications").path]
        return folders.contains { path.hasPrefix($0 + "/") }
    }
}
