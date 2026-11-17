import BottleSortCore
import DistilleryCore
import Foundation
import Observation

/// What a Daily Distillery win looked like, for the share text and the screen (the streak itself
/// lives in the `DailyResult`).
struct DistillDailyDetail: Codable, Hashable {
    var stars: Int
    var taps: Int
    var minTaps: Int
    var usedHint: Bool
}

/// Persistence of the Daily Distillery: its own `DailyHistory` and per-day details, under keys apart
/// from the Daily Brew's and the Daily Gathering's (`distill.daily.history.v1`, `distill.daily.details.v1`).
protocol DistillDailyStore {
    func loadHistory() -> DailyHistory
    func saveHistory(_ history: DailyHistory)
    func loadDetails() -> [DailyDate: DistillDailyDetail]
    func saveDetails(_ details: [DailyDate: DistillDailyDetail])
}

struct UserDefaultsDistillDailyStore: DistillDailyStore {
    var defaults: UserDefaults = .standard
    var key = "distill.daily.history.v1"
    var detailsKey = "distill.daily.details.v1"

    func loadHistory() -> DailyHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(DailyHistory.self, from: data) else { return DailyHistory() }
        return history
    }

    func saveHistory(_ history: DailyHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    func loadDetails() -> [DailyDate: DistillDailyDetail] {
        guard let data = defaults.data(forKey: detailsKey),
              let raw = try? JSONDecoder().decode([String: DistillDailyDetail].self, from: data) else { return [:] }
        var result: [DailyDate: DistillDailyDetail] = [:]
        for (iso, detail) in raw { if let date = DailyDate(isoString: iso) { result[date] = detail } }
        return result
    }

    func saveDetails(_ details: [DailyDate: DistillDailyDetail]) {
        let raw = Dictionary(uniqueKeysWithValues: details.map { ($0.key.isoString, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults.set(data, forKey: detailsKey)
    }
}

/// Kept in memory only (the DEBUG pretend-date / fake-results launch arguments).
final class MemoryDistillDailyStore: DistillDailyStore {
    private var history: DailyHistory
    private var details: [DailyDate: DistillDailyDetail]

    init(_ history: DailyHistory = DailyHistory(), details: [DailyDate: DistillDailyDetail] = [:]) {
        self.history = history
        self.details = details
    }

    func loadHistory() -> DailyHistory { history }
    func saveHistory(_ history: DailyHistory) { self.history = history }
    func loadDetails() -> [DailyDate: DistillDailyDetail] { details }
    func saveDetails(_ details: [DailyDate: DistillDailyDetail]) { self.details = details }
}

/// The Daily Distillery (generator `distill-daily-v1`, R10): today's UTC date and level (built off the
/// main thread, cached), its own results, streak and stats. Separate from the Daily Brew and the Daily
/// Gathering, which it never touches; it only borrows the same UTC-day rules (`DailyStreaks`).
@MainActor
@Observable
final class DistillDailyModel {
    enum LevelState: Equatable {
        case idle, generating
        case ready(DistillLevel)
    }

    enum RecordOutcome: Equatable {
        case recorded(DailyResult)
        case alreadySolved(DailyResult)
        case dayEnded
        case clockBehind
    }

    @ObservationIgnored private let store: DistillDailyStore
    @ObservationIgnored let clockOffset: TimeInterval

    private(set) var today: DailyDate
    private(set) var history: DailyHistory
    private(set) var details: [DailyDate: DistillDailyDetail]
    private(set) var levelState: LevelState = .idle

    @ObservationIgnored private var cache: [DailyDate: DistillLevel] = [:]
    @ObservationIgnored private var generatingDate: DailyDate?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var midnightTask: Task<Void, Never>?

    init(store: DistillDailyStore, clockOffset: TimeInterval = 0) {
        self.store = store
        self.clockOffset = clockOffset
        history = store.loadHistory()
        details = store.loadDetails()
        today = DailyDate(Date().addingTimeInterval(clockOffset))
        scheduleMidnightRefresh()
        prepareLevel()
    }

    /// Saved in UserDefaults; with the DEBUG `-LPDailyDate` / `-LPDailySeedResults` arguments (shared
    /// with the other dailies) a pretend date and fake results kept in memory only.
    static func makeDefault() -> DistillDailyModel {
        #if DEBUG
        let defaults = UserDefaults.standard
        let pretend = defaults.string(forKey: "LPDailyDate").flatMap(DailyDate.init(isoString:))
        let seedDays = defaults.integer(forKey: "LPDailySeedResults")
        if pretend != nil || seedDays > 0 {
            let realToday = DailyDate(Date())
            let today = pretend ?? realToday
            let offset = TimeInterval(today.days(since: realToday)) * 86_400
            let (history, details) = debugSeed(days: seedDays, before: today)
            return DistillDailyModel(store: MemoryDistillDailyStore(history, details: details), clockOffset: offset)
        }
        #endif
        return DistillDailyModel(store: UserDefaultsDistillDailyStore())
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

    var spec: DistillDailySpec { DistillDaily.spec(for: today) }
    var stats: DailyStats { history.stats(today: today) }
    var todayResult: DailyResult? { history.result(for: today) }
    var todayDetail: DistillDailyDetail? { details[today] }

    var level: DistillLevel? {
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
            let level = await Task.detached(priority: .userInitiated) { DistillDaily.level(for: date) }.value
            guard let self, !Task.isCancelled else { return }
            self.cache = [date: level]
            self.generationTask = nil
            self.generatingDate = nil
            if self.today == date { self.levelState = .ready(level) }
        }
    }

    // MARK: Results

    /// Records a won Daily Distillery of `date`: only the first win finished on that UTC day counts
    /// (replays never change it). "Perfect" is the fewest taps without a hint (three stars).
    @discardableResult
    func record(date: DailyDate, level: DistillLevel, stars: Int, taps: Int, usedHint: Bool) -> RecordOutcome {
        refresh()
        let result = DistillDaily.result(date: date, taps: taps, minTaps: level.minTaps, usedHint: usedHint, solvedAt: now())
        guard result.counts else { return .dayEnded }
        if let existing = history.result(for: date) { return .alreadySolved(existing) }
        guard history.record(result) else { return .clockBehind }
        details[date] = DistillDailyDetail(stars: stars, taps: taps, minTaps: level.minTaps, usedHint: usedHint)
        store.saveHistory(history)
        store.saveDetails(details)
        return .recorded(result)
    }

    #if DEBUG
    /// Fake wins for the `days` days before `today`, with a few gaps and an unbroken run ending yesterday.
    static func debugSeed(days: Int, before today: DailyDate) -> (DailyHistory, [DailyDate: DistillDailyDetail]) {
        guard days > 0 else { return (DailyHistory(), [:]) }
        var details: [DailyDate: DistillDailyDetail] = [:]
        let results: [DailyResult] = (1...days).compactMap { back in
            if back > 3, back % 4 == 0 || back % 11 == 6 { return nil }
            let date = today.adding(days: -back)
            let minTaps = 8 + back % 9
            let extra = back % 3 == 0 ? 0 : (back % 3 == 1 ? 2 : 6)
            let stars = DistillStars.stars(taps: minTaps + extra, minTaps: minTaps)
            details[date] = DistillDailyDetail(stars: stars, taps: minTaps + extra, minTaps: minTaps, usedHint: false)
            return DistillDaily.result(date: date, taps: minTaps + extra, minTaps: minTaps, usedHint: false,
                                       solvedAt: date.startDate.addingTimeInterval(9 * 3600 + Double(back) * 400))
        }
        return (DailyHistory(results: results), details)
    }
    #endif
}

enum DistillDailyText {
    /// "Pourfect Distillery — 17 Nov ★★★ 12 taps (fewest 12)" (no board, no spoilers).
    static func share(date: DailyDate, detail: DistillDailyDetail) -> String {
        let n = min(3, max(0, detail.stars))
        let stars = String(repeating: "★", count: n) + String(repeating: "☆", count: 3 - n)
        return String(localized: "Pourfect Distillery — \(M3DailyText.shortDate(date)) \(stars) \(detail.taps) taps (fewest \(detail.minTaps))",
                      comment: "Shared Daily Distillery result: date, stars as ★/☆, taps used and the minimum")
    }

    /// "Monday · Gentle"
    static func label(_ spec: DistillDailySpec) -> String {
        String(localized: "\(spec.weekday.localizedName) · \(tierName(spec.tier))")
    }

    static func tierName(_ tier: DistillDailyTier) -> String {
        switch tier {
        case .gentle: DailyTier.gentle.localizedName
        case .splitter: String(localized: "Splitter", comment: "Daily Distillery flavour (Tuesday): tee pieces")
        case .twoColors: String(localized: "Two Potions", comment: "Daily Distillery flavour (Wednesday): two colors")
        case .heat: String(localized: "Heat Coil", comment: "Daily Distillery flavour (Thursday)")
        case .valves: String(localized: "Valves", comment: "Daily Distillery flavour (Friday)")
        case .crossings: String(localized: "Crossings", comment: "Daily Distillery flavour (Saturday)")
        case .grand: String(localized: "Grand Still", comment: "Daily Distillery flavour (Sunday)")
        }
    }

    static func symbol(_ tier: DistillDailyTier) -> String {
        switch tier {
        case .gentle: "leaf.fill"
        case .splitter: "arrow.triangle.branch"
        case .twoColors: "drop.halffull"
        case .heat: "flame.fill"
        case .valves: "spigot.fill"
        case .crossings: "plus"
        case .grand: "crown.fill"
        }
    }

    /// "New distillery in 3 h 12 m"
    nonisolated static func countdown(seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return String(localized: "New distillery in \(m) m", comment: "Countdown to the next Daily Distillery, minutes") }
        return String(localized: "New distillery in \(h) h \(m) m", comment: "Countdown to the next Daily Distillery, hours and minutes")
    }
}
