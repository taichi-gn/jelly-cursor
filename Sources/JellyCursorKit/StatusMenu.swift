import AppKit
import JellyCursorCore

// メニューバーのアイコンとメニュー。メニューは開くたびに今の状態から作り直す
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var toggleEnabled: () -> Void
        var toggleExclusion: (AppIdentity) -> Void
        var applyPreset: (MotionPreset) -> Void
        var openSettings: () -> Void
        var restoreRealCursor: () -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let settings: AppSettings
    private let state: AppState
    private let frontApp: () -> AppIdentity?
    private let actions: Actions

    init(settings: AppSettings, state: AppState, frontApp: @escaping () -> AppIdentity?, actions: Actions) {
        self.settings = settings
        self.state = state
        self.frontApp = frontApp
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

    // アイコンを今の状態に合わせる。一時停止中は薄く、本物のカーソルを隠せないときは警告の形にする
    func update() {
        let icon = StatusIcon(activity: state.activity, canHideCursor: state.canHideCursor)
        guard let button = item.button else { return }
        if let image = NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: icon.accessibilityDescription) {
            image.isTemplate = true
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
        }
        if let app = frontApp() {
            let exclusion = addItem("「\(app.name)」では無効", action: #selector(toggleExclusion(_:)), symbol: "nosign")
            exclusion.state = values.isExcluded(bundleID: app.bundleID) ? .on : .off
            exclusion.representedObject = FrontApp(app)
        }

        let presets = NSMenu()
        for preset in MotionPreset.allCases {
            let presetItem = NSMenuItem(title: preset.title, action: #selector(applyPreset(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = preset.rawValue
            presetItem.state = values.preset == preset ? .on : .off
            presets.addItem(presetItem)
        }
        if values.preset == nil {
            let custom = NSMenuItem(title: "カスタム", action: nil, keyEquivalent: "")
            custom.state = .on
            custom.isEnabled = false
            presets.addItem(custom)
        }
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
        addItem("本物のカーソルに戻す", action: #selector(restoreRealCursor), symbol: "arrow.uturn.backward")
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

    @objc private func toggleExclusion(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? FrontApp else { return }
        actions.toggleExclusion(app.identity)
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = MotionPreset(rawValue: raw) else { return }
        actions.applyPreset(preset)
    }

    @objc private func openSettings() {
        actions.openSettings()
    }

    @objc private func restoreRealCursor() {
        actions.restoreRealCursor()
    }
}

// メニューの項目に持たせる前面のアプリ（representedObject は Objective-C のオブジェクトにする）
private final class FrontApp: NSObject {
    let identity: AppIdentity

    init(_ identity: AppIdentity) {
        self.identity = identity
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
