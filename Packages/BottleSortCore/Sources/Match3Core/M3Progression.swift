import BottleSortCore
import Foundation

/// Where the gathering episodes sit in the game (DECISIONS 262). Episodes are optional: they never
/// block a sorting chapter, and their stars never count towards the chapter gate (the app keeps them
/// in a separate store keyed by the `m3-…` ids, which no chapter gate reads).
public enum M3Progression {
    public static let episodes = 1...10

    /// Episode `n` (1…9) opens together with sorting chapter n + 1; episode 10 opens once the last
    /// own recipe of chapter 10 is solved (customer orders don't count).
    /// - `chapterUnlocked`: open flags for chapters 1…10 (`ChapterGate.unlockedChapters`).
    public static func isEpisodeUnlocked(_ n: Int, chapterUnlocked: [Bool], finalChapterComplete: Bool) -> Bool {
        guard episodes.contains(n) else { return false }
        if n == episodes.upperBound { return finalChapterComplete }
        return chapterUnlocked.indices.contains(n) && chapterUnlocked[n]
    }

    /// Levels inside an episode open in order: level 0 is open, level i once level i − 1 is won.
    /// - `won`: per level of the episode, whether it has been won at least once.
    public static func isLevelUnlocked(_ index: Int, won: [Bool]) -> Bool {
        index == 0 || (index > 0 && index - 1 < won.count && won[index - 1])
    }

    /// The story scene id that plays the first time episode `n` is opened (the app's String catalog
    /// holds the lines: apprentice and alchemist gathering for the next chapter), nil once seen.
    public static func sceneOnOpening(episode n: Int, seen: Set<String>) -> String? {
        guard episodes.contains(n) else { return nil }
        let id = sceneID(episode: n)
        return seen.contains(id) ? nil : id
    }

    /// "gathering.3"
    public static func sceneID(episode n: Int) -> String { "gathering.\(n)" }
}

extension M3Daily {
    /// A daily match-3 win as a `DailyResult`, so the existing `DailyStreaks` rules give its own
    /// streak and stats (kept in a separate store from the Daily Brew's). "Perfect" means three stars:
    /// `minMoves` is the moves used and `usedHint` is true below three stars. The idle hint glow is
    /// free and never costs a perfect day.
    public static func result(date: DailyDate, movesUsed: Int, stars: Int, solvedAt: Date) -> DailyResult {
        DailyResult(date: date, moves: movesUsed, minMoves: movesUsed, usedHint: stars < 3, solvedAt: solvedAt)
    }
}
