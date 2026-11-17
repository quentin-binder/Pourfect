import BottleSortCore
import Foundation
import Testing
@testable import DistilleryCore

@Suite struct GeneratorTests {
    static let configs: [DistillGenConfig] = [
        DistillGenConfig(width: 4, height: 4, taps: 2...5),
        DistillGenConfig(width: 5, height: 5, targetsPerGroup: 2...2, fixedNetwork: 2, fixedDecoys: 1, repairWithRivets: true,
                         capStubs: 1, taps: 5...12),
        DistillGenConfig(width: 6, height: 6, groups: 2, crosses: 1...2, decoyFill: 90, taps: 8...16, minNetwork: 14),
        DistillGenConfig(width: 7, height: 7, groups: 2, targetsPerGroup: 1...2, fixedNetwork: 1, repairWithRivets: true,
                         valves: 1, coils: 1, decoyFill: 90, taps: 14...28, minNetwork: 18, maxAttempts: 120),
    ]

    @Test(arguments: 0..<4) func generatedLevelsAreUniqueAndInTheWindow(_ k: Int) {
        let config = Self.configs[k]
        for seed in UInt64(1)...4 {
            guard let l = DistillGenerator.generate(config, seed: seed, id: "g") else {
                Issue.record("config \(k) seed \(seed) gave up")
                continue
            }
            #expect(l.validate().isEmpty)
            #expect(l.validateSolving().isEmpty)
            #expect(config.taps.contains(l.minTaps))
            #expect(l.board.width == config.width && l.board.height == config.height)
            #expect(l.board.sources.count == config.groups)
            #expect(!l.board.isWon)
            let solved = DistillSolver.solve(l.board).best!.apply(to: l.board)
            #expect(solved.isWon)
            #expect(solved.pieces.filter { $0.valve != nil }.count == config.valves)
            #expect(solved.pieces.filter { $0.coil != nil }.count == config.coils)
            #expect(solved.pieces.filter { $0.shape == .cross }.count >= config.crosses.lowerBound)
            #expect(l.stats!.networkCells >= config.minNetwork)
        }
    }

    @Test func sameSeedSameLevel() throws {
        let config = Self.configs[3]
        let a = DistillGenerator.generate(config, seed: 77, id: "x"), b = DistillGenerator.generate(config, seed: 77, id: "x")
        #expect(a != nil && a == b)
        let c = DistillGenerator.generate(config, seed: 78, id: "x")
        #expect(a != c)
    }

    @Test func coilsColorTheFlasksBelowThem() {
        var config = DistillGenConfig(width: 6, height: 6, targetsPerGroup: 2...2, coils: 1, taps: 6...16)
        config.maxAttempts = 200
        for seed in UInt64(1)...6 {
            guard let l = DistillGenerator.generate(config, seed: seed, id: "c") else { Issue.record("gave up"); continue }
            let coil = l.board.pieces.compactMap(\.coil).first!
            #expect(l.board.sources[0].color == coil.from)
            #expect(l.board.targets.contains { $0.color == coil.to })
            #expect(DistillGenerator.heatRecipes.contains { $0.from == coil.from && $0.to == coil.to })
        }
    }

    @Test func randomTiersAreSeeded() {
        for tier in DistillRandomTier.allCases {
            let a = DistillRandom.level(tier: tier, seed: 5), b = DistillRandom.level(tier: tier, seed: 5)
            #expect(a == b)
            #expect(a.validateSolving().isEmpty)
            #expect(a.board.width == tier.config.width)
            #expect(tier.config.taps.contains(a.minTaps))
        }
    }

    @Test func scoreFormula() {
        #expect(DistillGenerator.score(minTaps: 10, decisions: 2, mechanics: 1, networkCells: 12, decoys: 8) == 10 + 6 + 2 + 4 + 2)
    }
}

@Suite struct DailyDistillTests {
    static func date(_ s: String) -> DailyDate { DailyDate(isoString: s)! }

    /// distill-daily-v1 must never change: these fingerprints are the shipped levels.
    @Test(.enabled(if: heavyTestsEnabled)) func goldenDays() {
        let golden: [(String, UInt64)] = [
            ("2026-11-16", 0x28f9_f43b_96d2_b8e7), ("2026-11-17", 0x91f9_c10e_2fe2_2dfe), ("2026-11-18", 0x6f4a_002c_ee61_d918),
            ("2026-11-19", 0xb9d2_fb89_1cff_328d), ("2026-11-20", 0x11eb_bf28_8954_99e3), ("2026-11-21", 0xcf60_e08e_8767_4462),
            ("2026-11-22", 0x3ca4_b379_0c66_f586), ("2027-03-01", 0x07e1_a729_4583_5903), ("2030-12-31", 0x3d20_87c2_3af8_6b9a),
        ]
        for (day, fp) in golden {
            let l = DistillDaily.level(for: Self.date(day))
            #expect(DistillDaily.fingerprint(l) == fp, "\(day)")
            #expect(l.id == "distill-daily-\(day)")
            #expect(l.validateSolving().isEmpty)
        }
    }

    @Test func goldenMonday() {
        #expect(DistillDaily.fingerprint(DistillDaily.level(for: Self.date("2026-11-16"))) == 0x28f9_f43b_96d2_b8e7)
    }

    @Test(.enabled(if: heavyTestsEnabled)) func aYearOfDailiesIsValidAndRisesByWeekday() {
        var start = Self.date("2026-11-16")
        var scores = Array(repeating: 0, count: 7)
        for _ in 0..<8 {
            for k in 0..<7 {
                let day = start.adding(days: k)
                let l = DistillDaily.level(for: day)
                let spec = DistillDaily.spec(for: day)
                #expect(spec.weekday.rawValue == k + 1)
                #expect(spec.config.taps.contains(l.minTaps), "\(day)")
                #expect(l.board.width == spec.config.width)
                #expect(l.validateSolving().isEmpty, "\(day)")
                scores[k] += l.stats!.score
            }
            start = start.adding(days: 7)
        }
        #expect(scores == scores.sorted())
    }

    @Test func resultFeedsTheStreaks() {
        let r = DistillDaily.result(date: Self.date("2026-11-17"), taps: 9, minTaps: 9, usedHint: false, solvedAt: Date())
        #expect(r.isPerfect)
        #expect(!DistillDaily.result(date: Self.date("2026-11-17"), taps: 10, minTaps: 9, usedHint: false, solvedAt: Date()).isPerfect)
        #expect(DistillDaily.algorithmVersion == "distill-daily-v1")
        #expect(DistillDaily.baseSeed(for: Self.date("2026-11-17")) != DistillDaily.baseSeed(for: Self.date("2026-11-18")))
    }
}
