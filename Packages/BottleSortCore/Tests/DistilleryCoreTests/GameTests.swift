import BottleSortCore
import Testing
@testable import DistilleryCore

@Suite struct GameTests {
    let start = board(["S I0 L0", ". . I1", ". F L0"], sources: [(0, 0, 0, .east)], targets: [(2, 1, 0, .east)])

    @Test func tapsUndoRestart() {
        var g = DistillGame(level: level(start, minTaps: 4))
        #expect(g.taps == 0)
        #expect(!g.canTap(P(0, 0)))        // source
        #expect(!g.canTap(P(1, 0)))        // empty
        #expect(tap(&g, P(1, 1)) == nil)   // nothing counted
        let r = tap(&g, P(0, 1))
        #expect(r?.newRotation == 1)
        #expect(r?.newlyWet == [DistillNodeRef(pos: P(0, 1), channel: 0)])
        #expect(g.taps == 1)
        _ = g.undo()
        #expect(g.taps == 0)
        #expect(g.board == start)
        tap(&g, P(0, 2), clockwise: false)
        #expect(g.board[P(0, 2)].rotation == 3)
        g.restart()
        #expect(g.taps == 0 && g.board == start)
    }

    @Test func winStopsTheBoard() {
        var g = DistillGame(level: level(start, minTaps: 4))
        // straight → 1, elbow (0,2) 0 → 2, straight (1,2) 1 → 0, elbow (2,2) 0 → 3.
        tap(&g, P(0, 1))
        tap(&g, P(0, 2)); tap(&g, P(0, 2))
        tap(&g, P(1, 2))
        let last = tap(&g, P(2, 2), clockwise: false)
        #expect(last?.didWin == true)
        #expect(last?.newlySatisfied == [0])
        #expect(g.isWon)
        #expect(g.taps == 5)
        #expect(g.stars == 2)
        #expect(!g.canUndo)
        #expect(tap(&g, P(0, 1)) == nil)
        #expect(DistillSolver.minTaps(start) == 5)
    }

    @Test func starsByTaps() {
        #expect(DistillStars.stars(taps: 5, minTaps: 5) == 3)
        #expect(DistillStars.margin(minTaps: 5) == 3)
        #expect(DistillStars.stars(taps: 8, minTaps: 5) == 2)
        #expect(DistillStars.stars(taps: 9, minTaps: 5) == 1)
        #expect(DistillStars.margin(minTaps: 20) == 6)
    }

    @Test func hintFromTheGame() {
        let g = DistillGame(level: level(start, minTaps: 5))
        #expect(g.hint() != nil)
    }
}
