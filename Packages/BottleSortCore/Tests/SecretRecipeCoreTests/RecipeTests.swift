import BottleSortCore
import Foundation
import Testing
@testable import SecretRecipeCore

func R(_ digits: String) -> RecipeCode { RecipeCode(digits: digits)! }
func day(_ y: Int, _ m: Int, _ d: Int) -> DailyDate { DailyDate(year: y, month: m, day: d)! }

/// Keeps `#expect` free of mutating calls.
func brew(_ game: inout RecipeGame, _ guess: RecipeCode) -> RecipeTurn? { game.brew(guess) }
func save(_ history: inout RecipeDailyHistory, _ date: DailyDate, _ guesses: [RecipeCode], at now: Date)
    -> RecipeDailyHistory.SaveOutcome { history.save(date: date, guesses: guesses, now: now) }

/// Slot-by-slot reference: exact = same slot; misplaced = a guess ingredient found in another slot.
func naiveFeedback(secret: RecipeCode, guess: RecipeCode) -> RecipeFeedback {
    var exact = 0, misplaced = 0
    for (i, ingredient) in guess.slots.enumerated() {
        if secret.slots[i] == ingredient { exact += 1 } else if secret.slots.contains(ingredient) { misplaced += 1 }
    }
    return RecipeFeedback(exact: exact, misplaced: misplaced)
}

/// The all-pairs check (45 million) runs optimized (`scripts/test-fast.sh`), in debug only with LP_SLOW_TESTS=1.
let heavyTestsEnabled: Bool = {
    #if DEBUG
    return ProcessInfo.processInfo.environment["LP_SLOW_TESTS"] == "1"
    #else
    return true
    #endif
}()

@Suite("Secret Recipe model")
struct RecipeModelTests {
    @Test func recipesAreFiveDifferentOfEight() {
        #expect(RecipeCode(digits: "01234") != nil)
        #expect(RecipeCode(digits: "76543") != nil)
        #expect(RecipeCode(digits: "0123") == nil)       // too short
        #expect(RecipeCode(digits: "012345") == nil)     // too long
        #expect(RecipeCode(digits: "01231") == nil)      // repeat
        #expect(RecipeCode(digits: "01238") == nil)      // no ingredient 8
        #expect(RecipeCode(digits: "0123a") == nil)
        #expect(RecipeCode(trayPositions: [0, 1, 2, 3, -1]) == nil)
        #expect(RecipeIngredient.allCases.count == 8)
    }

    @Test func allPermutations() {
        let all = RecipeCode.all
        #expect(all.count == 6720)
        #expect(Set(all).count == 6720)
        #expect(all.first == R("01234"))
        #expect(all.last == R("76543"))
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.digits < $1.digits })
    }

    @Test func codableAsDigits() throws {
        let data = try JSONEncoder().encode([R("07152")])
        #expect(String(decoding: data, as: UTF8.self) == "[\"07152\"]")
        #expect(try JSONDecoder().decode([RecipeCode].self, from: data) == [R("07152")])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([RecipeCode].self, from: Data("[\"00112\"]".utf8)) }
    }

    @Test func trayOrdered() {
        #expect(R("01234").isTrayOrdered)
        #expect(R("13567").isTrayOrdered)
        #expect(R("75310").isTrayOrdered)
        #expect(!R("01243").isTrayOrdered)
        // 2 · C(8,5) recipes follow the tray up or down.
        #expect(RecipeCode.all.filter(\.isTrayOrdered).count == 112)
    }
}

@Suite("Secret Recipe feedback")
struct RecipeFeedbackTests {
    @Test func examples() {
        let secret = R("01234")
        #expect(secret.feedback(for: R("01234")) == RecipeFeedback(exact: 5, misplaced: 0))
        #expect(secret.feedback(for: R("43210")) == RecipeFeedback(exact: 1, misplaced: 4))
        #expect(secret.feedback(for: R("12340")) == RecipeFeedback(exact: 0, misplaced: 5))
        #expect(secret.feedback(for: R("56701")) == RecipeFeedback(exact: 0, misplaced: 2))
        #expect(secret.feedback(for: R("01567")) == RecipeFeedback(exact: 2, misplaced: 0))
        #expect(secret.feedback(for: R("01235")) == RecipeFeedback(exact: 4, misplaced: 0))
        #expect(secret.feedback(for: R("10235")) == RecipeFeedback(exact: 2, misplaced: 2))
        #expect(secret.feedback(for: R("01234")).isSolved)
        #expect(!secret.feedback(for: R("01235")).isSolved)
    }

    /// Every guess against a spread of secrets matches the slot-by-slot reference, and the counts
    /// per (exact, misplaced) follow the combinatorics.
    @Test func everyGuessAgainstManySecrets() {
        for secret in stride(from: 0, to: 6720, by: 97).map({ RecipeCode.all[$0] }) {
            var table: [RecipeFeedback: Int] = [:]
            for guess in RecipeCode.all {
                let fast = secret.feedback(for: guess)
                #expect(fast == naiveFeedback(secret: secret, guess: guess))
                table[fast, default: 0] += 1
            }
            // Shared ingredients k: C(5,k)·C(3,5−k)·5! guesses.
            for (k, ways) in [(2, 10), (3, 30), (4, 15), (5, 1)] {
                #expect(table.filter { $0.key.common == k }.values.reduce(0, +) == ways * 120)
            }
            #expect(table[RecipeFeedback(exact: 5, misplaced: 0)] == 1)
            #expect(table[RecipeFeedback(exact: 4, misplaced: 1)] == nil)   // impossible
            #expect(table[RecipeFeedback(exact: 3, misplaced: 2)] == 10)    // one swap of two
            #expect(table[RecipeFeedback(exact: 4, misplaced: 0)] == 15)    // one slot replaced
            #expect(table[RecipeFeedback(exact: 0, misplaced: 5)] == 44)    // derangements of 5
            #expect(table.keys.allSatisfy { $0.common >= 2 && $0.common <= 5 })
        }
    }

    @Test(.enabled(if: heavyTestsEnabled)) func allPairsMatchReferenceAndAreSymmetric() {
        var mismatches = 0
        for secret in RecipeCode.all {
            for guess in RecipeCode.all {
                let f = secret.feedback(for: guess)
                if f != naiveFeedback(secret: secret, guess: guess) || f != guess.feedback(for: secret) { mismatches += 1 }
            }
        }
        #expect(mismatches == 0)
    }
}

@Suite("Secret Recipe game")
struct RecipeGameTests {
    @Test func winOnTheThirdGuess() {
        var game = RecipeGame(secret: R("31704"))
        #expect(game.status == .playing && game.guessesLeft == 8 && game.revealed == nil)
        #expect(brew(&game, R("01234"))?.feedback == RecipeFeedback(exact: 2, misplaced: 2))
        #expect(brew(&game, R("31702"))?.feedback == RecipeFeedback(exact: 4, misplaced: 0))
        #expect(game.status == .playing && game.guessesLeft == 6)
        #expect(brew(&game, R("31704"))?.feedback.isSolved == true)
        #expect(game.status == .won && game.isOver && game.guessesLeft == 0)
        #expect(game.revealed == R("31704"))
        #expect(brew(&game, R("01234")) == nil)
        #expect(game.turns.count == 3)
    }

    @Test func eightWrongGuessesLoseAndReveal() {
        let wrong = Array(RecipeCode.all.prefix(8))
        var game = RecipeGame(secret: R("76543"), guesses: wrong)
        #expect(game.status == .lost)
        #expect(game.revealed == R("76543"))
        #expect(brew(&game, R("76543")) == nil)   // too late
        #expect(game.status == .lost)
    }

    @Test func winOnTheLastGuess() {
        let game = RecipeGame(secret: R("76543"), guesses: Array(RecipeCode.all.prefix(7)) + [R("76543")])
        #expect(game.status == .won && game.turns.count == 8)
    }

    @Test func replayIgnoresGuessesAfterTheEnd() {
        let game = RecipeGame(secret: R("01234"), guesses: [R("01234"), R("43210")])
        #expect(game.turns.count == 1 && game.status == .won)
    }

    @Test func candidatesShrinkAndKeepTheSecret() {
        #expect(RecipeCandidates.count(consistentWith: []) == 6720)
        var game = RecipeGame(secret: R("52716"))
        var last = 6720
        for guess in [R("01234"), R("56701"), R("52710"), R("52716")] {
            _ = brew(&game, guess)
            let left = RecipeCandidates.consistent(with: game.turns)
            #expect(left.contains(game.secret))
            #expect(left.count == game.candidatesLeft)
            #expect(left.count <= last)
            // Same as filtering every recipe with the reference feedback.
            let reference = RecipeCode.all.filter { c in game.turns.allSatisfy { naiveFeedback(secret: c, guess: $0.guess) == $0.feedback } }
            #expect(left == reference)
            last = left.count
        }
        #expect(game.candidatesLeft == 1)
    }

    @Test func candidateCountIsFast() {
        let game = RecipeGame(secret: R("40617"), guesses: [R("01234"), R("23456"), R("45670")])
        let start = Date()
        for _ in 0..<20 { _ = game.candidatesLeft }
        #expect(Date().timeIntervalSince(start) < 2.0)   // ~20× 6720 checks; well under in debug
    }
}

@Suite("Secret Recipe daily")
struct RecipeDailyTests {
    /// recipe-daily-v1 must never change: these are the secrets every player gets.
    @Test func goldenSecrets() {
        let golden: [(DailyDate, String)] = [
            (day(2026, 11, 17), "57463"),
            (day(2026, 11, 18), "50261"),
            (day(2026, 12, 25), "50462"),
            (day(2027, 1, 1), "14703"),
            (day(2028, 2, 29), "72106"),
        ]
        for (date, digits) in golden {
            #expect(RecipeDaily.secret(for: date).digits == digits, "\(date)")
        }
        #expect(RecipeDaily.algorithmVersion == "recipe-daily-v1")
    }

    @Test func deterministicVariedAndNeverTrayOrdered() {
        let start = day(2026, 1, 1)
        let secrets = (0..<730).map { RecipeDaily.secret(for: start.adding(days: $0)) }
        #expect(secrets == (0..<730).map { RecipeDaily.secret(for: start.adding(days: $0)) })
        #expect(secrets.allSatisfy { !$0.isTrayOrdered })
        #expect(Set(secrets).count > 680)
        // Every ingredient lands in every slot sometimes, roughly evenly (expected 730·5/8 ≈ 456 uses).
        for ingredient in RecipeIngredient.allCases {
            let uses = secrets.filter { $0.slots.contains(ingredient) }.count
            #expect(uses > 380 && uses < 540, "\(ingredient)")
            for slot in 0..<RecipeCode.length { #expect(secrets.contains { $0.slots[slot] == ingredient }) }
        }
    }

    @Test func practiceSeeds() {
        #expect(RecipePractice.secret(seed: 42) == RecipePractice.secret(seed: 42))
        let secrets = (1...500).map { RecipePractice.secret(seed: UInt64($0)) }
        #expect(Set(secrets).count > 470)
        #expect(secrets.allSatisfy { !$0.isTrayOrdered })
        #expect(RecipePractice.secret(seed: RecipeDaily.seed(for: day(2026, 11, 17))) != RecipeDaily.secret(for: day(2026, 11, 17)))
        #expect(RecipePractice.game(seed: 7).secret == RecipePractice.secret(seed: 7))
    }

    @Test func shareTextIsSpoilerFree() {
        let date = day(2026, 11, 17)
        let secret = RecipeDaily.secret(for: date)
        let other = RecipeCode.all.first { secret.feedback(for: $0) == RecipeFeedback(exact: 1, misplaced: 2) }!
        let game = RecipeGame(secret: secret, guesses: [other, secret])
        #expect(RecipeShare.row(RecipeFeedback(exact: 2, misplaced: 1)) == "🟡🟡⚪⚫⚫")
        #expect(RecipeShare.row(RecipeFeedback(exact: 0, misplaced: 5)) == "⚪⚪⚪⚪⚪")
        #expect(RecipeShare.dailyText(date: date, game: game) == "Pourfect Secret Recipe 2026-11-17 2/8\n🟡⚪⚪⚫⚫\n🟡🟡🟡🟡🟡")
        let lost = RecipeGame(secret: R("76543"), guesses: Array(RecipeCode.all.prefix(8)))
        #expect(RecipeShare.score(lost) == "X/8")
        #expect(RecipeShare.score(RecipeGame(secret: secret)) == "…/8")
        #expect(RecipeShare.text(header: "H", game: lost).split(separator: "\n").count == 9)
        // No ingredient digits or names in the text.
        let text = RecipeShare.grid(game.turns)
        #expect(!text.contains { $0.isNumber })
        #expect(!RecipeIngredient.allCases.contains { text.contains($0.name) })
    }
}

@Suite("Secret Recipe history and stats")
struct RecipeStatsTests {
    let today = day(2026, 11, 17)

    func noon(_ date: DailyDate, hour: Double = 12) -> Date { date.startDate.addingTimeInterval(hour * 3600) }

    /// Guesses that win `date`'s recipe on guess `n` (1...8); nil = lose with 8 wrong guesses.
    func guesses(for date: DailyDate, winningOn n: Int?) -> [RecipeCode] {
        let secret = RecipeDaily.secret(for: date)
        let wrong = RecipeCode.all.filter { $0 != secret }
        guard let n else { return Array(wrong.prefix(8)) }
        return Array(wrong.prefix(n - 1)) + [secret]
    }

    func history(_ days: [(Int, Int?)]) -> RecipeDailyHistory {
        var history = RecipeDailyHistory()
        for (back, n) in days.sorted(by: { $0.0 > $1.0 }) {
            let date = today.adding(days: -back)
            history.save(date: date, guesses: guesses(for: date, winningOn: n), now: noon(date))
        }
        return history
    }

    @Test func progressIsSavedAndOnlyExtended() {
        var history = RecipeDailyHistory()
        let g = guesses(for: today, winningOn: 4)
        #expect(save(&history, today, Array(g.prefix(1)), at: noon(today)) == .saved)
        #expect(history.record(for: today)?.guesses.count == 1)
        #expect(history.record(for: today)?.isFinished == false)
        #expect(save(&history, today, [g[1]], at: noon(today)) == .mismatch)        // rewriting a guess
        #expect(save(&history, today, [], at: noon(today)) == .mismatch)            // dropping guesses
        #expect(save(&history, today, Array(g.prefix(3)), at: noon(today)) == .saved)
        #expect(save(&history, today, g, at: noon(today, hour: 13)) == .finished(counts: true))
        #expect(history.record(for: today)?.finishedAt == noon(today, hour: 13))
        #expect(save(&history, today, g, at: noon(today)) == .alreadyFinished)
        #expect(history.stats(today: today).distribution == [0, 0, 0, 1, 0, 0, 0, 0])
    }

    @Test func finishingAfterMidnightDoesNotCount() {
        var history = RecipeDailyHistory()
        let g = guesses(for: today, winningOn: 2)
        #expect(save(&history, today, g, at: today.next.startDate.addingTimeInterval(60)) == .finished(counts: false))
        let stats = history.stats(today: today.next)
        #expect(stats.played == 0 && stats.currentStreak == 0)
    }

    @Test func clockSetBackDoesNotCount() {
        var history = RecipeDailyHistory()
        let yesterday = today.previous
        history.save(date: today, guesses: guesses(for: today, winningOn: 3), now: noon(today))
        // The clock goes back to yesterday to fill the gap: the game is kept but doesn't count.
        #expect(save(&history, yesterday, guesses(for: yesterday, winningOn: 3), at: noon(yesterday)) == .finished(counts: false))
        #expect(history.stats(today: today).currentStreak == 1)
    }

    @Test func statsDistributionAndStreaks() {
        // 6 days ago … today: won in 2, 3, lost, won in 4, 5, 1, 8.
        let h = history([(6, 2), (5, 3), (4, nil), (3, 4), (2, 5), (1, 1), (0, 8)])
        let s = h.stats(today: today)
        #expect(s.played == 7 && s.won == 6 && s.lost == 1)
        #expect(s.winPercent == 85)
        #expect(s.distribution == [1, 1, 1, 1, 1, 0, 0, 1])
        #expect(s.currentStreak == 4)
        #expect(s.bestStreak == 4)
        #expect(s.lostDates == [today.adding(days: -4)])
        #expect(s.calendar.solvedDates.count == 6)
        #expect(s.calendar.perfectDates.count == 4)    // ≤ 4 guesses
        #expect(s.isTodayFinished)
    }

    @Test func todayOpenKeepsTheStreakALossEndsIt() {
        var h = history([(3, 2), (2, 3), (1, 4)])
        #expect(h.stats(today: today).currentStreak == 3)
        #expect(!h.stats(today: today).isTodayFinished)
        h.save(date: today, guesses: guesses(for: today, winningOn: nil), now: noon(today))
        let s = h.stats(today: today)
        #expect(s.currentStreak == 0 && s.bestStreak == 3 && s.isTodayFinished)
        // A missed day breaks the run too.
        #expect(history([(3, 2), (1, 4)]).stats(today: today).currentStreak == 1)
    }

    @Test func historyIsCodable() throws {
        let h = history([(2, 2), (1, nil)])
        var progress = h
        progress.save(date: today, guesses: Array(guesses(for: today, winningOn: 5).prefix(2)), now: noon(today))
        let data = try JSONEncoder().encode(progress)
        let back = try JSONDecoder().decode(RecipeDailyHistory.self, from: data)
        #expect(back == progress)
        #expect(back.stats(today: today) == progress.stats(today: today))
        #expect(back.record(for: today)?.game.status == .playing)
    }
}
