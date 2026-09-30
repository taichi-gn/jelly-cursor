import Foundation
import Observation

// どのカーソルを自前で描くか。オフにした種類は本物のカーソルに任せる
package struct CursorKinds: Codable, Equatable, Sendable {
    package var arrow = true
    package var iBeam = true
    package var pointingHand = true

    package init() {}

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        arrow = (try? c.decode(Bool.self, forKey: .arrow)) ?? true
        iBeam = (try? c.decode(Bool.self, forKey: .iBeam)) ?? true
        pointingHand = (try? c.decode(Bool.self, forKey: .pointingHand)) ?? true
    }

    // どれか1つでも自前で描くか。すべてオフなら、描くものが無いので止める
    package var drawsAny: Bool { arrow || iBeam || pointingHand }

    package func contains(_ kind: CursorKind) -> Bool {
        switch kind {
        case .arrow: arrow
        case .iBeam: iBeam
        case .pointingHand: pointingHand
        case .other: false
        }
    }
}

// 使っている間は止めるアプリ
package struct ExcludedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    package var bundleID: String
    package var name: String

    package var id: String { bundleID }

    package init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

// 保存する設定の値。項目が増えたり壊れたりしても、読めない項目だけ初期値に戻して読む
package struct SettingsValues: Codable, Equatable, Sendable {
    package var isEnabled = true
    // 動きの強さ。どのプリセットとも違う値にしたら、カスタムとして覚えておく
    package var motion = MotionStyle.standard {
        didSet { if MotionPreset(matching: motion) == nil { customMotion = motion } }
    }
    // 最後にカスタムにした値。プリセットを選んだあとでも、カスタムを選べばこの値に戻す
    package private(set) var customMotion: MotionStyle?
    // クリックしたときに、押すとつぶれ、離すと弾んで戻る
    package var clickBounce = true
    package var cursorKinds = CursorKinds()
    // Mac の設定に合わせて止めるのは、選んだときだけ（オンにしたら動く、を基本にする）
    package var pauseWhenReduceMotion = false
    package var pauseOnLowPower = false
    package var pauseInFullScreen = false
    package var excludedApps: [ExcludedApp] = []
    package var showsMenuBarIcon = true
    package var shortcut: KeyCombo?

    package init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, motion, customMotion, clickBounce, cursorKinds, pauseWhenReduceMotion, pauseOnLowPower, pauseInFullScreen
        case excludedApps, showsMenuBarIcon, shortcut
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsValues()
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? d.isEnabled
        motion = (try? c.decode(MotionStyle.self, forKey: .motion)) ?? d.motion
        customMotion = try? c.decode(MotionStyle.self, forKey: .customMotion)
        clickBounce = (try? c.decode(Bool.self, forKey: .clickBounce)) ?? d.clickBounce
        cursorKinds = (try? c.decode(CursorKinds.self, forKey: .cursorKinds)) ?? d.cursorKinds
        pauseWhenReduceMotion = (try? c.decode(Bool.self, forKey: .pauseWhenReduceMotion)) ?? d.pauseWhenReduceMotion
        pauseOnLowPower = (try? c.decode(Bool.self, forKey: .pauseOnLowPower)) ?? d.pauseOnLowPower
        pauseInFullScreen = (try? c.decode(Bool.self, forKey: .pauseInFullScreen)) ?? d.pauseInFullScreen
        excludedApps = (try? c.decode([ExcludedApp].self, forKey: .excludedApps)) ?? d.excludedApps
        showsMenuBarIcon = (try? c.decode(Bool.self, forKey: .showsMenuBarIcon)) ?? d.showsMenuBarIcon
        shortcut = try? c.decode(KeyCombo.self, forKey: .shortcut)
    }

    package var preset: MotionPreset? { MotionPreset(matching: motion) }

    // カスタムの値に戻す。まだカスタムにしたことがなければ何もしない
    package mutating func applyCustomMotion() {
        if let customMotion { motion = customMotion }
    }

    // 描く側に渡す動きの値
    package var motionParameters: MotionParameters { MotionParameters(motion, clickBounce: clickBounce) }

    package func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains { $0.bundleID == bundleID }
    }

    package mutating func setExcluded(_ app: ExcludedApp, _ excluded: Bool) {
        excludedApps.removeAll { $0.bundleID == app.bundleID }
        if excluded { excludedApps.append(app) }
    }
}

// 設定。変えるとすぐ UserDefaults に保存し、onChange で知らせる。
// 設定画面は Observation で、描く側は onChange で受け取った値の写しで動く
@MainActor
@Observable
package final class AppSettings {
    package static let defaultsKey = "settings"

    package var values: SettingsValues {
        didSet {
            guard values != oldValue else { return }
            save()
            onChange?(oldValue)
        }
    }

    // 変わる前の値を受け取る
    @ObservationIgnored package var onChange: ((SettingsValues) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(SettingsValues.self, from: $0) } ?? SettingsValues()
    }

    package func reset() {
        values = SettingsValues()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
