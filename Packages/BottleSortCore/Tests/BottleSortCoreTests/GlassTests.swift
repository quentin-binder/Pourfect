import Foundation
import Testing
@testable import BottleSortCore

/// Layers from color numbers, with `.key(k)` for negative numbers −k.
private func layers(_ values: [Int]) -> [Layer] {
    values.map { $0 < 0 ? .key(KeyID(-$0)) : .color(ColorID($0)) }
}

/// C2 narrow necks and C4 funnels / taps: the rule cases.
@Suite struct GlassRuleTests {
    @Test func narrowNeckPoursOneLayerOut() throws {
        let s = GameState(bottles: [bottle([0, 1, 1, 1], capacity: 4, [.narrowNeck]), bottle([], capacity: 4)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[0].layers == layers([0, 1, 1]))
        #expect(turn.state.bottles[1].layers == layers([1]))
        #expect(turn.pour == PourEvent(move: Move(from: 0, to: 1), layer: .color(1), amount: 1))
        #expect(Rules.pourAmount(from: s.bottles[0], to: s.bottles[1]) == 1)
    }

    @Test func narrowNeckTakesOneLayerIn() {
        let source = bottle([0, 2, 2, 2], capacity: 4)
        #expect(Rules.pourAmount(from: source, to: bottle([], capacity: 4, [.narrowNeck])) == 1)
        #expect(Rules.pourAmount(from: source, to: bottle([2], capacity: 4, [.narrowNeck])) == 1)
        #expect(Rules.pourAmount(from: source, to: bottle([1], capacity: 4, [.narrowNeck])) == 0)   // colors differ
        #expect(Rules.pourAmount(from: source, to: bottle([2], capacity: 4)) == 3)                 // plain: the whole run
        // A narrow neck changes nothing else: full target, and a single layer, as before.
        #expect(Rules.pourAmount(from: source, to: bottle([2, 2, 2, 2], capacity: 4, [.narrowNeck])) == 0)
        #expect(Rules.pourAmount(from: bottle([1, 2], capacity: 4), to: bottle([], capacity: 4, [.narrowNeck])) == 1)
    }

    @Test func narrowNeckKeyOpensASeal() throws {
        let s = GameState(bottles: [Bottle(layers: layers([0, -1]), capacity: 2, modifiers: [.narrowNeck]),
                                    Bottle(layers: layers([1, 1]), capacity: 2, lockedBy: 1),
                                    Bottle(layers: layers([0]), capacity: 2)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[1].lockedBy == nil && turn.state.bottles[1].layers == layers([1, 1]))
        #expect(turn.pour?.openedSeal == 1 && turn.pour?.amount == 1)
        // A sealed narrow neck opens with its key and keeps its neck.
        let sealedNeck = GameState(bottles: [Bottle(layers: layers([-1]), capacity: 2),
                                             Bottle(layers: layers([0]), capacity: 2, modifiers: [.sealed(1), .narrowNeck]),
                                             Bottle(layers: layers([0]), capacity: 2)])
        let opened = try #require(sealedNeck.pouring(Move(from: 0, to: 1)))
        #expect(opened.bottles[1].modifiers == [.narrowNeck])
    }

    @Test func funnelReceivesButNeverPours() throws {
        let s = GameState(bottles: [bottle([1, 0, 0], capacity: 4), bottle([0], capacity: 4, [.funnel]),
                                    bottle([], capacity: 4)])
        // Receives normally: the whole run.
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[1].layers == layers([0, 0, 0]))
        // Never pours, even into an empty flask.
        #expect(!s.canPour(Move(from: 1, to: 2)) && !s.canPour(Move(from: 1, to: 0)))
        #expect(!s.legalMoves().contains { $0.from == 1 })
        var plan = PourPlan(layer: .color(0))
        #expect(!Rules.apply(.funnel, as: .source, to: &plan, source: s.bottles[1], target: s.bottles[2]))
        #expect(Rules.apply(.funnel, as: .target, to: &plan, source: s.bottles[0], target: s.bottles[1]))
        #expect(Rules.refusal(of: Move(from: 1, to: 2), in: s)! == (1, .funnel))
        #expect(Rules.outlet(of: s.bottles[1]) == nil)
    }

    @Test func funnelSolvedWhenFullWithOneColor() {
        #expect(Rules.isSolved(bottle([0, 0], capacity: 2, [.funnel])))
        #expect(Rules.isSolved(bottle([], capacity: 2, [.funnel])))
        #expect(!Rules.isSolved(bottle([0], capacity: 2, [.funnel])))
        #expect(Rules.isSolved(bottle([], capacity: 2, [.tap])) && Rules.isSolved(bottle([1, 1], capacity: 2, [.tap])))
        #expect(Rules.isSolved(bottle([1, 1], capacity: 2, [.narrowNeck])))
    }

    @Test func tapPoursItsBottomRunAndTheStackSlidesDown() throws {
        let s = GameState(bottles: [bottle([0, 0, 1, 2], capacity: 4, [.tap]), bottle([], capacity: 4)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[0].layers == layers([1, 2]))
        #expect(turn.state.bottles[1].layers == layers([0, 0]))
        let event = try #require(turn.pour)
        #expect(event.fromBottom && event.amount == 2 && event.layer == .color(0) && event.openedSeal == nil)
        #expect(event.sourceRange(sourceCountBefore: 4) == 0..<2)
        // A top pour reports the top range.
        let top = PourEvent(move: Move(from: 0, to: 1), layer: .color(2), amount: 1)
        #expect(top.sourceRange(sourceCountBefore: 4) == 3..<4)
    }

    @Test func tapIsLimitedByTheTargetAndItsRules() {
        let tap = bottle([0, 0, 0, 1], capacity: 4, [.tap])
        #expect(Rules.pourAmount(from: tap, to: bottle([0, 0], capacity: 4)) == 2)        // free space
        #expect(Rules.pourAmount(from: tap, to: bottle([1], capacity: 4)) == 0)           // the top 1 doesn't count
        #expect(Rules.pourAmount(from: tap, to: bottle([], capacity: 4, [.narrowNeck])) == 1)
        #expect(Rules.pourAmount(from: tap, to: bottle([], capacity: 4, [.essence(0)])) == 3)
        #expect(Rules.pourAmount(from: tap, to: bottle([], capacity: 4, [.essence(1)])) == 0)   // judged by the bottom
        #expect(Rules.pourAmount(from: tap, to: bottle([], capacity: 4, [.funnel])) == 3)
        let afterPartial = Rules.pour(from: tap, to: bottle([0, 0], capacity: 4))
        #expect(afterPartial?.source.layers == layers([0, 1]))
        #expect(Rules.pourAmount(from: bottle([], capacity: 4, [.tap]), to: bottle([], capacity: 4)) == 0)
    }

    @Test func tapNeverReceives() {
        let s = GameState(bottles: [bottle([1, 0], capacity: 4), bottle([0], capacity: 4, [.tap]),
                                    bottle([], capacity: 4, [.tap])])
        #expect(!s.canPour(Move(from: 0, to: 1)) && !s.canPour(Move(from: 0, to: 2)))
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: s)! == (1, .tap))
        #expect(Rules.refusal(of: Move(from: 0, to: 2), in: s)! == (2, .tap))
        // Not even a key: a sealed tap is refused by validation, and the rule refuses the key anyway.
        let sealedTap = GameState(bottles: [Bottle(layers: layers([-1]), capacity: 2),
                                            Bottle(layers: layers([0, 0]), capacity: 2, modifiers: [.sealed(1), .tap])])
        #expect(!sealedTap.canPour(Move(from: 0, to: 1)))
        #expect(sealedTap.validate().contains(.sealedTap(bottle: 1)))
        // The tap pours into a plain flask and the refusal of a legal move is nil.
        #expect(s.canPour(Move(from: 1, to: 0)) && Rules.refusal(of: Move(from: 1, to: 0), in: s) == nil)
    }

    @Test func closedSidesExplainEvenWhenTheBaseRuleRefuses() {
        // Every chapter 5 tap starts full: pouring into it is still "a tap never fills".
        let s = GameState(bottles: [bottle([1, 0], capacity: 3), bottle([0, 1, 2], capacity: 3, [.tap]),
                                    bottle([2, 2], capacity: 2, [.funnel]), bottle([0, 0, 0], capacity: 3)])
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: s)! == (1, .tap))       // full and a tap
        // A funnel never pours, even onto a full flask or a wrong color.
        #expect(Rules.refusal(of: Move(from: 2, to: 3), in: s)! == (2, .funnel))
        #expect(Rules.refusal(of: Move(from: 2, to: 0), in: s)! == (2, .funnel))
        // Conditional modifiers keep the old rule: a full essence flask refuses for being full.
        let full = GameState(bottles: [bottle([1], capacity: 2), bottle([0, 0], capacity: 2, [.essence(0)])])
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: full) == nil)
    }

    @Test func tapPoursABottomKeyAlone() throws {
        let s = GameState(bottles: [Bottle(layers: layers([-1, 0, 0]), capacity: 3, modifiers: [.tap]),
                                    Bottle(layers: layers([1, 1, 1]), capacity: 3, lockedBy: 1),
                                    Bottle(layers: layers([0]), capacity: 3)])
        #expect(Rules.movableBottomRunCount(s.bottles[0]) == 1)
        #expect(!s.canPour(Move(from: 0, to: 2)))   // a key goes only into its seal
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[0].layers == layers([0, 0]))
        #expect(turn.state.bottles[1].lockedBy == nil)
        #expect(turn.pour?.openedSeal == 1 && turn.pour?.fromBottom == true)
    }

    @Test func displayHelpers() {
        let neck = bottle([0, 1, 1], capacity: 4, [.narrowNeck])
        let funnel = bottle([2], capacity: 4, [.funnel])
        let tap = bottle([0, 0, 1], capacity: 4, [.tap])
        #expect(neck.hasNarrowNeck && !neck.isFunnel && !neck.hasTap)
        #expect(funnel.isFunnel && tap.hasTap && !bottle([], capacity: 4).hasTap)
        #expect(tap.bottomRunCount == 2 && neck.bottomRunCount == 1 && bottle([], capacity: 4).bottomRunCount == 0)
        #expect(Rules.outlet(of: neck)! == (2..<3, false))
        #expect(Rules.outlet(of: tap)! == (0..<2, true))
        #expect(Rules.outlet(of: bottle([0, 1, 1], capacity: 4))! == (1..<3, false))
        #expect(Rules.outlet(of: funnel) == nil && Rules.outlet(of: bottle([], capacity: 4)) == nil)
        #expect(Rules.outlet(of: Bottle(layers: layers([0]), capacity: 4, lockedBy: 1)) == nil)
        let level = LevelDefinition(id: "g", state: GameState(bottles: [neck, funnel, tap,
                                                                       Bottle(layers: [], capacity: 4, lockedBy: 1)]),
                                    hidden: true)
        #expect(level.mechanics == [.sealed, .murky, .narrowNeck, .funnel, .tap])
        #expect(ChapterOutline.plan[4].introduces == [.narrowNeck, .funnel, .tap])
    }

    @Test func legalMovesAgreeWithResolve() {
        for s in GlassKeyTests.randomStates() {
            for from in s.bottles.indices {
                for to in s.bottles.indices {
                    let move = Move(from: from, to: to)
                    #expect(s.canPour(move) == (Rules.resolve(s, afterAction: .pour(move)) != nil))
                }
            }
        }
    }
}

/// Hand-made puzzles where the glass decides the solution.
@Suite struct GlassPuzzleTests {
    /// The run of two 1s must leave the narrow neck one at a time: 4 moves instead of 3.
    @Test func narrowNeckCostsAMove() throws {
        let s = GameState(bottles: [bottle([0, 1, 1], capacity: 3, [.narrowNeck]), bottle([1, 0, 0], capacity: 3),
                                    bottle([], capacity: 3)])
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 4)
        #expect(referenceMinMoves(s) == 4)
        let without = MechanicImpact.removing(.modifier(bottle: 0, .narrowNeck), from: s)
        #expect(Solver().solve(without).moves?.count == 3)
        #expect(MechanicImpact.matters(.modifier(bottle: 0, .narrowNeck), in: s, minMoves: 4))
        var replay = s
        for m in moves { replay = try #require(replay.pouring(m)) }
        #expect(replay.isSolved)
    }

    /// The tap's bottom 0 drains first (the stack above slides down), then its 1s follow.
    @Test func tapDrainsFromTheBottom() throws {
        let s = GameState(bottles: [bottle([0, 1, 1], capacity: 3, [.tap]), bottle([0, 0], capacity: 3),
                                    bottle([1], capacity: 3)])
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves == [Move(from: 0, to: 1), Move(from: 0, to: 2)])
        var current = s
        for m in moves {
            let turn = try #require(Rules.resolve(current, afterAction: .pour(m)))
            #expect(turn.pour?.fromBottom == true)
            current = turn.state
        }
        #expect(current.isSolved && current.bottles[0].isEmpty)
        // As a plain flask the top 1s would have to leave first.
        let plain = MechanicImpact.removing(.modifier(bottle: 0, .tap), from: s)
        #expect(Solver().solve(plain).moves?.first == Move(from: 0, to: 2))
    }

    /// A tap that would never be emptied keeps the level unsolved: it ends empty or full of one color.
    @Test func tapMustEndEmptyOrSorted() {
        let s = GameState(bottles: [bottle([0, 1], capacity: 2, [.tap]), bottle([1], capacity: 2), bottle([0], capacity: 2)])
        #expect(!s.isSolved)
        #expect(Solver().solve(s).moves?.count == 2)
    }

    /// A funnel never changes the optimum but sets traps: in the first funnel recipe a pour
    /// into the funnel a few moves in loses the level, which a plain flask would have saved.
    @Test func funnelSetsATrap() throws {
        let level = try #require(try LevelFileTests.load("chapter_05").levels.first { $0.mechanics.contains(.funnel) })
        let s = level.gameState
        let funnel = try #require(GlassImpact.instances(in: s).first)
        let minMoves = try #require(level.meta?.minMoves)
        #expect(Solver().solve(MechanicImpact.removing(funnel, from: s)).moves?.count == minMoves)
        let depth = try #require(MechanicImpact.trapDepth(of: funnel, in: s))
        #expect(depth >= 1 && depth <= minMoves)
        #expect(MechanicImpact.matters(funnel, in: s, minMoves: minMoves))
        // An empty funnel next to plenty of room sets no trap: it doesn't matter.
        let roomy = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([1, 0], capacity: 2),
                                        bottle([], capacity: 2), bottle([], capacity: 2, [.funnel])])
        #expect(MechanicImpact.trapDepth(of: .modifier(bottle: 3, .funnel), in: roomy) == nil)
        #expect(!MechanicImpact.matters(.modifier(bottle: 3, .funnel), in: roomy, minMoves: Solver().solve(roomy).moves!.count))
    }

    @Test func twoSidedInstances() {
        #expect(MechanicImpact.isTwoSided(.modifier(bottle: 0, .narrowNeck)))
        #expect(MechanicImpact.isTwoSided(.modifier(bottle: 0, .tap)))
        #expect(!MechanicImpact.isTwoSided(.modifier(bottle: 0, .funnel)))
        #expect(!MechanicImpact.isTwoSided(.modifier(bottle: 0, .essence(0))) && !MechanicImpact.isTwoSided(.seal(1)))
        #expect(GlassImpact.minimumCost == MechanicImpact.minimumCost(of: .modifier(bottle: 0, .tap)))
        #expect(GlassImpact.strongCost == 2)
    }
}

/// The solver with glass modifiers: exact, and its pruning stays safe.
@Suite struct GlassSolverTests {
    static let configs = [
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, narrowNecks: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, narrowNecks: 3),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, funnels: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, funnels: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, taps: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, taps: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, narrowNecks: 1, funnels: 1, taps: 1),
        GeneratorConfig(colors: 3, capacity: 2, emptyBottles: 2, narrowNecks: 2, taps: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, narrowNecks: 1, taps: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, essence: 1, narrowNecks: 1, funnels: 1),
    ]

    /// Solver vs. the naive BFS (no pruning, no canonical keys) on many small random levels.
    @Test(arguments: configs.indices)
    func solverMatchesReference(_ index: Int) throws {
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
                for m in moves { replay = try #require(replay.pouring(m)) }
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
                    #expect(all.subtracting(pruned).isSubset(of: [s.canonicalKey]), "\(s)")
                    let moves = s.legalMoves()
                    guard !moves.isEmpty else { break }
                    s = s.pouring(moves[(Int(seed) + step) % moves.count])!
                }
            }
        }
    }

    /// Rule 2 (a whole-content pour into an empty flask alike is a relocation) must not
    /// prune a narrow neck that moves only one of its layers, and rule 1 must not skip a
    /// finished plain flask while an empty glass flask could take it.
    @Test func relocationRulesRespectTheGlass() {
        let necks = GameState(bottles: [bottle([0, 0], capacity: 2, [.narrowNeck]), bottle([], capacity: 2, [.narrowNeck]),
                                        bottle([1, 1], capacity: 2)])
        #expect(Solver.candidateMoves(necks).contains(Move(from: 0, to: 1)))
        let single = GameState(bottles: [bottle([0], capacity: 2, [.narrowNeck]), bottle([], capacity: 2, [.narrowNeck]),
                                         bottle([1, 1, ], capacity: 2), bottle([0], capacity: 2)])
        #expect(!Solver.candidateMoves(single).contains(Move(from: 0, to: 1)))   // moves everything: a relocation
        let funnel = GameState(bottles: [bottle([0, 0], capacity: 2), bottle([1, 1], capacity: 2),
                                         bottle([], capacity: 2, [.funnel]), bottle([], capacity: 2)])
        let moves = Solver.candidateMoves(funnel)
        #expect(moves.contains(Move(from: 0, to: 2)) && moves.contains(Move(from: 1, to: 2)))
        #expect(!moves.contains(Move(from: 0, to: 3)))
        // An empty tap can't receive, so it doesn't keep a finished flask in play.
        let tap = GameState(bottles: [bottle([0, 0], capacity: 2), bottle([1, 1], capacity: 2),
                                      bottle([], capacity: 2, [.tap]), bottle([], capacity: 2)])
        #expect(Solver.candidateMoves(tap).isEmpty)
    }

    /// Without pruning (a move counter forces the general path) the optimum is the same.
    @Test func unprunedPathAgrees() {
        for config in Self.configs.prefix(7) {
            for seed in UInt64(1)...5 {
                let s = Generator.candidate(config, seed: seed)
                var counted = s
                counted.moveCount = 0
                #expect(Solver.candidateMoves(counted) == counted.legalMoves())
                #expect(Solver().solve(counted).moves?.count == Solver().solve(s).moves?.count, "\(s)")
            }
        }
    }
}

/// StateKey with glass modifiers.
@Suite struct GlassKeyTests {
    static func randomStates() -> [GameState] {
        var result: [GameState] = []
        let extra = GeneratorConfig(colors: 6, emptyBottles: 2, locks: 1, essence: 1, narrowNecks: 2, funnels: 1, taps: 2)
        for config in GlassSolverTests.configs + [extra] {
            for seed in UInt64(1)...6 {
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
        var rng = SplitMix64(seed: 5)
        for s in Self.randomStates() {
            for _ in 0..<3 {
                var order = Array(s.bottles.indices)
                rng.shuffle(&order)
                #expect(s.permuted(by: order).canonicalKey == s.canonicalKey)
            }
        }
    }

    @Test func pairPathEqualsTheGeneralEncoding() {
        for s in Self.randomStates() {
            #expect(StateKey.pairCodes(s) == StateKey.extendedCodes(s), "\(s)")
        }
    }

    @Test func modifierIsPartOfTheKey() {
        let base = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([1, 0], capacity: 2), bottle([], capacity: 2)])
        var keys: Set<StateKey> = [base.canonicalKey]
        for m in [BottleModifier.narrowNeck, .funnel, .tap] {
            for i in [0, 2] {
                var s = base
                s.bottles[i].modifiers = [m]
                keys.insert(s.canonicalKey)
            }
        }
        #expect(keys.count == 7)
        // Same layers and modifiers on other bottles: the same key.
        let a = GameState(bottles: [bottle([0, 1], capacity: 2, [.tap]), bottle([1, 0], capacity: 2)])
        let b = GameState(bottles: [bottle([1, 0], capacity: 2), bottle([0, 1], capacity: 2, [.tap])])
        #expect(a.canonicalKey == b.canonicalKey)
    }
}

/// Level files, validation and sessions with glass flasks.
@Suite struct GlassLevelTests {
    static let sample = GameState(bottles: [bottle([0, 1, 1], capacity: 3, [.narrowNeck]), bottle([1, 0], capacity: 3, [.tap]),
                                            bottle([0], capacity: 3, [.funnel]), bottle([], capacity: 3)])

    @Test func jsonRoundTrip() throws {
        let level = LevelDefinition(id: "g1", state: Self.sample, meta: LevelMeta(seed: 1, minMoves: 4))
        let pack = LevelPack(name: "Glass Works", kind: .chapter, chapter: 5, location: "Glass Works",
                             introduces: [.narrowNeck, .funnel, .tap], levels: [level])
        #expect(pack.requiredVersion == 2)
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        for name in ["narrowNeck", "funnel", "tap"] { #expect(text.contains(#""type" : "\#(name)""#)) }
        let loaded = try LevelLoader.load(data)
        #expect(loaded.levels == pack.levels && loaded.introduces == [.narrowNeck, .funnel, .tap])
        #expect(loaded.levels[0].gameState == Self.sample)
        #expect(try LevelLoader.encode(loaded) == data)
    }

    @Test func handWrittenJSON() throws {
        let json = #"""
        {"version": 2, "levels": [{"id": "a", "capacity": 2, "bottles": [
          {"layers": [0, 1], "modifiers": [{"type": "tap"}]}, {"layers": [1, 0], "modifiers": [{"type": "narrowNeck"}]},
          {"layers": [], "modifiers": [{"type": "funnel"}]}, {"layers": []}]}]}
        """#
        let s = try LevelLoader.load(Data(json.utf8)).levels[0].gameState
        #expect(s.bottles[0].hasTap && s.bottles[1].hasNarrowNeck && s.bottles[2].isFunnel)
        let v1 = json.replacingOccurrences(of: #""version": 2"#, with: #""version": 1"#)
        #expect(throws: LevelLoadError.needsVersion2(id: "a")) { try LevelLoader.load(Data(v1.utf8)) }
    }

    @Test func validation() {
        #expect(Self.sample.validate().isEmpty)
        var s = Self.sample
        s.bottles[1].modifiers = [.tap, .funnel]
        #expect(s.validate().contains(.funnelWithTap(bottle: 1)))
        s = Self.sample
        s.bottles[1].lockedBy = 1
        s.bottles[3].layers = [.key(1)]
        #expect(s.validate() == [.sealedTap(bottle: 1)])
        s = Self.sample
        s.bottles[2].layers = layers([0, 1])   // a funnel can never pour the 1 out
        s.bottles[1].layers = layers([1])
        s.bottles[0].layers = layers([0, 1, 0])
        #expect(s.validate() == [.unsortableFunnel(bottle: 2)])
        s = Self.sample
        s.bottles[2].modifiers = [.funnel, .essence(1)]   // a 0 in a funnel with a 1-rune
        #expect(s.validate().contains(.unsortableFunnel(bottle: 2)))
        let keyInFunnel = GameState(bottles: [Bottle(layers: layers([-1]), capacity: 2, modifiers: [.funnel]),
                                              Bottle(layers: layers([0, 0]), capacity: 2, lockedBy: 1)])
        #expect(keyInFunnel.validate() == [.unsortableFunnel(bottle: 0)])
        for e in [ValidationError.sealedTap(bottle: 1), .funnelWithTap(bottle: 1), .unsortableFunnel(bottle: 1)] {
            #expect(e.description.contains("1"))
        }
    }

    @Test func undoAndRestartRestoreTheFullState() throws {
        var session = GameSession(Self.sample, hidden: true)
        let masks = session.hiddenMasks
        // The tap shows its bottom run and its top run; the neck's 0 under the 1s is hidden.
        #expect(masks[0] == [true, false, false] && masks[1] == [false, false])
        let solution = try #require(Solver().solve(Self.sample).moves)
        var states: [GameState] = [session.state]
        for move in solution {
            let played = session.play(move)
            let turn = try #require(played)
            #expect(session.lastPour == turn.pour)
            states.append(session.state)
        }
        #expect(session.isSolved && session.moveCount == solution.count)
        for i in stride(from: solution.count - 1, through: 0, by: -1) {
            session.undo()
            #expect(session.state == states[i] && session.lastPour == nil)
        }
        #expect(session.hiddenMasks == masks)
        session.apply(solution[0])
        session.restart()
        #expect(session.state == Self.sample && session.hiddenMasks == masks && session.moveCount == 0)
        let refused = session.play(Move(from: 2, to: 3))   // a funnel never pours
        #expect(refused == nil && session.moveCount == 0)
    }

    /// Murky layers in a tap flask: the flags move with their layers as it drains from the
    /// bottom, so the stack sliding down keeps its hidden layers hidden.
    @Test func hiddenFlagsFollowATapDrain() throws {
        let s = GameState(bottles: [bottle([0, 1, 2, 3, 3], capacity: 5, [.tap]), bottle([], capacity: 5),
                                    bottle([0, 0, 0, 0], capacity: 5), bottle([1, 1, 1, 1], capacity: 5),
                                    bottle([2, 2, 2, 2], capacity: 5), bottle([3, 3, 3], capacity: 5)])
        var session = GameSession(s, hidden: true)
        #expect(session.hiddenMasks[0] == [false, true, true, false, false])
        session.apply(Move(from: 0, to: 2))   // the 0 drains; the 1 slides to the bottom and is revealed
        #expect(session.state.bottles[0].layers == layers([1, 2, 3, 3]))
        #expect(session.hiddenMasks[0] == [false, true, false, false])
        #expect(session.isHidden(bottle: 0, layer: 1) && !session.isHidden(bottle: 0, layer: 0))
        #expect(session.hiddenDepths[0] == 1)
        #expect(session.lastPour?.fromBottom == true)
        session.undo()
        #expect(session.hiddenMasks[0] == [false, true, true, false, false])
    }
}

/// Generator options for glass flasks.
@Suite struct GlassGeneratorTests {
    @Test func noGlassLeavesEveryLevelUnchanged() {
        for seed in UInt64(1)...10 {
            let config = GeneratorConfig(colors: 5, locks: 1, essence: 1)
            var glass = config
            glass.narrowNecks = 1
            glass.taps = 1
            glass.funnels = 1
            let plain = Generator.candidate(config, seed: seed)
            let marked = Generator.candidate(glass, seed: seed)
            #expect(marked.bottles.map(\.layers) == plain.bottles.map(\.layers))
            #expect(marked.bottles.map(\.lockedBy) == plain.bottles.map(\.lockedBy))
            #expect(marked.bottles.map(\.essenceColor) == plain.bottles.map(\.essenceColor))
            #expect(!plain.bottles.contains { $0.hasNarrowNeck || $0.isFunnel || $0.hasTap })
        }
    }

    @Test func placementRules() {
        for seed in UInt64(1)...40 {
            let config = GeneratorConfig(colors: 5, emptyBottles: 2, locks: 1, essence: 1, narrowNecks: 2, funnels: 1, taps: 1)
            let s = Generator.candidate(config, seed: seed)
            #expect(s.bottles.filter(\.hasNarrowNeck).count == 2)
            #expect(s.bottles.filter(\.isFunnel).count == 1 && s.bottles.filter(\.hasTap).count == 1)
            for b in s.bottles where b.hasNarrowNeck || b.isFunnel || b.hasTap {
                #expect(b.modifiers.count == 1)   // one modifier per flask: no seal, no rune with it
            }
            #expect(s.bottles.filter(\.isFunnel).allSatisfy { $0.isEmpty })
            #expect(s.bottles.filter(\.hasTap).allSatisfy { !$0.isEmpty })
            #expect(s.validate().isEmpty)
        }
    }

    @Test func generationIsDeterministicAndGlassMatters() throws {
        let config = GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 2, seed: 3, taps: 1,
                                     requireGlassMatter: true, glassCost: GlassImpact.strongCost)
        let a = try Generator.generate(config, count: 2)
        let b = try Generator.generate(config, count: 2)
        #expect(a == b)
        for level in a {
            #expect(GlassImpact.instances(in: level.state).count == 1)
            #expect(GlassImpact.everyGlassMatters(level.state, minMoves: level.report.minMoves, cost: GlassImpact.strongCost))
        }
    }
}

/// Glass Works (chapter 5).
@Suite struct GlassWorksTests {
    static func pack() throws -> LevelPack { try LevelFileTests.load("chapter_05") }

    @Test func shape() throws {
        let pack = try Self.pack()
        #expect(pack.version == 2 && pack.chapter == 5 && pack.location == "Glass Works")
        #expect(pack.introduces == [.narrowNeck, .funnel, .tap])
        #expect((28...32).contains(pack.levels.count))
        #expect(pack.levels.map(\.id) == pack.levels.indices.map { String(format: "c5_%03d", $0 + 1) })
        let glass: Set<Mechanic> = [.narrowNeck, .funnel, .tap]
        #expect(pack.levels.allSatisfy { !glass.isDisjoint(with: $0.mechanics) })
        for level in pack.levels {
            for b in level.gameState.bottles where b.hasNarrowNeck || b.isFunnel || b.hasTap {
                #expect(b.modifiers.count == 1, "\(level.id)")
            }
        }
        // Tutorial: a tiny level with one narrow neck only; funnels and taps come later.
        let tutorial = try #require(pack.levels.first)
        #expect(tutorial.capacity == 3 && tutorial.mechanics == [.narrowNeck] && (tutorial.meta?.minMoves ?? 99) <= 8)
        let firstFunnel = try #require(pack.levels.firstIndex { $0.mechanics.contains(.funnel) })
        let firstTap = try #require(pack.levels.firstIndex { $0.mechanics.contains(.tap) })
        #expect(firstFunnel > 1 && firstTap > firstFunnel)
        // Earlier mechanics join at the end.
        #expect(pack.levels.suffix(10).contains { $0.isHidden })
        #expect(pack.levels.suffix(10).contains { $0.mechanics.contains(.sealed) })
        #expect(pack.levels.suffix(10).contains { $0.mechanics.contains(.essence) })
        let scores = pack.levels.compactMap { $0.meta?.score }
        #expect(scores.count == pack.levels.count)
        #expect(scores.first! < 20 && scores.max()! >= 50 && scores.max()! <= 60)
    }

    /// Every glass flask matters (the tutorial's and every later narrow neck and tap change
    /// the optimum by 2+ moves; every funnel sets a trap), and seals and runes as in
    /// chapters 2–4. Small searches only, like the other shipped-pack tests.
    @Test func everyMechanicMatters() throws {
        var checked = 0
        for level in try Self.pack().levels {
            guard let meta = level.meta, let minMoves = meta.minMoves, (meta.statesExplored ?? 0) <= 8_000 else { continue }
            let s = level.gameState
            #expect(GlassImpact.everyGlassMatters(s, minMoves: minMoves, cost: GlassImpact.strongCost), "\(level.id)")
            #expect(EssenceImpact.everyEssenceMatters(s, minMoves: minMoves), "\(level.id)")
            #expect(LockImpact.everyLockMatters(s, minMoves: minMoves, cost: LockImpact.strongCost), "\(level.id)")
            checked += 1
        }
        #expect(checked >= 20)
    }
}
