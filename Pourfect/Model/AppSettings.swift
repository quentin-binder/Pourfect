import BottleSortCore
import Observation
import SwiftUI

/// Observable player preferences, saved through a `SettingsStore` on every change.
/// Injected at the app root with `.environment(settings)`; views bind to `value`.
@Observable
final class AppSettings {
    @ObservationIgnored private let store: SettingsStore

    var value: GameSettings {
        didSet { if value != oldValue { store.save(value) } }
    }

    init(store: SettingsStore) {
        self.store = store
        self.value = store.load()
    }

    /// Whether to use the reduced animations, given the system's accessibility setting.
    func reduceMotion(system: Bool) -> Bool {
        value.reduceMotion.resolved(system: system)
    }
}

private struct ColorRunesEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct EffectiveReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Draw a colorblind rune on every liquid layer (from settings; set at the app root).
    var colorRunesEnabled: Bool {
        get { self[ColorRunesEnabledKey.self] }
        set { self[ColorRunesEnabledKey.self] = newValue }
    }

    /// Reduce Motion after applying the in-app override (system / always / never).
    /// Read this instead of `accessibilityReduceMotion`.
    var effectiveReduceMotion: Bool {
        get { self[EffectiveReduceMotionKey.self] }
        set { self[EffectiveReduceMotionKey.self] = newValue }
    }
}

/// Publishes the settings-derived environment values (`colorRunesEnabled`, `effectiveReduceMotion`).
private struct SettingsEnvironment: ViewModifier {
    let settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        content
            .environment(settings)
            .environment(\.colorRunesEnabled, settings.value.colorRunesEnabled)
            .environment(\.effectiveReduceMotion, settings.reduceMotion(system: systemReduceMotion))
    }
}

extension View {
    /// Injects `settings` and the environment values derived from it.
    func settingsEnvironment(_ settings: AppSettings) -> some View {
        modifier(SettingsEnvironment(settings: settings))
    }
}
