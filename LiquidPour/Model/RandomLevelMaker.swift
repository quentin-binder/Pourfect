import BottleSortCore
import Foundation
import Observation

extension GameMode {
    var title: String {
        switch self {
        case .classic: return String(localized: "Classic", comment: "Random recipe mode")
        case .locksAndKeys: return String(localized: "Rune Seals", comment: "Random recipe mode with sealed flasks and rune keys")
        case .hidden: return String(localized: "Murky Layers", comment: "Random recipe mode with hidden layers")
        }
    }

    var blurb: String {
        switch self {
        case .classic: return String(localized: "Sort every potion into its own flask.")
        case .locksAndKeys: return String(localized: "Sealed flasks open when you pour their rune key into them. Keys move alone.")
        case .hidden: return String(localized: "Murky layers below the top show as “?” until you uncover them.")
        }
    }
}

/// Last-used Random Level settings, kept in UserDefaults. Launch arguments such as
/// `-random.colors 8` override them for one run (UserDefaults argument domain).
enum RandomSettings {
    static let modeKey = "random.mode"
    static let colorsKey = "random.colors"
    static let capacityKey = "random.capacity"
    static let emptyKey = "random.empty"
    static let locksKey = "random.locks"

    static func load(_ defaults: UserDefaults = .standard) -> RandomLevelOptions {
        let base = RandomLevelOptions()
        func int(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
        }
        return RandomLevelOptions(
            mode: defaults.string(forKey: modeKey).flatMap(GameMode.init(rawValue:)) ?? base.mode,
            colors: int(colorsKey, base.colors),
            capacity: int(capacityKey, base.capacity),
            emptyBottles: int(emptyKey, base.emptyBottles),
            locks: int(locksKey, base.locks)
        ).clamped
    }

    static func save(_ options: RandomLevelOptions, _ defaults: UserDefaults = .standard) {
        defaults.set(options.mode.rawValue, forKey: modeKey)
        defaults.set(options.colors, forKey: colorsKey)
        defaults.set(options.capacity, forKey: capacityKey)
        defaults.set(options.emptyBottles, forKey: emptyKey)
        defaults.set(options.locks, forKey: locksKey)
    }

    /// Flasks a recipe with these options will have (lock recipes get one extra, partly filled flask).
    static func bottleCount(_ options: RandomLevelOptions) -> Int {
        let o = options.clamped
        return o.colors + o.emptyBottles + (o.mode == .locksAndKeys ? 1 : 0)
    }
}

/// Runs `RandomLevel.generate` off the main thread and publishes its progress.
/// The core is deterministic for a seed; the fresh seed comes from the system RNG here.
@MainActor
@Observable
final class RandomLevelMaker {
    enum Phase: Equatable {
        case idle
        case generating(attempt: Int, of: Int)
        case failed
    }

    private(set) var phase: Phase = .idle
    private var generation = 0
    private var task: Task<Void, Never>?

    var isGenerating: Bool { if case .generating = phase { return true } else { return false } }

    static var failureMessage: String {
        String(localized: "Couldn't brew a solvable recipe in \(RandomLevel.defaultMaxAttempts) tries — try more empty flasks or fewer potions")
    }

    /// Generates a level and passes it to `completion` (on the main actor). On failure
    /// `phase` becomes `.failed`. `seed` defaults to a fresh random seed.
    func generate(_ options: RandomLevelOptions, seed: UInt64? = nil,
                  completion: @escaping (LevelDefinition) -> Void) {
        guard !isGenerating else { return }
        generation += 1
        let id = generation
        let seed = seed ?? UInt64.random(in: 1...999_999_999)
        phase = .generating(attempt: 1, of: RandomLevel.defaultMaxAttempts)
        task = Task {
            let work = Task.detached(priority: .userInitiated) {
                RandomLevel.generate(options, seed: seed) { attempt, max in
                    Task { @MainActor in self.report(attempt: attempt, of: max, generation: id) }
                }
            }
            // Cancelling `task` stops the core generation too (it checks Task.isCancelled).
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard id == self.generation else { return }   // cancelled meanwhile
            if let level = result.level {
                self.phase = .idle
                completion(level)
            } else {
                self.phase = .failed
            }
        }
    }

    /// Stops any running generation (its result is dropped) and resets the phase.
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        phase = .idle
    }

    private func report(attempt: Int, of max: Int, generation id: Int) {
        guard id == generation, isGenerating else { return }
        phase = .generating(attempt: attempt, of: max)
    }
}
