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
    /// The rules hold for states without goal or counter whose flasks share one
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
    ///
    /// Frozen layers (D1): their counters tick after *every* move, so a relocation (rule 2,
    /// and rule 1, its shortcut) is no longer a no-op while ice remains: it is a "wait" move
    /// that lets ice thaw, and a solution may need it. Both are off in a state with a
    /// frozen layer. Rule 3 stays: pouring into either of two empty flasks alike gives
    /// states that differ only by a bottle permutation, before and after the thaw step
    /// (an empty flask never holds ice: a frozen layer never moves, so its flask never
    /// empties). Once the last layer thaws, every rule applies again (DECISIONS 162).
    ///
    /// Bubbling flasks (D2): their phases tick after every move, forever, so rules 1 and 2
    /// are off in a state with a bubbling flask, like with ice. Instead every *relocation*
    /// (all of a source into an empty flask with the same modifiers, phase included) leads
    /// to the same canonical child: the position with two flasks swapped, then the timed
    /// step, i.e. a pure wait. So only the first relocation of the state is kept (one wait
    /// per state). Rule 3 stays: two empty flasks alike (equal storage, so the same period
    /// and phase if they bubble) give permuted states before and after the timed step
    /// (DECISIONS 172).
    ///
    /// Links (twins F1, overflow pipes F2; static, no counter): a pour into a linked flask
    /// goes through the link (`Rules.actionPlan`), and a linked flask is never *alike* any
    /// other: an empty linked flask is a target of its own (rule 3 never skips it, and its
    /// presence turns rule 1 off), and a linked source is never relocated (rules 1 and 2:
    /// moving all of a linked flask into another flask isn't a bottle permutation, the link
    /// stays where it was). One rule is added: pouring into either twin of a pair gives the
    /// same state (both get `k`, the source loses `2k`; legality is symmetric, and pouring
    /// from one twin into the other is illegal both ways), so only the twin with the lower
    /// index is tried. With a timed modifier and a link together every legal move is tried
    /// (no level combines them yet; DECISIONS 179).
    ///
    /// Cauldrons (E1; no state of their own): rule 1 is off in a state with a cauldron. Its
    /// premise fails twice: mixing changes color counts, so a full one-color flask need not
    /// hold every layer of its color (another flask may take part of it on the same color),
    /// and a cauldron whose top is the other ingredient of a recipe takes the color as a
    /// mixing pour, a real move. Rules 2 and 3 only use bottle permutations and stay: an
    /// empty cauldron is alike only another empty cauldron with the same recipes (equal
    /// storage), so pouring into it is never skipped for a plain flask, and moving a whole
    /// flask into an empty flask alike (plain into plain, cauldron into cauldron) mixes
    /// nothing and only swaps two flasks (DECISIONS 193).
    static func candidateMoves(_ state: GameState) -> [Move] {
        let bottles = state.bottles
        // Links (F1, F2): bit i set = bottle i is an end of a link; `secondTwin` marks the
        // twin of each pair that is never tried as a target (its pour equals the other's).
        var linked: UInt64 = 0, secondTwin: UInt64 = 0
        if !state.isBottlesOnly {
            guard state.moveCount == nil, state.hasStandardGoal, bottles.count <= 64 else { return state.legalMoves() }
            for link in state.links {
                let (a, b) = link.endpoints
                guard bottles.indices.contains(a), bottles.indices.contains(b), a != b else { return state.legalMoves() }
                switch link {
                case .twins: secondTwin |= 1 << UInt64(max(a, b))
                case .overflow: break
                case .switchGate: return state.legalMoves()
                }
                linked |= 1 << UInt64(a) | 1 << UInt64(b)
            }
        }
        @inline(__always) func isLinked(_ i: Int) -> Bool { linked != 0 && linked & (1 << UInt64(i)) != 0 }
        var icy = false, bubbling = false, mixing = false
        for bottle in bottles {
            let kind = bottle.pruningKind
            guard kind.ok else { return state.legalMoves() }
            if kind.frozen { icy = true }
            if kind.bubbling { bubbling = true }
            if kind.mixing { mixing = true }
        }
        let timed = icy || bubbling
        if timed && linked != 0 { return state.legalMoves() }
        var waitKept = false
        // The first plain empty flask; flasks with other modifiers are rare and are
        // compared one by one (`isFirstEmptyAlike`). A linked flask is never alike any other.
        let firstPlainEmpty = bottles.indices.first { bottles[$0].isEmpty && bottles[$0].isPlain && !isLinked($0) }
        let hasMarkedEmpty = bottles.indices.contains { i in
            let b = bottles[i]
            return b.isEmpty && (!b.isPlain || isLinked(i)) && !b.isSealed && !b.hasTap
        }
        func isFirstEmptyAlike(_ index: Int) -> Bool {
            let target = bottles[index]
            return !(0..<index).contains { bottles[$0].isEmpty && bottles[$0].storage == target.storage && !isLinked($0) }
        }
        var result: [Move] = []
        for from in bottles.indices {
            let source = bottles[from]
            if source.isEmpty { continue }
            let sourceFree = !isLinked(from)
            // Rule 1 (never with a cauldron: color counts change, and a cauldron can take a mixing pour).
            if !timed && !mixing && sourceFree && source.isPlain && !hasMarkedEmpty && source.isFull && Rules.isSolved(source) { continue }
            // Rule 2 (a plain source moves its whole top run into an empty plain flask).
            let movesWhole = !timed && sourceFree && Rules.movableRunCount(source) == source.layers.count
            for to in bottles.indices where to != from {
                let target = bottles[to]
                let targetLinked = isLinked(to)
                if targetLinked && secondTwin & (1 << UInt64(to)) != 0 { continue }  // twin rule
                var alikeEmpty = false
                if target.isEmpty && !targetLinked {
                    if target.isPlain {
                        if to != firstPlainEmpty || (movesWhole && source.isPlain) { continue }  // rules 3, 2
                        alikeEmpty = bubbling && source.isPlain
                    } else if !target.isSealed {
                        if !isFirstEmptyAlike(to) { continue }  // rule 3
                        alikeEmpty = (!icy || bubbling) && sourceFree && target.storage == source.storage
                    }
                }
                // `Rules.actionPlan` without its index checks: in a state of bottles only it
                // is exactly the two-bottle plan (the one legality check, DECISIONS 125); a pour
                // into a linked flask goes through the link.
                let plan = targetLinked ? Rules.actionPlan(for: Move(from: from, to: to), in: state)
                                        : Rules.plan(from: source, to: target)
                guard let plan else { continue }
                if alikeEmpty && plan.amount == source.layers.count {
                    if !timed { continue }  // rule 2
                    if waitKept { continue }  // bubbling: one wait per state
                    waitKept = true
                }
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
    /// The states by node id, only when explored with `keepStates` (else empty).
    var states: [GameState] = []

    var nodeCount: Int { solved.count }

    /// Explores every reachable state, or returns nil if there are more than `maxStates`.
    static func explore(from start: GameState, maxStates: Int, keepStates: Bool = false) -> StateGraph? {
        guard StateKey.canEncode(start), Rules.isSupported(start) else { return nil }
        var graph = StateGraph()
        var index: [StateKey: Int32] = [start.canonicalKey: 0]
        graph.solved.append(start.isSolved)
        if keepStates { graph.states.append(start) }
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
                        if keepStates { graph.states.append(turn.state) }
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
