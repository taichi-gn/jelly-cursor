import Foundation
import Testing
@testable import JellyCursorCore

@MainActor
@Suite struct AppSettingsTests {
    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "jellycursor.tests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func startsWithDefaults() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.values == SettingsValues())
        #expect(settings.values.isEnabled)
        #expect(settings.values.motion == .standard)
        #expect(settings.values.preset == .standard)
        #expect(settings.values.shortcut == nil)
    }

    @Test func savesAndLoads() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.values.motion.stretch = 1.5
        settings.values.cursorKinds.iBeam = false
        settings.values.shortcut = KeyCombo(keyCode: 0x26, modifiers: [.control, .option], characters: "j")
        settings.values.setExcluded(ExcludedApp(bundleID: "com.example.game", name: "Game"), true)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.values == settings.values)
        #expect(reloaded.values.preset == nil)
    }

    // カスタムにした値は、プリセットを選んだあとでも覚えていて、カスタムを選ぶと戻る
    @Test func remembersCustomMotion() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.values.customMotion == nil)
        // まだカスタムにしたことがなければ、カスタムを選んでも変わらない
        settings.values.applyCustomMotion()
        #expect(settings.values.preset == .standard)

        settings.values.motion.stretch = 1.3
        let custom = MotionStyle(stretch: 1.3, wobble: 1)
        #expect(settings.values.preset == nil)
        #expect(settings.values.customMotion == custom)
        settings.values.motion = MotionPreset.lively.style
        #expect(settings.values.preset == .lively)
        #expect(settings.values.customMotion == custom)
        #expect(AppSettings(defaults: defaults).values.customMotion == custom)
        settings.values.applyCustomMotion()
        #expect(settings.values.motion == custom)
        settings.reset()
        #expect(settings.values.customMotion == nil)
    }

    @Test func notifiesWithOldValueOnlyWhenChanged() {
        let settings = AppSettings(defaults: freshDefaults())
        var received: [SettingsValues] = []
        settings.onChange = { received.append($0) }
        settings.values.pauseInFullScreen = true
        settings.values.pauseInFullScreen = true
        #expect(received.count == 1)
        #expect(received.first?.pauseInFullScreen == false)
    }

    @Test func toleratesBrokenAndPartialData() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: AppSettings.defaultsKey)
        #expect(AppSettings(defaults: defaults).values == SettingsValues())

        let partial = #"{"isEnabled": false, "motion": {"stretch": 0.5}, "cursorKinds": {"arrow": false}, "shortcut": 3}"#
        defaults.set(Data(partial.utf8), forKey: AppSettings.defaultsKey)
        let values = AppSettings(defaults: defaults).values
        #expect(!values.isEnabled)
        #expect(values.motion == MotionStyle(stretch: 0.5, wobble: 1))
        // カスタムを覚えていなかった版の設定でも、プリセットと違う値ならカスタムとして覚える
        #expect(values.customMotion == values.motion)
        #expect(!values.cursorKinds.arrow && values.cursorKinds.iBeam && values.cursorKinds.pointingHand)
        #expect(values.shortcut == nil)
        #expect(!values.pauseWhenReduceMotion && !values.pauseOnLowPower && !values.pauseInFullScreen)
        // 「クリックで弾む」が無かった版の設定は、オンとして読む
        #expect(values.clickBounce)
    }

    @Test func clickBounceReachesMotionParameters() {
        var values = SettingsValues()
        #expect(values.motionParameters.clickDepth > 0)
        values.clickBounce = false
        #expect(values.motionParameters.clickDepth == 0)
        #expect(values.motionParameters != SettingsValues().motionParameters)
    }

    @Test func resetRestoresDefaults() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.values.showsMenuBarIcon = false
        settings.values.motion = MotionPreset.lively.style
        settings.reset()
        #expect(settings.values == SettingsValues())
        #expect(AppSettings(defaults: defaults).values == SettingsValues())
    }

    @Test func exclusionIsUniquePerApp() {
        var values = SettingsValues()
        let app = ExcludedApp(bundleID: "com.example.a", name: "A")
        values.setExcluded(app, true)
        values.setExcluded(ExcludedApp(bundleID: "com.example.a", name: "A (renamed)"), true)
        #expect(values.excludedApps == [ExcludedApp(bundleID: "com.example.a", name: "A (renamed)")])
        #expect(values.isExcluded(bundleID: "com.example.a"))
        #expect(!values.isExcluded(bundleID: nil))
        values.setExcluded(app, false)
        #expect(values.excludedApps.isEmpty)
    }

    @Test func cursorKindsCoverOnlyDrawnKinds() {
        var kinds = CursorKinds()
        #expect(kinds.contains(.arrow) && kinds.contains(.iBeam) && kinds.contains(.pointingHand))
        #expect(!kinds.contains(.other))
        kinds.pointingHand = false
        #expect(!kinds.contains(.pointingHand))
    }
}
