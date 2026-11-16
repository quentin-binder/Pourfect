public struct SolverLimits: Sendable, Hashable {
    /// Maximum number of distinct states to visit before giving up.
    public var maxStates: Int
    /// Optional wall-clock limit. Makes the result depend on machine speed, so leave it
    /// nil where results must be reproducible (e.g. random level generation).
    public var timeout: Duration?

    public init(maxStates: Int = 2_000_000, timeout: Duration? = nil) {
        self.maxStates = maxStates
        self.timeout = timeout
    }

    public static let `default` = SolverLimits()
}

public enum SolverResult: Sendable, Hashable {
    case solved(moves: [Move], statesExplored: Int)
    case unsolvable(statesExplored: Int)
    case unknown(reason: UnknownReason)

    public enum UnknownReason: Sendable, Hashable {
        case stateLimit(statesExplored: Int)
        case timeout(statesExplored: Int)
        /// The calling task was cancelled (checked every 4096 states).
        case cancelled(statesExplored: Int)
        /// Doesn't fit the packed StateKey encoding, or uses a mechanic `Rules` doesn't implement yet.
        case unsupportedState
    }

    public var moves: [Move]? {
        if case .solved(let moves, _) = self { return moves }
        return nil
    }
}

/// Result of asking for a hint from the player's current state.
public enum HintResult: Sendable, Hashable {
    case move(Move)
    case alreadySolved
    case unsolvable          // "No solution from here — undo?"
    case unknown             // search limit hit
}

/// Breadth-first search for the minimum number of moves.
public struct Solver: Sendable {
    public init() {}

    public func solve(_ start: GameState, limits: SolverLimits = .default) -> SolverResult {
        guard StateKey.canEncode(start), Rules.isSupported(start) else { return .unknown(reason: .unsupportedState) }
        if start.isSolved { return .solved(moves: [], statesExplored: 1) }

        let deadline = limits.timeout.map { ContinuousClock.now + $0 }
        var visited: Set<StateKey> = [start.canonicalKey]
        // Search tree for path reconstruction: node i was reached from
        // parents[i] via moves[i]. Moves are relative to the actual (not
        // canonical) parent state, so replaying them from `start` is valid.
        var parents: [Int32] = [-1]
        var moves: [Move] = [Move(from: -1, to: -1)]
        var frontier: [(GameState, Int32)] = [(start, 0)]

        while !frontier.isEmpty {
            var next: [(GameState, Int32)] = []
            for (state, index) in frontier {
                for move in Solver.candidateMoves(state) {
                    guard let turn = Rules.resolve(state, afterAction: .pour(move)),
                          visited.insert(turn.state.canonicalKey).inserted else { continue }
                    let child = turn.state
                    parents.append(index)
                    moves.append(move)
                    let childIndex = Int32(parents.count - 1)
                    if turn.isWon {
                        return .solved(moves: Solver.path(to: childIndex, parents: parents, moves: moves),
                                       statesExplored: visited.count)
                    }
                    if visited.count >= limits.maxStates {
                        return .unknown(reason: .stateLimit(statesExplored: visited.count))
                    }
                    if visited.count & 0xFFF == 0 {
                        if Task.isCancelled {
                            return .unknown(reason: .cancelled(statesExplored: visited.count))
                        }
                        if let deadline, ContinuousClock.now > deadline {
                            return .unknown(reason: .timeout(statesExplored: visited.count))
                        }
                    }
                    next.append((child, childIndex))
                }
            }
            frontier = next
        }
        return .unsolvable(statesExplored: visited.count)
    }

    /// First move of an optimal solution from `state`.
    public func hint(for state: GameState, limits: SolverLimits = .default) -> HintResult {
        switch solve(state, limits: limits) {
        case .solved(let moves, _):
            return moves.first.map(HintResult.move) ?? .alreadySolved
        case .unsolvable:
            return .unsolvable
        case .unknown:
            return .unknown
        }
    }

    /// Legal moves minus the ones that can never be needed on an optimal path.
    /// Every pruned move leads to a state that is canonically identical to the
    /// current one (a no-op) or to a sibling that is already generated.
    ///
    /// The rules hold for states without links, goal or counter whose flasks share one
    /// capacity (as `validate()` requires) and carry only *static* modifiers
    /// (`BottleModifier.isStatic`: seal, essence rune, narrow neck, funnel, tap), whose
    /// effect depends only on the two bottles of a pour. Two flasks are *alike* when their
    /// modifier sets are equal (`Bottle.storage`): an empty flask is then interchangeable
    /// with any other empty flask alike (a bottle permutation, which the key ignores). Any
    /// other state gets every legal move (later mechanics add their own safe pruning here).
    ///
    /// - Rule 3: pouring into an empty unsealed flask gives the same canonical state as
    ///   pouring into the first empty flask alike, so only that one is tried. An empty
    ///   flask that is *not* alike (an essence rune vs. a plain flask, two different
    ///   runes) is a different target and is tried on its own (DECISIONS 133).
    /// - Rule 2: if the pour moves everything in the source (the plan's amount, so a narrow
    ///   neck moving one of two layers doesn't count), pouring it into an empty flask
    ///   alike just relocates the flask (a canonical no-op). Into an empty flask that is
    ///   not alike it is a real move (e.g. a plain flask's finished color into its essence
    ///   flask, or into a narrow neck) and is kept.
    /// - Rule 1 (shortcut of rule 2): a full single-color plain flask holds all `capacity`
    ///   layers of its color, so its only legal targets are empty flasks; when no empty
    ///   flask that can receive (unsealed, no tap) carries a modifier, they're all plain,
    ///   all no-ops, and the source is skipped.
    ///
    /// Seals: the key includes each seal and a key layer has its own token, so
    /// "canonically identical" still means "same position for the rules"; only unsealed
    /// empty targets are ever skipped, and a key can't go into those, so no key move is
    /// pruned. For classic and sealed states (all unsealed flasks plain) these are exactly
    /// the rules from before essence flasks existed.
    static func candidateMoves(_ state: GameState) -> [Move] {
        let bottles = state.bottles
        guard state.isBottlesOnly, bottles.allSatisfy(\.hasOnlyStaticModifiers) else {
            return state.legalMoves()
        }
        // The first plain empty flask; flasks with other modifiers are rare and are
        // compared one by one (`isFirstEmptyAlike`).
        let firstPlainEmpty = bottles.firstIndex { $0.isEmpty && $0.isPlain }
        let hasMarkedEmpty = bottles.contains { $0.isEmpty && !$0.isPlain && !$0.isSealed && !$0.hasTap }
        func isFirstEmptyAlike(_ index: Int) -> Bool {
            let target = bottles[index]
            return !bottles[..<index].contains { $0.isEmpty && $0.storage == target.storage }
        }
        var result: [Move] = []
        for from in bottles.indices {
            let source = bottles[from]
            if source.isEmpty { continue }
            // Rule 1.
            if source.isPlain && !hasMarkedEmpty && source.isFull && Rules.isSolved(source) { continue }
            // Rule 2 (a plain source moves its whole top run into an empty plain flask).
            let movesWhole = Rules.movableRunCount(source) == source.layers.count
            for to in bottles.indices where to != from {
                let target = bottles[to]
                var alikeEmpty = false
                if target.isEmpty {
                    if target.isPlain {
                        if to != firstPlainEmpty || (movesWhole && source.isPlain) { continue }  // rules 3, 2
                    } else if !target.isSealed {
                        if !isFirstEmptyAlike(to) { continue }  // rule 3
                        alikeEmpty = target.storage == source.storage
                    }
                }
                // `Rules.actionPlan` without its index checks: in a state of bottles only it
                // is exactly the two-bottle plan (the one legality check, DECISIONS 125).
                guard let plan = Rules.plan(from: source, to: target) else { continue }
                if alikeEmpty && plan.amount == source.layers.count { continue }  // rule 2
                result.append(Move(from: from, to: to))
            }
        }
        return result
    }

    static func path(to index: Int32, parents: [Int32], moves: [Move]) -> [Move] {
        var path: [Move] = []
        var i = index
        while i > 0 {
            path.append(moves[Int(i)])
            i = parents[Int(i)]
        }
        return path.reversed()
    }
}

// MARK: - Full state-graph exploration (used for difficulty metrics)

/// The reachable state graph (with the solver's safe pruning applied).
struct StateGraph {
    var solved: [Bool] = []
    var edgeStart: [Int32] = []   // CSR: edges of node i are edges[edgeStart[i]..<edgeStart[i+1]]
    var edges: [Int32] = []

    var nodeCount: Int { solved.count }

    /// Explores every reachable state, or returns nil if there are more than `maxStates`.
    static func explore(from start: GameState, maxStates: Int) -> StateGraph? {
        guard StateKey.canEncode(start), Rules.isSupported(start) else { return nil }
        var graph = StateGraph()
        var index: [StateKey: Int32] = [start.canonicalKey: 0]
        graph.solved.append(start.isSolved)
        // FIFO queue of states still to expand (node ids are assigned in queue
        // order). Processed states are dropped periodically to save memory.
        var queue: [GameState] = [start]
        var head = 0
        while head < queue.count {
            let state = queue[head]
            head += 1
            graph.edgeStart.append(Int32(graph.edges.count))
            if !state.isSolved {  // solved states are terminal
                for move in Solver.candidateMoves(state) {
                    guard let turn = Rules.resolve(state, afterAction: .pour(move)) else { continue }
                    let key = turn.state.canonicalKey
                    if let existing = index[key] {
                        graph.edges.append(existing)
                    } else {
                        let id = graph.solved.count
                        if id >= maxStates { return nil }
                        index[key] = Int32(id)
                        queue.append(turn.state)
                        graph.solved.append(turn.isWon)
                        graph.edges.append(Int32(id))
                    }
                }
            }
            if head > 50_000 && head * 2 > queue.count {
                queue.removeFirst(head)
                head = 0
            }
        }
        graph.edgeStart.append(Int32(graph.edges.count))
        return graph
    }

    /// For each node, whether a solved state is reachable from it.
    func solvableFlags() -> [Bool] {
        let n = nodeCount
        // Build reverse adjacency (CSR).
        var inCount = [Int32](repeating: 0, count: n + 1)
        for e in edges { inCount[Int(e) + 1] += 1 }
        for i in 0..<n { inCount[i + 1] += inCount[i] }
        var fill = inCount
        var reverse = [Int32](repeating: 0, count: edges.count)
        for node in 0..<n {
            for e in Int(edgeStart[node])..<Int(edgeStart[node + 1]) {
                let target = Int(edges[e])
                reverse[Int(fill[target])] = Int32(node)
                fill[target] += 1
            }
        }
        var solvable = solved
        var stack = (0..<n).filter { solved[$0] }
        while let node = stack.popLast() {
            for r in Int(inCount[node])..<Int(inCount[node + 1]) {
                let parent = Int(reverse[r])
                if !solvable[parent] {
                    solvable[parent] = true
                    stack.append(parent)
                }
            }
        }
        return solvable
    }
}
