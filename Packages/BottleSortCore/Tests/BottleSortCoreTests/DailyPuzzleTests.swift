import Foundation
import Testing
@testable import BottleSortCore

/// Compact layout string, e.g. "0123|1230|…|L1:…|" (L = locked flask, k = key).
private func layout(_ level: LevelDefinition) -> String {
    level.bottles.map { b in
        (b.lockedBy.map { "L\($0.rawValue):" } ?? "") + b.layers.map { layer in
            switch layer {
            case .color(let c): return String(c.rawValue, radix: 16)
            case .key(let k): return "k\(k.rawValue)"
            }
        }.joined()
    }.joined(separator: "|")
}

@Suite("Daily plan & puzzle")
struct DailyPuzzleTests {
    @Test func weekdayPlan() {
        let specs = Weekday.allCases.map(DailyPlan.spec(for:))
        #expect(specs.map(\.mode) == [.classic, .classic, .sealed, .murky, .classic, .sealed, .murkySealed])
        #expect(specs.map(\.label).first == "Monday · Gentle")
        // Difficulty rises: Monday has the shortest window, Sunday (with Friday) the longest.
        #expect(specs.dropFirst().allSatisfy { $0.minMoves.lowerBound > specs[0].minMoves.upperBound })
        #expect(specs.last!.minMoves.lowerBound >= specs.dropLast().map(\.minMoves.lowerBound).max()!)
        for spec in specs {
            #expect(spec.hidden == spec.mode.isMurky)
            #expect((spec.locks > 0) == spec.mode.hasSeals)
            #expect(spec.locks <= 1)  // no 2-seal searches on device
        }
        #expect(DailyPlan.spec(for: day(2026, 11, 16)).tier == .gentle)
    }

    @Test func seedIsStableAndDiffersPerDay() {
        #expect(DailyPuzzle.baseSeed(for: day(2026, 11, 15)) == DailyPuzzle.baseSeed(for: day(2026, 11, 15)))
        #expect(DailyPuzzle.baseSeed(for: day(2026, 11, 15)) != DailyPuzzle.baseSeed(for: day(2026, 11, 16)))
        #expect(DailyPuzzle.baseSeed(for: day(2026, 11, 15)) == goldenSeed)
    }

    /// Golden values: if these change, the daily generation changed and
    /// `DailyPuzzle.algorithmVersion` must be bumped (see DECISIONS).
    let goldenSeed: UInt64 = 15_850_784_904_836_853_840
    let goldenLayout = "L1:5213|2k110|0634|1265|3246|4406|1505|3|"
    let goldenMinMoves = 23

    @Test func goldenLevel() throws {
        #expect(DailyPuzzle.algorithmVersion == "daily-v2")
        let g = try DailyPuzzle.generate(for: day(2026, 11, 15))
        #expect(g.level.id == "daily-2026-11-15")
        #expect(g.level.isHidden)
        #expect(g.phase == .spec)
        #expect(g.attempts == 1)
        #expect(g.level.meta?.seed == goldenSeed)
        #expect(g.level.meta?.minMoves == goldenMinMoves)
        #expect(layout(g.level) == goldenLayout)
    }

    @Test func sameDateSameLevelBytes() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for date in [day(2026, 11, 18), day(2026, 11, 19)] {
            let a = try encoder.encode(DailyPuzzle.level(for: date))
            let b = try encoder.encode(DailyPuzzle.level(for: date))
            #expect(a == b)
        }
    }

    /// One full week: every level matches its spec, its minMoves is the solver's, seals matter.
    @Test func weekMatchesSpecs() throws {
        var date = day(2026, 11, 16)  // Monday
        for _ in 0..<7 {
            let g = try DailyPuzzle.generate(for: date)
            let spec = g.spec
            let state = g.level.gameState
            #expect(g.phase == .spec)
            #expect(g.level.id == "daily-\(date.isoString)")
            #expect(g.level.isHidden == spec.hidden)
            #expect(state.bottles.filter { $0.lockedBy != nil }.count == spec.locks)
            #expect(state.validate().isEmpty)
            let moves = Solver().solve(state).moves?.count
            #expect(moves == g.level.meta?.minMoves)
            #expect(spec.minMoves.contains(moves ?? -1))
            #expect(LockImpact.everyLockMatters(state, minMoves: moves ?? 0))
            date = date.next
        }
    }

    @Test func fixedFallbackIsSolvable() {
        let level = DailyPuzzle.fixedLevel(for: day(2026, 1, 1), hidden: true)
        #expect(level.gameState.validate().isEmpty)
        #expect(Solver().solve(level.gameState).moves?.count == DailyPuzzle.fixedLevelMinMoves)
        #expect(level.isHidden)
    }

    @Test func cancelledTaskThrows() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DailyPuzzle.generate(for: day(2026, 11, 15))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// 60 consecutive days in a debug build (loose bound; release numbers are in DECISIONS).
    @Test func sixtyDaysPerformance() throws {
        var date = day(2026, 11, 15)
        var worst = Duration.zero
        var total = Duration.zero
        let clock = ContinuousClock()
        for _ in 0..<60 {
            var phase = DailyGenerationPhase.spec
            let elapsed = try clock.measure { phase = try DailyPuzzle.generate(for: date).phase }
            #expect(phase == .spec)
            worst = max(worst, elapsed)
            total += elapsed
            date = date.next
        }
        print("daily: 60 days, debug, max \(worst), total \(total)")
        #expect(worst < .seconds(10))
    }
}

