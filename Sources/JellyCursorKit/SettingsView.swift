import AppKit
import Combine
import JellyCursorCore
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable {
    case general, motion, cursors, autoPause, about
}

// 設定画面で今開いているタブ。窓の外（起動時の指定など）からも切り替えられるようにする
@MainActor
@Observable
final class SettingsNavigation {
    var tab = SettingsTab.general
    // 窓を閉じている間は、プレビューを描き直さない
    var isWindowOpen = false
    // はじめて起動したときの案内を出しているか
    var showsWelcome = false
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let state: AppState
    let actions: AppActions
    @Bindable var navigation: SettingsNavigation
    let recorder: KeyRecorder

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralPane(settings: settings, state: state, actions: actions, recorder: recorder, navigation: navigation)
                .tabItem { Label("一般", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            MotionPane(settings: settings, isPreviewPaused: !navigation.isWindowOpen)
                .tabItem { Label("動き", systemImage: "wand.and.rays") }
                .tag(SettingsTab.motion)
            CursorsPane(settings: settings)
                .tabItem { Label("カーソル", systemImage: "cursorarrow") }
                .tag(SettingsTab.cursors)
            AutoPausePane(settings: settings)
                .tabItem { Label("自動で止める", systemImage: "pause.circle") }
                .tag(SettingsTab.autoPause)
            AboutPane(settings: settings, state: state)
                .tabItem { Label("情報", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 560, height: 600)
    }
}

// 一般: オン・オフ、ログイン時の起動、アイコン、ショートカット、初期化
private struct GeneralPane: View {
    @Bindable var settings: AppSettings
    let state: AppState
    let actions: AppActions
    let recorder: KeyRecorder
    @Bindable var navigation: SettingsNavigation
    @State private var loginItem = LoginItem()
    @State private var confirmsReset = false

    var body: some View {
        Form {
            if navigation.showsWelcome {
                Section {
                    WelcomeBanner { navigation.showsWelcome = false }
                }
            }
            Section {
                Toggle("JellyCursor を有効にする", isOn: Binding(
                    get: { state.isEnabled(in: settings) },
                    set: { actions.setEnabled($0) }))
                if let line = state.activity.statusLine {
                    Text(line).font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("起動") {
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }))
                    .disabled(!loginItem.isInstalled && !loginItem.isEnabled)
                if !loginItem.isInstalled {
                    Note("アプリケーションフォルダに置くと使えます（make install で ~/Applications に入ります）")
                }
                if loginItem.needsApproval {
                    HStack {
                        Note("システム設定の「ログイン項目」で許可してください")
                        Spacer()
                        Button("システム設定を開く") { loginItem.openSystemSettings() }
                    }
                }
                if let message = loginItem.errorMessage {
                    Note(message, color: .red)
                }
            }

            Section("メニューバー") {
                Toggle("メニューバーにアイコンを表示", isOn: $settings.values.showsMenuBarIcon)
                Note("隠しても、JellyCursor をもう一度開くとこの画面が開きます")
            }

            Section("ショートカット") {
                LabeledContent("オン・オフの切り替え") {
                    ShortcutRecorder(combo: $settings.values.shortcut, recorder: recorder)
                }
                if state.shortcutFailed {
                    Note("このショートカットはほかのアプリが使っているため登録できませんでした", color: .red)
                } else {
                    Note("どのアプリを使っているときでも効きます。⌘・⌃・⌥のうち2つ以上と組み合わせてください（ファンクションキーは単独でも使えます）")
                }
            }

            Section {
                Button("すべての設定を初期状態に戻す…") { confirmsReset = true }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
        // システム設定で許可して戻ってきたときにも読み直す
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .confirmationDialog("すべての設定を初期状態に戻しますか？", isPresented: $confirmsReset) {
            Button("初期状態に戻す", role: .destructive) { settings.reset() }
        } message: {
            Text("ログイン時に起動する設定は変わりません。")
        }
    }
}

// 動き: プリセット・強さ・プレビュー
private struct MotionPane: View {
    @Bindable var settings: AppSettings
    let isPreviewPaused: Bool

    var body: some View {
        Form {
            Section {
                Picker("プリセット", selection: Binding(
                    get: { settings.values.preset },
                    set: { if let preset = $0 { settings.values.motion = preset.style } })
                ) {
                    ForEach(MotionPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(Optional(preset))
                    }
                    if settings.values.preset == nil {
                        Text("カスタム").tag(MotionPreset?.none)
                    }
                }
                .pickerStyle(.segmented)

                StrengthSlider(title: "伸び", value: $settings.values.motion.stretch,
                               low: "なし", high: "大きく",
                               note: "速く動かしたときに伸びる・太る・傾く大きさ")
                StrengthSlider(title: "弾み", value: $settings.values.motion.wobble,
                               low: "なし", high: "大きく",
                               note: "止めたときや向きを変えたときの揺れ")
            }

            Section("プレビュー") {
                MotionPreview(style: settings.values.motion, isPaused: isPreviewPaused)
                    .frame(height: 170)
                Note("標準は、これまでの JellyCursor と同じ動きです")
            }
        }
        .formStyle(.grouped)
    }
}

private struct StrengthSlider: View {
    let title: String
    @Binding var value: Double
    let low: String
    let high: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: MotionStyle.range, step: 0.05) {
                Text(title)
            } minimumValueLabel: {
                Text(low).font(.caption)
            } maximumValueLabel: {
                Text(high).font(.caption)
            }
            .labelsHidden()
            Note(note)
        }
    }
}

// カーソル: 種類ごとのオン・オフ
private struct CursorsPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                CursorKindToggle(isOn: $settings.values.cursorKinds.arrow, cursor: .arrow, title: "矢印",
                                 note: "進行方向を向いて伸び、止めると1回揺れて左上向きに戻ります")
                CursorKindToggle(isOn: $settings.values.cursorKinds.iBeam, cursor: .iBeam, title: "文字の上の I 字",
                                 note: "横に振ると太く、縦に振ると伸び、斜めに振るとその向きに傾きます")
                CursorKindToggle(isOn: $settings.values.cursorKinds.pointingHand, cursor: .pointingHand,
                                 title: "リンクの上の指", note: "進行方向を指差して伸び、止めると上向きに戻ります")
            } footer: {
                Note("オフにした種類と、リサイズなどそれ以外のカーソルは、macOS の本物のカーソルのまま表示します")
            }
        }
        .formStyle(.grouped)
    }
}

private struct CursorKindToggle: View {
    @Binding var isOn: Bool
    let cursor: NSCursor
    let title: String
    let note: String

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(nsImage: cursor.image)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// 自動で止める: 視差効果・低電力・全画面・除外するアプリ
private struct AutoPausePane: View {
    @Bindable var settings: AppSettings
    // 起動中のアプリ。アプリが起動・終了したら読み直す
    @State private var runningApps: [ExcludedApp] = []

    var body: some View {
        Form {
            Section {
                Toggle("「視差効果を減らす」がオンのとき", isOn: $settings.values.pauseWhenReduceMotion)
                Toggle("低電力モードのとき", isOn: $settings.values.pauseOnLowPower)
                Toggle("全画面のアプリを使っているとき", isOn: $settings.values.pauseInFullScreen)
            } header: {
                Text("次のときは止めて、本物のカーソルに戻します")
            } footer: {
                Note("画面のロック中、ほかのユーザーに切り替えている間、スクリーンセーバーとスリープの間は、いつも止めます")
            }

            Section("このアプリを使っている間は止める") {
                if settings.values.excludedApps.isEmpty {
                    Text("なし").foregroundStyle(.secondary)
                }
                ForEach(settings.values.excludedApps) { app in
                    HStack {
                        AppIcon(bundleID: app.bundleID)
                        Text(app.name)
                        Spacer()
                        Button {
                            settings.values.setExcluded(app, false)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("リストから外す")
                    }
                }
                HStack {
                    Menu("起動中のアプリから追加") {
                        ForEach(runningApps.filter { !settings.values.isExcluded(bundleID: $0.bundleID) },
                                id: \.bundleID) { app in
                            Button(app.name) { add(app) }
                        }
                    }
                    .fixedSize()
                    Button("ほかのアプリを選ぶ…") { chooseApp() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshRunningApps() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshRunningApps()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshRunningApps()
        }
    }

    // Dock に出ているふつうのアプリ（JellyCursor 以外）
    private func refreshRunningApps() {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> ExcludedApp? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own else { return nil }
            return ExcludedApp(bundleID: id, name: app.localizedName ?? id)
        }
        runningApps = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a }).values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func add(_ app: ExcludedApp) {
        settings.values.setExcluded(app, true)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "追加"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        add(ExcludedApp(bundleID: id, name: name))
    }
}

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 18, height: 18)
        }
    }
}

// はじめて起動したときの案内
private struct WelcomeBanner: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: AppIconImage.make())
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("JellyCursor へようこそ").font(.headline)
                Text("マウスを動かすと、カーソルが伸びて揺れます。メニューバーの \(Image(systemName: "cursorarrow.motionlines")) から、いつでもオン・オフや設定の変更ができます。")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("案内を閉じる")
        }
        .padding(.vertical, 4)
    }
}

// 情報: バージョン・今の状態・困ったとき
private struct AboutPane: View {
    let settings: AppSettings
    let state: AppState
    @State private var copied = false
    @State private var copies = 0

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: AppIconImage.make())
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("JellyCursor").font(.title2.weight(.semibold))
                        Text("動かすと伸びて、止めると揺れて戻るカーソル").foregroundStyle(.secondary)
                        Text("バージョン \(version)").font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("今の状態", value: status)
                LabeledContent("本物のカーソルを隠す",
                               value: state.canHideCursor ? "できます" : "できません（自前の絵を重ねて描きます）")
            }

            Section("困ったとき") {
                Note("カーソルが見えなくなったら、ショートカットかメニューの「本物のカーソルに戻す」でオフにできます。"
                    + "ターミナルで killall JellyCursor を実行しても、本物のカーソルに戻って終わります")
                Note("Shift キーを押しながら JellyCursor を開くと、止めた状態（セーフモード）で起動します")
                HStack {
                    Button("診断情報をコピー") { copyDiagnostics() }
                    if copied {
                        Text("コピーしました").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Note("おかしな動きを伝えるときに貼り付けてください。この起動のあいだの状態の変化の記録も入ります")
            }
        }
        .formStyle(.grouped)
    }

    private func copyDiagnostics() {
        let report = Diagnostics(
            appVersion: version, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            activity: state.activity, canHideCursor: state.canHideCursor, safeMode: state.safeMode,
            pointerScale: Double(SystemPointer.scale()),
            screens: NSScreen.screens.map { "\(Int($0.frame.width))×\(Int($0.frame.height))@\($0.backingScaleFactor)x" },
            settings: settings.values, shortcutFailed: state.shortcutFailed, recentLog: recentLogLines())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text, forType: .string)
        // 続けて押したときは、最後に押してから2秒たつまで「コピーしました」を出しておく
        copies += 1
        let copy = copies
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copies == copy { copied = false }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "開発版"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private var status: String { state.activity.summary }
}

// 小さな灰色の説明文
private struct Note: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
