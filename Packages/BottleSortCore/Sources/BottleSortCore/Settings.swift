import Foundation

/// How the app decides whether to reduce motion.
public enum ReduceMotionPreference: String, CaseIterable, Codable, Sendable {
    /// Follow the system accessibility setting.
    case system
    /// Always use the reduced animations.
    case always
    /// Always use the full animations.
    case never

    /// The value to use, given the system's accessibility setting.
    public func resolved(system: Bool) -> Bool {
        switch self {
        case .system: system
        case .always: true
        case .never: false
        }
    }
}

/// Player preferences. Plain value; persisted through a `SettingsStore`.
public struct GameSettings: Equatable, Codable, Sendable {
    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    /// Draw a rune on every liquid layer so colors can be told apart without hue.
    public var colorRunesEnabled: Bool
    public var reduceMotion: ReduceMotionPreference
    /// The chosen workbench theme, flask shape and completion effect (R7). Only the choice is
    /// stored; the app resolves it against the unlocked rewards (`CosmeticSelection.resolved`).
    public var cosmetics: CosmeticSelection

    public init(soundEnabled: Bool = true, hapticsEnabled: Bool = true,
                colorRunesEnabled: Bool = false, reduceMotion: ReduceMotionPreference = .system,
                cosmetics: CosmeticSelection = .starter) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.colorRunesEnabled = colorRunesEnabled
        self.reduceMotion = reduceMotion
        self.cosmetics = cosmetics
    }

    public static let defaults = GameSettings()
}

/// Persistence for `GameSettings`. Swap the implementation to change storage.
public protocol SettingsStore {
    func load() -> GameSettings
    func save(_ settings: GameSettings)
}

/// Stores each setting under its own `UserDefaults` key (`settings.sound`, …), so a missing
/// or unreadable key falls back to its default without losing the others.
public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe.
    public let defaults: UserDefaults

    public enum Key {
        public static let sound = "settings.sound"
        public static let haptics = "settings.haptics"
        public static let colorRunes = "settings.colorRunes"
        public static let reduceMotion = "settings.reduceMotion"
        public static let theme = "settings.theme"
        public static let flaskShape = "settings.flaskShape"
        public static let potionEffect = "settings.potionEffect"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> GameSettings {
        let fallback = GameSettings.defaults
        return GameSettings(
            soundEnabled: bool(Key.sound) ?? fallback.soundEnabled,
            hapticsEnabled: bool(Key.haptics) ?? fallback.hapticsEnabled,
            colorRunesEnabled: bool(Key.colorRunes) ?? fallback.colorRunesEnabled,
            reduceMotion: defaults.string(forKey: Key.reduceMotion).flatMap(ReduceMotionPreference.init(rawValue:))
                ?? fallback.reduceMotion,
            cosmetics: CosmeticSelection(
                theme: raw(Key.theme).flatMap(WorkbenchTheme.init(rawValue:)) ?? fallback.cosmetics.theme,
                flask: raw(Key.flaskShape).flatMap(FlaskShapeStyle.init(rawValue:)) ?? fallback.cosmetics.flask,
                effect: raw(Key.potionEffect).flatMap(PotionEffect.init(rawValue:)) ?? fallback.cosmetics.effect))
    }

    private func raw(_ key: String) -> String? { defaults.string(forKey: key) }

    public func save(_ settings: GameSettings) {
        defaults.set(settings.soundEnabled, forKey: Key.sound)
        defaults.set(settings.hapticsEnabled, forKey: Key.haptics)
        defaults.set(settings.colorRunesEnabled, forKey: Key.colorRunes)
        defaults.set(settings.reduceMotion.rawValue, forKey: Key.reduceMotion)
        defaults.set(settings.cosmetics.theme.rawValue, forKey: Key.theme)
        defaults.set(settings.cosmetics.flask.rawValue, forKey: Key.flaskShape)
        defaults.set(settings.cosmetics.effect.rawValue, forKey: Key.potionEffect)
    }

    /// A stored Bool. Also accepts strings such as "1" / "YES" (launch arguments like
    /// `-settings.colorRunes 1` arrive as strings), read the way `UserDefaults.bool` does.
    private func bool(_ key: String) -> Bool? {
        guard let value = defaults.object(forKey: key) else { return nil }
        return value as? Bool ?? defaults.bool(forKey: key)
    }
}
