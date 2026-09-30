import AppKit
import JellyCursorCore

// メニューバーのアイコンとメニュー。メニューは開くたびに今の状態から作り直す
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var toggleEnabled: () -> Void
        var applyPreset: (MotionPreset) -> Void
        var applyCustomMotion: () -> Void
        var openSettings: (SettingsTab?) -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let settings: AppSettings
    private let state: AppState
    private let actions: Actions

    init(settings: AppSettings, state: AppState, actions: Actions) {
        self.settings = settings
        self.state = state
        self.actions = actions
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        update()
    }

    var isVisible: Bool {
        get { item.isVisible }
        set { item.isVisible = newValue }
    }

    // メニューを開く（-OpenMenu YES で起動したとき。メニューの見た目を撮るため）
    func open() {
        item.button?.performClick(nil)
    }

    // アイコンを今の状態に合わせる。オフのときは薄く、一時停止中と本物のカーソルを隠せないときは印を付ける
    func update() {
        let icon = StatusIcon(activity: state.activity, canHideCursor: state.canHideCursor)
        guard let button = item.button else { return }
        if let image = StatusIconImage.image(for: icon) {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "J"
        }
        button.appearsDisabled = icon.isDimmed
        button.toolTip = state.activity.statusLine.map { "JellyCursor — \($0)" } ?? "JellyCursor"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let values = settings.values

        let enabled = addItem("有効", action: #selector(toggleEnabled), symbol: "cursorarrow.motionlines")
        enabled.state = state.isEnabled(in: settings) ? .on : .off
        if let shortcut = values.shortcut, !state.shortcutFailed, let key = shortcut.menuKeyEquivalent {
            enabled.keyEquivalent = key
            enabled.keyEquivalentModifierMask = NSEvent.ModifierFlags(shortcut.modifiers)
        }
        if let line = state.activity.statusLine {
            addInfo(line, symbol: "pause.circle")
            // 止めている理由を設定で変えられるときは、その設定を開く項目を添える（状態の行は押せる項目にしない）
            if case .paused(let reason) = state.activity, let tab = Self.settingsTab(for: reason) {
                let fix = addItem(tab == .cursors ? "カーソルの設定…" : "自動で止める設定…",
                                  action: #selector(openPauseSettings(_:)), symbol: "gearshape")
                fix.representedObject = tab.rawValue
            }
        }

        let presets = NSMenu()
        // カスタムを押せないときに、押せる表示に戻されないようにする
        presets.autoenablesItems = false
        for preset in MotionPreset.allCases {
            let presetItem = NSMenuItem(title: preset.title, action: #selector(applyPreset(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = preset.rawValue
            presetItem.state = values.preset == preset ? .on : .off
            presets.addItem(presetItem)
        }
        // カスタムはいつも出す。まだカスタムにしたことがなければ押せない
        let custom = NSMenuItem(title: "カスタム", action: #selector(applyCustomMotion), keyEquivalent: "")
        custom.target = self
        custom.state = values.preset == nil ? .on : .off
        custom.isEnabled = values.customMotion != nil
        presets.addItem(custom)
        let presetsItem = NSMenuItem(title: "動きの強さ", action: nil, keyEquivalent: "")
        presetsItem.submenu = presets
        decorate(presetsItem, symbol: "slider.horizontal.3")
        menu.addItem(presetsItem)

        menu.addItem(.separator())
        if !state.canHideCursor {
            addInfo("本物のカーソルを隠せないため、重ねて描いています", symbol: "exclamationmark.triangle")
        }
        if state.shortcutFailed, let shortcut = values.shortcut {
            addInfo("\(shortcut.displayString) はほかのアプリが使っているため登録できませんでした",
                    symbol: "exclamationmark.triangle")
        }
        let settingsItem = addItem("設定…", action: #selector(openSettings), symbol: "gearshape")
        settingsItem.keyEquivalent = ","
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "JellyCursor を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        decorate(quit, symbol: "power")
        menu.addItem(quit)
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, symbol: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        decorate(menuItem, symbol: symbol)
        menu.addItem(menuItem)
        return menuItem
    }

    // macOS 26 からは、メニューの項目に記号を添えるのがふつうの見た目なので、そのときだけ付ける
    private func decorate(_ menuItem: NSMenuItem, symbol: String) {
        if #available(macOS 26, *) {
            menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    // 押せない説明の行
    private func addInfo(_ title: String, symbol: String) {
        let info = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        info.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        info.isEnabled = false
        menu.addItem(info)
    }

    @objc private func toggleEnabled() {
        actions.toggleEnabled()
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = MotionPreset(rawValue: raw) else { return }
        actions.applyPreset(preset)
    }

    @objc private func applyCustomMotion() {
        actions.applyCustomMotion()
    }

    @objc private func openSettings() {
        actions.openSettings(nil)
    }

    @objc private func openPauseSettings(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = SettingsTab(rawValue: raw) else { return }
        actions.openSettings(tab)
    }

    // 止めている理由を変えられる設定のタブ。ロックやスリープなど、設定では変えられない理由なら nil
    private static func settingsTab(for reason: PauseReason) -> SettingsTab? {
        switch reason {
        case .noCursorKinds: .cursors
        case .excludedApp, .fullScreen, .reduceMotion, .lowPower: .autoPause
        case .sessionInactive, .screenLocked, .screenSaver, .asleep: nil
        }
    }
}

extension NSEvent.ModifierFlags {
    init(_ modifiers: KeyModifiers) {
        self = []
        if modifiers.contains(.control) { insert(.control) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.command) { insert(.command) }
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}
