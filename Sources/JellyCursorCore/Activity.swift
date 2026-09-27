import Foundation

package struct AppIdentity: Equatable, Sendable {
    package var bundleID: String
    package var name: String

    package init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

// 自動で止めるかを決めるための、Mac の今の状態
package struct SystemConditions: Equatable, Sendable {
    // ユーザーの切り替えで、この画面が裏に回っていない
    package var sessionActive = true
    package var screenLocked = false
    package var screenSaverRunning = false
    // スリープ中か、画面が眠っている
    package var asleep = false
    package var reduceMotion = false
    package var lowPower = false
    // 前面のアプリ（JellyCursor 自身も含む）
    package var frontApp: AppIdentity?
    package var frontAppFullScreen = false

    package init() {}
}

package enum PauseReason: Equatable, Sendable {
    case sessionInactive
    case screenLocked
    case screenSaver
    case asleep
    case excludedApp(String)
    case fullScreen
    case reduceMotion
    case lowPower

    package var message: String {
        switch self {
        case .sessionInactive: "ほかのユーザーに切り替え中"
        case .screenLocked: "画面がロックされています"
        case .screenSaver: "スクリーンセーバーが動いています"
        case .asleep: "スリープ中"
        case .excludedApp(let name): "「\(name)」では無効にしています"
        case .fullScreen: "全画面のアプリを使っています"
        case .reduceMotion: "「視差効果を減らす」がオンです"
        case .lowPower: "低電力モードです"
        }
    }
}

// 自前のカーソルを描くかどうか
package enum Activity: Equatable, Sendable {
    // 設定でオフ
    case off
    // Shift を押しながら起動した。メニューか設定でオンにするまで止めておく
    case safeMode
    case paused(PauseReason)
    case running

    // 強い理由から順に見る。ロックやユーザーの切り替えの間は、ほかの設定に関係なく本物のカーソルに戻す
    package init(settings: SettingsValues, conditions: SystemConditions, safeMode: Bool) {
        guard settings.isEnabled else { self = .off; return }
        guard !safeMode else { self = .safeMode; return }
        if !conditions.sessionActive {
            self = .paused(.sessionInactive)
        } else if conditions.screenLocked {
            self = .paused(.screenLocked)
        } else if conditions.screenSaverRunning {
            self = .paused(.screenSaver)
        } else if conditions.asleep {
            self = .paused(.asleep)
        } else if let app = conditions.frontApp, settings.isExcluded(bundleID: app.bundleID) {
            self = .paused(.excludedApp(app.name))
        } else if settings.pauseInFullScreen && conditions.frontAppFullScreen {
            self = .paused(.fullScreen)
        } else if settings.pauseWhenReduceMotion && conditions.reduceMotion {
            self = .paused(.reduceMotion)
        } else if settings.pauseOnLowPower && conditions.lowPower {
            self = .paused(.lowPower)
        } else {
            self = .running
        }
    }

    package var isRunning: Bool { self == .running }

    // メニューに出す今の状態。動いているときとオフのときは出さない
    package var statusLine: String? {
        switch self {
        case .off, .running: nil
        case .safeMode: "セーフモードで起動しました（オンにすると動きます）"
        case .paused(let reason): "一時停止中: " + reason.message
        }
    }
}

// メニューバーのアイコン
package enum StatusIcon: Equatable, Sendable {
    case running
    case off
    case paused
    // 本物のカーソルを隠せず、自前の絵と重なって見えている
    case warning

    package init(activity: Activity, canHideCursor: Bool) {
        switch activity {
        case .running: self = canHideCursor ? .running : .warning
        case .paused: self = .paused
        case .off, .safeMode: self = .off
        }
    }

    // SF Symbols の名前
    package var symbolName: String {
        switch self {
        case .running, .paused: "cursorarrow.motionlines"
        case .off: "cursorarrow"
        case .warning: "exclamationmark.triangle"
        }
    }

    // 一時停止中は薄く表示する
    package var isDimmed: Bool { self == .paused }

    package var accessibilityDescription: String {
        switch self {
        case .running: "JellyCursor: オン"
        case .off: "JellyCursor: オフ"
        case .paused: "JellyCursor: 一時停止中"
        case .warning: "JellyCursor: 本物のカーソルを隠せません"
        }
    }
}
