import Testing
@testable import BottleSortCore

@Suite struct HiddenLayerTests {
    /// Hidden flags per bottle, bottom → top.
    func mask(_ session: GameSession) -> [[Bool]] {
        session.state.bottles.indices.map { b in
            session.state.bottles[b].layers.indices.map { session.isHidden(bottle: b, layer: $0) }
        }
    }

    static let start = state([[0, 1, 1, 0], [1, 0, 2, 2], [2, 2, 1, 0], [], []])

    @Test func notHiddenByDefault() {
        let session = GameSession(Self.start)
        #expect(!session.hidden)
        #expect(session.hiddenDepths == [0, 0, 0, 0, 0])
        #expect(!session.isHidden(bottle: 0, layer: 0))
    }

    @Test func initiallyEverythingBelowTopRunIsHidden() {
        let session = GameSession(Self.start, hidden: true)
        #expect(session.hiddenDepths == [3, 2, 3, 0, 0])
        #expect(mask(session) == [[true, true, true, false], [true, true, false, false], [true, true, true, false], [], []])
        // Out-of-range queries are simply "not hidden".
        #expect(!session.isHidden(bottle: 9, layer: 0))
        #expect(!session.isHidden(bottle: 0, layer: -1))
    }

    @Test func revealIsPermanentAndPouredLayersAreVisible() {
        var session = GameSession(Self.start, hidden: true)
        // Pour bottle 0's top 0 away: its 1,1 run becomes the top run → revealed.
        session.apply(Move(from: 0, to: 3))
        #expect(session.hiddenDepths == [1, 2, 3, 0, 0])
        // Pour the 1,1 away: the bottom 0 is revealed.
        session.apply(Move(from: 0, to: 4))
        #expect(session.hiddenDepths == [0, 2, 3, 0, 0])
        // Cover it again (0 onto 0): it stays revealed.
        session.apply(Move(from: 3, to: 0))
        #expect(session.hiddenDepths[0] == 0)
        #expect(mask(session)[0] == [false, false])
        // Bottle 2's top 0 leaves: its 1 is revealed, the 2,2 below stay hidden.
        session.apply(Move(from: 2, to: 0))
        #expect(session.hiddenDepths == [0, 2, 2, 0, 0])
        // A 1 poured onto bottle 2 lands above the hidden part and is visible.
        session.apply(Move(from: 4, to: 2))
        #expect(session.state.bottles[2] == Bottle([2, 2, 1, 1], capacity: 4))
        #expect(mask(session)[2] == [true, true, false, false])
        // Depths never went up along the way.
        #expect(session.hiddenDepths == [0, 2, 2, 0, 0])
    }

    @Test func undoAndRestartRestoreHiddenDepths() {
        var session = GameSession(Self.start, hidden: true)
        let initial = session.hiddenDepths
        session.apply(Move(from: 0, to: 3))
        let afterFirst = session.hiddenDepths
        session.apply(Move(from: 0, to: 4))
        #expect(session.hiddenDepths != afterFirst)
        session.undo()
        #expect(session.hiddenDepths == afterFirst)
        session.undo()
        #expect(session.hiddenDepths == initial)
        session.apply(Move(from: 0, to: 3))
        session.apply(Move(from: 0, to: 4))
        session.restart()
        #expect(session.hiddenDepths == initial)
        #expect(session.state == Self.start)
        #expect(session.moveCount == 0)
    }

    @Test func illegalMoveChangesNothing() {
        var session = GameSession(state([[0, 1], [1, 0]], capacity: 2), hidden: true)
        let applied = session.apply(Move(from: 0, to: 1))
        #expect(!applied)
        #expect(session.hiddenDepths == [1, 1])
    }

    @Test func keysAndLocks() {
        // A key on top is its own run of 1: the layers below it are hidden.
        let start = GameState(bottles: [
            Bottle(layers: [.color(1), .color(0), .color(0)], capacity: 3, lockedBy: 1),
            Bottle(layers: [.color(0), .color(1), .key(1)], capacity: 3),
            Bottle(layers: [.color(1)], capacity: 3),
            Bottle(capacity: 3),
        ])
        var session = GameSession(start, hidden: true)
        #expect(session.hiddenDepths == [1, 2, 0, 0])
        // Use the key: bottle 1's 1 becomes its top run; bottle 0 unlocks.
        let opened = session.apply(Move(from: 1, to: 0))
        #expect(opened)
        #expect(session.state.bottles[0].lockedBy == nil)
        #expect(session.hiddenDepths == [1, 1, 0, 0])
        // Pour bottle 0's 0,0 run out: its last layer is revealed.
        session.apply(Move(from: 0, to: 3))
        #expect(session.hiddenDepths == [0, 1, 0, 0])
        session.undo()
        session.undo()
        #expect(session.hiddenDepths == [1, 2, 0, 0])
        #expect(session.state == start)
    }
}
