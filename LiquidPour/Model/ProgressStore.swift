import Foundation
import Observation

/// Persistence for per-level best stars. Swap the implementation to change storage.
protocol ProgressStore {
    func loadStars() -> [String: Int]
    func saveStars(_ stars: [String: Int])
}

struct UserDefaultsProgressStore: ProgressStore {
    var defaults: UserDefaults = .standard
    var key = "progress.bestStars.v1"

    func loadStars() -> [String: Int] {
        defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    func saveStars(_ stars: [String: Int]) {
        defaults.set(stars, forKey: key)
    }
}

/// Observable progress: best stars per level id; a level unlocks when the previous one is cleared.
@Observable
final class ProgressModel {
    private let store: ProgressStore
    private(set) var bestStars: [String: Int]

    init(store: ProgressStore) {
        self.store = store
        self.bestStars = store.loadStars()
    }

    func stars(for id: String) -> Int { bestStars[id] ?? 0 }

    /// Level `index` (in pack order `ids`) is playable once the previous level is cleared.
    func isUnlocked(index: Int, ids: [String]) -> Bool {
        #if DEBUG
        // Dev aid: launch with `-LPUnlockAll 1` to make every level playable (saved stars are untouched).
        if UserDefaults.standard.bool(forKey: "LPUnlockAll") { return true }
        #endif
        return index == 0 || stars(for: ids[index - 1]) > 0
    }

    func record(stars: Int, for id: String) {
        guard stars > self.stars(for: id) else { return }
        bestStars[id] = stars
        store.saveStars(bestStars)
    }
}
