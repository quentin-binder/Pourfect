import Testing
@testable import BottleSortCore

@Suite struct BottleTests {
    @Test func computedProperties() {
        let b = Bottle([0, 1, 1], capacity: 4)
        #expect(!b.isEmpty)
        #expect(!b.isFull)
        #expect(b.freeSpace == 1)
        #expect(b.topLayer == .color(1))
        #expect(b.topRunCount == 2)
        #expect(Bottle([], capacity: 4).topRunCount == 0)
        #expect(Bottle([2, 2, 2, 2], capacity: 4).topRunCount == 4)
    }

    @Test func bottleSolved() {
        #expect(Bottle([], capacity: 4).isSolved)
        #expect(Bottle([1, 1, 1, 1], capacity: 4).isSolved)
        #expect(!Bottle([1, 1, 1], capacity: 4).isSolved)      // not full
        #expect(!Bottle([1, 1, 2, 1], capacity: 4).isSolved)   // mixed
    }
}

@Suite struct PourTests {
    @Test func pourOntoEmpty() throws {
        let s = state([[0, 1], []])
        let next = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(next == state([[0], [1]]))
    }

    @Test func pourOntoMatchingColor() throws {
        let s = state([[0, 1], [2, 1]])
        let next = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(next == state([[0], [2, 1, 1]]))
    }

    @Test func rejectMismatchedColor() {
        let s = state([[0, 1], [1, 2]])
        #expect(!s.canPour(Move(from: 0, to: 1)))
        #expect(s.pouring(Move(from: 0, to: 1)) == nil)
    }

    @Test func rejectFullTarget() {
        let s = state([[0, 1], [1, 1, 1, 1]])
        #expect(!s.canPour(Move(from: 0, to: 1)))
    }

    @Test func rejectEmptySource() {
        let s = state([[], [1]])
        #expect(!s.canPour(Move(from: 0, to: 1)))
    }

    @Test func rejectSameBottle() {
        let s = state([[0, 1], []])
        #expect(!s.canPour(Move(from: 0, to: 0)))
    }

    @Test func rejectOutOfRange() {
        let s = state([[0, 1], []])
        #expect(!s.canPour(Move(from: 0, to: 5)))
        #expect(!s.canPour(Move(from: -1, to: 1)))
    }

    @Test func partialPourLeavesRemainder() throws {
        let s = state([[0, 1, 1, 1], [2, 2, 1]])
        let next = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(next == state([[0, 1, 1], [2, 2, 1, 1]]))
    }

    @Test func pourMovesWholeRunWhenRoom() throws {
        let s = state([[0, 1, 1, 1], []])
        let next = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(next == state([[0], [1, 1, 1]]))
    }

    @Test func lockedBottlesCannotPour() {
        var s = state([[0, 1], [], [1]])
        s.bottles[1].lockedBy = 1
        #expect(!s.canPour(Move(from: 0, to: 1)))
        s.bottles[1].lockedBy = nil
        s.bottles[0].lockedBy = 1
        #expect(!s.canPour(Move(from: 0, to: 2)))
    }

    @Test func legalMovesList() {
        let s = state([[0, 1], [1], []], capacity: 2)
        // 0→1 (match), 0→2 (empty), 1→0? target full (cap 2) no, 1→2 yes.
        #expect(Set(s.legalMoves()) == [Move(from: 0, to: 1), Move(from: 0, to: 2), Move(from: 1, to: 2)])
    }
}

@Suite struct WinTests {
    @Test func solved() {
        #expect(state([[0, 0, 0, 0], [1, 1, 1, 1], []]).isSolved)
    }

    @Test func notSolvedPartial() {
        #expect(!state([[0, 0, 0], [1, 1, 1, 1], [0]]).isSolved)
    }

    @Test func fullButMixedIsNotSolved() {
        #expect(!state([[0, 0, 0, 1], [1, 1, 1, 0], []]).isSolved)
    }
}

@Suite struct SessionTests {
    @Test func undoRestoresExactPreviousState() {
        let start = state([[0, 1, 0, 1], [1, 0, 1, 0], [], []])
        var session = GameSession(start)
        let ok1 = session.apply(Move(from: 0, to: 2))
        let afterFirst = session.state
        let ok2 = session.apply(Move(from: 1, to: 3))
        #expect(ok1 && ok2)
        #expect(session.moveCount == 2)
        let undo1 = session.undo()
        #expect(undo1)
        #expect(session.state == afterFirst)
        #expect(session.moveCount == 1)
        let undo2 = session.undo()
        #expect(undo2)
        #expect(session.state == start)
        let undo3 = session.undo()
        #expect(!undo3)
    }

    @Test func illegalMoveIsNotRecorded() {
        var session = GameSession(state([[0, 1], [1, 0]], capacity: 2))
        let applied = session.apply(Move(from: 0, to: 1))
        #expect(!applied)
        #expect(session.moveCount == 0)
    }

    @Test func restartRestoresInitial() {
        let start = state([[0, 1, 0, 1], [1, 0, 1, 0], [], []])
        var session = GameSession(start)
        session.apply(Move(from: 0, to: 2))
        session.apply(Move(from: 1, to: 3))
        session.restart()
        #expect(session.state == start)
        #expect(session.moveCount == 0)
        #expect(!session.canUndo)
    }
}

@Suite struct ValidationTests {
    @Test func validLevel() {
        #expect(state([[0, 1, 0, 1], [1, 0, 1, 0], []]).validate().isEmpty)
    }

    @Test func badColorCount() {
        let errors = state([[0, 1, 0, 1], [1, 0, 1], []]).validate()
        #expect(errors.contains(.wrongColorCount(color: 0, count: 3, expected: 4)))
    }

    @Test func overfilled() {
        let s = GameState(bottles: [Bottle([0, 0, 0, 0, 0], capacity: 4), Bottle([], capacity: 4)])
        #expect(s.validate().contains(.overfilled(bottle: 0, count: 5, capacity: 4)))
    }

    @Test func inconsistentCapacity() {
        let s = GameState(bottles: [Bottle([0, 0, 0], capacity: 3), Bottle([], capacity: 4)])
        #expect(s.validate().contains(.inconsistentCapacity(bottle: 1, capacity: 4, expected: 3)))
    }

    @Test func noBottles() {
        #expect(GameState(bottles: []).validate() == [.noBottles])
    }
}

@Suite struct StarRatingTests {
    @Test func thresholds() {
        #expect(StarRating.stars(moves: 10, minMoves: 10) == 3)
        #expect(StarRating.stars(moves: 11, minMoves: 10) == 2)
        #expect(StarRating.stars(moves: 13, minMoves: 10) == 2)
        #expect(StarRating.stars(moves: 14, minMoves: 10) == 1)
    }
}
