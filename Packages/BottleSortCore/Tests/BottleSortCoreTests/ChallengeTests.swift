import Foundation
import Testing
@testable import BottleSortCore

/// R6 challenge modes: the gold seal, the main-path gate, Rush.
@Suite("Gold seal & main-path gate")
struct GoldSealTests {
    @Test func earnedOnlyAtTheMinimumWithoutAHint() {
        #expect(GoldSeal.isEarned(moves: 12, minMoves: 12, usedHint: false))
        #expect(!GoldSeal.isEarned(moves: 13, minMoves: 12, usedHint: false))
        #expect(!GoldSeal.isEarned(moves: 12, minMoves: 12, usedHint: true))
        #expect(!GoldSeal.isEarned(moves: 12, minMoves: nil, usedHint: false))
        #expect(!GoldSeal.isEarned(moves: 0, minMoves: 0, usedHint: false))
        // A seal always comes with three stars.
        for moves in 5...20 where GoldSeal.isEarned(moves: moves, minMoves: 9, usedHint: false) {
            #expect(StarRating.stars(moves: moves, minMoves: 9) == 3)
        }
    }

    @Test func progressCountsOnlyTheGivenRecipes() {
        let ids = ["c2_001", "c2_002", "c2_003"]
        let sealed: Set<String> = ["c2_001", "c2_003", "p4_009", "rush-1-1"]
        let p = GoldSeal.progress(of: ids, sealed: sealed)
        #expect(p == GoldSealProgress(earned: 2, total: 3))
        #expect(!p.isComplete)
        #expect(GoldSeal.progress(of: ids, sealed: sealed.union(["c2_002"])).isComplete)
        #expect(!GoldSeal.progress(of: [], sealed: sealed).isComplete)
    }

    /// Stars of challenge books (and anything else outside the chapters) never open a chapter.
    @Test func challengeResultsNeverOpenChapters() {
        let chapters = [["a1", "a2"], ["b1", "b2"], ["c1"]]
        var stars: [String: Int] = ["a1": 1]
        let base = ChapterGate.unlockedChapters(recipeIDs: chapters) { stars[$0] ?? 0 }
        #expect(base == [true, false, false])
        // Three-star every challenge recipe and some Rush / random / daily ids.
        for id in ["p2_001", "p3_001", "p6_030", "rush-7-1", "random-5", "daily-2026-11-16"] { stars[id] = 3 }
        #expect(ChapterGate.unlockedChapters(recipeIDs: chapters) { stars[$0] ?? 0 } == base)
        // A chapter's own stars do open the next one (half of 6 = 3).
        stars["a2"] = 2
        #expect(ChapterGate.unlockedChapters(recipeIDs: chapters) { stars[$0] ?? 0 } == [true, true, false])
        // Out-of-range saved values are clamped like everywhere else.
        stars["b1"] = 99
        #expect(ChapterGate.unlockedChapters(recipeIDs: chapters) { stars[$0] ?? 0 } == [true, true, true])
    }
}

@Suite("Rush")
struct RushTests {
    @Test func clock() {
        var c = RushClock()
        #expect(c.remaining == 180 && c.displaySeconds == 180 && !c.isOver)
        c.tick(0.4)
        #expect(c.displaySeconds == 180)   // rounds up
        c.tick(-5)
        #expect(c.remaining == 179.6)
        c.solve()
        #expect(c.solved == 1 && c.remaining == 179.6 + RushClock.solveBonus)
        c.skip()
        #expect(c.skipped == 1 && c.remaining == 179.6 + RushClock.solveBonus - RushClock.skipPenalty)
        c.tick(1_000)
        #expect(c.isOver && c.remaining == 0 && c.displaySeconds == 0)
        // Nothing counts after the end.
        c.solve()
        c.skip()
        #expect(c.solved == 1 && c.skipped == 1 && c.remaining == 0)
        var short = RushClock(duration: 8)
        short.skip()
        #expect(short.isOver && short.remaining == 0)
    }

    @Test func record() {
        var r = RushRecord()
        var newBests: [Bool] = []
        for solved in [0, 4, 4, 2, 7] {
            let isNew = r.record(solved: solved)
            newBests.append(isNew)
        }
        #expect(newBests == [false, true, false, false, true])
        #expect(r == RushRecord(best: 7, runs: 5))
        let data = try! JSONEncoder().encode(r)
        #expect(try! JSONDecoder().decode(RushRecord.self, from: data) == r)
    }

    @Test func unlockedMechanics() {
        #expect(RushMechanic.unlocked(by: [.basic]) == [])
        #expect(RushMechanic.unlocked(by: [.frozen, .basic, .sealed, .twins, .cauldron]) == [.sealed, .frozen])
        #expect(RushMechanic.unlocked(by: Set(RushMechanic.allCases.map(\.mechanic))) == RushMechanic.allCases)
    }

    static let subsets: [[RushMechanic]] = [[], [.sealed], [.murky, .frozen], RushMechanic.allCases]

    @Test(arguments: subsets)
    func rampOnlyGoesUp(mechanics: [RushMechanic]) {
        for seed: UInt64 in [1, 2, 99, 123_456_789] {
            let specs = (0..<40).map { RushPlan.spec(index: $0, seed: seed, mechanics: mechanics) }
            #expect(specs == (0..<40).map { RushPlan.spec(index: $0, seed: seed, mechanics: mechanics) })
            #expect(specs.first?.colors == 3)
            for (a, b) in zip(specs, specs.dropFirst()) {
                #expect(a.minMoves.lowerBound <= b.minMoves.lowerBound)
                #expect(a.minMoves.upperBound <= b.minMoves.upperBound)
                #expect(a.colors + (a.mechanic == nil ? 0 : 1) <= b.colors + (b.mechanic == nil ? 0 : 1))
                if mechanics.count > 1, let m = a.mechanic { #expect(m != b.mechanic) }
            }
            for spec in specs {
                #expect(spec.minMoves.lowerBound >= 4 && spec.minMoves.upperBound <= 18)
                #expect((spec.mechanic == nil) == (spec.index < RushPlan.firstMechanicIndex || mechanics.isEmpty))
                if let m = spec.mechanic { #expect(mechanics.contains(m)) }
                #expect(spec.hidden == (spec.mechanic == .murky))
                #expect(spec.emptyBottles == (spec.mechanic == .sealed ? 1 : 2))
            }
            // Every unlocked mechanic turns up within one round.
            let round = specs[RushPlan.firstMechanicIndex..<(RushPlan.firstMechanicIndex + mechanics.count)]
            #expect(Set(round.compactMap(\.mechanic)) == Set(mechanics))
        }
    }

    @Test func seedsDiffer() {
        #expect(RushPlan.baseSeed(seed: 1, index: 0) != RushPlan.baseSeed(seed: 1, index: 1))
        #expect(RushPlan.baseSeed(seed: 1, index: 0) != RushPlan.baseSeed(seed: 2, index: 0))
        #expect(RushPlan.levelID(seed: 42, index: 0) == "rush-42-1")
        // The mechanic order is shuffled per run.
        let orders = (1...8).map { seed in
            (5..<10).compactMap { RushPlan.spec(index: $0, seed: UInt64(seed), mechanics: RushMechanic.allCases).mechanic }
        }
        #expect(Set(orders).count > 1)
    }

    /// Every recipe of a run is valid, solvable in its stored minimum and uses its mechanic.
    @Test func levelsArePlayable() throws {
        let seed: UInt64 = 7
        for index in 0..<16 {
            let rush = try RushPlan.level(index: index, seed: seed, mechanics: RushMechanic.allCases)
            try check(rush)
        }
        // Deterministic.
        let a = try RushPlan.level(index: 9, seed: 31, mechanics: [.frozen, .essence])
        let b = try RushPlan.level(index: 9, seed: 31, mechanics: [.frozen, .essence])
        #expect(a == b)
    }

    /// Regression: the relaxed phase keeps the spec's lower bound, so a late recipe is never
    /// shorter than earlier ones (frozen run 32, recipe 17 used to come out at 12 moves).
    @Test func relaxedPhaseKeepsTheRamp() throws {
        let rush = try RushPlan.level(index: 16, seed: 32, mechanics: [.frozen])
        #expect(rush.phase == .relaxed)
        try check(rush)
        let minMoves = try #require(rush.level.meta?.minMoves)
        #expect(minMoves >= 14)
    }

    func check(_ rush: RushLevel) throws {
        let level = rush.level
        let state = level.gameState
        #expect(state.validate().isEmpty)
        #expect(rush.phase == .spec || rush.phase == .relaxed)
        let minMoves = try #require(level.meta?.minMoves)
        #expect((4...RushPlan.relaxedMaxMoves).contains(minMoves))
        if rush.phase == .spec { #expect(rush.spec.minMoves.contains(minMoves)) }
        // Never easier than the spec asked for, even when relaxed.
        #expect(minMoves >= rush.spec.minMoves.lowerBound)
        guard case .solved(let moves, _) = Solver().solve(state, limits: RushPlan.solverLimits) else {
            Issue.record("rush \(level.id) unsolved"); return
        }
        #expect(moves.count == minMoves)
        #expect(level.isHidden == rush.spec.hidden)
        let modifiers = state.bottles.flatMap(\.modifiers)
        switch rush.spec.mechanic {
        case .sealed: #expect(state.bottles.contains { $0.lockedBy != nil })
        case .essence: #expect(modifiers.contains { if case .essence = $0 { true } else { false } })
        case .narrowNeck: #expect(modifiers.contains(.narrowNeck))
        case .frozen: #expect(state.bottles.contains { !$0.frozenLayers.isEmpty })
        case .murky, nil: #expect(modifiers.isEmpty && state.bottles.allSatisfy { $0.lockedBy == nil })
        }
    }

    /// Slow: many runs, every recipe within the time a background pre-generation hides
    /// (measured in release: worst ≈ 0.5 s, mean ≈ 0.04 s on an M-series Mac).
    @Test(.enabled(if: slowTestsEnabled)) func generationIsQuick() throws {
        let clock = ContinuousClock()
        var worst: Duration = .zero
        for seed: UInt64 in 1...12 {
            for index in 0..<25 {
                var rush: RushLevel?
                let time = try clock.measure { rush = try RushPlan.level(index: index, seed: seed, mechanics: RushMechanic.allCases) }
                worst = max(worst, time)
                try check(try #require(rush))
            }
        }
        #expect(worst < .seconds(2))
    }
}
