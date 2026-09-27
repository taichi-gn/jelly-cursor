import AppKit
import JellyCursorCore
import Observation

// メニューと設定画面に出す、アプリの今の状態。AppController が書き、画面は読むだけ
@MainActor
@Observable
final class AppState {
    var activity = Activity.off
    // 本物のカーソルを隠せるか（非公開APIが使えるか）
    var canHideCursor = true
    // Shift を押しながら起動した。オンにするまで止めておく
    var safeMode = false
    // ショートカットをほかのアプリが使っていて登録できなかった
    var shortcutFailed = false

    // メニューや設定の「有効」の表示。セーフモードの間はオフに見せる
    func isEnabled(in settings: AppSettings) -> Bool {
        settings.values.isEnabled && !safeMode
    }
}

// 画面から AppController に頼む操作
@MainActor
struct AppActions {
    var setEnabled: (Bool) -> Void
    var restoreRealCursor: () -> Void
    // ショートカットを記録している間は、今のショートカットを外しておく
    var suspendShortcut: (Bool) -> Void
}
