import DistilleryCore
import Foundation
import Observation

/// Best stars and fewest taps of the distillery levels (R10), keyed by the `d…` level ids.
/// Kept apart from the sorting chapters' stars (`distill.bestStars.v1` / `distill.bestTaps.v1`):
/// no chapter gate ever reads them (DECISIONS 277). Injected at the app root.
@Observable
final class DistillProgressModel {
    @ObservationIgnored private let defaults: UserDefaults
    private static let starsKey = "distill.bestStars.v1"
    private static let tapsKey = "distill.bestTaps.v1"

    private(set) var bestStars: [String: Int]
    private(set) var bestTaps: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bestStars = defaults.dictionary(forKey: Self.starsKey) as? [String: Int] ?? [:]
        bestTaps = defaults.dictionary(forKey: Self.tapsKey) as? [String: Int] ?? [:]
    }

    func stars(_ id: String) -> Int { min(3, max(0, bestStars[id] ?? 0)) }
    /// Fewest taps of a win (nil before the first win).
    func bestTaps(_ id: String) -> Int? { bestTaps[id] }
    func isWon(_ id: String) -> Bool { stars(id) > 0 }

    /// Records a win; returns true when the tap count is a new best for the level.
    @discardableResult
    func recordWin(_ id: String, stars: Int, taps: Int) -> Bool {
        let newStars = max(self.stars(id), min(3, max(1, stars)))
        if newStars != bestStars[id] {
            bestStars[id] = newStars
            defaults.set(bestStars, forKey: Self.starsKey)
        }
        let previous = bestTaps[id]
        guard previous.map({ taps < $0 }) ?? true else { return false }
        bestTaps[id] = taps
        defaults.set(bestTaps, forKey: Self.tapsKey)
        return previous != nil
    }

    /// Level `index` of a pack opens once the one before it is won (`-LPUnlockAll`: all).
    func isLevelUnlocked(_ index: Int, in file: DistillPackFile) -> Bool {
        if ProgressModel.unlockAll { return true }
        return DistillProgression.isLevelUnlocked(index, won: file.levels.map { isWon($0.id) })
    }
}
