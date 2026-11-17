import BottleSortCore

/// A match-3 level being played. A value type: copy it to look ahead, re-create it to retry.
///
/// Determinism: ONE `SplitMix64` stream seeded with `level.seed` is consumed in this fixed order —
/// (1) the start board, (2) each settle's flask spawns then piece refills, (3) reshuffles,
/// (4) the finale. The same swaps therefore always give the same boards (DECISIONS 255).
public struct M3Game: Sendable {
    public let level: M3Level
    public private(set) var board: M3Board
    public private(set) var movesLeft: Int
    public private(set) var movesUsed = 0
    public private(set) var score = 0
    /// Cleared pieces per kind, indexed by `M3Kind.index`.
    public private(set) var collected = [Int](repeating: 0, count: 6)
    public private(set) var flasksCollected = 0
    /// Flasks that have been on the board so far (layout ones included).
    public private(set) var flasksSpawned: Int
    public private(set) var status: M3Status = .playing
    public private(set) var finalePlayed = false
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

    // MARK: Start board

    /// The start board: layout cells, placed pieces, then seeded pieces for every other open cell,
    /// columns left → right, cells bottom → top, each kind drawn uniformly among the level's kinds
    /// that make no run of 3 with pieces already there. Rejected (the stream continues) until the
    /// board has no match and at least one valid swap.
    static func makeStart(_ level: M3Level) -> (M3Board, SplitMix64)? {
        let rows = level.layoutChars
        guard level.width > 0, rows.allSatisfy({ $0.count == level.width }), !level.kinds.isEmpty else { return nil }
        var rng = SplitMix64(seed: level.seed)
        var base = M3Rules.emptyBoard(level)
        for p in level.pieces ?? [] where base.contains(M3Pos(p.row, p.col)) { M3Rules.place(p, on: &base, layout: rows) }
        for _ in 0..<M3Rules.startAttempts {
            var b = base
            for c in 0..<b.width {
                for r in stride(from: b.height - 1, through: 0, by: -1) where b[r, c].isOpen && b[r, c].item == nil {
                    let k = M3Game.drawKind(on: b, at: M3Pos(r, c), kinds: level.kinds, rng: &rng)
                    b[r, c].item = .piece(M3Piece(kind: k, frost: M3Rules.frost(rows[r][c])))
                }
            }
            if !M3Rules.hasMatch(b) && M3Rules.hasValidSwap(b) { return (b, rng) }
        }
        return nil
    }

    /// A kind for `p` that makes no run of 3 with its current neighbours (uniform among those, in
    /// the level's kind order); if every kind would, uniform among all kinds.
    static func drawKind(on b: M3Board, at p: M3Pos, kinds: [M3Kind], rng: inout SplitMix64) -> M3Kind {
        func same(_ r: Int, _ c: Int, _ k: Int) -> Bool {
            r >= 0 && r < b.height && c >= 0 && c < b.width && M3Rules.kindIndex(b[r, c]) == k
        }
        func runs(_ k: Int) -> Bool {
            var h = 1, x = p.col - 1
            while same(p.row, x, k) { h += 1; x -= 1 }
            x = p.col + 1
            while same(p.row, x, k) { h += 1; x += 1 }
            if h >= 3 { return true }
            var v = 1, y = p.row - 1
            while same(y, p.col, k) { v += 1; y -= 1 }
            y = p.row + 1
            while same(y, p.col, k) { v += 1; y += 1 }
            return v >= 3
        }
        let candidates = kinds.filter { !runs($0.index) }
        let pool = candidates.isEmpty ? kinds : candidates
        return pool[rng.nextInt(below: pool.count)]
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

    // MARK: Waves

    /// Resolves one clear wave.
    /// - `initial`: cells cleared up front as `.combo` (`fire`: whether a special there fires).
    /// - `seeds`: activations with a fixed effect (combos), fired before any other special.
    ///
    /// Rules: unfrozen group cells are cleared (`.match`), frozen ones lose a layer. Every cleared
    /// special fires once, in queue order (seeds, then specials in the order they were cleared). An
    /// effect clears every unfrozen piece it reaches (`.blast`), takes a layer off frozen pieces, hits
    /// crates, and passes flasks by. Every cell cleared by a match also hits its orthogonal
    /// neighbours' frost and crates. Each frozen piece and crate takes at most ONE hit per wave.
    /// New specials are placed last, so they never fire in the wave that made them.
    mutating func resolveWave(cascade: Int, groups: [M3MatchGroup], initial: [(Int, Bool)] = [],
                              seeds: [(Int, M3Special, M3Effect)] = [], conversions: [M3SpecialPiece] = []) -> M3Wave {
        let n = board.cells.count
        var clearing = [UInt8](repeating: 0, count: n)  // 0 no, 1 match, 2 blast, 3 combo
        var clearedBy = [Int](repeating: -1, count: n)
        var fired = [Bool](repeating: false, count: n)
        var frostHit = [Bool](repeating: false, count: n)
        var crateHit = [Bool](repeating: false, count: n)
        var order: [Int] = []
        var queue: [(at: Int, special: M3Special, effect: M3Effect?)] = seeds.map { ($0.0, $0.1, $0.2) }
        var activations: [M3Activation] = []

        func clear(_ i: Int, _ cause: UInt8, by act: Int, fire: Bool) {
            guard clearing[i] == 0 else { return }
            clearing[i] = cause
            clearedBy[i] = act
            order.append(i)
            if fire, !fired[i], let sp = board.cells[i].piece?.special {
                fired[i] = true
                queue.append((i, sp, nil))
            } else {
                fired[i] = true
            }
        }

        for (i, fire) in initial { clear(i, 3, by: -1, fire: fire) }
        for g in groups {
            for p in g.cells {
                let i = board.index(p)
                if board.cells[i].piece?.isFrozen == true { frostHit[i] = true } else { clear(i, 1, by: -1, fire: true) }
            }
        }
        var q = 0
        while q < queue.count {
            let (at, special, fixed) = queue[q]
            q += 1
            guard let effect = fixed ?? M3Rules.effect(of: special, board: board, clearing: clearing) else { continue }
            let pos = board.pos(at)
            let cells = M3Rules.cells(of: effect, at: pos, on: board)
            let act = activations.count
            activations.append(M3Activation(at: pos, special: special, effect: effect, cells: cells))
            for p in cells {
                let i = board.index(p)
                let cell = board.cells[i]
                if cell.crate > 0 { crateHit[i] = true; continue }
                guard let piece = cell.piece else { continue }
                if piece.isFrozen { frostHit[i] = true } else { clear(i, 2, by: act, fire: true) }
            }
        }
        for i in 0..<n where clearing[i] == 1 {
            for p in board.neighbors(board.pos(i)) {
                let j = board.index(p)
                if board.cells[j].crate > 0 { crateHit[j] = true } else if board.cells[j].piece?.isFrozen == true { frostHit[j] = true }
            }
        }

        var points = 0
        let multiplier = min(cascade, M3Rules.Points.maxMultiplier)
        var cleared: [M3Cleared] = []
        cleared.reserveCapacity(order.count)
        for i in order {
            guard let piece = board.cells[i].piece else { continue }
            let cause: M3Cleared.Cause = clearing[i] == 1 ? .match : clearing[i] == 2 ? .blast : .combo
            cleared.append(M3Cleared(at: board.pos(i), piece: piece, cause: cause,
                                     activation: clearedBy[i] >= 0 ? clearedBy[i] : nil))
            if let k = piece.kind { collected[k.index] += 1 }
            points += M3Rules.Points.piece * multiplier
            board.cells[i].item = nil
        }
        var frostHits: [M3Damage] = [], crateHits: [M3Damage] = []
        for i in 0..<n {
            if frostHit[i], var p = board.cells[i].piece, p.isFrozen {
                p.frost -= 1
                board.cells[i].item = .piece(p)
                frostHits.append(M3Damage(at: board.pos(i), remaining: p.frost))
                points += M3Rules.Points.obstacleHit
            }
            if crateHit[i], board.cells[i].crate > 0 {
                board.cells[i].crate -= 1
                crateHits.append(M3Damage(at: board.pos(i), remaining: board.cells[i].crate))
                points += M3Rules.Points.obstacleHit
            }
        }
        points += activations.count * M3Rules.Points.activation
        var created: [M3SpecialPiece] = []
        for g in groups {
            guard let sp = g.creates, let at = g.createdAt, board[at].item == nil else { continue }
            let piece = M3Piece(kind: sp == .prism ? nil : g.kind, special: sp)
            board[at].item = .piece(piece)
            created.append(M3SpecialPiece(at: at, piece: piece))
            points += M3Rules.Points.created(sp)
        }
        score += points
        return M3Wave(cascade: cascade, groups: groups, conversions: conversions, activations: activations,
                      cleared: cleared, frostHits: frostHits, crateHits: crateHits, created: created, score: points)
    }

    // MARK: Gravity and refill

    /// Gravity, then refill. Each column's open cells (existing, no crate) form one stack, top to
    /// bottom: pieces and flasks (frozen pieces too) drop straight down to the lowest free open
    /// cells, keeping their order — passing behind crates and across holes; nothing slides
    /// diagonally (v1). Then, from the RNG: while flasks are owed (`flasksSpawned < drops.total`) and
    /// fewer than `drops.maxOnBoard` are on the board, a flask goes to the TOP empty cell of a column
    /// drawn uniformly from the allowed columns with an empty cell; then every remaining empty open
    /// cell gets a uniform kind from `level.kinds`, columns left → right, cells bottom → top.
    mutating func settle() -> M3Settle {
        var falls: [M3Fall] = []
        let w = board.width
        var columns: [[M3Pos]] = []
        for c in 0..<w {
            let open = board.openCells(column: c)
            columns.append(open)
            var write = open.count - 1
            for k in stride(from: open.count - 1, through: 0, by: -1) {
                let p = open[k]
                guard let item = board[p].item else { continue }
                if k != write {
                    board[open[write]].item = item
                    board[p].item = nil
                    falls.append(M3Fall(from: p, to: open[write], item: item))
                }
                write -= 1
            }
        }
        var spawned = Set<M3Pos>()
        if let d = level.drops {
            let allowed = (d.columns ?? Array(0..<w)).filter { (0..<w).contains($0) }
            var onBoard = board.flaskCount
            while flasksSpawned < d.total && onBoard < d.maxOnBoard {
                let candidates = Array(Set(allowed)).sorted().filter { c in columns[c].contains { board[$0].item == nil } }
                if candidates.isEmpty { break }
                let c = candidates[rng.nextInt(below: candidates.count)]
                let top = columns[c].first { board[$0].item == nil }!
                board[top].item = .flask
                spawned.insert(top)
                flasksSpawned += 1
                onBoard += 1
            }
        }
        var spawns: [M3Spawn] = []
        for c in 0..<w {
            var column: [(M3Pos, M3Item)] = []
            for p in columns[c].reversed() {
                if board[p].item == nil {
                    let k = level.kinds[rng.nextInt(below: level.kinds.count)]
                    board[p].item = .piece(M3Piece(kind: k))
                    column.append((p, board[p].item!))
                } else if spawned.contains(p) {
                    column.append((p, .flask))
                }
            }
            for (rank, (p, item)) in column.enumerated() {
                spawns.append(M3Spawn(at: p, item: item, rank: rank, columnCount: column.count))
            }
        }
        return M3Settle(falls: falls, spawns: spawns)
    }

    /// Removes every flask resting on its column's bottom open cell.
    mutating func collectFlasks() -> [M3Pos] {
        var out: [M3Pos] = []
        for c in 0..<board.width {
            if let b = board.bottomOpenCell(column: c), board[b].item == .flask {
                board[b].item = nil
                flasksCollected += 1
                score += M3Rules.Points.flask
                out.append(b)
            }
        }
        return out
    }

    // MARK: Reshuffle

    /// Rearranges the unfrozen pieces (specials included; frozen pieces, flasks and crates stay):
    /// up to `reshuffleAttempts` Fisher–Yates shuffles from the stream, the first with no match and a
    /// valid swap wins. Failing that, plain unfrozen pieces get new kinds (start-board rule, columns
    /// left → right, bottom → top) until the board has a valid swap. nil if both fail.
    mutating func reshuffle() -> M3Reshuffle? {
        let original = board
        let movable = original.cells.indices.filter { original.cells[$0].piece.map { !$0.isFrozen } ?? false }
        let items = movable.map { original.cells[$0].item! }
        if movable.count >= 2 {
            for _ in 0..<M3Rules.reshuffleAttempts {
                var perm = Array(movable.indices)
                rng.shuffle(&perm)
                var b = original
                for (j, cell) in movable.enumerated() { b.cells[cell].item = items[perm[j]] }
                if !M3Rules.hasMatch(b) && M3Rules.hasValidSwap(b) {
                    board = b
                    var moves: [M3Fall] = []
                    for (j, cell) in movable.enumerated() where perm[j] != j {
                        moves.append(M3Fall(from: original.pos(movable[perm[j]]), to: original.pos(cell), item: items[perm[j]]))
                    }
                    return M3Reshuffle(moves: moves, rerolled: [])
                }
            }
        }
        for _ in 0..<M3Rules.reshuffleAttempts {
            var b = original
            var rerolled: [M3SpecialPiece] = []
            for c in 0..<b.width {
                for r in stride(from: b.height - 1, through: 0, by: -1) {
                    guard let p = b[r, c].piece, !p.isFrozen, p.special == nil else { continue }
                    b[r, c].item = nil
                    let k = M3Game.drawKind(on: b, at: M3Pos(r, c), kinds: level.kinds, rng: &rng)
                    b[r, c].item = .piece(M3Piece(kind: k))
                    if k != p.kind { rerolled.append(M3SpecialPiece(at: M3Pos(r, c), piece: M3Piece(kind: k))) }
                }
            }
            if !M3Rules.hasMatch(b) && M3Rules.hasValidSwap(b) {
                board = b
                return M3Reshuffle(moves: [], rerolled: rerolled)
            }
        }
        return nil
    }

    // MARK: Finale

    /// "Bubbling Over": after a win, each leftover move picks a random plain unfrozen piece (uniform,
    /// row-major list) and a random special (comet row / comet column / bloom, uniform), turns the
    /// piece into it and fires it at once; cascades resolve as usual, plus a flat bonus per burst.
    /// Uses the level's stream after the last swap. Does nothing unless won and not yet played.
    @discardableResult
    public mutating func playFinale() -> M3Finale {
        let start = score
        var bursts: [M3FinaleBurst] = []
        guard status == .won, !finalePlayed else {
            return M3Finale(bursts: [], scoreGained: 0, finalScore: score, stars: stars)
        }
        finalePlayed = true
        let specials: [M3Special] = [.row, .column, .bloom]
        while movesLeft > 0 {
            let candidates = board.cells.indices.filter {
                guard let p = board.cells[$0].piece else { return false }
                return !p.isFrozen && p.special == nil && p.kind != nil
            }
            if candidates.isEmpty { break }
            movesLeft -= 1
            let before = score
            let i = candidates[rng.nextInt(below: candidates.count)]
            let sp = specials[rng.nextInt(below: specials.count)]
            var piece = board.cells[i].piece!
            piece.special = sp
            board.cells[i].item = .piece(piece)
            var phases: [M3Phase] = [.wave(resolveWave(cascade: 1, groups: [], initial: [(i, true)]))]
            runCascades(after: 1, into: &phases)
            score += M3Rules.Points.finaleBurst
            bursts.append(M3FinaleBurst(at: board.pos(i), special: sp, phases: phases, scoreGained: score - before))
        }
        return M3Finale(bursts: bursts, scoreGained: score - start, finalScore: score, stars: stars)
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
