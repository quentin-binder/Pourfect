import BottleSortCore
import Foundation
import Match3Core
import Observation

/// What a daily gathering win looked like, for the share text and the screen (the streak itself
/// lives in the `DailyResult`).
struct M3DailyDetail: Codable, Hashable {
    var stars: Int
    var movesLeft: Int
    var score: Int
}

/// Persistence of the daily gathering: its own `DailyHistory` and the per-day details, under keys
/// apart from the Daily Brew's. Swap the implementation to change storage.
protocol M3DailyStore {
    func loadHistory() -> DailyHistory
    func saveHistory(_ history: DailyHistory)
    func loadDetails() -> [DailyDate: M3DailyDetail]
    func saveDetails(_ details: [DailyDate: M3DailyDetail])
}

struct UserDefaultsM3DailyStore: M3DailyStore {
    var defaults: UserDefaults = .standard
    var key = "m3daily.history.v1"
    var detailsKey = "m3daily.details.v1"

    func loadHistory() -> DailyHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(DailyHistory.self, from: data) else { return DailyHistory() }
        return history
    }

    func saveHistory(_ history: DailyHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    func loadDetails() -> [DailyDate: M3DailyDetail] {
        guard let data = defaults.data(forKey: detailsKey),
              let raw = try? JSONDecoder().decode([String: M3DailyDetail].self, from: data) else { return [:] }
        var result: [DailyDate: M3DailyDetail] = [:]
        for (iso, detail) in raw { if let date = DailyDate(isoString: iso) { result[date] = detail } }
        return result
    }

    func saveDetails(_ details: [DailyDate: M3DailyDetail]) {
        let raw = Dictionary(uniqueKeysWithValues: details.map { ($0.key.isoString, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults.set(data, forKey: detailsKey)
    }
}

/// Kept in memory only (the DEBUG pretend-date / fake-results launch arguments).
final class MemoryM3DailyStore: M3DailyStore {
    private var history: DailyHistory
    private var details: [DailyDate: M3DailyDetail]

    init(_ history: DailyHistory = DailyHistory(), details: [DailyDate: M3DailyDetail] = [:]) {
        self.history = history
        self.details = details
    }

    func loadHistory() -> DailyHistory { history }
    func saveHistory(_ history: DailyHistory) { self.history = history }
    func loadDetails() -> [DailyDate: M3DailyDetail] { details }
    func saveDetails(_ details: [DailyDate: M3DailyDetail]) { self.details = details }
}

/// The daily gathering (match-3, generator `m3daily-v1`): today's UTC date and level (built off
/// the main thread, cached), its own results, streak and stats. Separate from the Daily Brew, which
/// it never touches; it only borrows the same UTC-day rules (`DailyStreaks`). Injected at the root.
@MainActor
@Observable
final class M3DailyModel {
    enum LevelState: Equatable {
        case idle, generating
        case ready(M3Level)
    }

    enum RecordOutcome: Equatable {
        case recorded(DailyResult)
        case alreadySolved(DailyResult)
        case dayEnded
        case clockBehind
    }

    @ObservationIgnored private let store: M3DailyStore
    @ObservationIgnored let clockOffset: TimeInterval

    private(set) var today: DailyDate
    private(set) var history: DailyHistory
    private(set) var details: [DailyDate: M3DailyDetail]
    private(set) var levelState: LevelState = .idle

    @ObservationIgnored private var cache: [DailyDate: M3Level] = [:]
    @ObservationIgnored private var generatingDate: DailyDate?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var midnightTask: Task<Void, Never>?

    init(store: M3DailyStore, clockOffset: TimeInterval = 0) {
        self.store = store
        self.clockOffset = clockOffset
        history = store.loadHistory()
        details = store.loadDetails()
        today = DailyDate(Date().addingTimeInterval(clockOffset))
        scheduleMidnightRefresh()
        prepareLevel()
    }

    /// Saved in UserDefaults; with the DEBUG `-LPDailyDate` / `-LPDailySeedResults` arguments
    /// (shared with the Daily Brew) a pretend date and fake results kept in memory only.
    static func makeDefault() -> M3DailyModel {
        #if DEBUG
        let defaults = UserDefaults.standard
        let pretend = defaults.string(forKey: "LPDailyDate").flatMap(DailyDate.init(isoString:))
        let seedDays = defaults.integer(forKey: "LPDailySeedResults")
        if pretend != nil || seedDays > 0 {
            let realToday = DailyDate(Date())
            let today = pretend ?? realToday
            let offset = TimeInterval(today.days(since: realToday)) * 86_400
            let (history, details) = debugSeed(days: seedDays, before: today)
            return M3DailyModel(store: MemoryM3DailyStore(history, details: details), clockOffset: offset)
        }
        #endif
        return M3DailyModel(store: UserDefaultsM3DailyStore())
    }

    func now() -> Date { Date().addingTimeInterval(clockOffset) }

    func refresh() {
        let current = DailyDate(now())
        if current != today { today = current }
        scheduleMidnightRefresh()
        prepareLevel()
    }

    private func scheduleMidnightRefresh() {
        midnightTask?.cancel()
        let shifted = now()
        let wait = max(0, DailyDate(shifted).next.startDate.timeIntervalSince(shifted)) + 0.5
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: Today

    var spec: M3DailySpec { M3Daily.spec(for: today) }
    var stats: DailyStats { history.stats(today: today) }
    var todayResult: DailyResult? { history.result(for: today) }
    var todayDetail: M3DailyDetail? { details[today] }

    var level: M3Level? {
        if case .ready(let level) = levelState { return level }
        return nil
    }

    func prepareLevel() {
        let date = today
        if let cached = cache[date] {
            levelState = .ready(cached)
            return
        }
        if generatingDate == date, generationTask != nil { return }
        generationTask?.cancel()
        generatingDate = date
        levelState = .generating
        generationTask = Task { [weak self] in
            let level = await Task.detached(priority: .userInitiated) { M3Daily.level(for: date) }.value
            guard let self, !Task.isCancelled else { return }
            self.cache = [date: level]
            self.generationTask = nil
            self.generatingDate = nil
            if self.today == date { self.levelState = .ready(level) }
        }
    }

    // MARK: Results

    /// Records a won daily gathering of `date`: only the first win finished on that UTC day counts
    /// (replays never change it). Three stars is a "perfect" day.
    func record(date: DailyDate, level: M3Level, stars: Int, score: Int, movesLeft: Int) -> RecordOutcome {
        refresh()
        let result = M3Daily.result(date: date, movesUsed: max(0, level.moves - movesLeft), stars: stars, solvedAt: now())
        guard result.counts else { return .dayEnded }
        if let existing = history.result(for: date) { return .alreadySolved(existing) }
        guard history.record(result) else { return .clockBehind }
        details[date] = M3DailyDetail(stars: stars, movesLeft: movesLeft, score: score)
        store.saveHistory(history)
        store.saveDetails(details)
        return .recorded(result)
    }

    #if DEBUG
    /// Fake wins for the `days` days before `today`, with a few gaps and an unbroken run of four
    /// ending yesterday.
    static func debugSeed(days: Int, before today: DailyDate) -> (DailyHistory, [DailyDate: M3DailyDetail]) {
        guard days > 0 else { return (DailyHistory(), [:]) }
        var details: [DailyDate: M3DailyDetail] = [:]
        let results: [DailyResult] = (1...days).compactMap { back in
            if back > 4, back % 5 == 0 || back % 9 == 7 { return nil }
            let date = today.adding(days: -back)
            let stars = back % 3 == 1 ? 2 : (back % 4 == 2 ? 1 : 3)
            let movesLeft = 2 + back % 9
            details[date] = M3DailyDetail(stars: stars, movesLeft: movesLeft, score: 9000 + back * 731 % 6000)
            return M3Daily.result(date: date, movesUsed: 20, stars: stars,
                                  solvedAt: date.startDate.addingTimeInterval(10 * 3600 + Double(back) * 300))
        }
        return (DailyHistory(results: results), details)
    }
    #endif
}

enum M3DailyText {
    /// "Pourfect Gathering — 17 Nov ★★☆ 12 moves left" (no board, no spoilers).
    static func share(date: DailyDate, detail: M3DailyDetail) -> String {
        let stars = String(repeating: "★", count: min(3, max(0, detail.stars)))
            + String(repeating: "☆", count: 3 - min(3, max(0, detail.stars)))
        return String(localized: "Pourfect Gathering — \(shortDate(date)) \(stars) \(detail.movesLeft) moves left",
                      comment: "Shared daily gathering result: date, stars as ★/☆, moves left at the win")
    }

    /// "17 Nov", for a UTC day.
    static func shortDate(_ date: DailyDate) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).day().month(.abbreviated)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        style.calendar = Calendar(identifier: .gregorian)
        return date.startDate.formatted(style)
    }

    /// "Monday · Gentle"
    static func label(_ spec: M3DailySpec) -> String {
        // The Daily Brew's label pattern ("Sunday · Grand Brew").
        String(localized: "\(spec.weekday.localizedName) · \(tierName(spec.tier))")
    }

    static func tierName(_ tier: M3DailyTier) -> String {
        switch tier {
        // The same words as the Daily Brew's tiers.
        case .gentle: DailyTier.gentle.localizedName
        case .steady: DailyTier.steady.localizedName
        case .frost: String(localized: "Frosty", comment: "Daily gathering flavour (Wednesday): frost tiles")
        case .crates: String(localized: "Sealed Crates", comment: "Daily gathering flavour (Thursday)")
        case .flasks: String(localized: "Flask Drop", comment: "Daily gathering flavour (Friday): potion flasks to bring down")
        case .tricky: DailyTier.tricky.localizedName
        case .grand: String(localized: "Grand Gathering", comment: "Daily gathering flavour (Sunday)")
        }
    }

    static func symbol(_ tier: M3DailyTier) -> String {
        switch tier {
        case .gentle, .steady: "leaf.fill"
        case .frost: "snowflake"
        case .crates: "shippingbox.fill"
        case .flasks: "arrow.down.to.line"
        case .tricky: "sparkles"
        case .grand: "basket.fill"
        }
    }
}
