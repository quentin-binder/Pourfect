import Foundation
import Testing
@testable import BottleSortCore

@Suite struct SettingsTests {
    /// A fresh, isolated defaults domain per test.
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "BottleSortCoreTests.settings.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func emptyStoreLoadsDefaults() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let loaded = UserDefaultsSettingsStore(defaults: defaults).load()
        #expect(loaded == GameSettings.defaults)
        #expect(loaded.soundEnabled && loaded.hapticsEnabled)
        #expect(!loaded.colorRunesEnabled)
        #expect(loaded.reduceMotion == .system)
    }

    @Test func roundTrip() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let custom = GameSettings(soundEnabled: false, hapticsEnabled: false,
                                  colorRunesEnabled: true, reduceMotion: .always)
        UserDefaultsSettingsStore(defaults: defaults).save(custom)
        // A new store instance reads what the previous one wrote.
        #expect(UserDefaultsSettingsStore(defaults: defaults).load() == custom)
    }

    @Test func unknownOrMissingValuesFallBackIndividually() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("sometimes", forKey: UserDefaultsSettingsStore.Key.reduceMotion)
        defaults.set(false, forKey: UserDefaultsSettingsStore.Key.sound)
        let loaded = UserDefaultsSettingsStore(defaults: defaults).load()
        #expect(loaded.reduceMotion == .system)
        #expect(!loaded.soundEnabled)
        #expect(loaded.hapticsEnabled)
    }

    @Test func reduceMotionResolution() {
        #expect(ReduceMotionPreference.system.resolved(system: true))
        #expect(!ReduceMotionPreference.system.resolved(system: false))
        #expect(ReduceMotionPreference.always.resolved(system: false))
        #expect(!ReduceMotionPreference.never.resolved(system: true))
    }
}
