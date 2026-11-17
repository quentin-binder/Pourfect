import BottleSortCore

public struct DistillSolverLimits: Sendable, Hashable {
    /// Search nodes before giving up (deterministic; no clock involved).
    public var maxNodes: Int
    public init(maxNodes: Int = 400_000) { self.maxNodes = maxNodes }
}

/// A solved network: the openings every wet rotatable piece must have.
public struct DistillSolution: Hashable, Sendable {
    /// Per cell: the opening mask a rotatable wet piece needs, nil for every other cell (dry pieces may stay).
    public var masks: [UInt8?]
    /// Taps from the board the solver started on.
    public var taps: Int
    /// Turns to make (rotatable pieces not already right), row-major, with their cheapest target rotation.
    public var turns: [(pos: DistillPos, rotation: Int, taps: Int)]

    public static func == (a: DistillSolution, b: DistillSolution) -> Bool { a.masks == b.masks && a.taps == b.taps }
    public func hash(into h: inout Hasher) { h.combine(masks); h.combine(taps) }

    /// The board with every turn made.
    public func apply(to board: DistillBoard) -> DistillBoard {
        var b = board
        for t in turns { b[t.pos].rotation = t.rotation }
        return b
    }
}

public struct DistillSolveResult: Sendable {
    /// Distinct solved networks found, capped at the count limit.
    public var solutionCount: Int
    /// The fewest taps to a win (nil if none found).
    public var minTaps: Int? { best?.taps }
    public var best: DistillSolution?
    /// Up to the count limit of the networks found (first is not necessarily the cheapest).
    public var solutions: [DistillSolution]
    /// Search nodes (counting pass plus the cheapest-search pass, if it ran).
    public var nodes: Int
    /// Branch points of the counting pass: placements where more than one orientation was still possible.
    public var decisions: Int
    /// False when the node limit stopped a pass (counts and minimum may then be incomplete).
    public var complete: Bool

    public var isUnique: Bool { complete && solutionCount == 1 }
}

/// Exact solver (DECISIONS 273). A solution is a closed network grown from every source outlet and target inlet:
/// each placed (wet) piece's openings must face openings of wet neighbours; anything else stays dry and costs
/// nothing. Search: pick the unplaced piece with the fewest orientations that fit its wet neighbours (MRV),
/// propagate, and prune on leaks, on colors meeting inside coil-free stretches (labels from sources and targets)
/// and, when minimizing, on taps so far + the cheapest fit of every pending piece. Every finished network is
/// checked by the full flow evaluation (valves, coils, murk), so the solver agrees with `DistillFlow` exactly.
/// A tap turns a quarter either way, so a piece costs min(k, 4 − k) taps.
public enum DistillSolver {
    /// Counts networks up to `countLimit`; when there is more than one, searches the cheapest separately.
    public static func solve(_ board: DistillBoard, countLimit: Int = 2, limits: DistillSolverLimits = .init()) -> DistillSolveResult {
        var s = Search(board, limits: limits)
        s.countLimit = countLimit
        s.run()
        var result = DistillSolveResult(solutionCount: s.found.count, best: s.bestSolution, solutions: s.found.map { s.solution($0.0) },
                                        nodes: s.nodes, decisions: s.decisions, complete: !s.aborted)
        if s.found.count >= countLimit && !s.aborted || s.aborted {
            var m = Search(board, limits: limits)
            m.minimize = true
            m.run()
            result.nodes += m.nodes
            if m.aborted { result.complete = false }
            if let b = m.bestSolution, result.best == nil || b.taps < result.best!.taps { result.best = b }
        }
        return result
    }

    /// The fewest taps to a win (nil if unsolvable or the limit hit).
    public static func minTaps(_ board: DistillBoard, limits: DistillSolverLimits = .init()) -> Int? {
        var m = Search(board, limits: limits)
        m.minimize = true
        m.run()
        return m.aborted ? nil : m.bestSolution?.taps
    }

    /// A tap that starts the cheapest win: the first piece (row-major) not yet in its solved orientation,
    /// turned the shorter way.
    public static func hint(_ board: DistillBoard, limits: DistillSolverLimits = .init()) -> DistillTap? {
        var m = Search(board, limits: limits)
        m.minimize = true
        m.run()
        guard let best = m.bestSolution, let turn = best.turns.first else { return nil }
        let k = ((turn.rotation - board[turn.pos].rotation) % 4 + 4) % 4
        return DistillTap(turn.pos, clockwise: k != 3)
    }

    /// Brute force over every rotation of every rotatable piece (tests; keep it to ≤ 8 pieces):
    /// distinct winning networks (wet rotatable pieces' masks) and the fewest taps.
    public static func reference(_ board: DistillBoard) -> (networks: Int, minTaps: Int?) {
        let cells = board.rotatablePositions.map(board.index)
        var networks = Set<[UInt8]>()
        var best: Int?
        var net = DistillNet(board)
        let total = 1 << (2 * cells.count)
        for code in 0..<total {
            var cost = 0
            var masks: [UInt8] = []
            for (k, cell) in cells.enumerated() {
                let r = (code >> (2 * k)) & 3
                let piece = board.pieces[cell]
                let m = DistillMask.rotate(piece.shape.baseMask, by: r)
                net.setMask(cell: cell, m)
                masks.append(m)
                cost += distillTapCost(from: piece.rotation, to: r)
            }
            let (pass, _, _, _) = net.fixpoint()
            guard net.won(pass) else { continue }
            networks.insert(cells.indices.map { pass.wave[2 * cells[$0]] >= 0 ? masks[$0] : 0xFF })
            if best == nil || cost < best! { best = cost }
        }
        return (networks.count, best)
    }

    // MARK: Search

    struct Option {
        var mask: UInt8
        var cost: Int
        var rotation: Int
    }

    struct State {
        var mask: [UInt8]   // per cell: rotatable assigned mask, 0xFF unassigned; const cells unused
        var wet: [Bool]     // per node
        var need: [UInt8]   // per cell
        var label: [Int16]  // per node, -1 unknown
        var cost: Int
    }

    struct Search {
        let board: DistillBoard
        let net: DistillNet
        let w: Int, h: Int, n: Int
        let isRot: [Bool]
        let options: [[Option]]
        let staticForbid: [UInt8]
        let isCoil: [Bool]
        let limits: DistillSolverLimits
        var countLimit = 2
        var minimize = false
        var nodes = 0
        var decisions = 0
        var aborted = false
        var found: [([UInt8], Int)] = []
        var bestCost = Int.max
        var bestMasks: [UInt8]?
        var start: State?

        init(_ board: DistillBoard, limits: DistillSolverLimits) {
            self.board = board
            self.limits = limits
            net = DistillNet(board)
            w = board.width
            h = board.height
            n = w * h
            var isRot = Array(repeating: false, count: n)
            var options = Array(repeating: [Option](), count: n)
            var forbid = Array(repeating: UInt8(0), count: n)
            var isCoil = Array(repeating: false, count: n)
            for i in 0..<n {
                let p = board.pieces[i]
                isCoil[i] = p.coil != nil && net.sourceColor[i] < 0 && net.targetIndex[i] < 0
                guard p.isRotatable, net.sourceColor[i] < 0, net.targetIndex[i] < 0 else { continue }
                isRot[i] = true
                var seen: [UInt8] = []
                for r in 0..<4 {
                    let m = DistillMask.rotate(p.shape.baseMask, by: r)
                    if seen.contains(m) { continue }
                    seen.append(m)
                    let t = p.cheapestTurn(to: m)!
                    options[i].append(Option(mask: m, cost: t.taps, rotation: t.rotation))
                }
                options[i].sort { $0.cost < $1.cost }
            }
            for i in 0..<n where isRot[i] {
                let r = i / w, c = i % w
                for d in DistillDir.allCases {
                    let rr = r + d.dr, cc = c + d.dc
                    if rr < 0 || rr >= h || cc < 0 || cc >= w { forbid[i] |= d.bit; continue }
                    let q = rr * w + cc
                    if isRot[q] { continue }
                    let ob = d.opposite.bit
                    if net.nodeMask[2 * q] & ob == 0 && net.nodeMask[2 * q + 1] & ob == 0 { forbid[i] |= d.bit }
                }
            }
            self.isRot = isRot
            self.options = options
            staticForbid = forbid
            self.isCoil = isCoil
        }

        func solution(_ masks: [UInt8]) -> DistillSolution {
            var out = Array(repeating: UInt8?.none, count: n)
            var turns: [(pos: DistillPos, rotation: Int, taps: Int)] = []
            var taps = 0
            for i in 0..<n where isRot[i] && masks[i] != 0xFF {
                out[i] = masks[i]
                let o = options[i].first { $0.mask == masks[i] }!
                if o.cost > 0 {
                    turns.append((board.pos(i), o.rotation, o.cost))
                    taps += o.cost
                }
            }
            return DistillSolution(masks: out, taps: taps, turns: turns)
        }

        var bestSolution: DistillSolution? { bestMasks.map(solution) }

        @inline(__always) func cellNode(_ q: Int, _ bit: UInt8, _ st: State) -> Int {
            if isRot[q] { return st.mask[q] != 0xFF && st.mask[q] & bit != 0 ? 2 * q : -1 }
            if net.nodeMask[2 * q] & bit != 0 { return 2 * q }
            if net.nodeMask[2 * q + 1] & bit != 0 { return 2 * q + 1 }
            return -1
        }

        @inline(__always) func nodeMask(_ u: Int, _ st: State) -> UInt8 {
            isRot[u >> 1] ? (u & 1 == 0 ? st.mask[u >> 1] : 0) : net.nodeMask[u]
        }

        @inline(__always) func neighborCell(_ cell: Int, _ d: Int) -> Int {
            let r = cell / w + [-1, 0, 1, 0][d], c = cell % w + [0, 1, 0, -1][d]
            guard r >= 0, r < h, c >= 0, c < w else { return -1 }
            return r * w + c
        }

        /// Joins the color labels of two connected wet nodes (coils separate stretches).
        func unify(_ a: Int, _ b: Int, _ st: inout State) -> Bool {
            if isCoil[a >> 1] || isCoil[b >> 1] { return true }
            let la = st.label[a], lb = st.label[b]
            if la == lb { return true }
            if la >= 0 && lb >= 0 { return false }
            let (from, color) = la < 0 ? (a, lb) : (b, la)
            var stack = [from]
            st.label[from] = color
            while let x = stack.popLast() {
                let m = nodeMask(x, st)
                for d in 0..<4 where m & (1 << d) != 0 {
                    let q = neighborCell(x >> 1, d)
                    guard q >= 0 else { continue }
                    let y = cellNode(q, UInt8(1 << ((d + 2) & 3)), st)
                    guard y >= 0, st.wet[y], !isCoil[y >> 1] else { continue }
                    if st.label[y] < 0 {
                        st.label[y] = color
                        stack.append(y)
                    } else if st.label[y] != color { return false }
                }
            }
            return true
        }

        /// Marks a constant node wet and follows constant neighbours.
        func addWet(_ node: Int, _ st: inout State) -> Bool {
            st.wet[node] = true
            var stack = [node]
            while let u = stack.popLast() {
                let m = net.nodeMask[u]
                for d in 0..<4 where m & (1 << d) != 0 {
                    let q = neighborCell(u >> 1, d)
                    guard q >= 0 else { return false }
                    let ob = UInt8(1 << ((d + 2) & 3))
                    if isRot[q] {
                        if st.mask[q] != 0xFF {
                            if st.mask[q] & ob == 0 { return false }
                            if !unify(u, 2 * q, &st) { return false }
                        } else {
                            st.need[q] |= ob
                        }
                    } else {
                        let v = cellNode(q, ob, st)
                        guard v >= 0 else { return false }
                        if !st.wet[v] {
                            st.wet[v] = true
                            stack.append(v)
                        }
                        if !unify(u, v, &st) { return false }
                    }
                }
            }
            return true
        }

        func assign(_ q: Int, _ o: Option, _ st: inout State) -> Bool {
            st.mask[q] = o.mask
            st.wet[2 * q] = true
            st.cost += o.cost
            for d in 0..<4 {
                let nb = neighborCell(q, d)
                let bit = UInt8(1 << d), ob = UInt8(1 << ((d + 2) & 3))
                if o.mask & bit != 0 {
                    guard nb >= 0 else { return false }
                    if isRot[nb] {
                        if st.mask[nb] != 0xFF {
                            if st.mask[nb] & ob == 0 { return false }
                            if !unify(2 * q, 2 * nb, &st) { return false }
                        } else {
                            st.need[nb] |= ob
                        }
                    } else {
                        let v = cellNode(nb, ob, st)
                        guard v >= 0 else { return false }
                        if !st.wet[v] { if !addWet(v, &st) { return false } }
                        if !unify(2 * q, v, &st) { return false }
                    }
                } else if nb >= 0 {
                    if isRot[nb] {
                        if st.mask[nb] != 0xFF && st.mask[nb] & ob != 0 { return false }
                    } else {
                        let v = cellNode(nb, ob, st)
                        if v >= 0 && st.wet[v] { return false }
                    }
                }
            }
            return true
        }

        mutating func run() {
            var st = State(mask: Array(repeating: 0xFF, count: n), wet: Array(repeating: false, count: 2 * n),
                           need: Array(repeating: 0, count: n), label: Array(repeating: -1, count: 2 * n), cost: 0)
            for s in board.sources { st.label[2 * board.index(s.pos)] = Int16(s.color.rawValue) }
            for t in board.targets { st.label[2 * board.index(t.pos)] = Int16(t.color.rawValue) }
            for s in board.sources {
                let u = 2 * board.index(s.pos)
                if !st.wet[u] { if !addWet(u, &st) { return } }
            }
            for t in board.targets {
                let u = 2 * board.index(t.pos)
                if !st.wet[u] { if !addWet(u, &st) { return } }
            }
            // Riveted wet pieces are reached through addWet; nothing else to seed.
            dfs(st)
        }

        func dynamicForbid(_ q: Int, _ st: State) -> UInt8 {
            var f = staticForbid[q]
            for d in 0..<4 {
                let nb = neighborCell(q, d)
                guard nb >= 0, isRot[nb], st.mask[nb] != 0xFF else { continue }
                if st.mask[nb] & UInt8(1 << ((d + 2) & 3)) == 0 { f |= UInt8(1 << d) }
            }
            return f
        }

        mutating func dfs(_ st: State) {
            if aborted { return }
            nodes += 1
            if nodes > limits.maxNodes { aborted = true; return }
            if !minimize && found.count >= countLimit { return }
            // Choose the pending piece with the fewest fitting orientations.
            var bestCell = -1
            var bestFits: [Option] = []
            var bound = st.cost
            for q in 0..<n where isRot[q] && st.mask[q] == 0xFF && st.need[q] != 0 {
                let need = st.need[q], forbid = dynamicForbid(q, st)
                var fits: [Option] = []
                for o in options[q] where o.mask & need == need && o.mask & forbid == 0 { fits.append(o) }
                if fits.isEmpty { return }
                bound += fits[0].cost
                if bestCell < 0 || fits.count < bestFits.count {
                    bestCell = q
                    bestFits = fits
                }
            }
            if minimize && bound >= bestCost { return }
            if bestCell < 0 {
                leaf(st)
                return
            }
            if bestFits.count > 1 && !minimize { decisions += 1 }
            for o in bestFits {
                var next = st
                if assign(bestCell, o, &next) { dfs(next) }
                if aborted || (!minimize && found.count >= countLimit) { return }
            }
        }

        mutating func leaf(_ st: State) {
            var leafNet = net
            for q in 0..<n where isRot[q] {
                leafNet.setMask(cell: q, st.mask[q] != 0xFF ? st.mask[q] : board.pieces[q].mask)
            }
            guard leafNet.isWon() else { return }
            if st.cost < bestCost {
                bestCost = st.cost
                bestMasks = st.mask
            }
            if !minimize { found.append((st.mask, st.cost)) }
        }
    }
}
