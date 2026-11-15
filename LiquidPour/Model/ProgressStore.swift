import BottleSortCore
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

    func stars(for id: String) -> Int { ChapterGate.clampedStars(bestStars[id]) }

    /// Dev aid: launch with `-LPUnlockAll 1` to open every chapter and recipe (saved stars are untouched).
    static var unlockAll: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "LPUnlockAll")
        #else
        return false
        #endif
    }

    /// Level `index` (in pack order `ids`) is playable once the previous level is cleared.
    func isUnlocked(index: Int, ids: [String]) -> Bool {
        if Self.unlockAll { return true }
        return ChapterGate.isRecipeUnlocked(at: index, in: ids) { stars(for: $0) > 0 }
    }

    /// Stars earned in a pack out of its maximum. Ids that no longer ship (old Locks & Keys and
    /// Hidden Depths recipes) are simply never asked for.
    func progress(of pack: LevelPackInfo) -> ChapterProgress {
        ChapterProgress(stars: pack.levels.reduce(0) { $0 + stars(for: $1.id) }, maxStars: pack.maxStars)
    }

    /// Open flags for `chapters` (in chapter order) under the 50 % star gate.
    func unlockedChapters(_ chapters: [LevelPackInfo]) -> [Bool] {
        if Self.unlockAll { return chapters.map { _ in true } }
        return ChapterGate.unlockedChapters(chapters.map(progress(of:)))
    }

    func record(stars: Int, for id: String) {
        guard stars > self.stars(for: id) else { return }
        bestStars[id] = stars
        store.saveStars(bestStars)
    }
}
