import BottleSortCore

/// Every match-3 rule (DECISIONS 251–263): pure board functions here, and the rules that change a
/// game (start board, clear waves, gravity and refill, reshuffle, finale) in the `M3Game` extension below. Board-level functions are pure; `M3Game` drives them.
public enum M3Rules {
    // MARK: Scoring

    public enum Points {
        /// Per cleared piece, times the cascade multiplier min(cascade, 5).
        public static let piece = 30
        public static let maxMultiplier = 5
        /// Per special that fires.
        public static let activation = 40
        public static let createdComet = 60
        public static let createdBloom = 90
        public static let createdPrism = 150
        /// Per frost layer or crate hit.
        public static let obstacleHit = 50
        /// Per potion flask collected.
        public static let flask = 500
        /// Flat bonus per finale burst (plus whatever it clears).
        public static let finaleBurst = 100

        public static func created(_ s: M3Special) -> Int {
            switch s {
            case .row, .column: createdComet
            case .bloom: createdBloom
            case .prism: createdPrism
            }
        }
    }

    /// Safety cap on cascades per swap (never reached in practice; refills are random).
    public static let maxCascades = 200
    /// Reshuffle tries: rearrangements first, then re-rolled kinds.
    public static let reshuffleAttempts = 60
    /// Start-board tries.
    public static let startAttempts = 200

    // MARK: Board from a level

    /// The level's cells without seeded pieces: holes, crates, flasks, empty open cells. Frost layers
    /// are applied when the pieces are placed (`frostLayers(at:)`).
    public static func emptyBoard(_ level: M3Level) -> M3Board {
        let rows = level.layoutChars
        var cells: [M3Cell] = []
        for row in rows {
            for ch in row {
                switch ch {
                case ".": cells.append(M3Cell(exists: false))
                case "A": cells.append(M3Cell(crate: 1))
                case "B": cells.append(M3Cell(crate: 2))
                case "C": cells.append(M3Cell(crate: 3))
                case "F": cells.append(M3Cell(item: .flask))
                default: cells.append(M3Cell())
                }
            }
        }
        return M3Board(width: level.width, height: level.height, cells: cells)
    }

    static func frost(_ ch: Character) -> Int { ch == "1" ? 1 : ch == "2" ? 2 : 0 }

    static func place(_ p: M3PlacedPiece, on board: inout M3Board, layout rows: [[Character]]) {
        board[p.row, p.col].item = .piece(M3Piece(kind: p.special == .prism ? nil : p.kind, special: p.special,
                                                 frost: frost(rows[p.row][p.col])))
    }

    // MARK: Matches

    @inline(__always) static func kindIndex(_ cell: M3Cell) -> Int {
        guard case .piece(let p)? = cell.item, let k = p.kind else { return -1 }
        return k.index
    }

    /// Every match group on the board. Runs are maximal straight lines of 3+ pieces of one kind
    /// (frozen pieces and comets/blooms count with their kind; prisms, flasks, crates, holes and
    /// empty cells break runs). Runs sharing a cell form one group. Groups come in row-major order of
    /// their first cell.
    ///
    /// Special made by a group: a run of 5+ → prism; else crossing runs → bloom; else a run of 4 →
    /// comet. It is placed at the swap's `to` cell if the group has it, else at its `from` cell; in a
    /// cascade a bloom goes to the lowest (then leftmost) crossing cell, the others to the lowest (then
    /// leftmost) cell of the group. A frozen cell is skipped for the lowest-then-leftmost unfrozen one.
    /// A swap-made comet clears along the swap's axis (horizontal swap → row); a cascade comet clears
    /// across its run (a horizontal run → column).
    public static func findGroups(_ board: M3Board, swap: M3Swap?) -> [M3MatchGroup] {
        let w = board.width, h = board.height, n = w * h
        var kinds = [Int](repeating: -1, count: n)
        for i in 0..<n { kinds[i] = kindIndex(board.cells[i]) }
        var runs: [(cells: [Int], horizontal: Bool)] = []
        for r in 0..<h {
            var c = 0
            while c < w {
                let k = kinds[r * w + c]
                var e = c
                while e + 1 < w && k >= 0 && kinds[r * w + e + 1] == k { e += 1 }
                if k >= 0 && e - c >= 2 { runs.append(((c...e).map { r * w + $0 }, true)) }
                c = e + 1
            }
        }
        for c in 0..<w {
            var r = 0
            while r < h {
                let k = kinds[r * w + c]
                var e = r
                while e + 1 < h && k >= 0 && kinds[(e + 1) * w + c] == k { e += 1 }
                if k >= 0 && e - r >= 2 { runs.append(((r...e).map { $0 * w + c }, false)) }
                r = e + 1
            }
        }
        if runs.isEmpty { return [] }
        // Union runs sharing a cell.
        var parent = Array(runs.indices)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        var owner = [Int](repeating: -1, count: n)
        for (ri, run) in runs.enumerated() {
            for i in run.cells {
                if owner[i] >= 0 { parent[find(ri)] = find(owner[i]) } else { owner[i] = ri }
            }
        }
        var byRoot: [Int: [Int]] = [:]
        var rootOrder: [Int] = []
        for ri in runs.indices {
            let root = find(ri)
            if byRoot[root] == nil { rootOrder.append(root) }
            byRoot[root, default: []].append(ri)
        }
        var groups: [(first: Int, group: M3MatchGroup)] = []
        for root in rootOrder {
            let members = byRoot[root]!
            var cellSet = Set<Int>()
            var hCells = Set<Int>(), vCells = Set<Int>()
            var maxLen = 0
            var longest = members[0]
            for ri in members {
                for i in runs[ri].cells {
                    cellSet.insert(i)
                    if runs[ri].horizontal { hCells.insert(i) } else { vCells.insert(i) }
                }
                if runs[ri].cells.count > maxLen { maxLen = runs[ri].cells.count; longest = ri }
            }
            let cells = cellSet.sorted()
            let kind = M3Kind(index: kinds[cells[0]])!
            let hasH = !hCells.isEmpty, hasV = !vCells.isEmpty
            let shape: M3MatchGroup.Shape = maxLen >= 5 ? .five : (hasH && hasV) ? .cross : maxLen == 4 ? .four : .three
            var special: M3Special?
            var at: Int?
            if shape != .three {
                let frozen = { (i: Int) in board.cells[i].piece?.isFrozen ?? false }
                func lowestLeftmost(_ list: [Int]) -> Int? {
                    list.filter { !frozen($0) }.min { a, b in
                        let ra = a / w, rb = b / w
                        return ra != rb ? ra > rb : a % w < b % w
                    }
                }
                var swapMade = false
                if let swap {
                    let to = board.index(swap.to), from = board.index(swap.from)
                    if cellSet.contains(to), !frozen(to) { at = to; swapMade = true } else if cellSet.contains(from), !frozen(from) {
                        at = from; swapMade = true
                    }
                }
                if at == nil {
                    if shape == .cross { at = lowestLeftmost(Array(hCells.intersection(vCells))) }
                    if at == nil { at = lowestLeftmost(cells) }
                }
                switch shape {
                case .five: special = .prism
                case .cross: special = .bloom
                case .four:
                    if swapMade, let swap { special = swap.isHorizontal ? .row : .column } else {
                        special = runs[longest].horizontal ? .column : .row
                    }
                case .three: break
                }
                if at == nil { special = nil }
            }
            let group = M3MatchGroup(kind: kind, cells: cells.map(board.pos), shape: shape, creates: special,
                                     createdAt: at.map(board.pos))
            groups.append((cells[0], group))
        }
        return groups.sorted { $0.first < $1.first }.map(\.group)
    }

    /// Whether any run of 3 exists (cheap check, no groups built).
    public static func hasMatch(_ board: M3Board) -> Bool {
        let w = board.width, h = board.height
        for r in 0..<h {
            for c in 0..<w {
                let k = kindIndex(board[r, c])
                if k < 0 { continue }
                if c + 2 < w, kindIndex(board[r, c + 1]) == k, kindIndex(board[r, c + 2]) == k { return true }
                if r + 2 < h, kindIndex(board[r + 1, c]) == k, kindIndex(board[r + 2, c]) == k { return true }
            }
        }
        return false
    }

    // MARK: Swaps

    /// Whether `swap` is a legal move: two orthogonal neighbours, both unfrozen pieces, and either a
    /// prism is involved, both are specials (comet/bloom), or the swap makes a match through one of them.
    public static func isValidSwap(_ board: M3Board, _ swap: M3Swap) -> Bool {
        guard swap.from.isAdjacent(to: swap.to), board.isSwappable(swap.from), board.isSwappable(swap.to),
              let a = board[swap.from].piece, let b = board[swap.to].piece else { return false }
        if a.isPrism || b.isPrism { return true }
        if a.special != nil && b.special != nil { return true }
        return makesMatch(board, swap)
    }

    /// Whether swapping makes a run of 3 through either cell (ignores specials' combos).
    static func makesMatch(_ board: M3Board, _ swap: M3Swap) -> Bool {
        let ia = board.index(swap.from), ib = board.index(swap.to)
        let w = board.width, h = board.height
        @inline(__always) func k(_ i: Int) -> Int {
            if i == ia { return kindIndex(board.cells[ib]) }
            if i == ib { return kindIndex(board.cells[ia]) }
            return kindIndex(board.cells[i])
        }
        for i in [ia, ib] {
            let kind = k(i)
            if kind < 0 { continue }
            let r = i / w, c = i % w
            var len = 1
            var x = c - 1
            while x >= 0 && k(r * w + x) == kind { len += 1; x -= 1 }
            x = c + 1
            while x < w && k(r * w + x) == kind { len += 1; x += 1 }
            if len >= 3 { return true }
            len = 1
            var y = r - 1
            while y >= 0 && k(y * w + c) == kind { len += 1; y -= 1 }
            y = r + 1
            while y < h && k(y * w + c) == kind { len += 1; y += 1 }
            if len >= 3 { return true }
        }
        return false
    }

    /// Every legal swap, in row-major order of `from`, rightward before downward.
    public static func validSwaps(_ board: M3Board) -> [M3Swap] {
        var result: [M3Swap] = []
        for r in 0..<board.height {
            for c in 0..<board.width {
                let p = M3Pos(r, c)
                guard board.isSwappable(p) else { continue }
                for q in [M3Pos(r, c + 1), M3Pos(r + 1, c)] where board.contains(q) {
                    let s = M3Swap(p, q)
                    if isValidSwap(board, s) { result.append(s) }
                }
            }
        }
        return result
    }

    public static func hasValidSwap(_ board: M3Board) -> Bool {
        for r in 0..<board.height {
            for c in 0..<board.width {
                let p = M3Pos(r, c)
                guard board.isSwappable(p) else { continue }
                for q in [M3Pos(r, c + 1), M3Pos(r + 1, c)] where board.contains(q) {
                    if isValidSwap(board, M3Swap(p, q)) { return true }
                }
            }
        }
        return false
    }

    // MARK: Effects

    /// Existing cells an effect at `at` reaches, row-major.
    public static func cells(of effect: M3Effect, at: M3Pos, on board: M3Board) -> [M3Pos] {
        var out: [M3Pos] = []
        for r in 0..<board.height {
            for c in 0..<board.width where board[r, c].exists {
                let hit: Bool
                switch effect {
                case .row: hit = r == at.row
                case .column: hit = c == at.col
                case .square(let radius): hit = abs(r - at.row) <= radius && abs(c - at.col) <= radius
                case .cross(let width):
                    let half = width / 2
                    hit = abs(r - at.row) <= half || abs(c - at.col) <= half
                case .kind(let k): hit = board[r, c].piece?.kind == k
                case .board: hit = true
                }
                if hit { out.append(M3Pos(r, c)) }
            }
        }
        return out
    }

    /// The effect a lone special fires with. A prism fired by a blast takes the most common kind
    /// among the unfrozen pieces not already cleared (ties: lowest kind index); nil if none is left.
    static func effect(of special: M3Special, board: M3Board, clearing: [UInt8]) -> M3Effect? {
        switch special {
        case .row: return .row
        case .column: return .column
        case .bloom: return .square(radius: 1)
        case .prism:
            var counts = [Int](repeating: 0, count: 6)
            for (i, cell) in board.cells.enumerated() where clearing[i] == 0 {
                if let p = cell.piece, !p.isFrozen, let k = p.kind { counts[k.index] += 1 }
            }
            guard let best = counts.indices.max(by: { counts[$0] < counts[$1] || (counts[$0] == counts[$1] && $0 > $1) }),
                  counts[best] > 0 else { return nil }
            return .kind(M3Kind(index: best)!)
        }
    }

    /// The combo effect of swapping two specials (neither a prism).
    static func comboEffect(_ a: M3Special, _ b: M3Special) -> M3Effect {
        switch (a.isLine, b.isLine) {
        case (true, true): return .cross(width: 1)
        case (false, false): return .square(radius: 2)
        default: return .cross(width: 3)
        }
    }
}

// MARK: - Rules that change a game (start board, waves, gravity and refill, reshuffle, finale)

extension M3Game {
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
}
