import BottleSortCore

/// What a channel (or a target flask) holds.
public enum DistillLiquid: Hashable, Sendable {
    case dry
    case liquid(ColorID)
    /// Two colors met here: the channel turns murky and passes nothing on.
    case murky

    public var color: ColorID? { if case .liquid(let c) = self { return c } else { return nil } }
    public var isWet: Bool { self != .dry }
}

/// One liquid channel of a cell after evaluation (a cross has two, everything else one).
public struct DistillNodeFlow: Hashable, Sendable {
    public var pos: DistillPos
    /// 0, or 1 for a cross's east–west pipe.
    public var channel: Int
    /// Openings of this channel.
    public var mask: UInt8
    public var liquid: DistillLiquid
    /// Color at each opening (index = `DistillDir.rawValue`): differs from `liquid` only on a heat coil
    /// (its exit sides carry the heated color) and on a shut valve (only the sides liquid reached).
    /// nil on dry or murky sides and on sides without an opening.
    public var sideColors: [ColorID?]
    /// Sides the liquid came in through (empty for a source and for dry channels); the app animates
    /// the fill from these sides towards the others.
    public var entry: UInt8
    /// Animation time: the step at which liquid first reaches this channel (sources 0), counted across
    /// the valve stages; -1 when dry. Neighbours along a flow path differ by one.
    public var tick: Int
    /// A valve that is (still) shut at the end.
    public var shutValve: Bool
}

/// Liquid spilling out of an open pipe end (drips).
public struct DistillLeak: Hashable, Sendable {
    public var pos: DistillPos
    public var side: DistillDir
    /// nil when murky liquid leaks.
    public var color: ColorID?
    public var tick: Int
}

/// Two different colors meeting across the shared side of two cells (`pos` and its neighbour in `side`).
public struct DistillSeam: Hashable, Sendable {
    public var pos: DistillPos
    public var side: DistillDir
}

/// The flow of a static board configuration. Rules (DECISIONS 271):
/// - Every source fills the channels connected to it, one step per channel (breadth first, all sources at once).
/// - Liquid passes into a neighbour only through two facing openings. A target flask takes liquid in and passes
///   nothing on; a cap ends a line without leaking; a shut valve takes liquid in up to its gate on each side
///   and passes nothing; a heat coil passes `from` on as `to`.
/// - Murk: a channel reached in the same step by two different colors turns murky and passes nothing on; two
///   wet channels whose facing sides hold different colors meet in a murky seam.
/// - Leak: a wet channel's opening that faces the edge, an empty cell or a side without a facing opening.
/// - Valves are a fixpoint: all start shut; after each evaluation every valve whose target flask holds its own
///   color opens (and stays open); repeat until nothing opens.
/// - Won: no leak, no murky channel or seam, every target holds exactly its own color. Dry pieces are fine.
public struct DistillFlow: Hashable, Sendable {
    public var nodes: [DistillNodeFlow]
    public var leaks: [DistillLeak]
    public var seams: [DistillSeam]
    /// Per target flask (same order as the board's targets).
    public var received: [DistillLiquid]
    /// Per valve (row-major, `DistillBoard.valvePositions`): the stage at which it opened (1…), nil if shut.
    public var valveOpenedAt: [DistillPos: Int]
    /// Number of evaluations the valve fixpoint took (1 = no valve opened).
    public var stages: Int

    public var isWon: Bool

    public var murkyCount: Int { nodes.filter { $0.liquid == .murky }.count + seams.count }
    public var satisfiedTargets: Int { received.indices.filter { received[$0].color == targetColors[$0] }.count }
    var targetColors: [ColorID]

    /// The channel of `pos` that has an opening on `side` (nil if none).
    public func node(at pos: DistillPos, side: DistillDir) -> DistillNodeFlow? {
        nodes.first { $0.pos == pos && DistillMask.has($0.mask, side) }
    }

    /// The channels of a cell (one, two for a cross, none for an empty cell).
    public func nodes(at pos: DistillPos) -> [DistillNodeFlow] { nodes.filter { $0.pos == pos } }

    public func isValveOpen(at pos: DistillPos) -> Bool { valveOpenedAt[pos] != nil }

    /// The wet channels as `pos`/`channel` pairs (to diff two evaluations).
    public var wetNodes: Set<DistillNodeRef> {
        Set(nodes.filter { $0.liquid.isWet }.map { DistillNodeRef(pos: $0.pos, channel: $0.channel) })
    }

    public static func evaluate(_ board: DistillBoard) -> DistillFlow {
        DistillNet(board).evaluate()
    }
}

/// A channel of a cell.
public struct DistillNodeRef: Hashable, Sendable, Comparable {
    public var pos: DistillPos
    public var channel: Int
    public init(pos: DistillPos, channel: Int) {
        self.pos = pos
        self.channel = channel
    }
    public static func < (a: DistillNodeRef, b: DistillNodeRef) -> Bool { (a.pos, a.channel) < (b.pos, b.channel) }
}

extension DistillBoard {
    public var flow: DistillFlow { DistillFlow.evaluate(self) }
    public var isWon: Bool { DistillNet(self).isWon() }
}

// MARK: - Evaluation

/// Flat arrays for fast evaluation. Node id = cell * 2 + channel.
struct DistillNet {
    let w: Int, h: Int, n: Int
    var nodeMask: [UInt8]          // 2n
    var sourceColor: [Int]          // per cell, -1
    var targetIndex: [Int]          // per cell, -1
    var valveTarget: [Int]          // per cell, -1
    var coil: [DistillCoil?]        // per cell
    let targets: [DistillTarget]
    let sources: [DistillSource]

    init(_ board: DistillBoard) {
        w = board.width
        h = board.height
        n = w * h
        nodeMask = Array(repeating: 0, count: 2 * n)
        sourceColor = Array(repeating: -1, count: n)
        targetIndex = Array(repeating: -1, count: n)
        valveTarget = Array(repeating: -1, count: n)
        coil = Array(repeating: nil, count: n)
        targets = board.targets
        sources = board.sources
        for i in 0..<n {
            let p = board.pieces[i]
            let ch = p.channels
            for (k, m) in ch.enumerated() { nodeMask[2 * i + k] = m }
            if let v = p.valve { valveTarget[i] = v }
            coil[i] = p.coil
        }
        for s in sources {
            let i = s.pos.r * w + s.pos.c
            nodeMask[2 * i] = s.outlet.bit
            nodeMask[2 * i + 1] = 0
            sourceColor[i] = s.color.rawValue
            valveTarget[i] = -1
            coil[i] = nil
        }
        for (k, t) in targets.enumerated() {
            let i = t.pos.r * w + t.pos.c
            nodeMask[2 * i] = t.inlet.bit
            nodeMask[2 * i + 1] = 0
            targetIndex[i] = k
            valveTarget[i] = -1
            coil[i] = nil
        }
    }

    /// Sets a single-channel piece's openings (solver leaves).
    mutating func setMask(cell: Int, _ mask: UInt8) {
        nodeMask[2 * cell] = mask
        nodeMask[2 * cell + 1] = 0
    }

    @inline(__always) func neighbor(_ node: Int, _ d: Int) -> Int {
        let cell = node >> 1
        let r = cell / w + [-1, 0, 1, 0][d], c = cell % w + [0, 1, 0, -1][d]
        guard r >= 0, r < h, c >= 0, c < w else { return -1 }
        let q = r * w + c
        let ob = UInt8(1 << ((d + 2) & 3))
        if nodeMask[2 * q] & ob != 0 { return 2 * q }
        if nodeMask[2 * q + 1] & ob != 0 { return 2 * q + 1 }
        return -1
    }

    struct Pass {
        var wave: [Int]
        var color: [Int]        // -1 murky / dry
        var murky: [Bool]
        var entry: [UInt8]
        var sideIn: [Int]       // 4 per node, shut valves only (-1 none)
        var shut: [Bool]        // per node: a shut valve
    }

    /// One breadth-first evaluation with the given valves open (per cell).
    func run(open: [Bool]) -> Pass {
        let nn = 2 * n
        var p = Pass(wave: Array(repeating: -1, count: nn), color: Array(repeating: -1, count: nn),
                     murky: Array(repeating: false, count: nn), entry: Array(repeating: 0, count: nn),
                     sideIn: Array(repeating: -1, count: 4 * nn), shut: Array(repeating: false, count: nn))
        for cell in 0..<n where valveTarget[cell] >= 0 && !open[cell] {
            p.shut[2 * cell] = true
            p.shut[2 * cell + 1] = true
        }
        var current: [Int] = []
        for s in sources {
            let node = 2 * (s.pos.r * w + s.pos.c)
            p.wave[node] = 0
            p.color[node] = s.color.rawValue
            current.append(node)
        }
        var d = 0
        var arrivalColor = Array(repeating: -1, count: nn)
        var conflict = Array(repeating: false, count: nn)
        while !current.isEmpty {
            var touched: [Int] = []
            for u in current {
                if p.murky[u] || p.shut[u] { continue }
                let cell = u >> 1
                if targetIndex[cell] >= 0 { continue }
                let e = coil[cell].map { $0.apply(ColorID(p.color[u])).rawValue } ?? p.color[u]
                let mask = nodeMask[u]
                for dir in 0..<4 where mask & (1 << dir) != 0 && p.entry[u] & (1 << dir) == 0 {
                    let v = neighbor(u, dir)
                    guard v >= 0 else { continue }
                    let side = (dir + 2) & 3
                    if p.shut[v] && p.sideIn[4 * v + side] < 0 { p.sideIn[4 * v + side] = e }
                    if p.wave[v] == -1 {
                        p.wave[v] = d + 1
                        arrivalColor[v] = e
                        conflict[v] = false
                        p.entry[v] = UInt8(1 << side)
                        touched.append(v)
                    } else if p.wave[v] == d + 1 {
                        p.entry[v] |= UInt8(1 << side)
                        if arrivalColor[v] != e { conflict[v] = true }
                    }
                }
            }
            for v in touched {
                if conflict[v] && !p.shut[v] {
                    p.murky[v] = true
                } else {
                    p.color[v] = arrivalColor[v]
                }
            }
            current = touched
            d += 1
        }
        return p
    }

    /// Color at a node's side after a pass (nil dry / murky / no opening).
    func sideColor(_ p: Pass, _ u: Int, _ dir: Int) -> Int? {
        guard p.wave[u] >= 0, !p.murky[u], nodeMask[u] & (1 << dir) != 0 else { return nil }
        if p.shut[u] { let c = p.sideIn[4 * u + dir]; return c >= 0 ? c : nil }
        if let coil = coil[u >> 1], p.entry[u] & (1 << dir) == 0, sourceColor[u >> 1] < 0 {
            return coil.apply(ColorID(p.color[u])).rawValue
        }
        return p.color[u]
    }

    func received(_ p: Pass, target k: Int) -> DistillLiquid {
        let t = targets[k]
        let node = 2 * (t.pos.r * w + t.pos.c)
        if p.wave[node] < 0 { return .dry }
        if p.murky[node] { return .murky }
        return .liquid(ColorID(p.color[node]))
    }

    /// The valve fixpoint: (final pass, stage each valve opened at, first stage+tick per node, stages).
    func fixpoint() -> (Pass, [Int], [Int], Int) {
        var open = Array(repeating: false, count: n)
        var openedAt = Array(repeating: 0, count: n)
        var tick = Array(repeating: -1, count: 2 * n)
        var base = 0
        var stage = 0
        while true {
            let p = run(open: open)
            var maxTick = base
            for u in 0..<(2 * n) where p.wave[u] >= 0 && tick[u] < 0 {
                tick[u] = base + p.wave[u]
            }
            for u in 0..<(2 * n) where p.wave[u] >= 0 { maxTick = max(maxTick, tick[u]) }
            stage += 1
            var opened = false
            for cell in 0..<n where valveTarget[cell] >= 0 && !open[cell] {
                let k = valveTarget[cell]
                guard k < targets.count else { continue }
                if received(p, target: k) == .liquid(targets[k].color) {
                    open[cell] = true
                    openedAt[cell] = stage
                    opened = true
                }
            }
            if !opened {
                for u in 0..<(2 * n) where p.wave[u] < 0 { tick[u] = -1 }
                return (p, openedAt, tick, stage)
            }
            base = maxTick + 1
        }
    }

    /// Fast win check (no allocation of the result).
    func isWon() -> Bool {
        let (p, _, _, _) = fixpoint()
        return won(p)
    }

    func won(_ p: Pass) -> Bool {
        for (k, t) in targets.enumerated() where received(p, target: k) != .liquid(t.color) { return false }
        for u in 0..<(2 * n) where p.wave[u] >= 0 {
            if p.murky[u] { return false }
            let mask = nodeMask[u]
            for dir in 0..<4 where mask & (1 << dir) != 0 {
                let v = neighbor(u, dir)
                if v < 0 {
                    if targetIndex[u >> 1] >= 0 { continue }
                    if p.shut[u] && p.sideIn[4 * u + dir] < 0 { continue }
                    return false
                }
                if v > u, let a = sideColor(p, u, dir), let b = sideColor(p, v, (dir + 2) & 3), a != b { return false }
            }
        }
        return true
    }

    func evaluate() -> DistillFlow {
        let (p, openedAt, tick, stages) = fixpoint()
        var nodes: [DistillNodeFlow] = []
        var leaks: [DistillLeak] = []
        var seams: [DistillSeam] = []
        func pos(_ cell: Int) -> DistillPos { DistillPos(cell / w, cell % w) }
        for u in 0..<(2 * n) where nodeMask[u] != 0 {
            let liquid: DistillLiquid = p.wave[u] < 0 ? .dry : (p.murky[u] ? .murky : .liquid(ColorID(p.color[u])))
            var sides: [ColorID?] = [nil, nil, nil, nil]
            for dir in 0..<4 { sides[dir] = sideColor(p, u, dir).map { ColorID($0) } }
            nodes.append(DistillNodeFlow(pos: pos(u >> 1), channel: u & 1, mask: nodeMask[u], liquid: liquid,
                                         sideColors: sides, entry: p.entry[u], tick: tick[u], shutValve: p.shut[u]))
            guard p.wave[u] >= 0 else { continue }
            for dir in 0..<4 where nodeMask[u] & (1 << dir) != 0 {
                let v = neighbor(u, dir)
                if v < 0 {
                    if targetIndex[u >> 1] >= 0 { continue }
                    if p.shut[u] && p.sideIn[4 * u + dir] < 0 { continue }
                    leaks.append(DistillLeak(pos: pos(u >> 1), side: DistillDir(rawValue: dir)!,
                                             color: sideColor(p, u, dir).map { ColorID($0) }, tick: tick[u] + 1))
                } else if v > u, p.wave[v] >= 0, let a = sideColor(p, u, dir), let b = sideColor(p, v, (dir + 2) & 3), a != b {
                    seams.append(DistillSeam(pos: pos(u >> 1), side: DistillDir(rawValue: dir)!))
                }
            }
        }
        var opened: [DistillPos: Int] = [:]
        for cell in 0..<n where openedAt[cell] > 0 { opened[pos(cell)] = openedAt[cell] }
        let received = targets.indices.map { self.received(p, target: $0) }
        let won = leaks.isEmpty && seams.isEmpty && !nodes.contains { $0.liquid == .murky }
            && targets.indices.allSatisfy { received[$0] == .liquid(targets[$0].color) }
        return DistillFlow(nodes: nodes, leaks: leaks, seams: seams, received: received, valveOpenedAt: opened,
                           stages: stages, isWon: won, targetColors: targets.map(\.color))
    }
}
