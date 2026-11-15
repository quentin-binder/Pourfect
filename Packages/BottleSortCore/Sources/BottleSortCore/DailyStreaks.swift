import Foundation

/// One solve of a daily puzzle.
public struct DailyResult: Sendable, Hashable, Codable {
    /// The UTC date of the puzzle that was solved.
    public var date: DailyDate
    public var moves: Int
    /// The puzzle's optimal length (solver minimum).
    public var minMoves: Int
    /// Whether the player asked for a hint during this solve.
    public var usedHint: Bool
    public var solvedAt: Date

    public init(date: DailyDate, moves: Int, minMoves: Int, usedHint: Bool, solvedAt: Date) {
        self.date = date
        self.moves = moves
        self.minMoves = minMoves
        self.usedHint = usedHint
        self.solvedAt = solvedAt
    }

    /// "Perfect solve": matched the solver minimum without a hint (a hint forfeits it).
    public var isPerfect: Bool { !usedHint && moves <= minMoves }

    /// Only the puzzle of the day counts: the solve must happen on its own UTC date.
    /// A solve finished after UTC midnight (or with a date from another day) doesn't count.
    public var counts: Bool { DailyDate(solvedAt) == date }
}

/// Summary for the daily screen.
public struct DailyStats: Sendable, Hashable {
    /// Consecutive solved days ending today, or ending yesterday while today is still open.
    public var currentStreak: Int
    public var bestStreak: Int
    public var totalSolved: Int
    public var perfectCount: Int
    public var isTodaySolved: Bool
    /// Every counted day (for the calendar).
    public var solvedDates: Set<DailyDate>
    public var perfectDates: Set<DailyDate>
}

/// Pure streak rules. Results are deduplicated per date (the first counted solve of a
/// day wins, so replays can't upgrade it to perfect), results that don't `count` are
/// ignored, and dates after `today` are ignored (device clock set back). Input order
/// doesn't matter, and nothing depends on the device time zone.
public enum DailyStreaks {
    /// The counted result for each date: the earliest `solvedAt` among results that count.
    public static func firstSolves(_ results: [DailyResult]) -> [DailyDate: DailyResult] {
        var byDate: [DailyDate: DailyResult] = [:]
        for result in results where result.counts {
            if let existing = byDate[result.date], existing.solvedAt <= result.solvedAt { continue }
            byDate[result.date] = result
        }
        return byDate
    }

    public static func stats(_ results: [DailyResult], today: DailyDate) -> DailyStats {
        let solves = firstSolves(results).filter { $0.key <= today }
        let solved = Set(solves.keys)
        let perfect = Set(solves.filter { $0.value.isPerfect }.keys)

        // Best: longest run of consecutive days (sorted, so iteration order doesn't matter).
        var best = 0
        var run = 0
        var last: DailyDate?
        for date in solved.sorted() {
            run = (last.map { date.days(since: $0) == 1 } ?? false) ? run + 1 : 1
            best = max(best, run)
            last = date
        }

        // Current: ends today, or yesterday if today isn't solved yet (still alive).
        var current = 0
        var cursor = solved.contains(today) ? today : today.previous
        while solved.contains(cursor) {
            current += 1
            cursor = cursor.previous
        }

        return DailyStats(currentStreak: current, bestStreak: best, totalSolved: solved.count,
                          perfectCount: perfect.count, isTodaySolved: solved.contains(today),
                          solvedDates: solved, perfectDates: perfect)
    }
}

/// A player's daily history, ready to persist (Codable). Keeps one result per date.
public struct DailyHistory: Sendable, Hashable, Codable {
    /// One counted result per date, sorted by date.
    public private(set) var results: [DailyResult]

    public init(results: [DailyResult] = []) {
        self.results = DailyStreaks.firstSolves(results).values.sorted { $0.date < $1.date }
    }

    /// Adds a solve. Returns false (and changes nothing) if it doesn't count or its date
    /// already has a result.
    @discardableResult
    public mutating func record(_ result: DailyResult) -> Bool {
        guard result.counts, self.result(for: result.date) == nil else { return false }
        results.append(result)
        results.sort { $0.date < $1.date }
        return true
    }

    public func result(for date: DailyDate) -> DailyResult? { results.first { $0.date == date } }

    public func stats(today: DailyDate) -> DailyStats { DailyStreaks.stats(results, today: today) }
}
