import Foundation
import Testing
@testable import BottleSortCore

@Suite struct SolverTests {
    /// Hand-made puzzles with their optimal length (verified against the
    /// naive reference BFS, and the first two by hand).
    static let known: [(bottles: [[Int]], capacity: Int, minMoves: Int)] = [
        ([[0, 1], [1, 0], []], 2, 3),
        ([[0, 0, 1], [1, 1, 0], []], 3, 3),
        ([[0, 1, 0, 1], [1, 0, 1, 0], [], []], 4, 7),
        ([[0, 1, 2], [2, 0, 1], [1, 2, 0], []], 3, 7),
        ([[0, 1, 2, 0], [1, 2, 0, 1], [2, 0, 1, 2], [], []], 4, 10),
    ]

    @Test(arguments: SolverTests.known.indices)
    func findsKnownOptimum(_ i: Int) throws {
        let puzzle = Self.known[i]
        let start = state(puzzle.bottles, capacity: puzzle.capacity)
        let moves = try #require(Solver().solve(start).moves)
        #expect(moves.count == puzzle.minMoves)
        #expect(referenceMinMoves(start) == puzzle.minMoves)
    }

    @Test func alreadySolved() {
        let result = Solver().solve(state([[0, 0], [1, 1], []], capacity: 2))
        #expect(result == .solved(moves: [], statesExplored: 1))
    }

    @Test func unsolvableNoMoves() {
        let result = Solver().solve(state([[0, 1, 2], [1, 2, 0], [2, 0, 1]], capacity: 3))
        guard case .unsolvable = result else { Issue.record("expected unsolvable, got \(result)"); return }
    }

    @Test func unsolvableWithMoves() {
        // Valid level, several legal first moves, but every line runs out of room.
        let start = state([[1, 2, 2], [0, 2, 0], [1, 1, 0], []], capacity: 3)
        #expect(start.validate().isEmpty)
        #expect(start.legalMoves().count >= 2)
        #expect(referenceMinMoves(start) == nil)
        guard case .unsolvable = Solver().solve(start) else { Issue.record("expected unsolvable"); return }
    }

    @Test func stateLimitGivesUnknown() {
        let start = Generator.candidate(GeneratorConfig(colors: 6), seed: 3)
        let result = Solver().solve(start, limits: SolverLimits(maxStates: 10))
        #expect(result == .unknown(reason: .stateLimit(statesExplored: 10)))
    }

    @Test func timeoutGivesUnknown() {
        let start = Generator.candidate(GeneratorConfig(colors: 8), seed: 3)
        let result = Solver().solve(start, limits: SolverLimits(timeout: .zero))
        guard case .unknown(.timeout) = result else { Issue.record("expected timeout, got \(result)"); return }
    }

    /// Pruning safety: on many random small puzzles the solver's optimum equals
    /// the unpruned, uncanonicalized reference BFS, and its moves replay to a win.
    @Test(arguments: [(3, 3, 2), (3, 4, 2), (4, 3, 2), (3, 4, 1), (4, 4, 1)])
    func matchesReferenceAndReplays(colors: Int, capacity: Int, empty: Int) {
        let config = GeneratorConfig(colors: colors, capacity: capacity, emptyBottles: empty)
        for seed in UInt64(1)...25 {
            let start = Generator.candidate(config, seed: seed)
            let reference = referenceMinMoves(start)
            switch Solver().solve(start) {
            case .solved(let moves, _):
                #expect(moves.count == reference, "seed \(seed)")
                var s = start
                for move in moves {
                    guard let next = s.pouring(move) else { Issue.record("illegal move \(move), seed \(seed)"); return }
                    s = next
                }
                #expect(s.isSolved, "seed \(seed)")
            case .unsolvable:
                #expect(reference == nil, "seed \(seed)")
            case .unknown(let reason):
                Issue.record("unknown \(reason), seed \(seed)")
            }
        }
    }

    @Test func eightColorPerformance() throws {
        // Spec target is < 2 s in release; this debug-build test uses a loose bound.
        let start = Generator.candidate(GeneratorConfig(colors: 8), seed: 1)
        let clock = ContinuousClock()
        var result: SolverResult?
        let elapsed = clock.measure { result = Solver().solve(start) }
        #expect(try #require(result).moves != nil)
        #expect(elapsed < .seconds(10))
    }
}

@Suite struct HintTests {
    @Test func hintIsFirstOptimalMove() {
        let start = state([[0, 1], [1, 0], []], capacity: 2)
        guard case .move(let move) = Solver().hint(for: start) else { Issue.record("no hint"); return }
        let after = start.pouring(move)!
        #expect(Solver().solve(after).moves?.count == 2)
    }

    @Test func hintReportsUnsolvable() {
        #expect(Solver().hint(for: state([[0, 1], [1, 0]], capacity: 2)) == .unsolvable)
    }

    @Test func hintWhenSolved() {
        #expect(Solver().hint(for: state([[0, 0], []], capacity: 2)) == .alreadySolved)
    }
}

@Suite struct CanonicalKeyTests {
    @Test func permutedBottlesGiveEqualKeys() {
        let a = state([[0, 1, 2, 0], [1, 2, 0, 1], [2, 0, 1, 2], [], []])
        let b = state([[], [2, 0, 1, 2], [0, 1, 2, 0], [], [1, 2, 0, 1]])
        #expect(a.canonicalKey == b.canonicalKey)
    }

    @Test func differentStatesGiveDifferentKeys() {
        #expect(state([[0, 1], [1, 0]], capacity: 2).canonicalKey != state([[1, 0], [1, 0]], capacity: 2).canonicalKey)
        // Layer order within a bottle matters.
        #expect(state([[0, 1], []], capacity: 2).canonicalKey != state([[1, 0], []], capacity: 2).canonicalKey)
    }

    @Test func lockIdentityIsPartOfKey() {
        var a = state([[0], [1], []])
        var b = a
        a.bottles[0].lockedBy = 1
        b.bottles[0].lockedBy = 2
        #expect(a.canonicalKey != b.canonicalKey)
        #expect(a.canonicalKey != state([[0], [1], []]).canonicalKey)
        // A locked bottle moved to another position still matches.
        var c = state([[1], [], [0]])
        c.bottles[2].lockedBy = 1
        #expect(a.canonicalKey == c.canonicalKey)
    }
}

@Suite struct DifficultyTests {
    @Test func reportFields() throws {
        let start = state([[0, 1, 0, 1], [1, 0, 1, 0], [], []])
        let report = try #require(Difficulty.analyze(start))
        #expect(report.minMoves == 7)
        #expect(report.statesExplored > 0)
        #expect((0...1).contains(report.deadEndRatio))
        #expect(report.branchingFactor > 0)
        #expect(report.score == Difficulty.score(minMoves: report.minMoves, statesExplored: report.statesExplored,
                                                 deadEndRatio: report.deadEndRatio, branchingFactor: report.branchingFactor))
        guard case .exact = report.deadEndMethod else { Issue.record("expected exact dead-end ratio"); return }
    }

    @Test func deadEndRatioExact() {
        // Two solvable states only matter here: a 2-bottle puzzle with no moves is all dead ends.
        let (ratio, _) = Difficulty.deadEndRatio(state([[0, 1], [1, 0]], capacity: 2), minMoves: 0, sampleSeed: 0)
        #expect(ratio == 1)
        let (zero, _) = Difficulty.deadEndRatio(state([[0, 0, 1], [1, 1, 0], []], capacity: 3), minMoves: 3, sampleSeed: 0)
        #expect(zero >= 0 && zero < 1)
    }

    @Test func unsolvableHasNoReport() {
        #expect(Difficulty.analyze(state([[0, 1], [1, 0]], capacity: 2)) == nil)
    }
}

@Suite struct GeneratorTests {
    @Test func rngIsDeterministic() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        for _ in 0..<100 { #expect(a.next() == b.next()) }
        // Known first value of SplitMix64(seed: 0), from the reference implementation.
        var z = SplitMix64(seed: 0)
        #expect(z.next() == 0xE220_A839_7B1D_CDAF)
    }

    @Test func candidateHasCorrectShape() {
        let config = GeneratorConfig(colors: 5, capacity: 4, emptyBottles: 2)
        let s = Generator.candidate(config, seed: 7)
        #expect(s.bottles.count == 7)
        #expect(s.validate().isEmpty)
        #expect(s.bottles.filter(\.isEmpty).count == 2)
    }

    @Test func sameSeedSameLevel() throws {
        let config = GeneratorConfig(colors: 5, seed: 99, minMoves: 12...15)
        let a = try Generator.generate(config)
        let b = try Generator.generate(config)
        #expect(a == b)
        #expect(Generator.candidate(config, seed: 5) == Generator.candidate(config, seed: 5))
        #expect(Generator.candidate(config, seed: 5) != Generator.candidate(config, seed: 6))
    }

    @Test func generatedLevelsMeetConstraints() throws {
        let config = GeneratorConfig(colors: 4, seed: 1, minMoves: 10...12)
        let levels = try Generator.generate(config, count: 5)
        #expect(Set(levels.map(\.seed)).count == 5)
        for level in levels {
            #expect(level.state.validate().isEmpty)
            #expect((10...12).contains(level.report.minMoves))
            #expect(!level.state.bottles.contains { !$0.isEmpty && $0.isSolved })
            #expect(Solver().solve(level.state).moves?.count == level.report.minMoves)
        }
    }

    @Test func rejectsPresolvedBottle() {
        let config = GeneratorConfig(colors: 2, capacity: 2, emptyBottles: 1)
        #expect(Generator.evaluate(state([[0, 0], [1, 1], []], capacity: 2), config: config, seed: 0) == nil)
    }

    @Test func impossibleConstraintsThrow() {
        let config = GeneratorConfig(colors: 3, minMoves: 50...60, maxAttempts: 20)
        #expect(throws: GeneratorError.noLevelFound(attempts: 20)) { try Generator.generate(config) }
    }
}

@Suite struct LevelFileTests {
    static let packURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Levels/pack_01.json")

    @Test func decodesSpecExample() throws {
        let json = """
        {"version": 1, "levels": [{"id": "p1_001", "capacity": 4,
          "bottles": [{"layers": [0, 1, 1, 2]}, {"layers": [2, 0, 1, 0]}, {"layers": [1, 2, 2, 0]}, {"layers": []}, {"layers": []}],
          "meta": {"seed": 12345, "minMoves": 11, "score": 23.4}}]}
        """
        let pack = try LevelLoader.load(Data(json.utf8))
        let level = try #require(pack.levels.first)
        #expect(level.id == "p1_001")
        #expect(level.gameState.bottles[0] == Bottle([0, 1, 1, 2], capacity: 4))
        #expect(level.meta?.minMoves == 11)
    }

    @Test func roundTrip() throws {
        var s = state([[0, 1, 0, 1], [1, 0, 1, 0], [], []])
        s.bottles[3].lockedBy = 2
        let pack = LevelPack(levels: [LevelDefinition(id: "x", state: s, meta: LevelMeta(seed: 1, minMoves: 7))])
        let data = try LevelLoader.encode(pack)
        #expect(String(decoding: data, as: UTF8.self).contains("[0, 1, 0, 1]"))
        #expect(try LevelLoader.load(data) == pack)
    }

    @Test func rejectsInvalidLevel() {
        let json = #"{"version": 1, "levels": [{"id": "bad", "capacity": 2, "bottles": [{"layers": [0, 1]}, {"layers": [1]}]}]}"#
        #expect(throws: LevelLoadError.self) { try LevelLoader.load(Data(json.utf8)) }
    }

    @Test func rejectsUnknownVersionAndDuplicates() {
        let v2 = #"{"version": 2, "levels": []}"#
        #expect(throws: LevelLoadError.unsupportedVersion(2)) { try LevelLoader.load(Data(v2.utf8)) }
        let dup = #"{"version": 1, "levels": [{"id": "a", "capacity": 1, "bottles": [{"layers": [0]}]}, {"id": "a", "capacity": 1, "bottles": [{"layers": [0]}]}]}"#
        #expect(throws: LevelLoadError.duplicateID("a")) { try LevelLoader.load(Data(dup.utf8)) }
    }

    @Test func starterPackLoadsValidatesAndSolves() throws {
        let pack = try LevelLoader.load(contentsOf: Self.packURL)
        #expect((35...45).contains(pack.levels.count))
        for level in pack.levels {
            let moves = try #require(Solver().solve(level.gameState).moves, "\(level.id) not solved")
            #expect(moves.count == level.meta?.minMoves, "\(level.id)")
        }
    }
}
