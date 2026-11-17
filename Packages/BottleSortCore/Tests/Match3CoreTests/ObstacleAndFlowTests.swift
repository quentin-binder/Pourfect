import BottleSortCore
import Testing
@testable import Match3Core

@Suite struct FrostTests {
    @Test func aMatchThroughFrostTakesOneLayerAndLeavesThePiece() {
        let g = game("""
        c f m e d
        e m f m= c
        d e c f e
        """)
        let w = g.preview(S(0, 2, 1, 2))!
        #expect(Set(w.cleared.map(\.at)) == [P(1, 1), P(1, 2)])
        // In the match AND next to a cleared cell: still only one layer per wave.
        #expect(w.frostHits == [M3Damage(at: P(1, 3), remaining: 1)])
    }

    @Test func aMatchBesideFrostTakesOneLayer() {
        var g = game("""
        c f m e d
        m m f c e
        e d= c f o
        """)
        let r = play(&g, S(0, 2, 1, 2))
        #expect(r.waves[0].frostHits == [M3Damage(at: P(2, 1), remaining: 1)])
        #expect(g.board[2, 1].piece?.frost == 1)
        #expect(g.board[2, 1].piece?.kind == .drop)
    }

    @Test func blastsThawWithoutClearing() {
        let g = game("""
        c f m e d
        m- m f c e~
        e d c f o
        """)
        let w = g.preview(S(0, 2, 1, 2))!
        #expect(w.cleared.count == 4)
        #expect(w.frostHits == [M3Damage(at: P(1, 4), remaining: 0)])
    }

    @Test func frozenPiecesFallWithGravity() {
        var g = game("""
        c f d~ e
        e d m c
        m m f e
        c e d f
        """)
        let r = play(&g, S(1, 2, 2, 2))
        guard case .settle(let s) = r.phases[2] else { Issue.record("expected a settle after wave 1"); return }
        #expect(s.falls.contains(M3Fall(from: P(0, 2), to: P(1, 2), item: .piece(M3Piece(kind: .drop, frost: 1)))))
        #expect(s.falls.contains(M3Fall(from: P(1, 2), to: P(2, 2), item: .piece(M3Piece(kind: .feather)))))
    }

    @Test func frostGoalCountsLayers() {
        var g = game("""
        c f m e d
        m m f c e
        e d= c f o
        """, goals: [.frost])
        #expect(g.progress(.frost) == (0, 2))
        _ = play(&g, S(0, 2, 1, 2))
        #expect(g.progress(.frost).current >= 1)
    }
}

@Suite struct CrateTests {
    @Test func aMatchBesideACrateHitsItOnce() {
        var g = game("""
        c f m e d
        m m f c e
        e #2 c f o
        """, goals: [.crates])
        let r = play(&g, S(0, 2, 1, 2))
        #expect(r.waves[0].crateHits == [M3Damage(at: P(2, 1), remaining: 1)])
        #expect(g.progress(.crates).current >= 1)
        #expect(g.progress(.crates).target == 2)
    }

    @Test func blastsHitCratesAndCratesDontFall() {
        let g = game("""
        c f m e d
        m- m f c #1
        e d c f o
        """)
        let w = g.preview(S(0, 2, 1, 2))!
        #expect(w.crateHits == [M3Damage(at: P(1, 4), remaining: 0)])
        #expect(w.cleared.count == 4)
    }

    @Test func piecesFallBehindCratesAndAcrossHoles() {
        for blocker in ["#3", "."] {
            var g = game("""
            c f e d
            e \(blocker) c f
            c d m m
            f m e c
            """)
            let r = play(&g, S(3, 1, 2, 1))
            #expect(r.accepted)
            guard case .settle(let s) = r.phases[2] else { Issue.record("expected a settle"); continue }
            #expect(s.falls.contains(M3Fall(from: P(0, 1), to: P(2, 1), item: .piece(M3Piece(kind: .feather)))))
            #expect(s.spawns.contains { $0.at == P(0, 1) })
            #expect(!s.spawns.contains { $0.at == P(1, 1) })
            if blocker == "#3" { #expect(r.waves[0].crateHits == [M3Damage(at: P(1, 1), remaining: 2)]) }
        }
    }

    @Test func aBrokenCrateOpensItsCellForGravity() {
        var g = game("""
        c f m e d
        m m f c e
        e #1 c f o
        """)
        let r = play(&g, S(0, 2, 1, 2))
        #expect(r.waves[0].crateHits == [M3Damage(at: P(2, 1), remaining: 0)])
        #expect(g.board[2, 1].crate == 0)
        #expect(g.board[2, 1].item != nil)
    }
}

@Suite struct FlaskTests {
    @Test func flasksFallAndAreCollectedOnTheBottomCell() {
        var g = game("""
        c F e
        e _ d
        c _ f
        """, goals: [.drops(1)], drops: M3Drops(total: 1))
        let s = g.settle()
        #expect(s.falls == [M3Fall(from: P(0, 1), to: P(2, 1), item: .flask)])
        #expect(s.spawns.map(\.at) == [P(1, 1), P(0, 1)])
        #expect(s.spawns.map(\.rank) == [0, 1])
        #expect(g.collectFlasks() == [P(2, 1)])
        #expect(g.flasksCollected == 1)
        #expect(g.goalsMet)
    }

    @Test func blastsPassFlasksBy() {
        let g = game("""
        c f m e d
        m- m f c F
        e d c f o
        """)
        let w = g.preview(S(0, 2, 1, 2))!
        #expect(w.cleared.count == 4)
        #expect(!w.cleared.contains { $0.at == P(1, 4) })
    }

    @Test func flasksSpawnUpToTheLimitAndTheGoalIsReached() {
        let level = M3Level(id: "t", title: "T", seed: 9, layout: ["oooFooo"] + Array(repeating: "ooooooo", count: 5),
                            kinds: fiveKinds, moves: 99, goals: [.drops(3)], stars: M3StarThresholds(two: 1, three: 2),
                            drops: M3Drops(total: 3, maxOnBoard: 1, columns: [2, 3, 4]))
        #expect(level.validate().isEmpty)
        var g = M3Game(level: level)!
        var rng = SplitMix64(seed: 3)
        var sawCollect = false
        while g.status == .playing, let s = M3Bot.choose(g, policy: .greedy, rng: &rng) {
            let r = play(&g, s)
            #expect(g.board.flaskCount <= 1)
            #expect(g.flasksSpawned <= 3)
            for case .collect(let cells) in r.phases {
                sawCollect = true
                #expect(cells.allSatisfy { $0.row == 5 })
            }
            for case .settle(let st) in r.phases {
                for sp in st.spawns where sp.item == .flask { #expect([2, 3, 4].contains(sp.at.col)) }
            }
        }
        #expect(sawCollect)
        #expect(g.status == .won)
        #expect(g.flasksCollected == 3)
    }
}

@Suite struct GravityRefillCascadeTests {
    @Test func refillDrawsKindsColumnsLeftToRightCellsBottomToTop() {
        var g = game("""
        c f m e
        m m f c
        e d c f
        """, seed: 77)
        let r = play(&g, S(0, 2, 1, 2))
        guard case .settle(let s) = r.phases[2] else { Issue.record("expected a settle"); return }
        var rng = SplitMix64(seed: 77)
        let expected = (0..<3).map { _ in fiveKinds[rng.nextInt(below: 5)] }
        #expect(s.spawns.map(\.at) == [P(0, 0), P(0, 1), P(0, 2)])
        #expect(s.spawns.map { $0.item.piece?.kind } == expected)
        #expect(Set(s.falls.map(\.to)) == [P(1, 0), P(1, 1), P(1, 2)])
    }

    @Test func gravityMakesACascadeWithAHigherMultiplier() {
        var g = game("""
        c f e d
        e o o c
        m m f o
        f e m d
        """)
        let r = play(&g, S(3, 2, 2, 2))
        let waves = r.waves
        #expect(waves.count >= 2)
        #expect(waves[1].cascade == 2)
        #expect(waves[1].groups.contains { $0.kind == .moonflower && Set($0.cells).isSuperset(of: [P(2, 1), P(2, 2), P(2, 3)]) })
        let pieces = waves[1].cleared.count
        #expect(waves[1].score >= pieces * M3Rules.Points.piece * 2)
        #expect(r.scoreGained == waves.reduce(0) { $0 + $1.score })
    }

    @Test func sameSwapsGiveTheSameResults() throws {
        let file = try loadEpisode(3)
        for level in file.levels.prefix(3) {
            var a = M3Game(level: level)!
            var b = M3Game(level: level)!
            #expect(a.board == b.board)
            var rng = SplitMix64(seed: 5)
            while a.status == .playing, let s = M3Bot.choose(a, policy: .novice, rng: &rng) {
                let ra = play(&a, s)
                let rb = play(&b, s)
                #expect(ra == rb)
            }
            #expect(a.board == b.board)
            #expect(a.score == b.score)
        }
    }

    @Test func boardsStayPlayableAfterEveryMove() throws {
        var checked = 0
        for n in [1, 5, 9] {
            for level in try loadEpisode(n).levels.prefix(4) {
                var g = M3Game(level: level)!
                var rng = SplitMix64(seed: UInt64(n))
                while g.status == .playing, let s = M3Bot.choose(g, policy: .random, rng: &rng) {
                    _ = play(&g, s)
                    checked += 1
                    if g.status == .playing {
                        #expect(M3Rules.hasValidSwap(g.board))
                        #expect(!M3Rules.hasMatch(g.board))
                    }
                }
            }
        }
        #expect(checked > 100)
    }
}

@Suite struct ReshuffleAndHintTests {
    static let dead = """
    m c f o
    f o m c
    m c f o
    f o m c
    """

    @Test func reshuffleMakesAPlayableBoardFromTheSamePieces() {
        var g = game(Self.dead, kinds: [.mushroom, .crystal, .feather, .moonflower])
        #expect(!M3Rules.hasValidSwap(g.board))
        let before = g.board.cells.compactMap(\.piece).map(\.kind)
        let r = g.reshuffle()
        #expect(r != nil)
        #expect(M3Rules.hasValidSwap(g.board))
        #expect(!M3Rules.hasMatch(g.board))
        if r?.rerolled.isEmpty == true {
            #expect(g.board.cells.compactMap(\.piece).map(\.kind).sorted { ($0?.index ?? 9) < ($1?.index ?? 9) }
                    == before.sorted { ($0?.index ?? 9) < ($1?.index ?? 9) })
        }
        // Deterministic.
        var h = game(Self.dead, kinds: [.mushroom, .crystal, .feather, .moonflower])
        _ = h.reshuffle()
        #expect(h.board == g.board)
    }

    @Test func reshuffleKeepsFrozenPiecesCratesAndFlasks() {
        var g = game("""
        m c f o
        f o~ m c
        m #1 f o
        f o F c
        """, kinds: [.mushroom, .crystal, .feather, .moonflower])
        if M3Rules.hasValidSwap(g.board) { return }
        _ = g.reshuffle()
        #expect(g.board[1, 1].piece == M3Piece(kind: .moonflower, frost: 1))
        #expect(g.board[2, 1].crate == 1)
        #expect(g.board[3, 2].item == .flask)
    }

    @Test func aMoveThatLeavesNoSwapReshuffles() {
        // Small boards with many kinds run out of swaps often: every reshuffle phase must leave a
        // board with a valid swap and no match, and the reshuffled game goes on.
        var seen = 0
        for seed in UInt64(1)...60 {
            let level = M3Level(id: "t", title: "T", seed: seed, layout: ["ooooo", "ooooo", "ooooo"],
                                kinds: Array(M3Kind.allCases), moves: 40, goals: [.score(1_000_000)],
                                stars: M3StarThresholds(two: 1, three: 2))
            guard var g = M3Game(level: level) else { continue }
            var rng = SplitMix64(seed: seed)
            while g.status == .playing, let s = M3Bot.choose(g, policy: .random, rng: &rng) {
                let r = play(&g, s)
                guard case .reshuffle(let rs)? = r.phases.last else { continue }
                seen += 1
                #expect(!rs.moves.isEmpty || !rs.rerolled.isEmpty)
                #expect(M3Rules.hasValidSwap(g.board))
                #expect(!M3Rules.hasMatch(g.board))
                #expect(g.status == .playing)
            }
        }
        #expect(seen > 5)
    }

    @Test func hintIsAValidSwapAndPrefersTheGoal() {
        let g = game("""
        c f m e d
        m m f c e
        e d c f o
        """, goals: [.collect(.mushroom, 10)])
        let h = g.hint()
        #expect(h != nil)
        #expect(g.isValidSwap(h!))
        #expect(game(Self.dead, kinds: [.mushroom, .crystal, .feather, .moonflower]).hint() == nil)
    }
}

@Suite struct GoalAndFinaleTests {
    static let board = """
    c f m e d
    m m f c e
    e d c f o
    """

    @Test func collectingTheGoalWins() {
        var g = game(Self.board, goals: [.collect(.mushroom, 3)])
        let r = play(&g, S(0, 2, 1, 2))
        #expect(r.status == .won)
        #expect(g.status == .won)
        #expect(g.stars >= 1)
        #expect(!play(&g, S(0, 0, 0, 1)).accepted)
    }

    @Test func runningOutOfMovesLoses() {
        var g = game(Self.board, goals: [.collect(.mushroom, 500)], moves: 1)
        let r = play(&g, S(0, 2, 1, 2))
        #expect(r.status == .lost)
        #expect(g.stars == 0)
        #expect(g.hint() == nil)
    }

    @Test func scoreGoalAndProgress() {
        var g = game(Self.board, goals: [.score(50), .collect(.mushroom, 2)])
        #expect(g.progress(.score(50)) == (0, 50))
        _ = play(&g, S(0, 2, 1, 2))
        #expect(g.progress(.score(50)) == (50, 50))
        #expect(g.progress(.collect(.mushroom, 2)) == (2, 2))
        #expect(g.status == .won)
    }

    @Test func starsFollowTheThresholds() {
        let t = M3StarThresholds(two: 100, three: 200)
        #expect(t.stars(score: 5000, won: false) == 0)
        #expect(t.stars(score: 0, won: true) == 1)
        #expect(t.stars(score: 99, won: true) == 1)
        #expect(t.stars(score: 100, won: true) == 2)
        #expect(t.stars(score: 200, won: true) == 3)
    }

    @Test func finaleSpendsEveryLeftoverMoveDeterministically() {
        var g = game(Self.board, goals: [.collect(.mushroom, 3)], moves: 6)
        _ = play(&g, S(0, 2, 1, 2))
        let scoreAtWin = g.score
        var h = g
        let f = g.playFinale()
        #expect(f.bursts.count == 5)
        #expect(g.movesLeft == 0)
        #expect(f.finalScore == g.score)
        #expect(f.scoreGained == g.score - scoreAtWin)
        #expect(f.scoreGained >= 5 * M3Rules.Points.finaleBurst)
        #expect(f.bursts.allSatisfy { [.row, .column, .bloom].contains($0.special) })
        #expect(f.stars == g.stars)
        #expect(h.playFinale() == f)
        // A second call does nothing.
        #expect(g.playFinale().bursts.isEmpty)
    }

    @Test func noFinaleBeforeAWin() {
        var g = game(Self.board, goals: [.collect(.mushroom, 50)])
        #expect(g.playFinale().bursts.isEmpty)
        #expect(g.movesLeft == 20)
    }
}
