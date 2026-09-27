import AppKit
import JellyCursorCore
import Observation
import SwiftUI

// ショートカットを記録するボタン。押してから次に押したキーの組み合わせを記録する。
// esc でやめ、delete で消す。記録している間は onRecordingChange(true) で今のショートカットを外してもらう
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    let onRecordingChange: (Bool) -> Void
    @State private var recorder = KeyRecorder()

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start { combo = $0 }
                }
            } label: {
                Text(recorder.isRecording ? "キーを押してください…" : combo?.displayString ?? "記録する")
                    .frame(minWidth: 140)
            }
            .help(recorder.isRecording ? "esc でやめる、delete で消す" : "押してからショートカットのキーを押します")
            if combo != nil && !recorder.isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("ショートカットを消す")
            }
        }
        .onChange(of: recorder.isRecording) { _, recording in
            onRecordingChange(recording)
        }
        .onDisappear { recorder.stop() }
    }
}

@MainActor
@Observable
private final class KeyRecorder {
    private(set) var isRecording = false
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onRecord: ((KeyCombo?) -> Void)?

    func start(onRecord: @escaping (KeyCombo?) -> Void) {
        stop()
        self.onRecord = onRecord
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let press = KeyPress(event)
            let consumed = MainActor.assumeIsolated { self?.handle(press) ?? false }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onRecord = nil
        if isRecording { isRecording = false }
    }

    private func handle(_ press: KeyPress) -> Bool {
        if press.modifiers.isEmpty {
            switch press.keyCode {
            case 0x35: // esc
                stop()
                return true
            case 0x33, 0x75: // delete、forward delete
                onRecord?(nil)
                stop()
                return true
            default:
                break
            }
        }
        let combo = KeyCombo(keyCode: press.keyCode, modifiers: press.modifiers, characters: press.characters)
        guard combo.isValid else {
            NSSound.beep()
            return true
        }
        onRecord?(combo)
        stop()
        return true
    }
}

// キー入力から必要なものだけを写した値
private struct KeyPress: Sendable {
    let keyCode: UInt16
    let modifiers: KeyModifiers
    let characters: String?

    init(_ event: NSEvent) {
        keyCode = event.keyCode
        modifiers = KeyModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        characters = event.charactersIgnoringModifiers
    }
}
