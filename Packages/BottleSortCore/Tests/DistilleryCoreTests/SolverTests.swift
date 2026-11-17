import BottleSortCore
import Testing
@testable import DistilleryCore

@Suite struct SolverTests {
    @Test func oneTurn() {
        let b = board(["S I0 F"], sources: [(0, 0, 0, .east)], targets: [(0, 2, 0, .west)])
        let r = DistillSolver.solve(b)
        #expect(r.isUnique)
        #expect(r.minTaps == 1)
        #expect(r.best?.turns.map(\.pos) == [P(0, 1)])
        #expect(r.best.map { $0.apply(to: b).isWon } == true)
    }

    @Test func counterClockwiseCountsOne() {
        // Elbow needs rotation 2 from 1 (one cw tap) / from 3 (one ccw tap) / from 0 (two taps).
        for (start, taps) in [(1, 1), (3, 1), (0, 2), (2, 0)] {
            var b = board(["S L2", ". F"], sources: [(0, 0, 3, .east)], targets: [(1, 1, 3, .north)])
            b[P(0, 1)].rotation = start
            if taps == 0 { #expect(b.isWon) } else { #expect(DistillSolver.minTaps(b) == taps) }
        }
        var b = board(["S L2", ". F"], sources: [(0, 0, 3, .east)], targets: [(1, 1, 3, .north)])
        b[P(0, 1)].rotation = 3
        #expect(DistillSolver.hint(b) == DistillTap(P(0, 1), clockwise: false))
    }

    @Test func rivetedPieceCanBlock() {
        let b = board(["S I0* F"], sources: [(0, 0, 0, .east)], targets: [(0, 2, 0, .west)])
        let r = DistillSolver.solve(b)
        #expect(r.solutionCount == 0)
        #expect(r.minTaps == nil)
    }

    @Test func twoRoutesAreCounted() {
        // Around either side of a cap: two networks of different cost.
        let b = board(["L1 I1 L2", "S C0* F", "L0 I1 L3"], sources: [(1, 0, 0, .north)], targets: [(1, 2, 0, .north)])
        let r = DistillSolver.solve(b)
        #expect(r.solutionCount == 1)
        let both = board(["L1 I1 L2", "S . F", "L0 I1 L3"], sources: [(1, 0, 0, .east)], targets: [(1, 2, 0, .west)])
        #expect(DistillSolver.solve(both).solutionCount == 0)
    }

    @Test func deadlockedValveIsNoSolution() {
        let b = board([". F . .", "S T0 I0 F"], sources: [(1, 0, 0, .east)], targets: [(0, 1, 0, .south), (1, 3, 0, .west)],
                      valves: [(1, 2, 1)])
        #expect(DistillSolver.solve(b).solutionCount == 0)
        var ok = b
        ok[P(1, 2)].valve = 0
        let r = DistillSolver.solve(ok)
        #expect(r.isUnique)
        #expect(r.minTaps == 2)  // tee 0 → 3 (one ccw), straight 0 → 1
    }

    @Test func coilRouteIsForced() {
        // Red source, orange flask: only the route through the coil works.
        let rows = ["L1 I0 L2", "S . F", "L0 I0 L3"]
        let b = board(rows, sources: [(1, 0, 0, .north)], targets: [(1, 2, 5, .north)], coils: [(0, 1, 0, 5)])
        let r = DistillSolver.solve(b)
        #expect(r.isUnique)
        #expect(r.minTaps == 1)
        #expect(r.best?.turns.map(\.pos) == [P(0, 1)])
    }

    /// Random tiny boards (≤ 7 rotatable pieces, every mechanic): the solver agrees with brute force on the
    /// number of solved networks and on the fewest taps.
    @Test func agreesWithBruteForce() {
        var rng = SplitMix64(seed: 2026)
        var solvable = 0
        for round in 0..<(heavyTestsEnabled ? 300 : 60) {
            let b = round % 2 == 0 ? randomTinyBoard(&rng) : generatedTinyBoard(&rng)
            let ref = DistillSolver.reference(b)
            let r = DistillSolver.solve(b, countLimit: 10_000)
            #expect(r.complete)
            #expect(r.solutionCount == ref.networks, "round \(round)")
            #expect(r.minTaps == ref.minTaps, "round \(round)")
            if let best = r.best { #expect(best.apply(to: b).isWon) }
            if ref.minTaps != nil { solvable += 1 }
        }
        #expect(solvable > (heavyTestsEnabled ? 100 : 15))
    }

    @Test func hintStartsTheCheapestWin() {
        let b = board(["S I0 L0", ". . I0", ". F L0"], sources: [(0, 0, 0, .east)], targets: [(2, 1, 0, .east)])
        var cur = b
        var taps = 0
        while !cur.isWon, let h = DistillSolver.hint(cur), taps < 20 {
            cur[h.pos].rotation = (cur[h.pos].rotation + (h.clockwise ? 1 : 3)) % 4
            taps += 1
        }
        #expect(cur.isWon)
        #expect(taps == DistillSolver.minTaps(b))
    }
}

/// 3×3 / 4×3 boards with random pieces, 1–2 sources and 1–2 targets, sometimes a coil or a valve; pieces beyond
/// the seventh rotatable one are riveted.
func randomTinyBoard(_ rng: inout SplitMix64) -> DistillBoard {
    let w = 3 + rng.nextInt(below: 2), h = 3
    var cells = Array(0..<(w * h))
    rng.shuffle(&cells)
    let colors: [ColorID] = [0, 1, 5]
    func dirInto(_ cell: Int) -> DistillDir {
        let r = cell / w, c = cell % w
        let ok = DistillDir.allCases.filter { d in (0..<h).contains(r + d.dr) && (0..<w).contains(c + d.dc) }
        return ok[rng.nextInt(below: ok.count)]
    }
    let nSources = 1 + rng.nextInt(below: 2), nTargets = 1 + rng.nextInt(below: 2)
    var sources: [DistillSource] = []
    var targets: [DistillTarget] = []
    for k in 0..<nSources {
        let cell = cells[k]
        sources.append(DistillSource(pos: DistillPos(cell / w, cell % w), color: colors[rng.nextInt(below: 2)], outlet: dirInto(cell)))
    }
    for k in 0..<nTargets {
        let cell = cells[nSources + k]
        targets.append(DistillTarget(pos: DistillPos(cell / w, cell % w), color: colors[rng.nextInt(below: 3)], inlet: dirInto(cell)))
    }
    let shapes: [DistillShape] = [.empty, .cap, .straight, .straight, .elbow, .elbow, .elbow, .tee, .tee, .cross]
    var pieces = Array(repeating: DistillPiece.empty, count: w * h)
    var rotatable = 0
    for cell in cells.dropFirst(nSources + nTargets) {
        var p = DistillPiece(shapes[rng.nextInt(below: shapes.count)], rotation: rng.nextInt(below: 4))
        if p.isRotatable {
            if rotatable >= 7 || rng.nextInt(below: 8) == 0 { p.fixed = true } else { rotatable += 1 }
        }
        if [.straight, .elbow, .tee].contains(p.shape) {
            let roll = rng.nextInt(below: 12)
            if roll == 0 { p.coil = DistillCoil(from: 0, to: 5) }
            if roll == 1 { p.valve = rng.nextInt(below: nTargets) }
        }
        pieces[cell] = p
    }
    return DistillBoard(width: w, height: h, pieces: pieces, sources: sources, targets: targets)
}

/// A generated 3×3…4×4 level, then pieces beyond the seventh rotatable one riveted as they lie, and sometimes a
/// coil or valve added to a random piece (which may make it unsolvable: that is checked too).
func generatedTinyBoard(_ rng: inout SplitMix64) -> DistillBoard {
    let w = 3 + rng.nextInt(below: 2), h = 3 + rng.nextInt(below: 2)
    let config = DistillGenConfig(width: w, height: h, targetsPerGroup: 1...(w * h > 9 ? 2 : 1), decoyFill: 50,
                                  decoyShapes: [.straight, .elbow, .tee, .cap, .cross], waypoints: 0...0, taps: 1...6,
                                  maxAttempts: 200)
    guard let level = DistillGenerator.generate(config, seed: rng.next(), id: "tiny") else { return randomTinyBoard(&rng) }
    var b = level.board
    var cells = b.rotatablePositions
    rng.shuffle(&cells)
    for p in cells.dropFirst(7) { b[p].fixed = true }
    let roll = rng.nextInt(below: 6)
    let candidates = (0..<b.cellCount).map(b.pos).filter { [.straight, .elbow, .tee].contains(b[$0].shape) }
    if roll < 2, !candidates.isEmpty {
        let p = candidates[rng.nextInt(below: candidates.count)]
        if roll == 0 {
            b[p].coil = DistillCoil(from: b.sources[0].color, to: 5)
            if rng.nextInt(below: 2) == 0 { b.targets[0].color = 5 }
        } else {
            b[p].valve = rng.nextInt(below: b.targets.count)
        }
    }
    return b
}
