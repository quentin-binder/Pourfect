import Testing
@testable import BottleSortCore

@Suite struct CompletionTests {
    @Test func pourThatFillsTargetCompletesIt() throws {
        let before = state([[2, 1], [1, 1, 1], [3, 3, 3, 3], []])
        let after = try #require(before.pouring(Move(from: 0, to: 1)))
        // Bottle 2 was already complete; only the target is new.
        #expect(Rules.completedBottles(before: before, after: after) == [1])
    }

    @Test func partialOrMixedIsNotCompleted() throws {
        let before = state([[1, 1], [1], [2, 2, 1], []])
        let toPartial = try #require(before.pouring(Move(from: 0, to: 1)))
        #expect(Rules.completedBottles(before: before, after: toPartial).isEmpty)
        let toEmpty = try #require(before.pouring(Move(from: 2, to: 3)))
        #expect(Rules.completedBottles(before: before, after: toEmpty).isEmpty)
    }

    @Test func emptiedSourceIsNotCompleted() throws {
        let before = state([[1], [1, 1, 1]])
        let after = try #require(before.pouring(Move(from: 0, to: 1)))
        #expect(Rules.completedBottles(before: before, after: after) == [1])
        #expect(Rules.isSolved(after.bottles[0]))
        #expect(!Rules.isCompleted(after.bottles[0]))
    }

    @Test func sourceCanCompleteToo() throws {
        // Pouring the top layer off a bottle can't complete it (it stops being full), but
        // a state comparison reports any bottle that newly became complete.
        let before = state([[1, 1, 1, 2], [], [1]])
        let after = GameState(bottles: [Bottle([1, 1, 1, 1], capacity: 4), Bottle([2], capacity: 4), Bottle([], capacity: 4)])
        #expect(Rules.completedBottles(before: before, after: after) == [0])
    }

    @Test func lockedOrKeyBottlesAreNotCompleted() {
        var locked = Bottle([1, 1, 1, 1], capacity: 4)
        locked.lockedBy = 0
        #expect(!Rules.isCompleted(locked))
        let before = GameState(bottles: [locked])
        var unlocked = locked
        unlocked.lockedBy = nil
        let after = GameState(bottles: [unlocked])
        // Unlocking a full single-color bottle completes it.
        #expect(Rules.completedBottles(before: before, after: after) == [0])
    }

    @Test func unchangedStateReportsNothing() {
        let s = state([[1, 1, 1, 1], [2, 2, 2, 2], []])
        #expect(Rules.completedBottles(before: s, after: s).isEmpty)
    }
}
