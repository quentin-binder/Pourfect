import BottleSortCore
import Foundation

/// Persistence for the daily results (one `DailyResult` per UTC date, as a `DailyHistory`) and
/// the dates whose puzzle showed a hint before it was solved. Swap the implementation to change storage.
protocol DailyStore {
    func loadHistory() -> DailyHistory
    func saveHistory(_ history: DailyHistory)
    func loadHintedDates() -> Set<DailyDate>
    func saveHintedDates(_ dates: Set<DailyDate>)
}

/// Saves the history as JSON in UserDefaults. Unreadable data loads as an empty history.
struct UserDefaultsDailyStore: DailyStore {
    var defaults: UserDefaults = .standard
    var key = "daily.history.v1"
    var hintKey = "daily.hinted.v1"

    func loadHistory() -> DailyHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(DailyHistory.self, from: data) else { return DailyHistory() }
        return history
    }

    func saveHistory(_ history: DailyHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    func loadHintedDates() -> Set<DailyDate> {
        Set((defaults.stringArray(forKey: hintKey) ?? []).compactMap(DailyDate.init(isoString:)))
    }

    func saveHintedDates(_ dates: Set<DailyDate>) {
        defaults.set(dates.sorted().map(\.isoString), forKey: hintKey)
    }
}

/// Keeps the history in memory only (nothing is saved). Used by the DEBUG date / seed launch
/// arguments, so pretend dates and fake results never reach the player's real history.
final class MemoryDailyStore: DailyStore {
    private var history: DailyHistory
    private var hintedDates: Set<DailyDate> = []

    init(_ history: DailyHistory = DailyHistory()) { self.history = history }

    func loadHistory() -> DailyHistory { history }
    func saveHistory(_ history: DailyHistory) { self.history = history }
    func loadHintedDates() -> Set<DailyDate> { hintedDates }
    func saveHintedDates(_ dates: Set<DailyDate>) { hintedDates = dates }
}
