import Foundation
import Testing
@testable import BottleSortCore

@Suite("Daily streaks")
struct DailyStreakTests {
    /// A solve at noon UTC on `date` (counts).
    func solve(_ date: DailyDate, moves: Int = 12, minMoves: Int = 10, hint: Bool = false, hour: Double = 12) -> DailyResult {
        DailyResult(date: date, moves: moves, minMoves: minMoves, usedHint: hint,
                    solvedAt: date.startDate.addingTimeInterval(hour * 3600))
    }

    let today = day(2026, 11, 15)

    @Test func empty() {
        let s = DailyStreaks.stats([], today: today)
        #expect(s.currentStreak == 0 && s.bestStreak == 0 && s.totalSolved == 0 && s.perfectCount == 0)
        #expect(!s.isTodaySolved)
    }

    @Test func runEndingToday() {
        let results = (0..<5).map { solve(today.adding(days: -$0)) }
        let s = DailyStreaks.stats(results, today: today)
        #expect(s.currentStreak == 5)
        #expect(s.bestStreak == 5)
        #expect(s.isTodaySolved)
    }

    @Test func todayUnsolvedKeepsStreakAliveUntilTheDayEnds() {
        let results = (1...3).map { solve(today.adding(days: -$0)) }
        #expect(DailyStreaks.stats(results, today: today).currentStreak == 3)
        // The next UTC day, yesterday (= `today`) was missed: streak is gone, best stays.
        let later = DailyStreaks.stats(results, today: today.next)
        #expect(later.currentStreak == 0)
        #expect(later.bestStreak == 3)
    }

    @Test func gaps() {
        let dates = [-10, -9, -8, -7, -5, -4, -1, 0].map { today.adding(days: $0) }
        let s = DailyStreaks.stats(dates.map { solve($0) }, today: today)
        #expect(s.currentStreak == 2)
        #expect(s.bestStreak == 4)
        #expect(s.totalSolved == 8)
        #expect(s.solvedDates == Set(dates))
    }

    @Test func unsortedInputAndDoubleSolve() {
        var results = [-2, 0, -1, -3].map { solve(today.adding(days: $0)) }
        results.append(solve(today, moves: 10, hour: 18))  // replay later the same day
        let s = DailyStreaks.stats(results.reversed(), today: today)
        #expect(s.currentStreak == 4)
        #expect(s.totalSolved == 4)
        #expect(s.perfectCount == 0)  // the first solve of today counts, not the perfect replay
    }

    @Test func perfectRules() {
        #expect(solve(today, moves: 10, minMoves: 10).isPerfect)
        #expect(!solve(today, moves: 11, minMoves: 10).isPerfect)
        #expect(!solve(today, moves: 10, minMoves: 10, hint: true).isPerfect)
        let s = DailyStreaks.stats([solve(today, moves: 10, minMoves: 10), solve(today.previous, moves: 10, minMoves: 10, hint: true)],
                                   today: today)
        #expect(s.perfectCount == 1)
        #expect(s.perfectDates == [today])
    }

    @Test func onlyTheDayItselfCounts() {
        // Yesterday's puzzle finished 5 minutes after UTC midnight: doesn't count.
        let late = DailyResult(date: today.previous, moves: 10, minMoves: 10, usedHint: false,
                               solvedAt: today.startDate.addingTimeInterval(300))
        #expect(!late.counts)
        #expect(DailyStreaks.stats([late], today: today).totalSolved == 0)
        // A result dated in the future (clock set back afterwards) is ignored.
        let future = solve(today.next)
        #expect(DailyStreaks.stats([future], today: today).totalSolved == 0)
    }

    @Test func timeZoneIndependence() {
        // Solved at 09:30 local in Kiribati (UTC+14) on Nov 16 = Nov 15, 19:30 UTC.
        let kiribati = DailyResult(date: today, moves: 10, minMoves: 10, usedHint: false,
                                   solvedAt: instant(2026, 11, 16, 9, 30, offsetHours: 14))
        // Solved at 23:00 local at UTC−12 on Nov 14 = Nov 15, 11:00 UTC.
        let bakerIsland = DailyResult(date: today, moves: 10, minMoves: 10, usedHint: false,
                                      solvedAt: instant(2026, 11, 14, 23, 0, offsetHours: -12))
        #expect(kiribati.counts)
        #expect(bakerIsland.counts)
        #expect(DailyStreaks.stats([kiribati], today: DailyDate(kiribati.solvedAt)).currentStreak == 1)
        #expect(DailyStreaks.stats([bakerIsland], today: DailyDate(bakerIsland.solvedAt)).isTodaySolved)
    }

    @Test func historyRecordsOncePerDay() throws {
        var history = DailyHistory()
        let first = history.record(solve(today))
        let replay = history.record(solve(today, moves: 10, hour: 20))
        let older = history.record(solve(today.adding(days: -2)))
        let late = history.record(DailyResult(date: today.previous, moves: 10, minMoves: 10, usedHint: false,
                                              solvedAt: today.startDate))  // finished after its day: doesn't count
        #expect(first && !replay && older && !late)
        #expect(history.results.map(\.date) == [today.adding(days: -2), today])
        #expect(history.stats(today: today).currentStreak == 1)
        #expect(history.stats(today: today).bestStreak == 1)
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(DailyHistory.self, from: data) == history)
    }
}
