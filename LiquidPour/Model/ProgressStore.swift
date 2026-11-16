import BottleSortCore
import Foundation
import Observation

/// Persistence for per-level best stars and gold seals. Swap the implementation to change storage.
protocol ProgressStore {
    func loadStars() -> [String: Int]
    func saveStars(_ stars: [String: Int])
    /// Recipe ids with a gold seal (R6). Saves from before R6 have none.
    func loadGoldSeals() -> Set<String>
    func saveGoldSeals(_ ids: Set<String>)
    /// Story scenes already played (`StoryScene.id`, R7). Saves from before R7 have none.
    func loadStorySeen() -> Set<String>
    func saveStorySeen(_ ids: Set<String>)
    /// Rewards whose "New reward!" toast was shown (`Reward.id`, R7).
    func loadAnnouncedRewards() -> Set<String>
    func saveAnnouncedRewards(_ ids: Set<String>)
}

struct UserDefaultsProgressStore: ProgressStore {
    var defaults: UserDefaults = .standard
    var key = "progress.bestStars.v1"
    /// Its own key: the stars dictionary keeps its v1 shape, so older builds still read it.
    var goldSealKey = "progress.goldSeals.v1"
    var storyKey = "progress.storySeen.v1"
    var rewardsKey = "progress.rewardsAnnounced.v1"

    func loadStars() -> [String: Int] {
        defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    func saveStars(_ stars: [String: Int]) {
        defaults.set(stars, forKey: key)
    }

    func loadGoldSeals() -> Set<String> {
        Set(defaults.stringArray(forKey: goldSealKey) ?? [])
    }

    func saveGoldSeals(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: goldSealKey)
    }

    func loadStorySeen() -> Set<String> {
        Set(defaults.stringArray(forKey: storyKey) ?? [])
    }

    func saveStorySeen(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: storyKey)
    }

    func loadAnnouncedRewards() -> Set<String> {
        Set(defaults.stringArray(forKey: rewardsKey) ?? [])
    }

    func saveAnnouncedRewards(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: rewardsKey)
    }
}

/// Observable progress: best stars per level id; a level unlocks when the previous one is cleared.
@Observable
final class ProgressModel {
    private let store: ProgressStore
    private(set) var bestStars: [String: Int]
    /// Recipes solved in their minimum without a hint (R6 "perfect brewer"). Separate from the
    /// stars: never read by any gate.
    private(set) var goldSeals: Set<String>
    /// Story scenes already played (R7).
    private(set) var storySeen: Set<String>
    /// Rewards already announced with a "New reward!" toast (R7).
    private(set) var announcedRewards: Set<String>

    init(store: ProgressStore) {
        #if DEBUG
        // Dev aid: `-LPResetStory 1` forgets which story scenes were played (at launch).
        if UserDefaults.standard.bool(forKey: "LPResetStory") { store.saveStorySeen([]) }
        #endif
        self.store = store
        self.bestStars = store.loadStars()
        self.goldSeals = store.loadGoldSeals()
        self.storySeen = store.loadStorySeen()
        self.announcedRewards = store.loadAnnouncedRewards()
    }

    func markStorySeen(_ scene: StoryScene) {
        guard storySeen.insert(scene.id).inserted else { return }
        store.saveStorySeen(storySeen)
    }

    func markAnnounced(_ ids: Set<String>) {
        let all = announcedRewards.union(ids)
        guard all != announcedRewards else { return }
        announcedRewards = all
        store.saveAnnouncedRewards(all)
    }

    func stars(for id: String) -> Int { ChapterGate.clampedStars(bestStars[id]) }

    func hasGoldSeal(_ id: String) -> Bool { goldSeals.contains(id) }

    /// Gold seals earned in a chapter or challenge book.
    func goldSeals(of pack: LevelPackInfo) -> GoldSealProgress {
        GoldSeal.progress(of: pack.levels.map(\.id), sealed: goldSeals)
    }

    func recordGoldSeal(for id: String) {
        guard goldSeals.insert(id).inserted else { return }
        store.saveGoldSeals(goldSeals)
    }

    /// Main-path mechanics the player has met: those of every chapter whose first (tutorial)
    /// recipe is cleared, plus plain sorting. Rush only uses these (DECISIONS 225).
    func learnedMechanics(_ chapters: [LevelPackInfo]) -> Set<Mechanic> {
        var result: Set<Mechanic> = [.basic]
        for chapter in chapters where Self.unlockAll || chapter.levels.first.map({ stars(for: $0.id) > 0 }) == true {
            result.formUnion(chapter.introduces)
        }
        return result
    }

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
        ChapterProgress(stars: pack.levels.reduce(0) { $0 + stars(for: $1.id) }, maxStars: pack.maxStars,
                        gateMaxStars: pack.gateMaxStars)
    }

    /// Open flags for `chapters` (in chapter order) under the 50 % star gate. Reads only the
    /// chapters' own recipe stars (challenge books, gold seals and Rush never count).
    func unlockedChapters(_ chapters: [LevelPackInfo]) -> [Bool] {
        if Self.unlockAll { return chapters.map { _ in true } }
        // Customer orders (R7) add stars but never raise a chapter's gate (DECISIONS 233).
        let bonus = Set(chapters.flatMap { $0.levels.filter(\.isCustomerOrder).map(\.id) })
        return ChapterGate.unlockedChapters(recipeIDs: chapters.map { $0.levels.map(\.id) }, bonus: bonus) { stars(for: $0) }
    }

    func record(stars: Int, for id: String) {
        guard stars > self.stars(for: id) else { return }
        bestStars[id] = stars
        store.saveStars(bestStars)
    }
}
