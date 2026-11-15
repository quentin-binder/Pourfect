import Foundation

/// How hard a level is. See `Difficulty.score(...)` for the combined score.
public struct DifficultyReport: Sendable, Hashable, Codable {
    /// Optimal solution length.
    public var minMoves: Int
    /// States the BFS visited before finding the optimal solution.
    public var statesExplored: Int
    /// Share of reachable states from which the puzzle can't be solved (0...1).
    public var deadEndRatio: Double
    /// How `deadEndRatio` was computed.
    public var deadEndMethod: DeadEndMethod
    /// Average number of legal moves (player's view, no pruning) along the optimal path.
    public var branchingFactor: Double
    /// Combined difficulty score (higher = harder).
    public var score: Double

    public enum DeadEndMethod: Sendable, Hashable, Codable {
        /// Whole reachable graph explored; `states` = its size.
        case exact(states: Int)
        /// Graph too big: estimated from random-walk samples, `samples` of which were decided.
        case sampled(samples: Int)
    }
}

public enum Difficulty {
    /// Above this many reachable states, the dead-end ratio is sampled instead of exact.
    public static let exactExplorationLimit = 400_000
    public static let sampleCount = 48

    /// Combined score. Tunable; documented in DECISIONS.md.
    ///
    ///     score = 1.0 × minMoves
    ///           + 1.5 × log2(statesExplored)
    ///           + 40  × deadEndRatio
    ///           + 0.5 × branchingFactor
    public static func score(minMoves: Int, statesExplored: Int, deadEndRatio: Double, branchingFactor: Double) -> Double {
        let raw = Double(minMoves)
            + 1.5 * log2(Double(max(1, statesExplored)))
            + 40 * deadEndRatio
            + 0.5 * branchingFactor
        return (raw * 10).rounded() / 10
    }

    /// Full difficulty report, or nil if the solver can't solve the level within `limits`.
    public static func analyze(_ state: GameState, limits: SolverLimits = .default, sampleSeed: UInt64 = 0) -> DifficultyReport? {
        guard case .solved(let moves, let explored) = Solver().solve(state, limits: limits) else { return nil }
        return analyze(state, solution: moves, statesExplored: explored, sampleSeed: sampleSeed)
    }

    /// Report for a level whose optimal solution is already known.
    public static func analyze(_ state: GameState, solution: [Move], statesExplored: Int, sampleSeed: UInt64 = 0) -> DifficultyReport {
        // Branching factor along the optimal path.
        var branching = 0
        var current = state
        for move in solution {
            branching += current.legalMoves().count
            current = current.pouring(move) ?? current
        }
        let branchingFactor = solution.isEmpty ? 0 : Double(branching) / Double(solution.count)

        let (ratio, method) = deadEndRatio(state, minMoves: solution.count, sampleSeed: sampleSeed)
        let score = Difficulty.score(minMoves: solution.count, statesExplored: statesExplored,
                                     deadEndRatio: ratio, branchingFactor: branchingFactor)
        return DifficultyReport(minMoves: solution.count, statesExplored: statesExplored,
                                deadEndRatio: (ratio * 1000).rounded() / 1000, deadEndMethod: method,
                                branchingFactor: (branchingFactor * 100).rounded() / 100, score: score)
    }

    static func deadEndRatio(_ state: GameState, minMoves: Int, sampleSeed: UInt64) -> (Double, DifficultyReport.DeadEndMethod) {
        if let graph = StateGraph.explore(from: state, maxStates: exactExplorationLimit) {
            let solvable = graph.solvableFlags()
            let dead = solvable.lazy.filter { !$0 }.count
            return (Double(dead) / Double(graph.nodeCount), .exact(states: graph.nodeCount))
        }
        // Estimate: random walks from the start (uniform over legal moves,
        // length 1...2×minMoves); each endpoint is checked with a bounded solve.
        var rng = SplitMix64(seed: sampleSeed)
        var decided = 0
        var dead = 0
        let solver = Solver()
        for _ in 0..<sampleCount {
            var current = state
            let length = 1 + rng.nextInt(below: max(1, 2 * minMoves))
            for _ in 0..<length {
                let moves = current.legalMoves()
                if moves.isEmpty || current.isSolved { break }
                current = current.pouring(moves[rng.nextInt(below: moves.count)])!
            }
            switch solver.solve(current, limits: SolverLimits(maxStates: 200_000)) {
            case .solved: decided += 1
            case .unsolvable: decided += 1; dead += 1
            case .unknown: break
            }
        }
        return (decided == 0 ? 0 : Double(dead) / Double(decided), .sampled(samples: decided))
    }
}
