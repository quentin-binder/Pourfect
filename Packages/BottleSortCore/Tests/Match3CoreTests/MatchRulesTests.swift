import BottleSortCore
import Testing
@testable import Match3Core

@Suite struct MatchShapeTests {
    @Test func threeInARowClears() {
        var g = game("""
        c f m e d
        m m f c e
        e d c f o
        """)
        #expect(!M3Rules.hasMatch(g.board))
        let r = play(&g, S(0, 2, 1, 2))
        #expect(r.accepted)
        guard case .swap(let s) = r.phases[0] else { Issue.record("no swap phase"); return }
        #expect(s == S(0, 2, 1, 2))
        let w = r.waves[0]
        #expect(w.cascade == 1)
        #expect(w.groups.count == 1)
        #expect(w.groups[0].shape == .three)
        #expect(w.groups[0].creates == nil)
        #expect(Set(w.cleared.map(\.at)) == [P(1, 0), P(1, 1), P(1, 2)])
        #expect(w.cleared.allSatisfy { $0.cause == .match })
        #expect(g.collected[M3Kind.mushroom.index] >= 3)
        #expect(g.movesLeft == 19)
        #expect(g.movesUsed == 1)
    }

    @Test func fourFromAVerticalSwapMakesAColumnComet() {
        let g = game("""
        c f m e d
        m m f m e
        e d c f o
        """)
        let w = g.preview(S(0, 2, 1, 2))!
        #expect(w.groups[0].shape == .four)
        #expect(w.groups[0].creates == .column)
        #expect(w.created == [M3SpecialPiece(at: P(1, 2), piece: M3Piece(kind: .mushroom, special: .column))])
        #expect(w.cleared.count == 4)
    }

    @Test func fourFromAHorizontalSwapMakesARowComet() {
        let g = game("""
        c m e d
        f m c e
        m c f o
        e m d c
        """)
        let w = g.preview(S(2, 0, 2, 1))!
        #expect(w.groups[0].shape == .four)
        #expect(w.created == [M3SpecialPiece(at: P(2, 1), piece: M3Piece(kind: .mushroom, special: .row))])
    }

    @Test func lShapeMakesABloomAtTheSwapCell() {
        let g = game("""
        c f m e d
        d e m c e
        m m f o c
        e d m f o
        """)
        let w = g.preview(S(3, 2, 2, 2))!
        #expect(w.groups.count == 1)
        #expect(w.groups[0].shape == .cross)
        #expect(w.groups[0].cells.count == 5)
        #expect(w.created == [M3SpecialPiece(at: P(2, 2), piece: M3Piece(kind: .mushroom, special: .bloom))])
    }

    @Test func tShapeMakesABloom() {
        let g = game("""
        c f e d c
        d e m f e
        f m o m o
        e c m f d
        c d m e f
        """)
        let w = g.preview(S(1, 2, 2, 2))!
        #expect(w.groups.count == 1)
        #expect(w.groups[0].shape == .cross)
        #expect(Set(w.groups[0].cells) == [P(2, 1), P(2, 2), P(2, 3), P(3, 2), P(4, 2)])
        #expect(w.created.first?.piece.special == .bloom)
        #expect(w.created.first?.at == P(2, 2))
    }

    @Test func fiveMakesAPrism() {
        let g = game("""
        c f m e d f
        m m f m m c
        e d c f o e
        """)
        let w = g.preview(S(0, 2, 1, 2))!
        #expect(w.groups[0].shape == .five)
        #expect(w.created == [M3SpecialPiece(at: P(1, 2), piece: .prism())])
        #expect(w.score == 5 * M3Rules.Points.piece + M3Rules.Points.createdPrism)
    }

    @Test func cascadeFourMakesACometAcrossItsRunAtTheLowestLeftmostCell() {
        let b = M3Board(picture: """
        c f e d
        m m m m
        e d c f
        """)
        let groups = M3Rules.findGroups(b, swap: nil)
        #expect(groups.count == 1)
        #expect(groups[0].creates == .column)
        #expect(groups[0].createdAt == P(1, 0))
        let v = M3Board(picture: """
        c m e
        f m c
        e m d
        d m f
        """)
        let vg = M3Rules.findGroups(v, swap: nil)
        #expect(vg[0].creates == .row)
        #expect(vg[0].createdAt == P(3, 1))
    }

    @Test func cascadeCrossPutsTheBloomOnTheCrossing() {
        let b = M3Board(picture: """
        c m e d
        f m c e
        m m m o
        e d c f
        """)
        let groups = M3Rules.findGroups(b, swap: nil)
        #expect(groups.count == 1)
        #expect(groups[0].creates == .bloom)
        #expect(groups[0].createdAt == P(2, 1))
    }

    @Test func separateGroupsComeInRowMajorOrder() {
        let b = M3Board(picture: """
        c c c d
        f m e e
        m d f o
        m d c f
        m d c f
        """)
        let groups = M3Rules.findGroups(b, swap: nil)
        #expect(groups.map(\.kind) == [.crystal, .mushroom, .drop])
    }

    @Test func prismsFlasksCratesAndHolesBreakRuns() {
        for middle in ["*", "F", "#1", ".", "_"] {
            let b = M3Board(picture: "m \(middle) m m\nc d c d")
            #expect(M3Rules.findGroups(b, swap: nil).isEmpty)
        }
        // Frozen pieces and comets keep their kind in a run.
        #expect(M3Rules.findGroups(M3Board(picture: "m m~ m- c\nc d c d"), swap: nil).count == 1)
    }
}

@Suite struct SwapRuleTests {
    @Test func illegalSwapsAreRefusedAndChangeNothing() {
        var g = game("""
        c f m e d
        m m f c e
        e d c f o
        """)
        let before = g.board
        for s in [S(0, 0, 0, 1), S(0, 0, 1, 1), S(0, 0, 0, 2), S(0, 4, 0, 5)] {
            let r = play(&g, s)
            #expect(!r.accepted)
            #expect(r.phases.isEmpty)
        }
        #expect(g.board == before)
        #expect(g.movesLeft == 20)
    }

    @Test func validSwapsAreExactlyTheLegalOnes() {
        let g = game("""
        c f m e d
        m m f c e
        e d c f o
        """)
        let listed = Set(g.validSwaps)
        var brute = Set<M3Swap>()
        for p in g.board.positions {
            for q in [P(p.row, p.col + 1), P(p.row + 1, p.col)] where g.board.contains(q) {
                var copy = g.board
                let a = copy[p].item, b = copy[q].item
                copy[p].item = b
                copy[q].item = a
                if M3Rules.hasMatch(copy) { brute.insert(M3Swap(p, q)) }
            }
        }
        #expect(listed == brute)
        #expect(listed.contains(S(0, 2, 1, 2)))
    }

    @Test func specialPairsSwapWithoutAMatchButACometAndAPlainPieceDoNot() {
        let g = game("""
        c m- f
        e c+ d
        f d e
        """)
        #expect(!g.isValidSwap(S(0, 0, 0, 1)))
        #expect(g.isValidSwap(S(0, 1, 1, 1)))
        let p = game("""
        c * f
        e c d
        """)
        #expect(p.isValidSwap(S(0, 1, 0, 2)))
        #expect(p.isValidSwap(S(0, 1, 1, 1)))
    }

    @Test func frozenPiecesAndFlasksCantBeSwapped() {
        let g = game("""
        c f m~ e
        m m c F
        e d e f
        """)
        #expect(!g.isValidSwap(S(0, 2, 1, 2)))
        #expect(!g.isValidSwap(S(1, 2, 0, 2)))
        #expect(!g.isValidSwap(S(1, 3, 0, 3)))
        #expect(!g.board.isSwappable(P(1, 3)))
    }
}

@Suite struct SpecialTests {
    @Test func cometFiresAlongItsRowAndChainsIntoABloom() {
        let g = game("""
        c f m e d
        m- m f c e+
        e d c f o
        """)
        let w = g.preview(S(0, 2, 1, 2))!
        #expect(w.activations.count == 2)
        #expect(w.activations[0].effect == .row)
        #expect(w.activations[0].at == P(1, 0))
        #expect(w.activations[1].effect == .square(radius: 1))
        #expect(w.activations[1].at == P(1, 4))
        let cleared = Set(w.cleared.map(\.at))
        #expect(cleared == [P(1, 0), P(1, 1), P(1, 2), P(1, 3), P(1, 4), P(0, 3), P(0, 4), P(2, 3), P(2, 4)])
        let bloomHits = w.cleared.filter { $0.activation == 1 }.map(\.at)
        #expect(Set(bloomHits) == [P(0, 3), P(0, 4), P(2, 3), P(2, 4)])
    }

    @Test func columnCometClearsItsColumn() {
        let g = game("""
        c f e d
        m| m f c
        e d m f
        f c d e
        """)
        let w = g.preview(S(2, 2, 1, 2))!
        #expect(w.activations.map(\.effect) == [.column])
        #expect(Set(w.cleared.map(\.at)) == [P(1, 0), P(1, 1), P(1, 2), P(0, 0), P(2, 0), P(3, 0)])
    }

    @Test func bloomClearsTheSquareAroundIt() {
        let g = game("""
        c f e d c
        d m+ m f e
        e d o m d
        f c d e f
        """)
        let w = g.preview(S(1, 3, 2, 3))!  // m from (2,3) up → m+ m m
        #expect(w.activations.map(\.effect) == [.square(radius: 1)])
        #expect(Set(w.cleared.map(\.at)) == [P(0, 0), P(0, 1), P(0, 2), P(1, 0), P(1, 1), P(1, 2), P(1, 3),
                                             P(2, 0), P(2, 1), P(2, 2)])
    }

    @Test func prismWithAPlainPieceClearsThatKind() {
        let g = game("""
        c * m e
        m d c m
        e m f d
        """)
        let w = g.preview(S(0, 1, 0, 2))!
        #expect(w.activations.count == 1)
        #expect(w.activations[0].effect == .kind(.mushroom))
        let clearedKinds = w.cleared.compactMap(\.piece.kind)
        #expect(clearedKinds.allSatisfy { $0 == .mushroom })
        #expect(clearedKinds.count == 4)
        #expect(w.cleared.contains { $0.piece.isPrism && $0.cause == .combo })
    }

    @Test func prismHitByABlastTakesTheMostCommonKind() {
        let g = game("""
        c f m e d f
        m- m f c * c
        e d c f e d
        c e d c f c
        """)
        let w = g.preview(S(0, 2, 1, 2))!
        // The row comet reaches the prism; most common unfrozen kind left: crystal.
        #expect(w.activations.map(\.effect) == [.row, .kind(.crystal)])
        #expect(!w.cleared.contains { $0.piece.kind == .crystal && $0.cause == .match })
        #expect(w.cleared.filter { $0.piece.kind == .crystal }.count == 7)
    }
}

@Suite struct ComboTests {
    @Test func cometPlusCometIsACrossAtTheTarget() {
        let g = game("""
        c f e d c
        d m- f| e c
        e d c f e
        f c d e f
        """)
        let w = g.preview(S(1, 1, 1, 2))!
        #expect(w.activations.count == 1)
        #expect(w.activations[0].effect == .cross(width: 1))
        #expect(w.activations[0].at == P(1, 2))
        let expected = Set((0..<5).map { P(1, $0) } + (0..<4).map { P($0, 2) })
        #expect(Set(w.cleared.map(\.at)) == expected)
        #expect(w.cleared.filter { $0.cause == .combo }.count == 2)
    }

    @Test func cometPlusBloomIsAThreeWideCross() {
        let g = game("""
        c f e d c f
        d m- f+ e c d
        e d c f e c
        f c d e f e
        c e f c d f
        """)
        let w = g.preview(S(1, 1, 1, 2))!
        #expect(w.activations.map(\.effect) == [.cross(width: 3)])
        let cleared = Set(w.cleared.map(\.at))
        #expect(cleared.count == 6 * 3 + 5 * 3 - 9)
        #expect(!cleared.contains(P(4, 0)))
        #expect(cleared.contains(P(4, 1)) && cleared.contains(P(0, 5)) && cleared.contains(P(2, 5)))
    }

    @Test func bloomPlusBloomIsAFiveByFiveSquare() {
        let g = game("""
        c f e d c f
        d c f e c d
        e d m+ f+ e c
        f c d e f e
        c e f c d f
        e d c f e c
        """)
        let w = g.preview(S(2, 2, 2, 3))!
        #expect(w.activations.map(\.effect) == [.square(radius: 2)])
        #expect(w.activations[0].at == P(2, 3))
        #expect(w.cleared.count == 25)
    }

    @Test func prismPlusCometTurnsTheKindIntoCometsThatAllFire() {
        let g = game("""
        c * m- e
        m d c f
        e f d m
        d c e f
        """)
        let w = g.preview(S(0, 1, 0, 2))!
        #expect(w.conversions.count == 2)  // (1,0) and (2,3); the comet itself stays a comet
        #expect(w.conversions.allSatisfy { $0.piece.kind == .mushroom && $0.piece.special?.isLine == true })
        // Converted comets alternate by cell parity: (1,0) odd → column, (2,3) odd → column.
        #expect(w.conversions.map(\.piece.special) == [.column, .column])
        #expect(w.activations.count == 3)
        #expect(w.cleared.contains { $0.piece.isPrism })
    }

    @Test func prismPlusPrismClearsTheBoard() {
        let g = game("""
        c * * e
        m d c f~
        F d #2 m
        """)
        let w = g.preview(S(0, 1, 0, 2))!
        #expect(w.activations.map(\.effect) == [.board])
        #expect(w.cleared.count == 9)  // every unfrozen piece
        #expect(w.frostHits == [M3Damage(at: P(1, 3), remaining: 0)])
        #expect(w.crateHits == [M3Damage(at: P(2, 2), remaining: 1)])
    }
}
