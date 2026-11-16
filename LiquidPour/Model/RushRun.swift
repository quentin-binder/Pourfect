import BottleSortCore
import Foundation
import Observation

/// The best Rush score, on its own keys (never with recipe stars, so it can't open a chapter).
@MainActor
@Observable
final class RushRecordModel {
    static let bestKey = "rush.best.v1"
    static let runsKey = "rush.runs.v1"

    private let defaults: UserDefaults
    private(set) var record: RushRecord

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        record = RushRecord(best: defaults.integer(forKey: Self.bestKey), runs: defaults.integer(forKey: Self.runsKey))
    }

    var best: Int { record.best }

    /// Records a finished run; true when it set a new best.
    func record(solved: Int) -> Bool {
        let isNew = record.record(solved: solved)
        defaults.set(record.best, forKey: Self.bestKey)
        defaults.set(record.runs, forKey: Self.runsKey)
        return isNew
    }
}

/// One Rush run (R6): the clock, the recipes (`RushPlan`, generated one ahead in the background)
/// and the game model that plays them. The clock only runs while a recipe is on the board:
/// never while the next one is still brewing or during the short pause after a solve.
@MainActor
@Observable
final class RushRun {
    enum Phase: Equatable {
        /// Waiting for a recipe to finish generating (the clock is paused).
        case loading
        case playing
        /// A recipe was just solved: its corks settle before the next one (clock paused).
        case solved
        case over(newBest: Bool)
    }

    let seed: UInt64
    let mechanics: [RushMechanic]
    private(set) var clock: RushClock
    private(set) var phase: Phase = .loading
    /// 0-based index of the recipe on the board.
    private(set) var index = 0
    /// Plays the current recipe; nil until the first one is ready.
    private(set) var game: GameViewModel?
    /// The best before this run (shown on the end card).
    private(set) var previousBest: Int
    /// The app is in the background or inactive: the clock stops.
    var isPaused = false
    /// A "How to play" tip covers the board ("?"): the clock stops.
    var isShowingTip = false

    @ObservationIgnored private let records: RushRecordModel
    /// Dev aid (`-LPRushAutoplay 1`): every recipe plays itself; the result is not saved.
    @ObservationIgnored private let autoplay: Bool
    @ObservationIgnored private var pending: [Int: Task<RushLevel?, Never>] = [:]
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var flow: Task<Void, Never>?

    /// Pause after a solve, so the last cork and the "+5 s" read before the board changes.
    static let solvedPause: Duration = .milliseconds(900)

    init(seed: UInt64, mechanics: [RushMechanic], duration: Double = RushClock.duration,
         records: RushRecordModel, autoplay: Bool = false) {
        self.seed = seed
        self.mechanics = mechanics
        self.clock = RushClock(duration: duration)
        self.records = records
        self.previousBest = records.best
        self.autoplay = autoplay
    }

    var solved: Int { clock.solved }
    var isOver: Bool { if case .over = phase { return true } else { return false } }

    /// Starts the run: generates the first recipe (and the next in the background), then the clock.
    func start() {
        guard game == nil, flow == nil else { return }
        flow = Task { await self.show(index: 0) }
    }

    /// Ends the run without recording it (the screen was left).
    func stop() {
        ticker?.cancel()
        flow?.cancel()
        for task in pending.values { task.cancel() }
        pending.removeAll()
    }

    /// Skips the recipe on the board for `RushClock.skipPenalty`.
    func skip() {
        guard phase == .playing else { return }
        clock.skip()
        if clock.isOver { finish(); return }
        advance()
    }

    // MARK: Flow

    private func solvedRecipe() {
        guard phase == .playing else { return }
        clock.solve()
        phase = .solved
        flow = Task {
            try? await Task.sleep(for: Self.solvedPause)
            guard !Task.isCancelled else { return }
            self.advance()
        }
    }

    private func advance() {
        guard !isOver else { return }
        flow?.cancel()
        flow = Task { await self.show(index: self.index + 1) }
    }

    /// Waits for recipe `index` (clock paused), puts it on the board and starts the next one brewing.
    private func show(index: Int) async {
        phase = .loading
        let level = await level(at: index)
        guard !Task.isCancelled, let level else { return }
        pending[index] = nil
        prefetch(index + 1)
        self.index = index
        if let game {
            game.loadRush(level.level, number: index + 1)
        } else {
            let game = GameViewModel(rushLevel: level.level)
            game.onRushWin = { [weak self] in self?.solvedRecipe() }
            self.game = game
        }
        phase = .playing
        startTicker()
        #if DEBUG
        if autoplay, let game { Task { await game.debugPlayOptimal(moves: 99) } }
        #endif
    }

    private func level(at index: Int) async -> RushLevel? {
        prefetch(index)
        return await pending[index]?.value
    }

    /// Generates recipe `index` off the main thread unless it is already brewing.
    private func prefetch(_ index: Int) {
        guard pending[index] == nil else { return }
        let seed = seed, mechanics = mechanics
        pending[index] = Task.detached(priority: .userInitiated) {
            try? RushPlan.level(index: index, seed: seed, mechanics: mechanics)
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task {
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let now = ContinuousClock.now
                let elapsed = now - last
                last = now
                // A solved board stops the clock at once: the win counts from the winning pour,
                // not from when its animation lands.
                guard phase == .playing, !isPaused, !isShowingTip, game?.state.isSolved != true else { continue }
                let c = elapsed.components
                clock.tick(Double(c.seconds) + Double(c.attoseconds) / 1e18)
                if clock.isOver { finish() }
            }
        }
    }

    private func finish() {
        guard !isOver else { return }
        stop()
        let isNewBest = autoplay ? clock.solved > previousBest : records.record(solved: clock.solved)
        phase = .over(newBest: isNewBest)
    }
}
