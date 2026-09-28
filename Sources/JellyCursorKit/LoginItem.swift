import AppKit
import JellyCursorCore
import Observation
import ServiceManagement

// ログイン時に起動する設定（SMAppService）。アプリの場所を覚えるので、アプリケーションフォルダに置いてから使う
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.Status.notRegistered
    private(set) var errorMessage: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }
    var isInstalled: Bool {
        InstallLocation.isInApplicationsFolder(Bundle.main.bundleURL.path,
                                               home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            logger.error("ログイン時の起動を\(enabled ? "登録" : "解除", privacy: .public)できない: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
