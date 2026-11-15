import BottleSortCore
import Foundation
import Observation

/// Drives one game screen. Wraps `GameSession`; all rule decisions come from BottleSortCore.
@MainActor
@Observable
final class GameViewModel {
    enum Status: Equatable {
        case playing
        case won(stars: Int)
        case stuck
    }

    /// One legal pour that was just applied to the session. The view animates it, then calls
    /// `finishPour(_:)`. Holds the two bottles as they were *before* the move, so the
    /// animation can draw the transfer without re-deriving any rule.
    struct PourEvent: Identifiable, Equatable {
        let id: Int
        let from: Int
        let to: Int
        /// The layer kind that moved (all moved layers are identical).
        let layer: Layer
        /// Number of layers that moved.
        let amount: Int
        let sourceBefore: Bottle
        let targetBefore: Bottle
        /// Bottom layers of each bottle shown as "?" before the move (hidden-layers mode).
        let sourceHiddenBefore: Int
        let targetHiddenBefore: Int

        /// Bottles that became complete (full, one color) through this move. Reported as
        /// `.flaskCompleted` when the animation lands.
        let completed: [Int]

        /// A key pour: the key drops into the target's lock instead of liquid flowing.
        var isKey: Bool { layer.isKey }
    }

    /// Something the player should hear or feel. Published in order through `feedback`.
    enum FeedbackEvent: Equatable {
        /// A bottle was picked up as the pour source.
        case select(bottle: Int)
        /// A tap that can't do anything (empty bottle selected, or an illegal pour).
        case illegal(bottle: Int)
        /// A legal pour started animating (same moment as `pour` is set). `amount` = layers moved.
        case pour(from: Int, to: Int, amount: Int, isKey: Bool)
        /// Bottles that became complete; fires when the pour animation lands (`finishPour`).
        case flaskCompleted(bottles: [Int])
        /// The level was solved; fires when the winning pour lands, right after any `flaskCompleted`.
        case levelWon(stars: Int)
    }

    struct Feedback: Identifiable, Equatable {
        /// Increments by one per event, never reused within a model.
        let id: Int
        let event: FeedbackEvent
    }

    private(set) var levels: [LevelDefinition]
    /// Pack progress; nil for random levels, which never affect saved progress.
    private let progress: ProgressModel?
    /// Set when playing a random level: the options used to make the next one.
    let randomOptions: RandomLevelOptions?
    /// Generates the next random level ("New Random Brew" on the win card).
    let randomMaker = RandomLevelMaker()

    private(set) var levelIndex: Int
    private(set) var session: GameSession
    private(set) var status: Status = .playing
    /// Optimal move count (from level meta, or computed in the background).
    private(set) var minMoves: Int?
    /// Currently selected source bottle.
    private(set) var selected: Int?
    /// Move highlighted by the Hint button.
    private(set) var hint: Move?
    private(set) var hintMessage: String?
    private(set) var isThinking = false
    /// Incremented per bottle on an illegal move (drives the shake animation).
    private(set) var shakes: [Int] = []
    /// Recent feedback events, oldest first (only the last few are kept). Observe
    /// `feedback.last?.id` and read `feedback(after:)` so events published in one update
    /// (e.g. a completion followed by a queued tap) are never lost.
    /// Goes up each time a pour is cancelled mid-animation (undo, restart, level load), so the
    /// view can drop that pour's delayed sounds and haptics.
    private(set) var cancelledPours = 0
    private(set) var feedback: [Feedback] = []
    /// Incremented per bottle each time it becomes complete (drives the cork / burst visuals).
    private(set) var completions: [Int] = []
    /// The pour being animated, if any. While set, taps are queued (not applied) so the
    /// board the view shows and the session can't drift apart.
    private(set) var pour: PourEvent?

    /// Latest optimal solution, valid for `solutionState`. Lets Hint answer instantly.
    private var solution: (state: GameState, moves: [Move])?
    private var analysisTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var hintClearTask: Task<Void, Never>?
    private var pourCount = 0
    private var feedbackCount = 0
    /// Taps received while a pour animates; replayed in order when it ends.
    private var queuedTaps: [Int] = []
    /// Safety net: ends a pour even if the view never reports back (e.g. it went off screen).
    private var pourTimeout: Task<Void, Never>?

    nonisolated static let solverLimits = SolverLimits(maxStates: 1_000_000, timeout: .seconds(4))

    init(levels: [LevelDefinition], index: Int, progress: ProgressModel) {
        self.levels = levels
        self.progress = progress
        self.randomOptions = nil
        self.levelIndex = index
        self.session = GameSession(levels[index].gameState, hidden: levels[index].isHidden)
        startLevel(index)
    }

    /// Plays one generated level; the win card then offers a new one with the same options.
    init(randomLevel: LevelDefinition, options: RandomLevelOptions) {
        self.levels = [randomLevel]
        self.progress = nil
        self.randomOptions = options
        self.levelIndex = 0
        self.session = GameSession(randomLevel.gameState, hidden: randomLevel.isHidden)
        startLevel(0)
    }

    var isRandom: Bool { randomOptions != nil }
    var title: String {
        if let randomOptions { return String(localized: "Random Brew · \(randomOptions.mode.title)") }
        return String(localized: "Recipe \(levelIndex + 1)")
    }

    var level: LevelDefinition { levels[levelIndex] }
    var state: GameState { session.state }
    var moveCount: Int { session.moveCount }
    var canUndo: Bool { session.canUndo }
    var hasNextLevel: Bool { levelIndex + 1 < levels.count }

    /// Bottom layers of bottle `index` to draw as "?". While a pour animates, the source keeps
    /// its pre-move value so the reveal plays when the board bottle comes back.
    func hiddenLayerCount(_ index: Int) -> Int {
        if let pour, pour.from == index { return pour.sourceHiddenBefore }
        return session.hiddenDepths.indices.contains(index) ? session.hiddenDepths[index] : 0
    }

    // MARK: Intents

    func tap(bottle index: Int) {
        guard !isWon else { return }
        if pour != nil {
            if queuedTaps.count < 2 { queuedTaps.append(index) }
            return
        }
        clearHint()
        guard let from = selected else {
            if !state.bottles[index].isEmpty {
                selected = index
                emit(.select(bottle: index))
            } else {
                reject(index)
            }
            return
        }
        selected = nil
        if from == index { return }   // tapping the same bottle deselects
        let move = Move(from: from, to: index)
        let before = state
        let hiddenBefore = session.hiddenDepths
        if session.apply(move) {
            startPour(move, before: before, hiddenBefore: hiddenBefore)
            afterStateChange()
        } else {
            reject(from)
        }
    }

    /// Called by the view when the pour animation `id` has finished. Replays queued taps.
    func finishPour(_ id: Int) {
        guard let landed = pour, landed.id == id else { return }
        pour = nil
        pourTimeout?.cancel()
        if !landed.completed.isEmpty {
            for index in landed.completed where completions.indices.contains(index) { completions[index] += 1 }
            emit(.flaskCompleted(bottles: landed.completed))
        }
        if case .won(let stars) = status { emit(.levelWon(stars: stars)) }
        while pour == nil, !queuedTaps.isEmpty {
            tap(bottle: queuedTaps.removeFirst())
        }
    }

    func undo() {
        guard session.undo() else { return }
        randomMaker.cancel()   // the player went back to the board: drop a pending new level
        cancelPour()
        selected = nil
        clearHint()
        afterStateChange()
    }

    func restart() {
        session.restart()
        randomMaker.cancel()   // Replay while "New Random Brew" runs: keep the replayed board
        cancelPour()
        selected = nil
        clearHint()
        afterStateChange()
    }

    func requestHint() {
        guard !isWon else { return }
        selected = nil
        if let solution, solution.state == state, let first = solution.moves.first {
            showHint(first)
            return
        }
        isThinking = true
        let current = state
        hintTask?.cancel()
        hintTask = Task {
            let result = await Self.solve(current)
            guard !Task.isCancelled, current == self.state else { return }   // board changed meanwhile
            self.isThinking = false
            self.handle(result, for: current)
            switch result {
            case .solved(let moves, _):
                if let first = moves.first { self.showHint(first) }
            case .unsolvable:
                self.flash(String(localized: "No solution from here — undo?"))
            case .unknown:
                self.flash(String(localized: "Couldn't find a hint in time"))
            }
        }
    }

    func startLevel(_ index: Int) {
        analysisTask?.cancel()
        levelIndex = index
        // Present the bottles in a fresh random order on every load (Restart/Replay keep it),
        // so empty bottles aren't always at the end. Order doesn't change the puzzle.
        var rng = SystemRandomNumberGenerator()
        session = GameSession(levels[index].gameState.shufflingBottles(using: &rng), hidden: levels[index].isHidden)
        cancelPour()
        minMoves = levels[index].meta?.minMoves
        shakes = Array(repeating: 0, count: session.state.bottles.count)
        completions = Array(repeating: 0, count: session.state.bottles.count)
        selected = nil
        solution = nil
        clearHint()
        afterStateChange()
    }

    func nextLevel() {
        guard hasNextLevel else { return }
        startLevel(levelIndex + 1)
    }

    /// Random levels: generates a new level with the same options (off the main thread)
    /// and starts it. Progress and failure are published by `randomMaker`.
    func newRandomLevel() {
        guard let randomOptions else { return }
        randomMaker.generate(randomOptions) { [weak self] level in
            guard let self else { return }
            self.levels = [level]
            self.startLevel(0)
        }
    }

    // MARK: Helpers

    private var isWon: Bool { if case .won = status { return true } else { return false } }

    private func startPour(_ move: Move, before: GameState, hiddenBefore: [Int]) {
        let source = before.bottles[move.from]
        let amount = source.layers.count - state.bottles[move.from].layers.count
        guard amount > 0, let layer = source.topLayer else { return }
        pourCount += 1
        let id = pourCount
        pour = PourEvent(id: id, from: move.from, to: move.to, layer: layer, amount: amount,
                         sourceBefore: source, targetBefore: before.bottles[move.to],
                         sourceHiddenBefore: hiddenBefore[move.from], targetHiddenBefore: hiddenBefore[move.to],
                         completed: Rules.completedBottles(before: before, after: state))
        emit(.pour(from: move.from, to: move.to, amount: amount, isKey: layer.isKey))
        pourTimeout?.cancel()
        pourTimeout = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.finishPour(id)
        }
    }

    private func cancelPour() {
        if pour != nil { cancelledPours += 1 }
        pour = nil
        queuedTaps.removeAll()
        pourTimeout?.cancel()
    }

    private func reject(_ bottle: Int) {
        shakes[bottle] += 1
        emit(.illegal(bottle: bottle))
    }

    /// Events newer than `id` (all kept events for nil), oldest first.
    func feedback(after id: Int?) -> [Feedback] {
        guard let id else { return feedback }
        return feedback.filter { $0.id > id }
    }

    private func emit(_ event: FeedbackEvent) {
        feedbackCount += 1
        feedback.append(Feedback(id: feedbackCount, event: event))
        if feedback.count > 16 { feedback.removeFirst(feedback.count - 16) }
    }

    private func afterStateChange() {
        analysisTask?.cancel()
        hintTask?.cancel()
        isThinking = false
        if state.isSolved {
            let best = minMoves ?? moveCount
            let earned = StarRating.stars(moves: moveCount, minMoves: best)
            status = .won(stars: earned)
            progress?.record(stars: earned, for: level.id)
            return
        }
        if state.legalMoves().isEmpty {
            status = .stuck
            return
        }
        status = .playing
        // Check solvability (and cache the solution for Hint) off the main thread.
        let current = state
        analysisTask = Task {
            let result = await Self.solve(current)
            guard !Task.isCancelled, current == self.state else { return }
            self.handle(result, for: current)
        }
    }

    private func handle(_ result: SolverResult, for analyzed: GameState) {
        switch result {
        case .solved(let moves, _):
            solution = (analyzed, moves)
            if minMoves == nil && moveCount == 0 { minMoves = moves.count }
        case .unsolvable:
            if !isWon { status = .stuck }
        case .unknown:
            break
        }
    }

    /// Solves off the main actor. Cancelling the calling task stops the solver too
    /// (a detached task doesn't inherit cancellation, so it is forwarded).
    nonisolated private static func solve(_ state: GameState) async -> SolverResult {
        let work = Task.detached(priority: .userInitiated) {
            Solver().solve(state, limits: solverLimits)
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private func showHint(_ move: Move) {
        hint = move
        hintMessage = nil
        scheduleHintClear()
    }

    private func flash(_ message: String) {
        hintMessage = message
        scheduleHintClear(after: .seconds(2.5))
    }

    private func scheduleHintClear(after delay: Duration = .seconds(1.6)) {
        hintClearTask?.cancel()
        hintClearTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.hint = nil
            self.hintMessage = nil
        }
    }

    private func clearHint() {
        hintClearTask?.cancel()
        hint = nil
        hintMessage = nil
    }

    #if DEBUG
    /// Dev aid: plays the first `moves` optimal moves through `tap(bottle:)`, like a player would.
    func debugPlayOptimal(moves: Int) async {
        guard case .solved(let solution, _) = await Self.solve(state) else { return }
        for move in solution.prefix(moves) {
            while pour != nil { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(450))
            tap(bottle: move.from)
            try? await Task.sleep(for: .milliseconds(250))
            tap(bottle: move.to)
        }
    }
    #endif
}
