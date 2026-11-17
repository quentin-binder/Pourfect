import BottleSortCore

/// Settings for one generated distillery level (DECISIONS 274).
public struct DistillGenConfig: Sendable, Hashable {
    public var width: Int
    public var height: Int
    /// Networks, one source each, each its own color.
    public var groups: Int
    /// Target flasks per network (more than one makes tee splitters).
    public var targetsPerGroup: ClosedRange<Int>
    /// Crossings wanted: at least `crosses.lowerBound` (routes are nudged towards them when > 0).
    public var crosses: ClosedRange<Int>
    /// Riveted pieces in the network / among the decoys.
    public var fixedNetwork: Int
    public var fixedDecoys: Int
    /// May rivet a network piece to remove a second solution (counts on top of `fixedNetwork`).
    public var repairWithRivets: Bool
    public var valves: Int
    public var coils: Int
    /// Tee branches ending in a cap.
    public var capStubs: Int
    /// Percent of the free cells that get a decoy piece (the rest stay empty).
    public var decoyFill: Int
    /// Decoy shapes, repeated for weight.
    public var decoyShapes: [DistillShape]
    /// Detours per main path (random waypoints).
    public var waypoints: ClosedRange<Int>
    /// Random extra step cost per cell (wigglier routes when higher).
    public var noise: Int
    /// Accepted minimum taps.
    public var taps: ClosedRange<Int>
    /// Fewest pieces the solved network must use (longer, wigglier routes).
    public var minNetwork: Int
    /// Attempts before giving up.
    public var maxAttempts: Int
    public var limits: DistillSolverLimits

    public init(width: Int, height: Int, groups: Int = 1, targetsPerGroup: ClosedRange<Int> = 1...1,
                crosses: ClosedRange<Int> = 0...0, fixedNetwork: Int = 0, fixedDecoys: Int = 0, repairWithRivets: Bool = false,
                valves: Int = 0, coils: Int = 0, capStubs: Int = 0, decoyFill: Int = 70,
                decoyShapes: [DistillShape] = [.straight, .elbow, .elbow, .cap],
                waypoints: ClosedRange<Int> = 0...1, noise: Int = 3, taps: ClosedRange<Int> = 3...8, minNetwork: Int = 0,
                maxAttempts: Int = 60, limits: DistillSolverLimits = .init(maxNodes: 200_000)) {
        self.width = width
        self.height = height
        self.groups = groups
        self.targetsPerGroup = targetsPerGroup
        self.crosses = crosses
        self.fixedNetwork = fixedNetwork
        self.fixedDecoys = fixedDecoys
        self.repairWithRivets = repairWithRivets
        self.valves = valves
        self.coils = coils
        self.capStubs = capStubs
        self.decoyFill = decoyFill
        self.decoyShapes = decoyShapes
        self.waypoints = waypoints
        self.noise = noise
        self.taps = taps
        self.minNetwork = minNetwork
        self.maxAttempts = maxAttempts
        self.limits = limits
    }
}

/// Builds levels: route networks (paths from each source to its targets, tee branches, crossings, cap stubs),
/// colors and coils, valves, rivets, decoys; insist on one solved network (repairing decoys that allow a second);
/// then scramble rotations to a tap count inside the window. Deterministic for a seed (integer maths, arrays only).
public enum DistillGenerator {
    /// Heat-coil recipes (cauldron colors): red → orange, blue → purple, yellow → green.
    public static let heatRecipes: [(from: ColorID, to: ColorID)] = [(0, 5), (1, 4), (2, 3)]
    /// Network colors, in preference order (the coil outputs come last).
    static let colorPool: [ColorID] = [0, 1, 2, 7, 6, 9, 8, 3, 4, 5]

    /// One level, or nil after `maxAttempts` failed attempts.
    public static func generate(_ config: DistillGenConfig, seed: UInt64, id: String, title: String? = nil) -> DistillLevel? {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<config.maxAttempts {
            let attemptSeed = rng.next()
            if var level = attempt(config, seed: attemptSeed) {
                level.id = id
                level.title = title
                return level
            }
        }
        return nil
    }

    /// Difficulty score: taps + 3 per solver branch point + 2 per mechanic + network size / 3 + decoys / 4.
    public static func score(minTaps: Int, decisions: Int, mechanics: Int, networkCells: Int, decoys: Int) -> Int {
        minTaps + 3 * decisions + 2 * mechanics + networkCells / 3 + decoys / 4
    }

    // MARK: Attempt

    struct Build {
        let w: Int, h: Int
        var masks: [[UInt8]]        // per cell: channel masks (network)
        var reserved: [Bool]        // sources, targets, ports
        var sources: [DistillSource] = []
        var targets: [DistillTarget] = []
        var targetGroup: [Int] = []
        var sourcePorts: [Int] = []
        var targetPorts: [Int] = []
        var groupOf: [Int]          // per cell (single-channel network cells), -1
        var crossings = 0

        init(w: Int, h: Int) {
            self.w = w
            self.h = h
            masks = Array(repeating: [], count: w * h)
            reserved = Array(repeating: false, count: w * h)
            groupOf = Array(repeating: -1, count: w * h)
        }

        func neighbor(_ cell: Int, _ d: Int) -> Int {
            let r = cell / w + [-1, 0, 1, 0][d], c = cell % w + [0, 1, 0, -1][d]
            guard r >= 0, r < h, c >= 0, c < w else { return -1 }
            return r * w + c
        }

        func isFree(_ cell: Int) -> Bool { !reserved[cell] && masks[cell].isEmpty }
    }

    static func attempt(_ config: DistillGenConfig, seed: UInt64) -> DistillLevel? {
        var rng = SplitMix64(seed: seed)
        let w = config.width, h = config.height
        var b = Build(w: w, h: h)
        let groups = config.groups
        var targetCounts: [Int] = []
        for _ in 0..<groups {
            targetCounts.append(config.targetsPerGroup.lowerBound + rng.nextInt(below: config.targetsPerGroup.count))
        }
        // 1. Sources and targets on the rim, facing in.
        var rim: [(cell: Int, dir: Int)] = []
        for r in 0..<h {
            for c in 0..<w {
                var dirs: [Int] = []
                if r == 0 { dirs.append(2) }
                if r == h - 1 { dirs.append(0) }
                if c == 0 { dirs.append(1) }
                if c == w - 1 { dirs.append(3) }
                for d in dirs { rim.append((r * w + c, d)) }
            }
        }
        func place() -> (cell: Int, dir: Int)? {
            var options = rim.filter { cand in
                guard !b.reserved[cand.cell] else { return false }
                let port = b.neighbor(cand.cell, cand.dir)
                guard port >= 0, !b.reserved[port] else { return false }
                // Keep sources/targets apart: no reserved cell next to this one or its port.
                for d in 0..<4 {
                    let n1 = b.neighbor(cand.cell, d)
                    if n1 >= 0 && b.reserved[n1] { return false }
                    let n2 = b.neighbor(port, d)
                    if n2 >= 0 && n2 != cand.cell && b.reserved[n2] && rng.nextInt(below: 3) == 0 { return false }
                }
                return true
            }
            guard !options.isEmpty else { return nil }
            rng.shuffle(&options)
            return options[0]
        }
        var placedTargets: [[(cell: Int, dir: Int)]] = []
        for g in 0..<groups {
            guard let s = place() else { return nil }
            b.reserved[s.cell] = true
            let port = b.neighbor(s.cell, s.dir)
            b.reserved[port] = true
            b.sources.append(DistillSource(pos: DistillPos(s.cell / w, s.cell % w), color: 0, outlet: DistillDir(rawValue: s.dir)!))
            b.sourcePorts.append(port)
            var ts: [(cell: Int, dir: Int)] = []
            for _ in 0..<targetCounts[g] {
                guard let t = place() else { return nil }
                b.reserved[t.cell] = true
                b.reserved[b.neighbor(t.cell, t.dir)] = true
                ts.append(t)
            }
            placedTargets.append(ts)
        }
        for g in 0..<groups {
            for t in placedTargets[g] {
                b.targets.append(DistillTarget(pos: DistillPos(t.cell / w, t.cell % w), color: 0, inlet: DistillDir(rawValue: t.dir)!))
                b.targetGroup.append(g)
                b.targetPorts.append(b.neighbor(t.cell, t.dir))
            }
        }
        // 2. Routes.
        let wantCross = config.crosses.lowerBound > 0
        for g in 0..<groups {
            let tIdx = b.targets.indices.filter { b.targetGroup[$0] == g }
            let first = tIdx[0]
            // Main path: source port → waypoints → first target's port.
            let sPort = b.sourcePorts[g]
            let sEntry = (b.sources[g].outlet.rawValue + 2) & 3
            let tPort = b.targetPorts[first]
            let tExit = (b.targets[first].inlet.rawValue + 2) & 3
            var stops: [Int] = []
            let nWay = config.waypoints.lowerBound + rng.nextInt(below: config.waypoints.count)
            for _ in 0..<nWay {
                let free = (0..<(w * h)).filter { b.isFree($0) && !stops.contains($0) }
                guard !free.isEmpty else { break }
                stops.append(free[rng.nextInt(below: free.count)])
            }
            var cell = sPort, entry = sEntry
            b.reserved[sPort] = false
            b.reserved[tPort] = false
            for (k, stop) in (stops + [-1]).enumerated() {
                let last = k == stops.count
                let goal: (Build, Int, Int) -> Bool = last
                    ? { _, c, x in c == tPort && x == tExit }
                    : { bb, c, x in bb.neighbor(c, x) == stop }
                guard let steps = route(&b, from: cell, entry: entry, group: g, goal: goal, avoid: last ? -1 : tPort,
                                        cross: wantCross, noise: config.noise, rng: &rng) else { return nil }
                if last { break }
                let lastStep = steps.last!
                cell = stop
                entry = (lastStep.exit + 2) & 3
            }
            // Branches: from each further target's port back to the network of this group.
            for t in tIdx.dropFirst() {
                let port = b.targetPorts[t]
                b.reserved[port] = false
                let toward = (b.targets[t].inlet.rawValue + 2) & 3
                let goal: (Build, Int, Int) -> Bool = { bb, c, x in
                    let e = bb.neighbor(c, x)
                    guard e >= 0, bb.groupOf[e] == g, bb.masks[e].count == 1 else { return false }
                    let m = bb.masks[e][0]
                    return m.nonzeroBitCount == 2 && m & UInt8(1 << ((x + 2) & 3)) == 0
                }
                guard let steps = route(&b, from: port, entry: toward, group: g, goal: goal, avoid: -1,
                                        cross: wantCross, noise: config.noise, rng: &rng) else { return nil }
                let lastStep = steps.last!
                let e = b.neighbor(lastStep.cell, lastStep.exit)
                b.masks[e][0] |= UInt8(1 << ((lastStep.exit + 2) & 3))
            }
            // The port cells open towards their target / from their source.
            _ = port(&b, sPort, sEntry)
            for t in tIdx { _ = port(&b, b.targetPorts[t], (b.targets[t].inlet.rawValue + 2) & 3) }
        }
        if b.crossings < config.crosses.lowerBound || b.crossings > config.crosses.upperBound { return nil }
        // 3. Cap stubs.
        for _ in 0..<config.capStubs {
            var options: [(Int, Int)] = []
            for e in 0..<(w * h) where b.groupOf[e] >= 0 && b.masks[e].count == 1 && b.masks[e][0].nonzeroBitCount == 2 {
                for d in 0..<4 where b.masks[e][0] & UInt8(1 << d) == 0 {
                    let q = b.neighbor(e, d)
                    if q >= 0 && b.isFree(q) { options.append((e, d)) }
                }
            }
            guard !options.isEmpty else { return nil }
            let (e, d) = options[rng.nextInt(below: options.count)]
            let q = b.neighbor(e, d)
            b.masks[e][0] |= UInt8(1 << d)
            b.masks[q] = [UInt8(1 << ((d + 2) & 3))]
            b.groupOf[q] = b.groupOf[e]
        }
        if (0..<(w * h)).filter({ !b.masks[$0].isEmpty }).count < config.minNetwork { return nil }
        // 4. Pieces for the network.
        var pieces = Array(repeating: DistillPiece.empty, count: w * h)
        var network = Array(repeating: false, count: w * h)
        for i in 0..<(w * h) where !b.masks[i].isEmpty {
            network[i] = true
            if b.masks[i].count == 2 {
                pieces[i] = DistillPiece(.cross)
            } else {
                guard let (shape, r) = DistillShape.shape(forMask: b.masks[i][0]) else { return nil }
                pieces[i] = DistillPiece(shape, rotation: r)
            }
        }
        // 5. Colors and coils (flow tree from each source).
        var board = DistillBoard(width: w, height: h, pieces: pieces, sources: b.sources, targets: b.targets)
        let tree = flowTree(board)
        var coilGroups: [Int] = []
        if config.coils > 0 {
            var gs = Array(0..<groups)
            rng.shuffle(&gs)
            coilGroups = Array(gs.prefix(min(config.coils, groups, heatRecipes.count)))
        }
        var recipes = heatRecipes.map { $0 }
        rng.shuffle(&recipes)
        var groupColor = Array(repeating: ColorID(0), count: groups)
        var used: [ColorID] = []
        for (k, g) in coilGroups.enumerated() {
            groupColor[g] = recipes[k].from
            used.append(recipes[k].from)
            used.append(recipes[k].to)
        }
        var pool = colorPool.filter { !used.contains($0) }
        let head = Array(pool.prefix(max(4, groups)))
        var shuffledHead = head
        rng.shuffle(&shuffledHead)
        pool = shuffledHead + pool.dropFirst(head.count)
        for g in 0..<groups where !coilGroups.contains(g) {
            groupColor[g] = pool.removeFirst()
        }
        for g in 0..<groups { board.sources[g].color = groupColor[g] }
        for t in board.targets.indices { board.targets[t].color = groupColor[b.targetGroup[t]] }
        var coilCells: [Int] = []
        var coilsLeft = config.coils
        var coilRound = 0
        while coilsLeft > 0 {
            let g = coilGroups.isEmpty ? -1 : coilGroups[coilRound % coilGroups.count]
            coilRound += 1
            if g < 0 || coilRound > 3 * config.coils + 3 { return nil }
            // Cells of this group with two openings whose subtree has targets, no coil above or below.
            var cands: [Int] = []
            for i in 0..<(w * h) where b.groupOf[i] == g && b.masks[i].count == 1 && b.masks[i][0].nonzeroBitCount == 2 {
                if b.sourcePorts.contains(i) { continue }
                let below = tree.targetsBelow[2 * i]
                if below.isEmpty { continue }
                if tree.ancestors(2 * i).contains(where: { coilCells.contains($0 >> 1) }) { continue }
                if coilCells.contains(where: { tree.ancestors(2 * $0).contains(2 * i) }) { continue }
                cands.append(i)
            }
            guard !cands.isEmpty else { return nil }
            let cell = cands[rng.nextInt(below: cands.count)]
            let k = coilGroups.firstIndex(of: g)!
            board.pieces[cell].coil = DistillCoil(from: recipes[k].from, to: recipes[k].to)
            coilCells.append(cell)
            for t in tree.targetsBelow[2 * cell] { board.targets[t].color = recipes[k].to }
            coilsLeft -= 1
        }
        // 6. Valves.
        for _ in 0..<config.valves {
            var cands: [(Int, Int)] = []
            for i in 0..<(w * h) where b.groupOf[i] >= 0 && b.masks[i].count == 1 && b.masks[i][0].nonzeroBitCount == 2 {
                if board.pieces[i].coil != nil || board.pieces[i].valve != nil { continue }
                let below = tree.targetsBelow[2 * i]
                if below.isEmpty { continue }
                for t in board.targets.indices where !below.contains(t) { cands.append((i, t)) }
            }
            guard !cands.isEmpty else { return nil }
            let (cell, t) = cands[rng.nextInt(below: cands.count)]
            board.pieces[cell].valve = t
        }
        // 7. Rivets in the network.
        var netCells = (0..<(w * h)).filter { network[$0] && board.pieces[$0].isRotatable }
        rng.shuffle(&netCells)
        for cell in netCells.prefix(config.fixedNetwork) { board.pieces[cell].fixed = true }
        // 8. Decoys.
        var decoyCells: [Int] = []
        for i in 0..<(w * h) where !network[i] && b.isFree(i) {
            guard rng.nextInt(below: 100) < config.decoyFill, !config.decoyShapes.isEmpty else { continue }
            let shape = config.decoyShapes[rng.nextInt(below: config.decoyShapes.count)]
            board.pieces[i] = DistillPiece(shape, rotation: rng.nextInt(below: 4))
            decoyCells.append(i)
        }
        var fixable = decoyCells.filter { board.pieces[$0].shape != .cross }
        rng.shuffle(&fixable)
        for cell in fixable.prefix(config.fixedDecoys) { board.pieces[cell].fixed = true }
        // The solved board must win (valves open in some order, coils right).
        guard board.flow.isWon else { return nil }
        // 9. One solved network: repair decoys (or rivet) that allow another.
        let intended: [UInt8] = (0..<(w * h)).map { network[$0] && board.pieces[$0].isRotatable ? board.pieces[$0].mask : 0xFF }
        var changed = Array(repeating: 0, count: w * h)
        var unique = false
        for _ in 0..<16 {
            let result = DistillSolver.solve(board, limits: config.limits)
            guard result.complete else { return nil }
            if result.solutionCount == 1 { unique = true; break }
            guard let alt = result.solutions.first(where: { sol in
                (0..<(w * h)).contains { (sol.masks[$0] ?? 0xFF) != (board.pieces[$0].isRotatable ? intended[$0] : 0xFF) }
            }) else { return nil }
            let usedDecoys = (0..<(w * h)).filter { !network[$0] && alt.masks[$0] != nil }
            if !usedDecoys.isEmpty {
                let cell = usedDecoys[rng.nextInt(below: usedDecoys.count)]
                changed[cell] += 1
                if changed[cell] >= 2 || board.pieces[cell].shape == .cap {
                    board.pieces[cell] = .empty
                } else {
                    let others = config.decoyShapes.filter { $0 != board.pieces[cell].shape && $0 != .cross }
                    board.pieces[cell] = others.isEmpty ? .empty
                        : DistillPiece(others[rng.nextInt(below: others.count)], rotation: rng.nextInt(below: 4))
                }
                continue
            }
            guard config.repairWithRivets else { return nil }
            let differing = (0..<(w * h)).filter { network[$0] && board.pieces[$0].isRotatable && alt.masks[$0] != intended[$0] }
            guard !differing.isEmpty else { return nil }
            board.pieces[differing[rng.nextInt(below: differing.count)]].fixed = true
        }
        guard unique else { return nil }
        // 10. Scramble to a tap count in the window.
        let turnable = (0..<(w * h)).filter { network[$0] && board.pieces[$0].isRotatable }
        let solvedRotation = turnable.map { board.pieces[$0].rotation }
        func cost(_ k: Int, _ r: Int) -> Int {
            board.pieces[turnable[k]].shape == .straight ? r % 2 == solvedRotation[k] % 2 ? 0 : 1
                : distillTapCost(from: r, to: solvedRotation[k])
        }
        let maxCost = turnable.indices.map { board.pieces[turnable[$0]].shape == .straight ? 1 : 2 }
        let maxTotal = maxCost.reduce(0, +)
        guard config.taps.lowerBound <= maxTotal else { return nil }
        let goal = min(config.taps.lowerBound + rng.nextInt(below: config.taps.count), maxTotal)
        var rot = turnable.indices.map { _ in rng.nextInt(below: 4) }
        var total = turnable.indices.map { cost($0, rot[$0]) }.reduce(0, +)
        var guardSteps = 0
        while total != goal && guardSteps < 1000 {
            guardSteps += 1
            let k = rng.nextInt(below: turnable.count)
            let c = cost(k, rot[k])
            if total > goal && c > 0 {
                // One quarter turn towards the solution.
                let forward = (rot[k] + 1) % 4, back = (rot[k] + 3) % 4
                rot[k] = cost(k, forward) < c ? forward : back
                total -= 1
            } else if total < goal && c < maxCost[k] {
                let forward = (rot[k] + 1) % 4, back = (rot[k] + 3) % 4
                let options = [forward, back].filter { cost(k, $0) == c + 1 }
                rot[k] = options[rng.nextInt(below: options.count)]
                total += 1
            }
        }
        guard total == goal, goal >= 1 else { return nil }
        for (k, cell) in turnable.enumerated() { board.pieces[cell].rotation = rot[k] }
        // 11. Final solve for the record.
        let final = DistillSolver.solve(board, limits: config.limits)
        guard final.isUnique, let minTaps = final.minTaps, config.taps.contains(minTaps), !board.flow.isWon else { return nil }
        let decoys = (0..<(w * h)).filter { !network[$0] && board.pieces[$0].shape != .empty && !b.reserved[$0] }.count
        var mechanics: [String] = []
        if pieces.contains(where: { $0.shape == .tee }) { mechanics.append("tee") }
        if b.crossings > 0 { mechanics.append("cross") }
        if board.pieces.contains(where: { $0.fixed }) { mechanics.append("fixed") }
        if board.pieces.contains(where: { $0.valve != nil }) { mechanics.append("valve") }
        if board.pieces.contains(where: { $0.coil != nil }) { mechanics.append("coil") }
        if config.capStubs > 0 { mechanics.append("cap") }
        if groups > 1 { mechanics.append("colors\(groups)") }
        let netCount = network.filter { $0 }.count
        let stats = DistillStats(seed: seed, networkCells: netCount, decoys: decoys, decisions: final.decisions, nodes: final.nodes,
                                 mechanics: mechanics,
                                 score: score(minTaps: minTaps, decisions: final.decisions, mechanics: mechanics.count,
                                              networkCells: netCount, decoys: decoys))
        return DistillLevel(id: "", board: board, minTaps: minTaps, stats: stats)
    }

    /// Marks a port cell's opening (start/end of a route) — already in its mask; kept for clarity.
    static func port(_ b: inout Build, _ cell: Int, _ dir: Int) -> Bool {
        guard !b.masks[cell].isEmpty else { return false }
        b.masks[cell][0] |= UInt8(1 << dir)
        return true
    }

    struct Step {
        var cell: Int
        var entry: Int
        var exit: Int
    }

    /// Cheapest route (Dijkstra over cells, random step costs) starting in `from` (entered through `entry`)
    /// until `goal(cell, exit)` holds; may cross straight network pipes of other routes at right angles.
    /// Writes the route's openings into the build.
    static func route(_ b: inout Build, from start: Int, entry: Int, group: Int, goal: (Build, Int, Int) -> Bool, avoid: Int,
                      cross: Bool, noise: Int, rng: inout SplitMix64) -> [Step]? {
        let n = b.w * b.h
        guard b.isFree(start) else { return nil }
        var cost = Array(repeating: 1, count: n)
        for i in 0..<n { cost[i] = 2 + (noise > 0 ? rng.nextInt(below: noise + 1) : 0) }
        let crossCost = cross ? 0 : 6
        var dist = Array(repeating: Int.max, count: n)
        var ent = Array(repeating: -1, count: n)
        var pred = Array(repeating: -1, count: n)
        var via = Array(repeating: -1, count: n)
        var done = Array(repeating: false, count: n)
        dist[start] = 0
        ent[start] = entry
        func crossable(_ q: Int, _ x: Int) -> Bool {
            guard b.masks[q].count == 1, b.groupOf[q] >= 0 else { return false }
            let perpendicular: UInt8 = x % 2 == 0 ? 0b1010 : 0b0101
            return b.masks[q][0] == perpendicular && !b.sourcePorts.contains(q) && !b.targetPorts.contains(q)
        }
        var end: (cell: Int, exit: Int)?
        while end == nil {
            var c = -1
            for i in 0..<n where !done[i] && dist[i] != Int.max && (c < 0 || dist[i] < dist[c]) { c = i }
            guard c >= 0 else { return nil }
            done[c] = true
            let exits = [0, 1, 2, 3].filter { $0 != ent[c] }
            for x in exits where goal(b, c, x) { end = (c, x); break }
            if end != nil { break }
            for x in exits {
                let q = b.neighbor(c, x)
                guard q >= 0, q != avoid else { continue }
                let turn = x == (ent[c] + 2) & 3 ? 0 : 1
                if b.isFree(q) {
                    let d = dist[c] + cost[q] + turn
                    if !done[q] && d < dist[q] { dist[q] = d; ent[q] = (x + 2) & 3; pred[q] = c; via[q] = -1 }
                } else if crossable(q, x) {
                    let q2 = b.neighbor(q, x)
                    guard q2 >= 0, q2 != avoid, b.isFree(q2) else { continue }
                    let d = dist[c] + cost[q] + cost[q2] + crossCost + turn
                    if !done[q2] && d < dist[q2] { dist[q2] = d; ent[q2] = (x + 2) & 3; pred[q2] = c; via[q2] = q }
                }
            }
        }
        guard let (lastCell, lastExit) = end else { return nil }
        // Rebuild the path.
        var cells: [Int] = []
        var cur = lastCell
        while cur >= 0 { cells.append(cur); cur = pred[cur] }
        cells.reverse()
        var seen = Set<Int>()
        for c in cells where !seen.insert(c).inserted { return nil }
        var steps: [Step] = []
        for (k, c) in cells.enumerated() {
            let exit: Int
            if k + 1 < cells.count {
                exit = (ent[cells[k + 1]] + 2) & 3
            } else {
                exit = lastExit
            }
            steps.append(Step(cell: c, entry: ent[c], exit: exit))
        }
        // Crossings used twice are refused.
        var crossCells: [Int] = []
        for c in cells where via[c] >= 0 {
            if crossCells.contains(via[c]) { return nil }
            crossCells.append(via[c])
        }
        for s in steps {
            b.masks[s.cell] = [UInt8(1 << s.entry) | UInt8(1 << s.exit)]
            b.groupOf[s.cell] = group
        }
        for q in crossCells {
            b.masks[q].append(b.masks[q][0] == 0b1010 ? 0b0101 : 0b1010)
            b.groupOf[q] = -2
            b.crossings += 1
        }
        return steps
    }

    // MARK: Flow tree of the solved network

    struct Tree {
        var parent: [Int]               // per node
        var targetsBelow: [[Int]]       // per node
        func ancestors(_ node: Int) -> [Int] {
            var out: [Int] = []
            var u = parent[node]
            while u >= 0 { out.append(u); u = parent[u] }
            return out
        }
    }

    /// Breadth-first tree of the solved board from the sources, with the targets under each node.
    static func flowTree(_ board: DistillBoard) -> Tree {
        let net = DistillNet(board)
        let nn = 2 * board.cellCount
        var parent = Array(repeating: -1, count: nn)
        var seen = Array(repeating: false, count: nn)
        var queue: [Int] = []
        for s in board.sources {
            let u = 2 * board.index(s.pos)
            seen[u] = true
            queue.append(u)
        }
        var head = 0
        while head < queue.count {
            let u = queue[head]
            head += 1
            for d in 0..<4 where net.nodeMask[u] & (1 << d) != 0 {
                let v = net.neighbor(u, d)
                if v >= 0 && !seen[v] { seen[v] = true; parent[v] = u; queue.append(v) }
            }
        }
        var below = Array(repeating: [Int](), count: nn)
        for (k, t) in board.targets.enumerated() {
            var u = 2 * board.index(t.pos)
            while u >= 0 { below[u].append(k); u = parent[u] }
        }
        return Tree(parent: parent, targetsBelow: below)
    }
}
