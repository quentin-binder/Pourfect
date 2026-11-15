import BottleSortCore
import Foundation
import Observation

/// The daily puzzle in the app: today's UTC date, its level (generated on device, off the main
/// thread, cached per date), the saved results and the streak stats. Injected at the app root.
///
/// "Today" always comes from the core (`DailyDate(now)`, a UTC calendar day). It is refreshed
/// when the app becomes active and by a timer at the next UTC midnight, so a new puzzle appears
/// while the app stays open.
@MainActor
@Observable
final class DailyModel {
    /// How generating today's level is going.
    enum LevelState: Equatable {
        case idle
        case generating
        case ready(LevelDefinition)
    }

    /// What happened when a won daily was recorded.
    enum RecordOutcome: Equatable {
        /// First solve of the day: saved, counts for the streak and the calendar.
        case recorded(DailyResult)
        /// The day already had a result (a replay); the first one stays.
        case alreadySolved(DailyResult)
        /// Finished after that puzzle's UTC day ended: it doesn't count (DECISIONS 110).
        case dayEnded
    }

    @ObservationIgnored private let store: DailyStore
    /// Added to the system clock (DEBUG `-LPDailyDate` only; 0 otherwise).
    @ObservationIgnored let clockOffset: TimeInterval

    private(set) var today: DailyDate
    private(set) var history: DailyHistory
    private(set) var levelState: LevelState = .idle

    @ObservationIgnored private var cache: [DailyDate: LevelDefinition] = [:]
    @ObservationIgnored private var generatingDate: DailyDate?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var midnightTask: Task<Void, Never>?

    init(store: DailyStore, clockOffset: TimeInterval = 0) {
        self.store = store
        self.clockOffset = clockOffset
        self.history = store.loadHistory()
        self.today = DailyDate(Date().addingTimeInterval(clockOffset))
        scheduleMidnightRefresh()
        prepareLevel()
    }

    /// The model the app uses: saved in UserDefaults, or, with the DEBUG launch arguments
    /// `-LPDailyDate YYYY-MM-DD` / `-LPDailySeedResults N`, a pretend date and / or fake results
    /// kept in memory only.
    static func makeDefault() -> DailyModel {
        #if DEBUG
        let defaults = UserDefaults.standard
        let pretend = defaults.string(forKey: "LPDailyDate").flatMap(DailyDate.init(isoString:))
        let seedDays = defaults.integer(forKey: "LPDailySeedResults")
        if pretend != nil || seedDays > 0 {
            let realToday = DailyDate(Date())
            let offset = TimeInterval((pretend ?? realToday).days(since: realToday)) * 86_400
            let today = pretend ?? realToday
            return DailyModel(store: MemoryDailyStore(debugSeedHistory(days: seedDays, before: today)),
                              clockOffset: offset)
        }
        #endif
        return DailyModel(store: UserDefaultsDailyStore())
    }

    // MARK: Clock and today

    /// The current time (system clock plus the DEBUG offset).
    func now() -> Date { Date().addingTimeInterval(clockOffset) }

    /// Re-reads today's UTC date. When it changed, prepares the new day's level.
    func refresh() {
        let current = DailyDate(now())
        if current != today { today = current }
        scheduleMidnightRefresh()
        prepareLevel()
    }

    /// Seconds from `date` (a real clock reading, e.g. a `TimelineView` date) to the next puzzle.
    func secondsUntilNextPuzzle(at date: Date = Date()) -> TimeInterval {
        let shifted = date.addingTimeInterval(clockOffset)
        return max(0, DailyDate(shifted).next.startDate.timeIntervalSince(shifted))
    }

    private func scheduleMidnightRefresh() {
        midnightTask?.cancel()
        let wait = secondsUntilNextPuzzle() + 0.5
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: Today's puzzle

    var spec: DailySpec { DailyPlan.spec(for: today) }
    var stats: DailyStats { history.stats(today: today) }
    var todayResult: DailyResult? { history.result(for: today) }

    var level: LevelDefinition? {
        if case .ready(let level) = levelState { return level }
        return nil
    }

    /// Generates today's level in the background unless it is cached or already on its way.
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
            let work = Task.detached(priority: .userInitiated) { try DailyPuzzle.level(for: date) }
            // Cancelling stops the core too; it then throws instead of picking another level.
            let level = try? await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled, let level else { return }
            self.cache = [date: level]   // only one day is ever needed
            self.generationTask = nil
            self.generatingDate = nil
            if self.today == date { self.levelState = .ready(level) }
        }
    }

    // MARK: Results

    /// Records a won daily of `date`. Only the first solve finished on that UTC day counts.
    func record(date: DailyDate, moves: Int, minMoves: Int, usedHint: Bool) -> RecordOutcome {
        refresh()
        let result = DailyResult(date: date, moves: moves, minMoves: minMoves, usedHint: usedHint, solvedAt: now())
        guard result.counts else { return .dayEnded }
        if let existing = history.result(for: date) { return .alreadySolved(existing) }
        history.record(result)
        store.saveHistory(history)
        return .recorded(result)
    }

    #if DEBUG
    /// Fake results for the `days` days before `today`: a few gaps, most of them perfect, and an
    /// unbroken run of five ending yesterday (so today's solve makes a streak of six).
    static func debugSeedHistory(days: Int, before today: DailyDate) -> DailyHistory {
        guard days > 0 else { return DailyHistory() }
        let results: [DailyResult] = (1...days).compactMap { back in
            if back > 5, back % 7 == 6 || back % 11 == 9 { return nil }   // missed days
            let date = today.adding(days: -back)
            let minMoves = DailyPlan.spec(for: date).minMoves.lowerBound + back % 3
            let perfect = back % 3 != 1
            return DailyResult(date: date, moves: minMoves + (perfect ? 0 : 1 + back % 4), minMoves: minMoves,
                               usedHint: !perfect && back % 2 == 0,
                               solvedAt: date.startDate.addingTimeInterval(9 * 3600 + Double(back) * 600))
        }
        return DailyHistory(results: results)
    }
    #endif
}
