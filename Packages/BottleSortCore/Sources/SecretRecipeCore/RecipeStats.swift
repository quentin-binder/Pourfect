import BottleSortCore
import Foundation

/// The daily recipe of one UTC date as the player has it: guesses so far (saved after every brew,
/// so leaving the screen never resets the day) and when it ended.
public struct RecipeDayRecord: Sendable, Hashable, Codable {
    public let date: DailyDate
    public private(set) var guesses: [RecipeCode]
    /// When the game ended (won or lost); nil while in progress.
    public private(set) var finishedAt: Date?
    /// Whether the end counts for stats and streaks: finished on its own UTC date, and not before
    /// a game already saved (the device clock set back to fill a missed day). Set once, at the end.
    public private(set) var counts: Bool

    public init(date: DailyDate, guesses: [RecipeCode] = [], finishedAt: Date? = nil, counts: Bool = false) {
        self.date = date
        self.guesses = guesses
        self.finishedAt = finishedAt
        self.counts = counts
    }

    public var game: RecipeGame { RecipeGame(secret: RecipeDaily.secret(for: date), guesses: guesses) }
    public var isFinished: Bool { finishedAt != nil }
}

/// A player's daily recipe games, ready to persist (Codable). One record per date.
public struct RecipeDailyHistory: Sendable, Hashable, Codable {
    public private(set) var records: [RecipeDayRecord]

    public init(records: [RecipeDayRecord] = []) {
        var byDate: [DailyDate: RecipeDayRecord] = [:]
        for record in records where byDate[record.date] == nil { byDate[record.date] = record }
        self.records = byDate.values.sorted { $0.date < $1.date }
    }

    public enum SaveOutcome: Equatable, Sendable {
        /// Saved; the game goes on.
        case saved
        /// Saved and the game ended now (`counts`: it counts for stats and streaks).
        case finished(counts: Bool)
        /// The day's game was already over; nothing changed.
        case alreadyFinished
        /// The guesses don't continue the saved ones; nothing changed.
        case mismatch
    }

    public func record(for date: DailyDate) -> RecipeDayRecord? { records.first { $0.date == date } }

    /// Saves the guesses of `date`'s game at `now`. Guesses may only be added to the saved ones,
    /// never changed, and a finished day never changes again.
    @discardableResult
    public mutating func save(date: DailyDate, guesses: [RecipeCode], now: Date) -> SaveOutcome {
        let existing = record(for: date) ?? RecipeDayRecord(date: date)
        guard !existing.isFinished else { return .alreadyFinished }
        guard guesses.count >= existing.guesses.count, Array(guesses.prefix(existing.guesses.count)) == existing.guesses
        else { return .mismatch }
        let game = RecipeGame(secret: RecipeDaily.secret(for: date), guesses: guesses)
        var updated = RecipeDayRecord(date: date, guesses: game.guesses)
        var outcome = SaveOutcome.saved
        if game.isOver {
            let latest = records.compactMap(\.finishedAt).max()
            let counts = DailyDate(now) == date && latest.map { $0 <= now } ?? true
            updated = RecipeDayRecord(date: date, guesses: game.guesses, finishedAt: now, counts: counts)
            outcome = .finished(counts: counts)
        }
        records.removeAll { $0.date == date }
        records.append(updated)
        records.sort { $0.date < $1.date }
        return outcome
    }

    public func stats(today: DailyDate) -> RecipeStats { RecipeStats(records: records, today: today) }
}

/// Numbers for the daily screen: games played and won, streaks (consecutive won days; a loss or a
/// missed day breaks it), and the guess distribution of wins.
public struct RecipeStats: Sendable, Hashable {
    /// Wins in this many guesses or fewer are gold on the calendar.
    public static let sharpGuesses = 4

    public var played: Int
    public var won: Int
    public var currentStreak: Int
    public var bestStreak: Int
    /// `distribution[k]` = wins in k + 1 guesses (8 entries).
    public var distribution: [Int]
    public var lostDates: Set<DailyDate>
    /// Won days (`solvedDates`) and sharp wins (`perfectDates`, ≤ 4 guesses) for the calendar.
    public var calendar: DailyStats
    public var isTodayFinished: Bool

    public var lost: Int { played - won }
    /// Rounded down, 0 when nothing was played.
    public var winPercent: Int { played == 0 ? 0 : won * 100 / played }

    public init(records: [RecipeDayRecord], today: DailyDate) {
        let counted = records.filter { $0.counts && $0.date <= today }
        var distribution = Array(repeating: 0, count: RecipeGame.maxGuesses)
        var wins: [DailyResult] = []
        var lostDates: Set<DailyDate> = []
        for record in counted {
            let game = record.game
            if game.status == .won, let finishedAt = record.finishedAt {
                distribution[game.turns.count - 1] += 1
                wins.append(DailyResult(date: record.date, moves: game.turns.count, minMoves: RecipeStats.sharpGuesses,
                                        usedHint: false, solvedAt: finishedAt))
            } else if game.status == .lost {
                lostDates.insert(record.date)
            }
        }
        let calendar = DailyStreaks.stats(wins, today: today)
        played = wins.count + lostDates.count
        won = wins.count
        self.distribution = distribution
        self.lostDates = lostDates
        self.calendar = calendar
        bestStreak = calendar.bestStreak
        // A day lost today ends the streak at once (the shared rule keeps yesterday's run alive
        // while today is open).
        currentStreak = lostDates.contains(today) ? 0 : calendar.currentStreak
        isTodayFinished = calendar.isTodaySolved || lostDates.contains(today)
    }
}
