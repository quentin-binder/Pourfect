import BottleSortCore
import Foundation
import Observation
import SecretRecipeCore

/// Persistence of the daily Secret Recipe (its own key, apart from the other dailies).
protocol RecipeDailyStore {
    func load() -> RecipeDailyHistory
    func save(_ history: RecipeDailyHistory)
}

struct UserDefaultsRecipeDailyStore: RecipeDailyStore {
    var defaults: UserDefaults = .standard
    var key = "recipe.daily.v1"

    func load() -> RecipeDailyHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(RecipeDailyHistory.self, from: data) else { return RecipeDailyHistory() }
        return history
    }

    func save(_ history: RecipeDailyHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Kept in memory only (DEBUG pretend date / fake results).
final class MemoryRecipeDailyStore: RecipeDailyStore {
    private var history: RecipeDailyHistory
    init(_ history: RecipeDailyHistory = RecipeDailyHistory()) { self.history = history }
    func load() -> RecipeDailyHistory { history }
    func save(_ history: RecipeDailyHistory) { self.history = history }
}

/// The daily Secret Recipe (generator `recipe-daily-v1`): today's UTC date, the saved games (each
/// brew is saved at once, so the day can't be restarted), stats and streak. Never counts toward
/// any gate. Injected at the root.
@MainActor
@Observable
final class RecipeDailyModel {
    @ObservationIgnored private let store: RecipeDailyStore
    @ObservationIgnored let clockOffset: TimeInterval
    @ObservationIgnored private var midnightTask: Task<Void, Never>?

    private(set) var today: DailyDate
    private(set) var history: RecipeDailyHistory

    init(store: RecipeDailyStore, clockOffset: TimeInterval = 0) {
        self.store = store
        self.clockOffset = clockOffset
        history = store.load()
        today = DailyDate(Date().addingTimeInterval(clockOffset))
        scheduleMidnightRefresh()
    }

    /// Saved in UserDefaults; with the DEBUG `-LPDailyDate` / `-LPDailySeedResults` arguments (shared
    /// with the other dailies) a pretend date and fake games kept in memory only.
    static func makeDefault() -> RecipeDailyModel {
        #if DEBUG
        let defaults = UserDefaults.standard
        let pretend = defaults.string(forKey: "LPDailyDate").flatMap(DailyDate.init(isoString:))
        let seedDays = defaults.integer(forKey: "LPDailySeedResults")
        if pretend != nil || seedDays > 0 || defaults.integer(forKey: "LPRecipeDemo") > 0 {
            let realToday = DailyDate(Date())
            let today = pretend ?? realToday
            let offset = TimeInterval(today.days(since: realToday)) * 86_400
            return RecipeDailyModel(store: MemoryRecipeDailyStore(debugSeed(days: seedDays, before: today)), clockOffset: offset)
        }
        #endif
        return RecipeDailyModel(store: UserDefaultsRecipeDailyStore())
    }

    func now() -> Date { Date().addingTimeInterval(clockOffset) }

    func refresh() {
        let current = DailyDate(now())
        if current != today { today = current }
        scheduleMidnightRefresh()
    }

    func secondsUntilNextRecipe(at date: Date = Date()) -> TimeInterval {
        let shifted = date.addingTimeInterval(clockOffset)
        return max(0, DailyDate(shifted).next.startDate.timeIntervalSince(shifted))
    }

    private func scheduleMidnightRefresh() {
        midnightTask?.cancel()
        let wait = secondsUntilNextRecipe() + 0.5
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    var stats: RecipeStats { history.stats(today: today) }

    /// The game of `date` as saved (a fresh one if not started).
    func game(for date: DailyDate) -> RecipeGame {
        history.record(for: date)?.game ?? RecipeDaily.game(for: date)
    }

    var todayGame: RecipeGame { game(for: today) }
    var todayRecord: RecipeDayRecord? { history.record(for: today) }

    /// Saves the guesses of `date`'s game (after every brew).
    @discardableResult
    func save(date: DailyDate, guesses: [RecipeCode]) -> RecipeDailyHistory.SaveOutcome {
        let outcome = history.save(date: date, guesses: guesses, now: now())
        switch outcome {
        case .saved, .finished: store.save(history)
        case .alreadyFinished, .mismatch: break
        }
        return outcome
    }

    #if DEBUG
    /// Fake games for the `days` days before `today`: mostly wins in 3–6 guesses, a loss now and
    /// then, a few missed days, and an unbroken run of four ending yesterday.
    static func debugSeed(days: Int, before today: DailyDate) -> RecipeDailyHistory {
        guard days > 0 else { return RecipeDailyHistory() }
        var history = RecipeDailyHistory()
        for back in stride(from: days, through: 1, by: -1) {
            if back > 4, back % 5 == 0 { continue }
            let date = today.adding(days: -back)
            let secret = RecipeDaily.secret(for: date)
            let wrong = RecipeCode.all.lazy.filter { $0 != secret }
            let guesses: [RecipeCode]
            if back > 4, back % 7 == 3 {
                guesses = Array(wrong.prefix(RecipeGame.maxGuesses))
            } else {
                guesses = Array(wrong.prefix(2 + back % 4)) + [secret]
            }
            history.save(date: date, guesses: guesses, now: date.startDate.addingTimeInterval(10 * 3600 + Double(back) * 300))
        }
        return history
    }
    #endif
}

/// Labels and the share text of Secret Recipe.
enum RecipeText {
    /// "2 in place, 1 elsewhere" (VoiceOver and the guess list).
    static func feedback(_ feedback: RecipeFeedback) -> String {
        if feedback.isSolved {
            return String(localized: "All five in place", comment: "Secret Recipe feedback: the guess is the recipe")
        }
        return String(localized: "\(feedback.exact) in place, \(feedback.misplaced) elsewhere",
                      comment: "Secret Recipe feedback for VoiceOver: gold drops (right ingredient, right slot) and silver drops (right ingredient, other slot)")
    }

    static func ingredients(_ code: RecipeCode) -> String {
        code.slots.map(\.displayName).formatted(.list(type: .and, width: .narrow))
    }

    /// "Pourfect Secret Recipe · 17 Nov · 4/8" followed by one row of drops per guess.
    static func share(date: DailyDate, game: RecipeGame) -> String {
        let header = String(localized: "Pourfect Secret Recipe · \(M3DailyText.shortDate(date)) · \(RecipeShare.score(game))",
                            comment: "Shared Secret Recipe result header: date and guesses used (4/8, or X/8 when not found); the drop grid follows")
        return RecipeShare.text(header: header, game: game)
    }

    static func countdown(seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return String(localized: "New recipe in \(m) m", comment: "Countdown to the next daily Secret Recipe, minutes") }
        return String(localized: "New recipe in \(h) h \(m) m", comment: "Countdown to the next daily Secret Recipe, hours and minutes")
    }
}
