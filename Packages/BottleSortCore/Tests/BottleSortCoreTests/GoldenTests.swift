import Foundation
import Testing
@testable import BottleSortCore

/// Golden checks recorded before the R4 mechanics refactor: shipped files, canonical keys,
/// generator / random-level output and solver results must stay exactly the same.
/// The expected fingerprints are FNV-1a hashes of a textual dump (see `Golden.dump…`).
enum Golden {
    static func fnv(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }

    static func describe(_ result: SolverResult) -> String {
        switch result {
        case .solved(let moves, let n): return "solved \(n) " + moves.map(\.description).joined(separator: " ")
        case .unsolvable(let n): return "unsolvable \(n)"
        case .unknown(let r): return "unknown \(r)"
        }
    }

    static func describe(_ level: GeneratedLevel) -> String {
        let r = level.report
        return "\(level.seed) \(level.state) \(r.minMoves) \(r.statesExplored) \(r.deadEndRatio) \(r.branchingFactor) \(r.score)"
    }

    static func describe(_ result: RandomLevelResult) -> String {
        var text = result.attempts.map { "\($0.number):\($0.seed):\($0.outcome)" }.joined(separator: ",")
        if let level = result.level {
            text += " \(level.id) \(level.gameState) \(level.isHidden) \(String(describing: level.meta))"
        }
        return text
    }

    static let generatorConfigs: [GeneratorConfig] = [
        GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, seed: 1, minMoves: 8...30),
        GeneratorConfig(colors: 5, capacity: 4, emptyBottles: 1, seed: 40),
        GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 2, locks: 1, seed: 7, requireLocksMatter: true),
        GeneratorConfig(colors: 5, capacity: 4, emptyBottles: 2, locks: 2, seed: 100, minMoves: 10...40,
                        requireLocksMatter: true),
    ]

    static let randomOptions: [(RandomLevelOptions, UInt64)] = [
        (RandomLevelOptions(mode: .classic, colors: 5, capacity: 4, emptyBottles: 2), 11),
        (RandomLevelOptions(mode: .locksAndKeys, colors: 5, capacity: 4, emptyBottles: 2, locks: 2), 12),
        (RandomLevelOptions(mode: .hidden, colors: 4, capacity: 3, emptyBottles: 1), 13),
        (RandomLevelOptions(mode: .classic, colors: 6, capacity: 4, emptyBottles: 1), 14),
    ]

    static func dumpGenerator() throws -> String {
        try generatorConfigs.map { config in
            try Generator.generate(config, count: 3).map(describe).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static func dumpRandom() -> String {
        randomOptions.map { describe(RandomLevel.generate($0.0, seed: $0.1)) }.joined(separator: "\n")
    }

    /// Solver results on raw generator candidates (classic, two seals, one empty flask).
    static func dumpSolver() -> String {
        var lines: [String] = []
        for seed in UInt64(1)...4 {
            lines.append(describe(Solver().solve(Generator.candidate(GeneratorConfig(colors: 7), seed: seed))))
            lines.append(describe(Solver().solve(Generator.candidate(GeneratorConfig(colors: 6, locks: 2), seed: seed))))
            lines.append(describe(Solver().solve(Generator.candidate(GeneratorConfig(colors: 5, emptyBottles: 1), seed: seed))))
        }
        return lines.joined(separator: "\n")
    }

    /// The packs shipped when the R4 golden keys were recorded (later chapters use new
    /// mechanics and have their own tests).
    static let r4Packs = ["chapter_01", "chapter_02", "chapter_03",
                          "challenge_challenger", "challenge_expert", "challenge_master"]

    /// Canonical keys of every level of `r4Packs`.
    static func dumpKeys() throws -> String {
        try r4Packs.map { name in
            try LevelFileTests.load(name).levels.map { level in
                "\(level.id) " + level.gameState.canonicalKey.codes.map { String($0, radix: 16) }.joined(separator: ",")
            }.joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

@Suite struct GoldenTests {
    @Test func generatorOutputUnchanged() throws {
        #expect(Golden.fnv(try Golden.dumpGenerator()) == 14_699_114_120_840_442_546)
    }

    @Test func randomLevelOutputUnchanged() {
        #expect(Golden.fnv(Golden.dumpRandom()) == 16_946_629_798_807_944_383)
    }

    @Test func solverResultsUnchanged() {
        #expect(Golden.fnv(Golden.dumpSolver()) == 15_055_881_682_117_601_570)
    }

    /// Re-recorded after merging main's stronger-lock chapters 2–3 (DECISIONS 104), from
    /// main's pre-R4 code on the same files, so it still pins "keys unchanged by R4".
    @Test func shippedCanonicalKeysUnchanged() throws {
        #expect(Golden.fnv(try Golden.dumpKeys()) == 1_417_387_073_722_927_598)
    }

    /// Re-encoding a shipped pack reproduces the file byte for byte.
    @Test(arguments: LevelFileTests.shippedPacks)
    func shippedFileReencodesIdentically(_ name: String) throws {
        let url = LevelFileTests.levelsDir.appendingPathComponent(name + ".json")
        let data = try Data(contentsOf: url)
        #expect(try LevelLoader.encode(LevelLoader.load(data)) == data)
    }
}
