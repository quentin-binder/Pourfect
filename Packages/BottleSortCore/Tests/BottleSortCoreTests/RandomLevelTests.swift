import Foundation
import Testing
@testable import BottleSortCore

/// Thread-safe list of progress callbacks (Mutex needs macOS 15).
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Int] = []
    func append(_ n: Int) { lock.withLock { items.append(n) } }
    var all: [Int] { lock.withLock { items } }
}

@Suite struct RandomLevelTests {
    static let limits = SolverLimits(maxStates: 300_000)

    @Test func clamping() {
        let o = RandomLevelOptions(mode: .locksAndKeys, colors: 40, capacity: 1, emptyBottles: 9, locks: 5).clamped
        #expect(o.colors == 12 && o.capacity == 2 && o.emptyBottles == 4 && o.locks == 2)
        let low = RandomLevelOptions(colors: 0, capacity: 99, emptyBottles: -3, locks: 0).clamped
        #expect(low.colors == 2 && low.capacity == 6 && low.emptyBottles == 0 && low.locks == 1)
        #expect(RandomLevelOptions(colors: 2, locks: 2).clamped.locks == 1)   // locks < colors
        #expect(RandomLevel.defaultMaxAttempts == 6)
    }

    @Test(arguments: [GameMode.classic, .locksAndKeys, .hidden])
    func successPath(mode: GameMode) throws {
        let options = RandomLevelOptions(mode: mode, colors: 4, capacity: 4, emptyBottles: 2, locks: 1)
        let result = RandomLevel.generate(options, seed: 7, limits: Self.limits)
        let level = try #require(result.level)
        #expect(level.id == "random-7")
        #expect(level.isHidden == (mode == .hidden))
        #expect(level.gameState.validate().isEmpty)
        #expect(level.gameState.bottles.contains { $0.lockedBy != nil } == (mode == .locksAndKeys))
        let last = try #require(result.attempts.last)
        #expect(level.meta?.seed == last.seed)
        guard case .accepted(let minMoves) = last.outcome else { Issue.record("last attempt not accepted"); return }
        #expect(level.meta?.minMoves == minMoves)
        #expect(level.meta?.score != nil)
        #expect(Solver().solve(level.gameState).moves?.count == minMoves)
        #expect((1...6).contains(result.attempts.count))
    }

    /// A wall-clock timeout would make the outcome depend on device speed (DECISIONS #46).
    @Test func defaultLimitsHaveNoTimeout() {
        #expect(RandomLevel.defaultLimits.timeout == nil)
        #expect(RandomLevel.defaultLimits.maxStates == 1_000_000)
    }

    @Test func cancelledTaskStopsBeforeTheFirstAttempt() async {
        let options = RandomLevelOptions(mode: .classic, colors: 4, capacity: 4, emptyBottles: 2)
        let task = Task.detached { () -> RandomLevelResult in
            while !Task.isCancelled { await Task.yield() }
            return RandomLevel.generate(options, seed: 7, limits: Self.limits)
        }
        task.cancel()
        let result = await task.value
        #expect(result.level == nil)
        #expect(result.attempts.isEmpty)
    }

    @Test func deterministicForSameSeed() throws {
        let options = RandomLevelOptions(mode: .locksAndKeys, colors: 4, capacity: 3, emptyBottles: 1, locks: 2)
        let a = RandomLevel.generate(options, seed: 42, limits: Self.limits)
        let b = RandomLevel.generate(options, seed: 42, limits: Self.limits)
        #expect(a == b)
        #expect(a.level != nil)
        let c = RandomLevel.generate(options, seed: 43, limits: Self.limits)
        #expect(c.level?.bottles != a.level?.bottles)
    }

    @Test func capOfSixAttempts() {
        // No empty bottle and every bottle full: never a legal move, so every
        // attempt fails (unsolvable, or rejected for a pre-sorted bottle).
        let options = RandomLevelOptions(mode: .classic, colors: 8, capacity: 4, emptyBottles: 0)
        let calls = Calls()
        let result = RandomLevel.generate(options, seed: 1, limits: Self.limits) { attempt, max in
            #expect(max == 6)
            calls.append(attempt)
        }
        #expect(result.level == nil)
        #expect(result.attempts.count == 6)
        #expect(result.attempts.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(result.attempts.map(\.seed) == [1, 2, 3, 4, 5, 6])
        #expect(result.attempts.allSatisfy { $0.outcome == .unsolvable || $0.outcome == .presolvedBottle })
        #expect(calls.all == [1, 2, 3, 4, 5, 6])
    }

    @Test func customCapAndUnknownOutcome() {
        let options = RandomLevelOptions(colors: 8, capacity: 4, emptyBottles: 2)
        let result = RandomLevel.generate(options, seed: 1, maxAttempts: 2, limits: SolverLimits(maxStates: 10))
        #expect(result.level == nil)
        #expect(result.attempts.count == 2)
        #expect(result.attempts.allSatisfy { $0.outcome == .unknown || $0.outcome == .presolvedBottle })
    }
}
