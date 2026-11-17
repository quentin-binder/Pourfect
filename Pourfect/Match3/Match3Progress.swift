import BottleSortCore
import Foundation
import Match3Core
import Observation

/// One ingredient-gathering episode on the chapter map (R9).
struct MapEpisode: Identifiable {
    enum State: Equatable {
        case open
        /// Opens with sorting chapter `chapter` (episodes 1–9), or once chapter 10's last own
        /// recipe is solved (episode 10, `afterFinal`).
        case locked(chapter: Int, afterFinal: Bool)
    }

    let file: M3EpisodeFile
    let state: State
    let stars: Int
    let maxStars: Int
    /// Levels won at least once.
    let won: Int

    var number: Int { file.episode.number }
    var name: String { file.episode.name }
    var id: Int { number }
    var isOpen: Bool { state == .open }
    var isComplete: Bool { won >= file.levels.count && !file.levels.isEmpty }
}

/// Best stars and scores of the match-3 levels, and which episodes and levels are open.
/// Kept apart from the sorting chapters' stars (`m3.bestStars.v1` / `m3.bestScore.v1`, keyed by
/// the `m3-…` ids): no chapter gate, milestone or reward ever reads them (DECISIONS 262, 264).
/// Saves from before R9 simply have no entries. Injected at the app root.
@Observable
final class Match3ProgressModel {
    @ObservationIgnored private let defaults: UserDefaults
    private static let starsKey = "m3.bestStars.v1"
    private static let scoreKey = "m3.bestScore.v1"

    private(set) var bestStars: [String: Int]
    private(set) var bestScores: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bestStars = defaults.dictionary(forKey: Self.starsKey) as? [String: Int] ?? [:]
        bestScores = defaults.dictionary(forKey: Self.scoreKey) as? [String: Int] ?? [:]
    }

    func stars(_ id: String) -> Int { min(3, max(0, bestStars[id] ?? 0)) }
    func bestScore(_ id: String) -> Int { bestScores[id] ?? 0 }
    func isWon(_ id: String) -> Bool { stars(id) > 0 }

    /// Records a win; returns true when the score is a new best for the level.
    @discardableResult
    func recordWin(_ id: String, stars: Int, score: Int) -> Bool {
        let previous = bestScore(id)
        let newStars = max(self.stars(id), min(3, stars))
        if newStars != bestStars[id] { bestStars[id] = newStars; defaults.set(bestStars, forKey: Self.starsKey) }
        if score > previous { bestScores[id] = score; defaults.set(bestScores, forKey: Self.scoreKey) }
        return score > previous
    }

    // MARK: Unlocks

    /// Level `index` of an episode opens once the one before it is won (`-LPUnlockAll`: all).
    func isLevelUnlocked(_ index: Int, in file: M3EpisodeFile) -> Bool {
        if ProgressModel.unlockAll { return true }
        return M3Progression.isLevelUnlocked(index, won: file.levels.map { isWon($0.id) })
    }

    /// Whether episode `n` is open: with sorting chapter n + 1, episode 10 after chapter 10's last
    /// own recipe. Reads the sorting progress only; nothing here feeds back into it.
    func isEpisodeUnlocked(_ n: Int, catalog: LevelCatalog, progress: ProgressModel) -> Bool {
        if ProgressModel.unlockAll { return true }
        let open = progress.unlockedChapters(catalog.chapters)
        var chapterOpen = Array(repeating: false, count: Story.chapters.upperBound)
        for (i, pack) in catalog.chapters.enumerated() {
            if let c = pack.chapter, chapterOpen.indices.contains(c - 1) { chapterOpen[c - 1] = open[i] }
        }
        let finalDone = catalog.chapter(Story.finalChapter).flatMap { Story.finalRecipeID(of: $0.levels) }
            .map { progress.stars(for: $0) > 0 } ?? false
        return M3Progression.isEpisodeUnlocked(n, chapterUnlocked: chapterOpen, finalChapterComplete: finalDone)
    }

    func entries(catalog: LevelCatalog, progress: ProgressModel,
                 library: Match3Library.Library = Match3Library.shared) -> [MapEpisode] {
        library.episodes.map { file in
            let n = file.episode.number
            let unlocked = isEpisodeUnlocked(n, catalog: catalog, progress: progress)
            return MapEpisode(file: file,
                              state: unlocked ? .open : .locked(chapter: n + 1, afterFinal: n == M3Progression.episodes.upperBound),
                              stars: file.levels.reduce(0) { $0 + stars($1.id) },
                              maxStars: file.levels.count * 3,
                              won: file.levels.filter { isWon($0.id) }.count)
        }
    }
}
