import BottleSortCore

/// A match-3 level being played. A value type: copy it to look ahead, re-create it to retry.
///
/// Determinism: ONE `SplitMix64` stream seeded with `level.seed` is consumed in this fixed order —
/// (1) the start board, (2) each settle's flask spawns then piece refills, (3) reshuffles,
/// (4) the finale. The same swaps therefore always give the same boards (DECISIONS 255).
/// State and turn order live here; every rule (start board, waves, gravity, refill, reshuffle,
/// finale) is in M3Rules.swift.
public struct M3Game: Sendable {
    public let level: M3Level
    public internal(set) var board: M3Board
    public internal(set) var movesLeft: Int
    public internal(set) var movesUsed = 0
    public internal(set) var score = 0
    /// Cleared pieces per kind, indexed by `M3Kind.index`.
    public internal(set) var collected = [Int](repeating: 0, count: 6)
    public internal(set) var flasksCollected = 0
    /// Flasks that have been on the board so far (layout ones included).
    public internal(set) var flasksSpawned: Int
    public internal(set) var status: M3Status = .playing
    public internal(set) var finalePlayed = false
    public let startBoard: M3Board
    public let startFrost: Int
    public let startCrates: Int
    var rng: SplitMix64

    /// nil if no start board could be built (`M3Level.validate()` reports `.noPlayableStart`).
    public init?(level: M3Level) {
        guard let (board, rng) = M3Game.makeStart(level) else { return nil }
        self.level = level
        self.board = board
        self.rng = rng
        self.movesLeft = level.moves
        self.flasksSpawned = board.flaskCount
        self.startBoard = board
        self.startFrost = board.frostLayers
        self.startCrates = board.crateHits
    }

    /// Test/tool entry: play an exact board with the level's rules and seed stream.
    public init(level: M3Level, board: M3Board, rngSeed: UInt64? = nil) {
        self.level = level
        self.board = board
        self.rng = SplitMix64(seed: rngSeed ?? level.seed)
        self.movesLeft = level.moves
        self.flasksSpawned = board.flaskCount
        self.startBoard = board
        self.startFrost = board.frostLayers
        self.startCrates = board.crateHits
    }

    // MARK: Goals

    /// (current, target) for a goal; current never exceeds target.
    public func progress(_ goal: M3Goal) -> (current: Int, target: Int) {
        switch goal.type {
        case .collect:
            let t = goal.count ?? 0
            return (min(goal.kind.map { collected[$0.index] } ?? 0, t), t)
        case .frost: return (startFrost - board.frostLayers, startFrost)
        case .crates: return (startCrates - board.crateHits, startCrates)
        case .drops:
            let t = goal.count ?? 0
            return (min(flasksCollected, t), t)
        case .score:
            let t = goal.count ?? 0
            return (min(score, t), t)
        }
    }

    public var goalsMet: Bool { level.goals.allSatisfy { let p = progress($0); return p.current >= p.target } }

    /// 0 until won, then 1…3 by `level.stars`.
    public var stars: Int { level.stars.stars(score: score, won: status == .won) }

    public var validSwaps: [M3Swap] { M3Rules.validSwaps(board) }
    public func isValidSwap(_ swap: M3Swap) -> Bool { status == .playing && M3Rules.isValidSwap(board, swap) }

    // MARK: Playing

    /// Plays one swap. A refused swap (not playing, no moves, not legal) changes nothing.
    /// Accepted: one move is used, then swap → wave 1 → (settle → collect flasks …) → cascade waves
    /// until stable → win / loss check → reshuffle if no valid swap is left.
    public mutating func play(_ swap: M3Swap) -> M3StepResult {
        guard status == .playing, movesLeft > 0, M3Rules.isValidSwap(board, swap) else {
            return M3StepResult(swap: swap, accepted: false, phases: [], scoreGained: 0, movesLeft: movesLeft, status: status)
        }
        let before = score
        movesLeft -= 1
        movesUsed += 1
        var phases: [M3Phase] = [.swap(swap)]
        phases.append(.wave(applySwap(swap)))
        runCascades(after: 1, into: &phases)
        if goalsMet {
            status = .won
        } else if movesLeft == 0 {
            status = .lost
        } else if !M3Rules.hasValidSwap(board) {
            if let r = reshuffle() { phases.append(.reshuffle(r)) } else { status = .lost }
        }
        return M3StepResult(swap: swap, accepted: true, phases: phases, scoreGained: score - before,
                            movesLeft: movesLeft, status: status)
    }

    /// Swaps the two pieces and resolves wave 1 (no settle, no RNG). The caller checked legality.
    mutating func applySwap(_ swap: M3Swap) -> M3Wave {
        let a = board[swap.from].piece!, b = board[swap.to].piece!
        board[swap.from].item = .piece(b)
        board[swap.to].item = .piece(a)
        let ia = board.index(swap.to), ib = board.index(swap.from)  // where a and b are now
        if a.isPrism && b.isPrism {
            return resolveWave(cascade: 1, groups: [], initial: [(ia, false), (ib, false)],
                               seeds: [(ia, .prism, .board)])
        }
        if a.isPrism || b.isPrism {
            let (prismAt, other) = a.isPrism ? (ia, b) : (ib, a)
            let kind = other.kind!
            guard let sp = other.special else {
                return resolveWave(cascade: 1, groups: [], initial: [(prismAt, false)],
                                   seeds: [(prismAt, .prism, .kind(kind))])
            }
            var conversions: [M3SpecialPiece] = []
            var firing: [(Int, Bool)] = [(prismAt, false)]
            for i in board.cells.indices {
                guard var p = board.cells[i].piece, !p.isFrozen, p.kind == kind else { continue }
                if p.special == nil {
                    let pos = board.pos(i)
                    p.special = sp.isLine ? ((pos.row + pos.col) % 2 == 0 ? .row : .column) : sp
                    board.cells[i].item = .piece(p)
                    conversions.append(M3SpecialPiece(at: pos, piece: p))
                }
                firing.append((i, true))
            }
            return resolveWave(cascade: 1, groups: [], initial: firing, seeds: [], conversions: conversions)
        }
        if let sa = a.special, let sb = b.special {
            return resolveWave(cascade: 1, groups: [], initial: [(ia, false), (ib, false)],
                               seeds: [(ia, sa, M3Rules.comboEffect(sa, sb))])
        }
        return resolveWave(cascade: 1, groups: M3Rules.findGroups(board, swap: swap))
    }

    /// Settles, collects flasks and resolves cascade waves until the board is stable.
    mutating func runCascades(after cascade: Int, into phases: inout [M3Phase]) {
        var cascade = cascade
        while true {
            settleAndCollect(into: &phases)
            let groups = M3Rules.findGroups(board, swap: nil)
            if groups.isEmpty || cascade >= M3Rules.maxCascades { return }
            cascade += 1
            phases.append(.wave(resolveWave(cascade: cascade, groups: groups)))
        }
    }

    mutating func settleAndCollect(into phases: inout [M3Phase]) {
        let s = settle()
        if !s.falls.isEmpty || !s.spawns.isEmpty { phases.append(.settle(s)) }
        while true {
            let collected = collectFlasks()
            if collected.isEmpty { return }
            phases.append(.collect(collected))
            let s = settle()
            if !s.falls.isEmpty || !s.spawns.isEmpty { phases.append(.settle(s)) }
        }
    }

    /// Tools only: change the moves left (finales for other move limits).
    mutating func setMovesLeft(_ n: Int) { movesLeft = n }

    // MARK: Look-ahead

    /// Wave 1 of a swap without playing it (no settle, no RNG): what a hint or a bot sees.
    public func preview(_ swap: M3Swap) -> M3Wave? {
        guard M3Rules.isValidSwap(board, swap) else { return nil }
        var copy = self
        return copy.applySwap(swap)
    }
}
