import Foundation
import Testing
@testable import BottleSortCore

/// A bottle from color numbers carrying `modifiers`.
func bottle(_ colors: [Int], capacity: Int, _ modifiers: [BottleModifier] = []) -> Bottle {
    Bottle(layers: colors.map { .color(ColorID($0)) }, capacity: capacity, modifiers: modifiers)
}

/// C1 essence flasks: the rule cases.
@Suite struct EssenceRuleTests {
    let plain = Bottle(capacity: 4)

    @Test func hookVetoesOtherColorsAndKeysOnTheTargetSide() {
        var own = PourPlan(layer: .color(2))
        #expect(Rules.apply(.essence(2), as: .target, to: &own, source: plain, target: plain))
        #expect(own == PourPlan(layer: .color(2)))
        var other = PourPlan(layer: .color(1))
        #expect(!Rules.apply(.essence(2), as: .target, to: &other, source: plain, target: plain))
        var key = PourPlan(layer: .key(1))
        #expect(!Rules.apply(.essence(2), as: .target, to: &key, source: plain, target: plain))
        // A key its seal already accepted passes the rune.
        var sealKey = PourPlan(layer: .key(1))
        sealKey.opensSeal = 1
        #expect(Rules.apply(.essence(2), as: .target, to: &sealKey, source: plain, target: plain))
    }

    @Test func sourceSideChangesNothing() {
        for layer in [Layer.color(0), .color(2), .key(3)] {
            var plan = PourPlan(layer: layer)
            #expect(Rules.apply(.essence(2), as: .source, to: &plan, source: plain, target: plain))
            #expect(plan == PourPlan(layer: layer))
        }
    }

    @Test func emptyEssenceFlaskTakesOnlyItsColor() throws {
        let s = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([1, 0], capacity: 2), bottle([], capacity: 2, [.essence(0)])])
        #expect(!s.canPour(Move(from: 0, to: 2)))   // 1 on top: refused, although the flask is empty
        #expect(s.canPour(Move(from: 1, to: 2)))    // 0 on top: accepted
        let after = try #require(s.pouring(Move(from: 1, to: 2)))
        #expect(after.bottles[2].layers == [.color(0)])
        #expect(after.bottles[2].modifiers == [.essence(0)])   // the rune stays
        #expect(Rules.pourAmount(from: s.bottles[0], to: s.bottles[2]) == 0)
    }

    @Test func runOfItsColorFillsUpToTheFreeSpace() throws {
        let s = GameState(bottles: [bottle([1, 0, 0, 0], capacity: 4), bottle([0, 1, 1, 1], capacity: 4, [.essence(0)])])
        // Only 0s, and nothing onto a 1 top (base rule): the rune flask has 1 on top.
        #expect(!s.canPour(Move(from: 0, to: 1)))
        let t = GameState(bottles: [bottle([1, 0, 0, 0], capacity: 4), bottle([0], capacity: 4, [.essence(0)]),
                                    bottle([1, 1, 1], capacity: 4)])
        let after = try #require(t.pouring(Move(from: 0, to: 1)))
        #expect(after.bottles[1].layers.count == 4 && after.bottles[0].layers == [.color(1)])
    }

    @Test func mixedStartIsPouredOutNormally() throws {
        let s = GameState(bottles: [bottle([0, 1, 2], capacity: 3, [.essence(0)]), bottle([2, 2], capacity: 3),
                                    bottle([1, 1], capacity: 3), bottle([0, 0], capacity: 3)])
        #expect(s.canPour(Move(from: 0, to: 1)))
        let a = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(a.canPour(Move(from: 0, to: 2)))
        let b = try #require(a.pouring(Move(from: 0, to: 2)))
        #expect(b.canPour(Move(from: 3, to: 0)))
        let c = try #require(b.pouring(Move(from: 3, to: 0)))
        #expect(c.isSolved)
        #expect(Solver().solve(s).moves?.count == 3)
    }

    @Test func essenceFlaskMayPourIntoAnything() throws {
        let s = GameState(bottles: [bottle([1, 0], capacity: 2, [.essence(0)]), bottle([], capacity: 2), bottle([1], capacity: 2)])
        #expect(s.canPour(Move(from: 0, to: 1)))   // its own color out into a plain flask
        #expect(!s.canPour(Move(from: 0, to: 2)))  // base rule: 0 onto 1
    }

    @Test func keyIsRefusedByAnUnsealedRune() {
        let s = GameState(bottles: [Bottle(layers: [.color(0), .key(1)], capacity: 2),
                                    Bottle(layers: [], capacity: 2, modifiers: [.essence(0)]),
                                    Bottle(layers: [.color(0)], capacity: 2, lockedBy: 1)])
        #expect(!s.canPour(Move(from: 0, to: 1)))
        #expect(s.canPour(Move(from: 0, to: 2)))
    }

    /// Sealing rules apply first: a sealed essence flask takes its key (which opens the
    /// seal and leaves the rune), and nothing else, not even its own color.
    @Test func sealedEssenceFlask() throws {
        let s = GameState(bottles: [Bottle(layers: [.color(0), .color(0), .key(1)], capacity: 3),
                                    Bottle(layers: [.color(1), .color(0)], capacity: 3, modifiers: [.sealed(1), .essence(0)]),
                                    Bottle(layers: [.color(1), .color(1)], capacity: 3)])
        #expect(s.validate().isEmpty)
        #expect(!s.canPour(Move(from: 1, to: 2)))   // sealed: no pour out
        let opened = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(opened.bottles[1].modifiers == [.essence(0)])
        #expect(opened.bottles[1].lockedBy == nil)
        #expect(opened.canPour(Move(from: 0, to: 1)))   // its color goes in now
        #expect(!opened.canPour(Move(from: 2, to: 1)))  // 1s still don't (base rule and rune)
        #expect(Solver().solve(s).moves != nil)
        // 1s: refused by the seal and by the rune, so neither is "the" reason (plain shake).
        #expect(Rules.refusal(of: Move(from: 2, to: 1), in: s) == nil)
        // Its own color: only the seal refuses.
        let own = GameState(bottles: [bottle([1, 1, 0], capacity: 3), s.bottles[1], bottle([0, 0], capacity: 3)])
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: own)?.modifier == .sealed(1))
    }

    @Test func essenceFlaskWithItsColorFullIsSolved() {
        #expect(Rules.isSolved(bottle([2, 2, 2], capacity: 3, [.essence(2)])))
        #expect(Rules.isSolved(bottle([], capacity: 3, [.essence(2)])))
        #expect(!Rules.isSolved(bottle([2, 2], capacity: 3, [.essence(2)])))
        #expect(!Rules.isSolved(Bottle(layers: [], capacity: 3, modifiers: [.essence(2), .sealed(1)])))
        #expect(!Rules.blocksSolved(.essence(0)))
    }

    @Test func refusalNamesTheRune() {
        let s = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([1, 0], capacity: 2), bottle([], capacity: 2, [.essence(0)])])
        let refusal = Rules.refusal(of: Move(from: 0, to: 2), in: s)
        #expect(refusal?.bottle == 2 && refusal?.modifier == .essence(0))
        #expect(Rules.refusal(of: Move(from: 1, to: 2), in: s) == nil)   // legal
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: s) == nil)   // base rule (1 onto 0)
        #expect(Rules.refusal(of: Move(from: 2, to: 0), in: s) == nil)   // empty source
        #expect(Rules.refusal(of: Move(from: 0, to: 0), in: s) == nil)
    }

    /// The rune is named only when it is the reason: a full rune flask refuses every pour
    /// for being full, and a pour the top layer would refuse anyway gets the plain shake.
    @Test func refusalOnlyWhenTheRuneIsTheReason() {
        let full = GameState(bottles: [bottle([1, 1], capacity: 2), bottle([0, 0], capacity: 2, [.essence(1)]),
                                       bottle([], capacity: 2), bottle([0, 1], capacity: 2)])
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: full) == nil)   // wrong color, but full
        #expect(Rules.refusal(of: Move(from: 3, to: 1), in: full) == nil)   // own color, full
        let partial = GameState(bottles: [bottle([0, 2], capacity: 3), bottle([1], capacity: 3, [.essence(0)]),
                                          bottle([2, 1, 0], capacity: 3), bottle([2, 1], capacity: 3)])
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: partial) == nil)   // 2 onto 1: base rule too
        let refusal = Rules.refusal(of: Move(from: 3, to: 1), in: partial)   // 1 onto 1: only the rune says no
        #expect(refusal?.bottle == 1 && refusal?.modifier == .essence(0))
        #expect(Rules.refusal(of: Move(from: 2, to: 1), in: partial) == nil)   // 0 onto 1: base rule
    }

    @Test func displayHelpers() {
        #expect(bottle([], capacity: 2, [.essence(5)]).essenceColor == 5)
        #expect(Bottle(layers: [], capacity: 2, modifiers: [.sealed(1), .essence(3)]).essenceColor == 3)
        #expect(Bottle(capacity: 2).essenceColor == nil)
        #expect(Bottle(capacity: 2, lockedBy: 1).essenceColor == nil)
        var s = GameState(bottles: [bottle([0, 0], capacity: 2), bottle([], capacity: 2, [.essence(0)])])
        #expect(LevelDefinition(id: "a", state: s).mechanics == [.essence])
        #expect(LevelDefinition(id: "a", state: s, hidden: true).mechanics == [.murky, .essence])
        s.bottles[1].modifiers = []
        #expect(LevelDefinition(id: "a", state: s).mechanics.isEmpty)
        #expect(Mechanic.essence.rawValue == "essence")
        #expect(ChapterOutline.plan[3].introduces == [.essence])
    }

    @Test func legalMovesAgreeWithResolve() {
        let config = GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 2, locks: 1, essence: 2)
        for seed in UInt64(1)...20 {
            let s = Generator.candidate(config, seed: seed)
            for from in s.bottles.indices {
                for to in s.bottles.indices {
                    let move = Move(from: from, to: to)
                    #expect(s.canPour(move) == (Rules.resolve(s, afterAction: .pour(move)) != nil))
                    if from != to { #expect(s.canPour(move) == (Rules.pour(from: s.bottles[from], to: s.bottles[to]) != nil)) }
                }
            }
        }
    }
}

/// A hand-made puzzle in which the rune changes the solution.
@Suite struct EssencePuzzleTests {
    /// Without the rune the flask on the right is a free empty flask (5 moves); with it,
    /// it takes only color 2, which costs a detour (6 moves).
    static let puzzle = GameState(bottles: [
        bottle([1, 0, 0], capacity: 3),
        bottle([2, 2, 1], capacity: 3),
        bottle([0, 1, 2], capacity: 3),
        bottle([], capacity: 3, [.essence(2)]),
    ])

    @Test func runeAddsMoves() throws {
        let s = Self.puzzle
        #expect(s.validate().isEmpty)
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 6)
        #expect(referenceMinMoves(s) == 6)
        let plainLevel = MechanicImpact.removing(.modifier(bottle: 3, .essence(2)), from: s)
        let plainMoves = try #require(Solver().solve(plainLevel).moves)
        #expect(plainMoves.count == 5)
        // The plain optimum pours a foreign color into the rune flask: illegal here.
        var replay = s
        var refused = false
        for move in plainMoves {
            guard let next = replay.pouring(move) else {
                refused = Rules.refusal(of: move, in: replay)?.modifier == .essence(2)
                break
            }
            replay = next
        }
        #expect(refused)
        #expect(MechanicImpact.matters(.modifier(bottle: 3, .essence(2)), in: s, minMoves: 6))
        #expect(!MechanicImpact.matters(.modifier(bottle: 3, .essence(2)), in: s, minMoves: 6, cost: EssenceImpact.strongCost))
        #expect(EssenceImpact.everyEssenceMatters(s, minMoves: 6))
        #expect(!EssenceImpact.everyEssenceMatters(s, minMoves: 6, cost: 2))
    }

    @Test func solutionReplaysAndFillsTheRuneFlaskWithItsColor() throws {
        var session = GameSession(Self.puzzle)
        for move in try #require(Solver().solve(Self.puzzle).moves) {
            let applied = session.apply(move)
            #expect(applied)
        }
        #expect(session.isSolved)
        #expect(session.state.bottles[3].layers == [.color(2), .color(2), .color(2)])
    }

    @Test func essenceCanOnlyMakeALevelLonger() {
        let config = GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, essence: 1)
        for seed in UInt64(1)...30 {
            let s = Generator.candidate(config, seed: seed)
            guard let with = Solver().solve(s).moves?.count else { continue }
            let without = Solver().solve(MechanicImpact.removing(EssenceImpact.instances(in: s)[0], from: s)).moves?.count
            #expect(without != nil && without! <= with, "\(s)")
        }
    }
}

/// Solver correctness and pruning safety with essence flasks.
@Suite struct EssenceSolverTests {
    static let configs = [
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, essence: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, essence: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, essence: 2, essenceEmpty: 2),
        GeneratorConfig(colors: 3, capacity: 2, emptyBottles: 2, essence: 3),
        GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 2, essence: 1, essenceEmpty: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, essence: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, locks: 2, essence: 2),
    ]

    /// Solver vs. the naive BFS (no pruning, no canonical keys) on many small random levels.
    @Test(arguments: configs.indices)
    func solverMatchesReference(_ index: Int) {
        let config = Self.configs[index]
        var checked = 0
        for seed in UInt64(1)...25 {
            let s = Generator.candidate(config, seed: seed)
            #expect(s.validate().isEmpty, "\(s)")
            let expected = referenceMinMoves(s)
            let result = Solver().solve(s)
            #expect(result.moves?.count == expected, "\(s)")
            if case .unsolvable = result { #expect(expected == nil) }
            if let moves = result.moves {
                var replay = s
                for m in moves { replay = replay.pouring(m)! }
                #expect(replay.isSolved)
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    /// The pruned candidate list reaches the same canonical children as every legal move.
    @Test func pruningKeepsEveryDistinctChild() {
        for config in Self.configs {
            for seed in UInt64(1)...10 {
                var s = Generator.candidate(config, seed: seed)
                for step in 0..<6 {
                    let all = Set(s.legalMoves().compactMap { s.pouring($0)?.canonicalKey })
                    let pruned = Set(Solver.candidateMoves(s).compactMap { s.pouring($0)?.canonicalKey })
                    // Pruned moves only lead to the state itself (a canonical no-op) or to a kept child.
                    #expect(all.subtracting(pruned).isSubset(of: [s.canonicalKey]), "\(s)")
                    let moves = s.legalMoves()
                    guard !moves.isEmpty else { break }
                    s = s.pouring(moves[(Int(seed) + step) % moves.count])!
                }
            }
        }
    }

    /// The finished color of a plain flask into the empty rune flask of that color is a
    /// real move (the flasks are not alike) and must not be pruned as a relocation.
    @Test func moveIntoAnEmptyRuneFlaskIsNotPruned() {
        let s = GameState(bottles: [bottle([0, 0], capacity: 2), bottle([1, 1], capacity: 2),
                                    bottle([], capacity: 2, [.essence(0)]), bottle([], capacity: 2), bottle([], capacity: 2)])
        let moves = Solver.candidateMoves(s)
        #expect(moves.contains(Move(from: 0, to: 2)))
        #expect(!moves.contains(Move(from: 0, to: 3)))   // into a plain empty flask: a relocation
        #expect(!moves.contains(Move(from: 1, to: 2)))   // refused by the rune
        // Two alike empty rune flasks: only the first is tried.
        let twin = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([1, 0], capacity: 2),
                                       bottle([], capacity: 2, [.essence(1)]), bottle([], capacity: 2, [.essence(1)])])
        #expect(Solver.candidateMoves(twin) == [Move(from: 0, to: 2)])
    }

    /// Without pruning (a move counter forces the general path) the optimum is the same.
    @Test func unprunedPathAgrees() {
        for config in Self.configs.prefix(4) {
            for seed in UInt64(1)...6 {
                let s = Generator.candidate(config, seed: seed)
                var counted = s
                counted.moveCount = 0
                #expect(Solver.candidateMoves(counted) == counted.legalMoves())
                #expect(Solver().solve(counted).moves?.count == Solver().solve(s).moves?.count, "\(s)")
            }
        }
    }

    @Test func difficultyAnalysisRuns() throws {
        let report = try #require(Difficulty.analyze(EssencePuzzleTests.puzzle))
        #expect(report.minMoves == 6)
    }
}

/// StateKey with essence runes.
@Suite struct EssenceKeyTests {
    static func randomStates() -> [GameState] {
        var result: [GameState] = []
        for config in EssenceSolverTests.configs + [GeneratorConfig(colors: 6, emptyBottles: 2, locks: 1, essence: 3)] {
            for seed in UInt64(1)...8 {
                var s = Generator.candidate(config, seed: seed)
                result.append(s)
                for step in 0..<5 {
                    let moves = s.legalMoves()
                    guard !moves.isEmpty else { break }
                    s = s.pouring(moves[(Int(seed) * 7 + step) % moves.count])!
                    result.append(s)
                }
            }
        }
        return result
    }

    @Test func keyIsBottleOrderIndependent() {
        var rng = SplitMix64(seed: 4)
        for s in Self.randomStates() {
            for _ in 0..<3 {
                var order = Array(s.bottles.indices)
                rng.shuffle(&order)
                #expect(s.permuted(by: order).canonicalKey == s.canonicalKey)
            }
        }
    }

    /// The fast pair path writes exactly the general v2 codes.
    @Test func pairPathEqualsTheGeneralEncoding() {
        for s in Self.randomStates() {
            #expect(StateKey.pairCodes(s) == StateKey.extendedCodes(s), "\(s)")
        }
        // A cauldron with up to two recipes is one word; with three (several words) it falls
        // back to the general path.
        let c = GameState(bottles: [bottle([0], capacity: 1, [.cauldron([Recipe(0, 1, result: 2)])])])
        #expect(StateKey.pairCodes(c) == StateKey.extendedCodes(c))
        let c3 = GameState(bottles: [bottle([0], capacity: 1, [.cauldron([Recipe(0, 1, result: 2), Recipe(0, 2, result: 3),
                                                                          Recipe(1, 2, result: 4)])])])
        #expect(StateKey.pairCodes(c3) == nil)
        // Two seals (invalid, but encodable): the second one is an extension word.
        let twoSeals = GameState(bottles: [Bottle(layers: [], capacity: 2, modifiers: [.sealed(1), .sealed(2)])])
        #expect(StateKey.pairCodes(twoSeals) == StateKey.extendedCodes(twoSeals))
    }

    @Test func runeIsPartOfTheKey() {
        let a = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([], capacity: 2, [.essence(0)]), bottle([1, 0], capacity: 2)])
        var b = a
        b.bottles[1].modifiers = [.essence(1)]
        var c = a
        c.bottles[1].modifiers = []
        var d = a   // the rune on another (non-empty) flask
        d.bottles[1].modifiers = []
        d.bottles[0].modifiers = [.essence(0)]
        let keys = [a, b, c, d].map(\.canonicalKey)
        #expect(Set(keys).count == 4)
        // Classic and sealed states still produce v1 words (one per bottle).
        #expect(c.canonicalKey.codes.count == 3)
    }

    @Test func emptyRuneFlaskIsNotAnEmptyPlainFlask() {
        // Same layers; the rune sits on one of two empty flasks, or on none.
        let a = GameState(bottles: [bottle([0, 0], capacity: 2), bottle([], capacity: 2, [.essence(0)]), bottle([], capacity: 2)])
        let b = GameState(bottles: [bottle([0, 0], capacity: 2), bottle([], capacity: 2), bottle([], capacity: 2, [.essence(0)])])
        let c = GameState(bottles: [bottle([0, 0], capacity: 2, [.essence(0)]), bottle([], capacity: 2), bottle([], capacity: 2)])
        #expect(a.canonicalKey == b.canonicalKey)
        #expect(a.canonicalKey != c.canonicalKey)
    }
}

/// Level files, validation and sessions with essence flasks.
@Suite struct EssenceLevelTests {
    @Test func jsonRoundTrip() throws {
        var s = EssencePuzzleTests.puzzle
        s.bottles[1].lockedBy = 1
        s.bottles[3].layers = [.key(1)]
        let level = LevelDefinition(id: "e1", state: s, meta: LevelMeta(seed: 3, minMoves: 7))
        let pack = LevelPack(name: "Glyph Library", kind: .chapter, chapter: 4, location: "Glyph Library",
                             introduces: [.essence], levels: [level])
        #expect(pack.requiredVersion == 2)
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""version" : 2"#))
        #expect(text.contains(#""type" : "essence""#) && text.contains(#""color" : 2"#))
        #expect(text.contains(#""lockedBy" : 1"#))
        let loaded = try LevelLoader.load(data)   // validates too
        #expect(loaded.levels == pack.levels && loaded.introduces == [.essence])
        #expect(loaded.levels[0].gameState == s)
        #expect(loaded.levels[0].gameState.canonicalKey == s.canonicalKey)
        #expect(try LevelLoader.encode(loaded) == data)
    }

    @Test func handWrittenJSON() throws {
        let json = #"""
        {"version": 2, "levels": [{"id": "a", "capacity": 2, "bottles": [
          {"layers": [0, 1]}, {"layers": [1, 0]}, {"layers": [], "modifiers": [{"type": "essence", "color": 1}]}]}]}
        """#
        let pack = try LevelLoader.load(Data(json.utf8))
        #expect(pack.levels[0].gameState.bottles[2].essenceColor == 1)
        let v1 = json.replacingOccurrences(of: #""version": 2"#, with: #""version": 1"#)
        #expect(throws: LevelLoadError.needsVersion2(id: "a")) { try LevelLoader.load(Data(v1.utf8)) }
    }

    @Test func validation() {
        var s = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([1, 0], capacity: 2), bottle([], capacity: 2, [.essence(0)])])
        #expect(s.validate().isEmpty)
        s.bottles[2].modifiers = [.essence(0), .essence(1)]
        #expect(s.validate() == [.multipleEssences(bottle: 2)])
        s.bottles[2].modifiers = [.essence(7)]
        #expect(s.validate() == [.essenceColorAbsent(bottle: 2, color: 7)])
        s.bottles[2].modifiers = [.essence(-1)]
        #expect(s.validate() == [.essenceColorAbsent(bottle: 2, color: -1)])
        s.bottles[2].modifiers = [.essence(99)]
        #expect(s.validate() == [.essenceColorAbsent(bottle: 2, color: 99)])
        #expect(!StateKey.canEncode(s))
        #expect(ValidationError.multipleEssences(bottle: 2).description.contains("essence"))
        // A rune flask starting full of another color would count as sorted: rejected.
        let fullOther = GameState(bottles: [bottle([1, 1], capacity: 2, [.essence(0)]), bottle([0, 0], capacity: 2)])
        #expect(fullOther.validate() == [.essenceFullOfOtherColor(bottle: 0, color: 1)])
        #expect(Rules.isSolved(fullOther.bottles[0]))   // why validation has to catch it
        let fullOwn = GameState(bottles: [bottle([0, 0], capacity: 2, [.essence(0)]), bottle([1, 1], capacity: 2)])
        #expect(fullOwn.validate().isEmpty)
        let mixed = GameState(bottles: [bottle([1, 0], capacity: 2, [.essence(0)]), bottle([1, 0], capacity: 2)])
        #expect(mixed.validate().isEmpty)
        let partly = GameState(bottles: [bottle([1], capacity: 2, [.essence(0)]), bottle([1, 0, 0], capacity: 3)])
        #expect(!partly.validate().contains { if case .essenceFullOfOtherColor = $0 { true } else { false } })
    }

    @Test func undoAndRestartRestoreTheFullState() throws {
        var s = EssencePuzzleTests.puzzle
        s.bottles[1].lockedBy = 1
        s.bottles[3].layers = [.key(1)]
        // Key into the seal, then play on; undo brings back seal, key, rune and layers.
        var session = GameSession(s, hidden: true)
        let depths = session.hiddenDepths
        let keyPoured = session.apply(Move(from: 3, to: 1))
        #expect(keyPoured)
        #expect(session.state.bottles[1].lockedBy == nil)
        #expect(session.state.bottles[3].modifiers == [.essence(2)])
        let afterKey = session.state
        let solution = try #require(Solver().solve(afterKey).moves)
        for move in solution {
            let applied = session.apply(move)
            #expect(applied)
        }
        #expect(session.isSolved)
        #expect(session.moveCount == solution.count + 1)
        for _ in solution { session.undo() }
        #expect(session.state == afterKey)
        session.undo()
        #expect(session.state == s && session.hiddenDepths == depths)
        session.apply(Move(from: 3, to: 1))
        session.restart()
        #expect(session.state == s && session.hiddenDepths == depths && session.moveCount == 0)
        // A refused pour changes nothing and records no history.
        let refused = !session.apply(Move(from: 0, to: 3))
        #expect(refused && session.moveCount == 0)
    }
}

/// Generator options for essence flasks.
@Suite struct EssenceGeneratorTests {
    @Test func zeroEssenceLeavesTheLayoutUnchanged() {
        for seed in UInt64(1)...10 {
            let plain = Generator.candidate(GeneratorConfig(colors: 5, locks: 1), seed: seed)
            let marked = Generator.candidate(GeneratorConfig(colors: 5, locks: 1, essence: 2), seed: seed)
            #expect(marked.bottles.map(\.layers) == plain.bottles.map(\.layers))
            #expect(marked.bottles.map(\.lockedBy) == plain.bottles.map(\.lockedBy))
            #expect(plain.bottles.allSatisfy { $0.essenceColor == nil })
        }
    }

    @Test func placementRules() {
        for seed in UInt64(1)...40 {
            let config = GeneratorConfig(colors: 5, emptyBottles: 2, locks: 1, essence: 3)
            let s = Generator.candidate(config, seed: seed)
            let runes = s.bottles.compactMap(\.essenceColor)
            #expect(runes.count == 3)
            #expect(Set(runes).count == runes.count)   // different colors
            for b in s.bottles where b.essenceColor != nil && !b.isEmpty {
                #expect(b.layers.first?.colorID == b.essenceColor)   // a filled flask: its bottom color
            }
            #expect(s.validate().isEmpty)
            let empties = Generator.candidate(GeneratorConfig(colors: 5, emptyBottles: 2, essence: 2, essenceEmpty: 2), seed: seed)
            let emptyRunes = empties.bottles.filter { $0.essenceColor != nil }
            #expect(emptyRunes.count == 2 && emptyRunes.allSatisfy { $0.isEmpty })
            let filled = Generator.candidate(GeneratorConfig(colors: 5, emptyBottles: 2, essence: 2, essenceEmpty: 0), seed: seed)
            let filledRunes = filled.bottles.filter { $0.essenceColor != nil }
            #expect(filledRunes.allSatisfy { !$0.isEmpty })
        }
    }

    /// Murky levels: a rune never tells a hidden layer. Placement reads only which flasks
    /// are empty, so two layouts with the same empty flasks get the same runes from the
    /// same random stream, whatever their (hidden) layers are.
    @Test func hiddenPlacementIgnoresLayers() {
        let config = GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, essence: 2, essenceEmpty: 0, hidden: true)
        var differsFromBottom = 0
        for seed in UInt64(1)...30 {
            let a = Generator.candidate(GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2), seed: seed)
            var b = a
            for i in b.bottles.indices where !b.bottles[i].isEmpty {
                b.bottles[i].layers = b.bottles[i].layers.map { $0.colorID.map { .color(ColorID(($0.rawValue + 1) % 4)) } ?? $0 }
            }
            var markedA = a.bottles, markedB = b.bottles
            var rngA = SplitMix64(seed: seed), rngB = SplitMix64(seed: seed)
            Generator.markEssence(&markedA, config: config, rng: &rngA)
            Generator.markEssence(&markedB, config: config, rng: &rngB)
            #expect(markedA.map(\.modifiers) == markedB.map(\.modifiers))
            #expect(markedA.filter { $0.essenceColor != nil }.count == 2)
            differsFromBottom += markedA.filter { $0.essenceColor != nil && $0.layers.first?.colorID != $0.essenceColor }.count
        }
        #expect(differsFromBottom > 0)
        // Not murky: unchanged, a filled flask keeps its bottom color.
        let visible = Generator.candidate(GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, essence: 2, essenceEmpty: 0), seed: 3)
        #expect(visible.bottles.filter { $0.essenceColor != nil }.allSatisfy { $0.layers.first?.colorID == $0.essenceColor })
    }

    @Test func generationIsDeterministicAndRunesMatter() throws {
        let config = GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 2, seed: 77, essence: 2,
                                     requireEssenceMatter: true, essenceCost: EssenceImpact.strongCost)
        let a = try Generator.generate(config, count: 2)
        let b = try Generator.generate(config, count: 2)
        #expect(a == b)
        for level in a {
            #expect(EssenceImpact.instances(in: level.state).count == 2)
            #expect(EssenceImpact.everyEssenceMatters(level.state, minMoves: level.report.minMoves, cost: EssenceImpact.strongCost))
        }
    }

    @Test func impactConstants() {
        #expect(EssenceImpact.minimumCost == MechanicImpact.minimumCost(of: .modifier(bottle: 0, .essence(0))))
        #expect(EssenceImpact.strongCost == 2)
    }
}
