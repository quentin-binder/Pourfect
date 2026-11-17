import BottleSortCore

/// Every match-3 rule (DECISIONS 252–). Board-level functions are pure; `M3Game` drives them.
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
