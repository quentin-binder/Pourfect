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

    let levels: [LevelDefinition]
    private let progress: ProgressModel

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
    /// Incremented on every illegal move (drives haptics).
    private(set) var invalidMoveCount = 0

    /// Latest optimal solution, valid for `solutionState`. Lets Hint answer instantly.
    private var solution: (state: GameState, moves: [Move])?
    private var analysisTask: Task<Void, Never>?
    private var hintClearTask: Task<Void, Never>?

    nonisolated static let solverLimits = SolverLimits(maxStates: 1_000_000, timeout: .seconds(4))

    init(levels: [LevelDefinition], index: Int, progress: ProgressModel) {
        self.levels = levels
        self.progress = progress
        self.levelIndex = index
        self.session = GameSession(levels[index].gameState)
        startLevel(index)
    }

    var level: LevelDefinition { levels[levelIndex] }
    var state: GameState { session.state }
    var moveCount: Int { session.moveCount }
    var canUndo: Bool { session.canUndo }
    var hasNextLevel: Bool { levelIndex + 1 < levels.count }

    // MARK: Intents

    func tap(bottle index: Int) {
        guard !isWon else { return }
        clearHint()
        guard let from = selected else {
            if !state.bottles[index].isEmpty { selected = index }
            else { reject(index) }
            return
        }
        selected = nil
        if from == index { return }   // tapping the same bottle deselects
        let move = Move(from: from, to: index)
        if session.apply(move) {
            afterStateChange()
        } else {
            reject(from)
        }
    }

    func undo() {
        guard session.undo() else { return }
        selected = nil
        clearHint()
        afterStateChange()
    }

    func restart() {
        session.restart()
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
        Task {
            let result = await Self.solve(current)
            guard current == self.state else { return }   // board changed meanwhile
            self.isThinking = false
            self.handle(result, for: current)
            switch result {
            case .solved(let moves, _):
                if let first = moves.first { self.showHint(first) }
            case .unsolvable:
                self.flash("No solution from here — undo?")
            case .unknown:
                self.flash("Couldn't find a hint in time")
            }
        }
    }

    func startLevel(_ index: Int) {
        analysisTask?.cancel()
        levelIndex = index
        session = GameSession(levels[index].gameState)
        minMoves = levels[index].meta?.minMoves
        shakes = Array(repeating: 0, count: session.state.bottles.count)
        selected = nil
        solution = nil
        clearHint()
        afterStateChange()
    }

    func nextLevel() {
        guard hasNextLevel else { return }
        startLevel(levelIndex + 1)
    }

    // MARK: Helpers

    private var isWon: Bool { if case .won = status { return true } else { return false } }
    private var stars: Int { if case .won(let s) = status { return s } else { return 0 } }

    private func reject(_ bottle: Int) {
        shakes[bottle] += 1
        invalidMoveCount += 1
    }

    private func afterStateChange() {
        analysisTask?.cancel()
        isThinking = false
        if state.isSolved {
            let best = minMoves ?? moveCount
            let earned = StarRating.stars(moves: moveCount, minMoves: best)
            status = .won(stars: earned)
            progress.record(stars: earned, for: level.id)
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

    nonisolated private static func solve(_ state: GameState) async -> SolverResult {
        await Task.detached(priority: .userInitiated) {
            Solver().solve(state, limits: solverLimits)
        }.value
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
            try? await Task.sleep(for: .milliseconds(450))
            tap(bottle: move.from)
            try? await Task.sleep(for: .milliseconds(250))
            tap(bottle: move.to)
        }
    }
    #endif
}
