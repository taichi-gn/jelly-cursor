import Carbon
import JellyCursorCore

// どのアプリを使っているときでも効くショートカット。Carbon の RegisterEventHotKey は、アクセシビリティなどの権限が要らない
@MainActor
final class HotKey {
    // Carbon のイベントから呼び戻す先。アプリで1つだけ使う
    fileprivate static weak var current: HotKey?
    // 'JLCY'
    private static let signature: OSType = 0x4A4C_4359

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    // 登録できたら true。combo が nil なら今のものを外すだけ
    func register(_ combo: KeyCombo?, action: @escaping () -> Void) -> Bool {
        unregister()
        guard let combo else { return true }
        guard installHandler() else { return false }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        self.action = action
        Self.current = self
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        action = nil
    }

    fileprivate func fire() {
        action?()
    }

    private func installHandler() -> Bool {
        guard handlerRef == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &spec, nil, &handlerRef) == noErr
    }
}

// Carbon のイベントは主スレッドで届く
private func hotKeyPressed(_ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    MainActor.assumeIsolated { HotKey.current?.fire() }
    return noErr
}
