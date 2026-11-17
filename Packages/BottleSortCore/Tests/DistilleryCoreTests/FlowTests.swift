import BottleSortCore
import Testing
@testable import DistilleryCore

@Suite struct FlowTests {
    @Test func masksRotateClockwise() {
        #expect(DistillMask.rotate(DistillShape.elbow.baseMask, by: 1) == DistillDir.east.bit | DistillDir.south.bit)
        #expect(DistillMask.rotate(DistillShape.tee.baseMask, by: 3) == 0b1011)
        #expect(DistillPiece(.straight, rotation: 2).mask == DistillPiece(.straight).mask)
        #expect(DistillPiece(.cross, rotation: 1).channels == [0b0101, 0b1010])
        #expect(distillTapCost(from: 0, to: 3) == 1)
        #expect(distillTapCost(from: 1, to: 3) == 2)
        #expect(DistillPiece(.straight, rotation: 0).cheapestTurn(to: 0b0101)?.taps == 0)
        #expect(DistillPiece(.straight, rotation: 3).cheapestTurn(to: 0b0101)?.taps == 1)
    }

    @Test func straightLine() {
        let b = board(["S I1 F"], sources: [(0, 0, 0, .east)], targets: [(0, 2, 0, .west)])
        let f = b.flow
        #expect(f.isWon)
        #expect(f.received == [.liquid(0)])
        #expect(f.node(at: P(0, 1), side: .west)?.tick == 1)
        #expect(f.node(at: P(0, 2), side: .west)?.tick == 2)
        #expect(f.node(at: P(0, 1), side: .west)?.entry == DistillDir.west.bit)
    }

    @Test func blockedOutletLeaks() {
        let f = board(["S I0 F"], sources: [(0, 0, 0, .east)], targets: [(0, 2, 0, .west)]).flow
        #expect(!f.isWon)
        #expect(f.received == [.dry])
        #expect(f.leaks == [DistillLeak(pos: P(0, 0), side: .east, color: 0, tick: 1)])
    }

    @Test func openEndAtTheEdgeLeaks() {
        let f = board(["S I1 I1", ". F ."], sources: [(0, 0, 0, .east)], targets: [(1, 1, 0, .north)]).flow
        #expect(f.leaks.map(\.pos) == [P(0, 2)])
        #expect(f.leaks.first?.side == .east)
        #expect(!f.isWon)
    }

    @Test func elbowTurns() {
        let b = board(["S L2", ". F"], sources: [(0, 0, 3, .east)], targets: [(1, 1, 3, .north)])
        #expect(b.flow.isWon)
        var turned = b
        turned[P(0, 1)].rotation = 1
        #expect(!turned.flow.isWon)
    }

    @Test func teeSplitsToTwoFlasks() {
        let b = board([". F .", "S T3 F", ". . ."], sources: [(1, 0, 1, .east)], targets: [(0, 1, 1, .south), (1, 2, 1, .west)])
        let f = b.flow
        #expect(f.isWon)
        #expect(f.received == [.liquid(1), .liquid(1)])
    }

    @Test func teeBranchNeedsACap() {
        let open = board([". F .", "S T2 .", ". . ."], sources: [(1, 0, 1, .east)], targets: [(0, 1, 1, .south)])
        #expect(open.flow.leaks.map(\.side) == [.south])
        #expect(!open.flow.isWon)
        let capped = board([". F .", "S T2 .", ". C0 ."], sources: [(1, 0, 1, .east)], targets: [(0, 1, 1, .south)])
        #expect(capped.flow.isWon)
        #expect(capped.flow.leaks.isEmpty)
    }

    @Test func crossKeepsColorsApart() {
        let sources: [(Int, Int, Int, DistillDir)] = [(1, 0, 0, .east), (0, 1, 1, .south)]
        let targets: [(Int, Int, Int, DistillDir)] = [(1, 2, 0, .west), (2, 1, 1, .north)]
        let crossed = board([". S .", "S X F", ". F ."], sources: sources, targets: targets)
        #expect(crossed.flow.isWon)
        #expect(crossed.flow.nodes(at: P(1, 1)).map(\.liquid) == [.liquid(1), .liquid(0)])
        // A tee is one junction: the two colors meet there and it turns murky.
        let junction = board([". S .", "S T3 F", ". F ."], sources: sources, targets: targets)
        let f = junction.flow
        #expect(!f.isWon)
        #expect(f.nodes(at: P(1, 1)).first?.liquid == .murky)
        #expect(f.received == [.dry, .dry])
    }

    @Test func colorsMeetInAMurkyChannelOrSeam() {
        let odd = board(["S I1 I1 I1 S"], sources: [(0, 0, 0, .east), (0, 4, 1, .west)], targets: []).flow
        #expect(odd.nodes(at: P(0, 2)).first?.liquid == .murky)
        #expect(odd.seams.isEmpty)
        #expect(!odd.isWon)
        let even = board(["S I1 I1 S"], sources: [(0, 0, 0, .east), (0, 3, 1, .west)], targets: []).flow
        #expect(even.seams == [DistillSeam(pos: P(0, 1), side: .east)])
        #expect(even.nodes(at: P(0, 1)).first?.liquid == .liquid(0))
        #expect(even.nodes(at: P(0, 2)).first?.liquid == .liquid(1))
        #expect(!even.isWon)
        let same = board(["S I1 I1 S"], sources: [(0, 0, 2, .east), (0, 3, 2, .west)], targets: []).flow
        #expect(same.isWon)
    }

    @Test func valveOpensWhenItsFlaskIsFull() {
        let b = board([". F . .", "S T3 I1 F"], sources: [(1, 0, 0, .east)], targets: [(0, 1, 0, .south), (1, 3, 0, .west)],
                      valves: [(1, 2, 0)])
        let f = b.flow
        #expect(f.isWon)
        #expect(f.valveOpenedAt == [P(1, 2): 1])
        #expect(f.stages == 2)
        let t0 = f.node(at: P(0, 1), side: .south)!.tick, t1 = f.node(at: P(1, 3), side: .west)!.tick
        #expect(t1 > t0)
        // Linked to the flask behind it, the valve never opens.
        let stuck = board([". F . .", "S T3 I1 F"], sources: [(1, 0, 0, .east)], targets: [(0, 1, 0, .south), (1, 3, 0, .west)],
                          valves: [(1, 2, 1)]).flow
        #expect(!stuck.isWon)
        #expect(stuck.received == [.liquid(0), .dry])
        #expect(stuck.leaks.isEmpty)
        #expect(stuck.node(at: P(1, 2), side: .west)?.shutValve == true)
        #expect(stuck.node(at: P(1, 2), side: .west)?.sideColors == [nil, nil, nil, 0])
    }

    @Test func valveStaysShutForTheWrongColor() {
        // Flask 0 wants blue but gets red: the valve to flask 1 stays shut.
        let b = board([". F . .", "S T3 I1 F"], sources: [(1, 0, 0, .east)], targets: [(0, 1, 1, .south), (1, 3, 0, .west)],
                      valves: [(1, 2, 0)])
        #expect(b.flow.received == [.liquid(0), .dry])
        #expect(b.flow.valveOpenedAt.isEmpty)
    }

    @Test func heatCoilChangesTheColor() {
        let coil = [(0, 1, 0, 5)]
        let orange = board(["S I1 F"], sources: [(0, 0, 0, .east)], targets: [(0, 2, 5, .west)], coils: coil).flow
        #expect(orange.isWon)
        #expect(orange.node(at: P(0, 1), side: .west)?.sideColors == [nil, 5, nil, 0])
        let wantsRed = board(["S I1 F"], sources: [(0, 0, 0, .east)], targets: [(0, 2, 0, .west)], coils: coil).flow
        #expect(!wantsRed.isWon)
        #expect(wantsRed.received == [.liquid(5)])
        let blue = board(["S I1 F"], sources: [(0, 0, 1, .east)], targets: [(0, 2, 1, .west)], coils: coil).flow
        #expect(blue.isWon)
    }

    @Test func heatedAndRawLiquidMeetMurky() {
        // Red splits; one arm is heated to orange and both arms meet again.
        let b = board(["S T1 I1 L2", ". L0 I1 L3"], sources: [(0, 0, 0, .east)], targets: [], coils: [(0, 2, 0, 5)])
        let f = b.flow
        #expect(!f.isWon)
        #expect(f.murkyCount > 0)
    }

    @Test func dryPiecesAreFine() {
        let b = board(["S I1 F", "L0 T0 I0"], sources: [(0, 0, 0, .east)], targets: [(0, 2, 0, .west)])
        #expect(b.flow.isWon)
        #expect(b.flow.nodes(at: P(1, 1)).first?.liquid == .dry)
    }

    @Test func wetChannelsListAndHelpers() {
        let b = board(["S I1 F"], sources: [(0, 0, 0, .east)], targets: [(0, 2, 0, .west)])
        #expect(b.flow.wetNodes.count == 3)
        #expect(b.flow.satisfiedTargets == 1)
        #expect(b.isWon)
    }
}
