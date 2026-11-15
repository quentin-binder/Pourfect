import BottleSortCore
import Foundation

/// Persistence for the daily results (one `DailyResult` per UTC date, as a `DailyHistory`).
/// Swap the implementation to change storage.
protocol DailyStore {
    func loadHistory() -> DailyHistory
    func saveHistory(_ history: DailyHistory)
}

/// Saves the history as JSON in UserDefaults. Unreadable data loads as an empty history.
struct UserDefaultsDailyStore: DailyStore {
    var defaults: UserDefaults = .standard
    var key = "daily.history.v1"

    func loadHistory() -> DailyHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(DailyHistory.self, from: data) else { return DailyHistory() }
        return history
    }

    func saveHistory(_ history: DailyHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Keeps the history in memory only (nothing is saved). Used by the DEBUG date / seed launch
/// arguments, so pretend dates and fake results never reach the player's real history.
final class MemoryDailyStore: DailyStore {
    private var history: DailyHistory

    init(_ history: DailyHistory = DailyHistory()) { self.history = history }

    func loadHistory() -> DailyHistory { history }
    func saveHistory(_ history: DailyHistory) { self.history = history }
}
