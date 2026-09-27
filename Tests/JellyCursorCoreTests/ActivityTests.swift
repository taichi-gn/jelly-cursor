import Foundation
import Testing
@testable import JellyCursorCore

@Suite struct ActivityTests {
    private let game = AppIdentity(bundleID: "com.example.game", name: "Game")

    private var settings: SettingsValues {
        var s = SettingsValues()
        s.setExcluded(ExcludedApp(bundleID: game.bundleID, name: game.name), true)
        s.pauseInFullScreen = true
        return s
    }

    @Test func runsByDefault() {
        #expect(Activity(settings: SettingsValues(), conditions: SystemConditions(), safeMode: false) == .running)
    }

    @Test func offAndSafeModeComeFirst() {
        var s = settings
        var c = SystemConditions()
        c.screenLocked = true
        #expect(Activity(settings: s, conditions: c, safeMode: true) == .safeMode)
        s.isEnabled = false
        #expect(Activity(settings: s, conditions: c, safeMode: true) == .off)
    }

    @Test func reasonsInPriorityOrder() {
        var c = SystemConditions()
        c.sessionActive = false
        c.screenLocked = true
        c.screenSaverRunning = true
        c.asleep = true
        c.frontApp = game
        c.frontAppFullScreen = true
        c.reduceMotion = true
        c.lowPower = true
        let expected: [PauseReason] = [
            .sessionInactive, .screenLocked, .screenSaver, .asleep, .excludedApp("Game"), .fullScreen, .reduceMotion,
            .lowPower,
        ]
        for reason in expected {
            #expect(Activity(settings: settings, conditions: c, safeMode: false) == .paused(reason))
            switch reason {
            case .sessionInactive: c.sessionActive = true
            case .screenLocked: c.screenLocked = false
            case .screenSaver: c.screenSaverRunning = false
            case .asleep: c.asleep = false
            case .excludedApp: c.frontApp = AppIdentity(bundleID: "com.example.other", name: "Other")
            case .fullScreen: c.frontAppFullScreen = false
            case .reduceMotion: c.reduceMotion = false
            case .lowPower: c.lowPower = false
            }
        }
        #expect(Activity(settings: settings, conditions: c, safeMode: false) == .running)
    }

    @Test func settingsTurnOffAutomaticPauses() {
        var s = SettingsValues()
        s.pauseWhenReduceMotion = false
        s.pauseOnLowPower = false
        s.pauseInFullScreen = false
        var c = SystemConditions()
        c.reduceMotion = true
        c.lowPower = true
        c.frontAppFullScreen = true
        #expect(Activity(settings: s, conditions: c, safeMode: false) == .running)
        // 全画面を止める設定は初期値ではオフ
        #expect(!SettingsValues().pauseInFullScreen)
    }

    @Test func statusLines() {
        #expect(Activity.running.statusLine == nil)
        #expect(Activity.off.statusLine == nil)
        #expect(Activity.safeMode.statusLine != nil)
        #expect(Activity.paused(.excludedApp("Game")).statusLine == "一時停止中: 「Game」では無効にしています")
    }

    @Test func icons() {
        #expect(StatusIcon(activity: .running, canHideCursor: true) == .running)
        #expect(StatusIcon(activity: .running, canHideCursor: false) == .warning)
        #expect(StatusIcon(activity: .paused(.lowPower), canHideCursor: true) == .paused)
        #expect(StatusIcon(activity: .off, canHideCursor: false) == .off)
        #expect(StatusIcon(activity: .safeMode, canHideCursor: true) == .off)
        #expect(StatusIcon.paused.isDimmed && !StatusIcon.running.isDimmed)
        #expect(StatusIcon.off.symbolName != StatusIcon.running.symbolName)
    }
}

@Suite struct InstallLocationTests {
    @Test func applicationsFolders() {
        #expect(InstallLocation.isInApplicationsFolder("/Applications/JellyCursor.app", home: "/Users/a"))
        #expect(InstallLocation.isInApplicationsFolder("/Users/a/Applications/JellyCursor.app", home: "/Users/a"))
        #expect(InstallLocation.isInApplicationsFolder("/Applications/Utilities/../JellyCursor.app", home: "/Users/a"))
        #expect(!InstallLocation.isInApplicationsFolder("/Users/a/src/jelly-cursor/JellyCursor.app", home: "/Users/a"))
        #expect(!InstallLocation.isInApplicationsFolder("/ApplicationsX/JellyCursor.app", home: "/Users/a"))
        #expect(!InstallLocation.isInApplicationsFolder("/Users/b/Applications/JellyCursor.app", home: "/Users/a"))
    }
}
