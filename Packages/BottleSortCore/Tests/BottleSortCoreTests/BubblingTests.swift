import Foundation
import Testing
@testable import BottleSortCore

/// Layers from color numbers, with `.key(k)` for negative numbers −k.
private func layers(_ values: [Int]) -> [Layer] {
    values.map { $0 < 0 ? .key(KeyID(-$0)) : .color(ColorID($0)) }
}

private func bub(_ every: Int, _ phase: Int) -> BottleModifier { .bubbling(every: every, phase: phase) }

/// D2 bubbling flasks: the rule cases.
@Suite struct BubblingRuleTests {
    @Test func phaseAdvancesAndTheBottomLayerRises() throws {
        var s = GameState(bottles: [bottle([0, 1, 2], capacity: 4, [bub(3, 0)]), bottle([3, 3], capacity: 4),
                                    bottle([], capacity: 4)])
        // Two moves elsewhere: the phase counts 1, 2, nothing moves.
        let first = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 1, to: 2))))
        #expect(first.state.bottles[0].modifiers == [bub(3, 1)] && first.events.isEmpty)
        #expect(first.state.bottles[0].layers == layers([0, 1, 2]))
        s = first.state
        let second = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 2, to: 1))))
        #expect(second.state.bottles[0].modifiers == [bub(3, 2)] && second.events.isEmpty)
        // The third move: the 0 at the bottom rises to the top, the phase resets.
        let third = try #require(Rules.resolve(second.state, afterAction: .pour(Move(from: 1, to: 2))))
        #expect(third.state.bottles[0].layers == layers([1, 2, 0]))
        #expect(third.state.bottles[0].modifiers == [bub(3, 0)])
        #expect(third.events == [.bubbled(bottle: 0)])
        #expect(Rules.sunk(third.state.bottles[0].layers) == layers([0, 1, 2]))
    }

    @Test func theRiseFollowsThePour() throws {
        // The pour lands first (step 1), then the flask bubbles (step 4): the poured 1 is
        // on top of [0, 1] before the bottom 0 rises over it.
        let s = GameState(bottles: [bottle([0, 1], capacity: 3, [bub(2, 1)]), bottle([1, 0], capacity: 3),
                                    bottle([], capacity: 3)])
        let into = try #require(Rules.resolve(GameState(bottles: [s.bottles[0], bottle([0, 1], capacity: 3), s.bottles[2]]),
                                              afterAction: .pour(Move(from: 1, to: 0))))
        #expect(into.pour == PourEvent(move: Move(from: 1, to: 0), layer: .color(1), amount: 1))
        #expect(into.state.bottles[0].layers == layers([1, 1, 0]) && into.events == [.bubbled(bottle: 0)])
        // Pouring out of it: its top 1 leaves first, then the remaining single 0 "rises"
        // without changing anything (no event), and the phase still resets.
        let out = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 2))))
        #expect(out.state.bottles[0].layers == layers([0]) && out.events.isEmpty)
        #expect(out.state.bottles[0].bubbling == Bubbling(every: 2, phase: 0))
    }

    @Test func emptySingleAndOneColorFlasksCountWithoutMoving() throws {
        let s = GameState(bottles: [bottle([], capacity: 3, [bub(2, 1)]), bottle([2, 2], capacity: 3, [bub(2, 1)]),
                                    bottle([1], capacity: 3), bottle([], capacity: 3)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 2, to: 3))))
        #expect(turn.events.isEmpty)
        #expect(turn.state.bottles[0].modifiers == [bub(2, 0)] && turn.state.bottles[1].modifiers == [bub(2, 0)])
        #expect(turn.state.bottles[1].layers == layers([2, 2]))
    }

    @Test func bubblingChangesNoPour() {
        // Legality, amount, outlet and refusals are those of a plain flask, on both sides.
        let pairs: [(Bottle, Bottle)] = [
            (bottle([0, 1, 1], capacity: 4), bottle([1], capacity: 4)),
            (bottle([0, 1, 1], capacity: 4), bottle([0], capacity: 4)),
            (bottle([0, 1, 1], capacity: 4), bottle([1, 1, 1], capacity: 4)),
            (bottle([2], capacity: 4), bottle([], capacity: 4)),
        ]
        for (a, b) in pairs {
            for (x, y) in [(a, b), (b, a)] {
                var bx = x, by = y
                bx.modifiers = [bub(3, 1)]
                by.modifiers = [bub(4, 2)]
                #expect(Rules.pourAmount(from: bx, to: y) == Rules.pourAmount(from: x, to: y))
                #expect(Rules.pourAmount(from: x, to: by) == Rules.pourAmount(from: x, to: y))
                #expect(Rules.outlet(of: bx)?.layers == Rules.outlet(of: x)?.layers)
                #expect(Rules.outletBlocker(of: bx) == nil)
                let s = GameState(bottles: [bx, by])
                #expect(Rules.refusal(of: Move(from: 0, to: 1), in: s) == nil)
                for side in [PourSide.source, .target] {
                    var plan = PourPlan(layer: .color(1))
                    #expect(Rules.apply(bub(2, 0), as: side, to: &plan, source: x, target: y))
                    #expect(plan == PourPlan(layer: .color(1)))
                }
            }
        }
    }

    @Test func thawRunsBeforeBubbling() throws {
        let s = GameState(bottles: [bottle([2, 0], capacity: 2, [bub(2, 1)]), bottle([1, 1], capacity: 2, [.frozen(layer: 1, turns: 1)]),
                                    bottle([0], capacity: 2), bottle([2], capacity: 2)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 2))))
        #expect(turn.events == [.thawed(bottle: 1, layer: 1)])   // the single 2 left: nothing rises
        let other = GameState(bottles: [bottle([0, 2], capacity: 3, [bub(2, 1)]), bottle([1, 1], capacity: 3, [.frozen(layer: 1, turns: 1)]),
                                        bottle([0, 0], capacity: 3), bottle([2, 2], capacity: 3), bottle([1], capacity: 3),
                                        bottle([], capacity: 3)])
        let next = try #require(Rules.resolve(other, afterAction: .pour(Move(from: 4, to: 5))))
        #expect(next.events == [.thawed(bottle: 1, layer: 1), .bubbled(bottle: 0)])
        #expect(next.state.bottles[0].layers == layers([2, 0]))
    }

    @Test func aRefusedMoveDoesNotTick() {
        var session = GameSession(GameState(bottles: [bottle([0, 1], capacity: 2, [bub(2, 1)]), bottle([0, 1], capacity: 2)]))
        #expect(session.play(Move(from: 0, to: 1)) == nil)
        #expect(session.state.bottles[0].modifiers == [bub(2, 1)])
    }

    @Test func aFullOneColorBubblingFlaskIsSolved() throws {
        #expect(Rules.isSolved(bottle([1, 1, 1], capacity: 3, [bub(3, 2)])))
        #expect(Rules.isSolved(bottle([], capacity: 3, [bub(3, 2)])))
        #expect(!Rules.isSolved(bottle([1, 1, 0], capacity: 3, [bub(3, 2)])))
        // The last pour completes the board; the rise that follows changes nothing.
        let s = GameState(bottles: [bottle([0, 0], capacity: 3, [bub(2, 1)]), bottle([0], capacity: 3),
                                    bottle([1, 1, 1], capacity: 3, [bub(3, 0)])])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 1, to: 0))))
        #expect(turn.isWon && turn.events.isEmpty)
    }

    @Test func aKeyRisesLikeAnyLayer() throws {
        // The key at the bottom of a bubbling flask comes up and then opens its seal.
        let s = GameState(bottles: [Bottle(layers: layers([-1, 0]), capacity: 2, modifiers: [bub(2, 1)]),
                                    Bottle(layers: layers([1, 1]), capacity: 2, modifiers: [.sealed(1)]),
                                    Bottle(layers: layers([0]), capacity: 2), Bottle(capacity: 2)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 2))))
        #expect(turn.state.bottles[0].layers == layers([-1]))   // one layer: nothing to rise over
        let t2 = try #require(Rules.resolve(GameState(bottles: [Bottle(layers: layers([-1, 0, 2]), capacity: 3, modifiers: [bub(2, 1)]),
                                                                Bottle(layers: layers([2, 2]), capacity: 3),
                                                                Bottle(layers: layers([0, 0]), capacity: 3),
                                                                Bottle(layers: layers([1, 1, 1]), capacity: 3, modifiers: [.sealed(1)])]),
                                            afterAction: .pour(Move(from: 0, to: 1))))
        #expect(t2.state.bottles[0].layers == layers([0, -1]) && t2.events == [.bubbled(bottle: 0)])
        // Now the key is on top: it opens the seal.
        let opened = try #require(t2.state.pouring(Move(from: 0, to: 3)))
        #expect(!opened.bottles[3].isSealed)
    }

    @Test func aFlaskHoldingIceNeverRises() {
        // Invalid by validation, but the rule keeps frozen indices valid anyway.
        var b = bottle([0, 1, 2], capacity: 3, [bub(2, 1), .frozen(layer: 0, turns: 4)])
        var events: [TurnEvent] = []
        let list = b.modifiers
        Rules.bubble(&b, list: list, bottle: 0, events: &events)
        #expect(b.layers == layers([0, 1, 2]) && events.isEmpty && b.bubbling == Bubbling(every: 2, phase: 0))
    }

    @Test func displayHelpers() {
        let b = bottle([0, 1], capacity: 4, [bub(4, 1)])
        #expect(b.isBubbling && b.bubbling == Bubbling(every: 4, phase: 1) && b.bubbling?.movesUntilRise == 3)
        #expect(Bubbling(every: 2, phase: 1).movesUntilRise == 1)
        #expect(!bottle([0], capacity: 4).isBubbling && bottle([0], capacity: 4).bubbling == nil)
        let sealed = Bottle(layers: layers([0, 1]), capacity: 4, lockedBy: 2)
        #expect(!sealed.isBubbling)
        #expect(Rules.bubbledUp(layers([0, 1, 2])) == layers([1, 2, 0]))
        #expect(Rules.sunk(Rules.bubbledUp(layers([0, 1, 2, 3]))) == layers([0, 1, 2, 3]))
        #expect(Rules.bubbledUp([Layer]()) == [] && Rules.sunk(layers([4])) == layers([4]))
        let level = LevelDefinition(id: "b", state: GameState(bottles: [b, sealed]), hidden: true)
        #expect(level.mechanics == [.sealed, .murky, .bubbling])
        #expect(ChapterOutline.plan[6].introduces == [.bubbling] && ChapterOutline.plan[6].location == "Bubbling Bog")
        #expect(Mechanic.bubbling.rawValue == "bubbling" && bub(2, 0).isImplemented && bub(2, 0).isTimed)
        #expect(Rules.bubblingPeriods == 2...5 && Rules.maxBubblingFlasks == 2)
        #expect(!Rules.blocksSolved(bub(3, 1)))
    }

    @Test func legalMovesAgreeWithResolve() {
        for s in BubblingKeyTests.randomStates() {
            for from in s.bottles.indices {
                for to in s.bottles.indices {
                    let move = Move(from: from, to: to)
                    #expect(s.canPour(move) == (Rules.resolve(s, afterAction: .pour(move)) != nil))
                }
            }
        }
    }
}

/// Hand-made puzzles where the bubbling decides the solution.
@Suite struct BubblingPuzzleTests {
    /// The 0 at the bottom of flask 1 is needed by the other 0s, but without the bubbling
    /// it is trapped under the 1s for good (unsolvable). Its first rise, after the first
    /// move, brings it up: 5 moves.
    static let requires = GameState(bottles: [bottle([0, 2, 2], capacity: 3), bottle([0, 1, 1], capacity: 3, [bub(2, 1)]),
                                              bottle([0, 1, 2], capacity: 3), bottle([], capacity: 3)])

    @Test func theRiseIsRequired() throws {
        let s = Self.requires
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 5 && referenceMinMoves(s) == 5)
        let without = MechanicImpact.removing(.modifier(bottle: 1, bub(2, 1)), from: s)
        if case .unsolvable = Solver().solve(without) {} else { Issue.record("expected unsolvable without bubbling") }
        #expect(referenceMinMoves(without) == nil)
        #expect(BubblingImpact.everyBubblingMatters(s, minMoves: 5, cost: BubblingImpact.strongCost))
        var replay = s
        var rose = false
        for m in moves {
            let turn = try #require(Rules.resolve(replay, afterAction: .pour(m)))
            if turn.events.contains(.bubbled(bottle: 1)) { rose = true }
            replay = turn.state
        }
        #expect(replay.isSolved && rose)
        // The tutorial checks: no wait needed and a risen layer is poured; but some first
        // moves lose the level (e.g. the 1 of flask 2 into the empty flask), so it is no tutorial.
        #expect(BubblingImpact.solvesWithoutRelocation(s, in: 5, pouringARisenLayer: true))
        #expect(!MechanicImpact.everyFirstMoveSolvable(s))
        // Another phase changes the timing: a later first rise needs other moves.
        var late = s
        late.bottles[1].modifiers = [bub(2, 0)]
        #expect(Solver().solve(late).moves?.count == referenceMinMoves(late))
    }

    /// A rise can also bury what the player wanted on top: here the bubbling makes the
    /// level longer.
    @Test func aRiseCanCostMoves() throws {
        let s = GameState(bottles: [bottle([2, 0, 0], capacity: 3), bottle([2, 1, 0], capacity: 3),
                                    bottle([1, 1, 2], capacity: 3, [bub(2, 1)]), bottle([], capacity: 3)])
        let with = try #require(Solver().solve(s).moves)
        let without = try #require(Solver().solve(MechanicImpact.removing(.modifier(bottle: 2, bub(2, 1)), from: s)).moves)
        #expect(with.count == 8 && referenceMinMoves(s) == 8)
        #expect(without.count == 5)
        #expect(BubblingImpact.everyBubblingMatters(s, minMoves: 8, cost: BubblingImpact.strongCost))
    }

    @Test func bubblingIsTwoSided() {
        #expect(MechanicImpact.isTwoSided(.modifier(bottle: 0, bub(2, 0))))
        #expect(MechanicImpact.minimumCost(of: .modifier(bottle: 0, bub(2, 0))) == BubblingImpact.minimumCost)
        #expect(BubblingImpact.strongCost == 2)
    }
}

/// The solver with bubbling flasks: exact, and its pruning stays safe.
@Suite struct BubblingSolverTests {
    static let configs = [
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, bubbling: 1, bubblingPeriod: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, bubbling: 1, bubblingPeriod: 3),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, bubbling: 2, bubblingPeriod: 2),
        GeneratorConfig(colors: 3, capacity: 2, emptyBottles: 2, bubbling: 2, bubblingPeriod: 5),
        GeneratorConfig(colors: 4, capacity: 2, emptyBottles: 1, bubbling: 2, bubblingPeriod: 3),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, bubbling: 1, bubblingPeriod: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, essence: 1, bubbling: 1, bubblingPeriod: 4),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, narrowNecks: 1, funnels: 1, bubbling: 1, bubblingPeriod: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, frozen: 1, frozenMaxTurns: 3, bubbling: 1, bubblingPeriod: 3),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, essence: 1, bubbling: 2, bubblingPeriod: 3),
    ]

    /// Solver vs. the naive BFS (no pruning, no canonical keys) on many small random levels.
    @Test(arguments: configs.indices)
    func solverMatchesReference(_ index: Int) throws {
        let config = Self.configs[index]
        var checked = 0
        for seed in UInt64(1)...25 {
            let s = Generator.candidate(config, seed: seed)
            #expect(s.validate().isEmpty, "\(s)")
            #expect(s.bottles.contains { $0.isBubbling }, "\(s)")
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

    /// The pruned candidate list reaches the same canonical children as every legal move
    /// while a flask bubbles (only duplicate waits are dropped, which share one child).
    @Test func pruningKeepsEveryDistinctChild() {
        for config in Self.configs {
            for seed in UInt64(1)...10 {
                var s = Generator.candidate(config, seed: seed)
                for step in 0..<8 {
                    let all = Set(s.legalMoves().compactMap { s.pouring($0)?.canonicalKey })
                    let pruned = Set(Solver.candidateMoves(s).compactMap { s.pouring($0)?.canonicalKey })
                    #expect(all == pruned, "\(s)")
                    let moves = s.legalMoves()
                    guard !moves.isEmpty else { break }
                    s = s.pouring(moves[(Int(seed) + step) % moves.count])!
                }
            }
        }
    }

    /// Rules 1 and 2 (relocations) are off while a flask bubbles, but every relocation is
    /// the same wait: only the first one is kept.
    @Test func oneWaitPerState() {
        let s = GameState(bottles: [bottle([0, 1], capacity: 2, [bub(3, 0)]), bottle([1, 0], capacity: 2),
                                    bottle([2, 2], capacity: 2), bottle([3, 3], capacity: 2),
                                    bottle([], capacity: 2), bottle([], capacity: 2)])
        let moves = Solver.candidateMoves(s)
        let waits = moves.filter { FrozenImpact.isRelocation($0, in: s) }
        #expect(waits == [Move(from: 2, to: 4)])
        #expect(!moves.contains(Move(from: 0, to: 5)))   // rule 3: only the first empty flask
        // The wait is real: it moves the phase on.
        #expect(s.pouring(Move(from: 2, to: 4))?.bottles[0].bubbling?.phase == 1)
        var still = s
        still.bottles[0].modifiers = []
        #expect(!Solver.candidateMoves(still).contains { FrozenImpact.isRelocation($0, in: still) })
    }
}

/// StateKey with bubbling flasks.
@Suite struct BubblingKeyTests {
    static func randomStates() -> [GameState] {
        var result: [GameState] = []
        let extra = GeneratorConfig(colors: 6, emptyBottles: 2, locks: 1, essence: 1, bubbling: 2, bubblingPeriod: 5)
        for config in BubblingSolverTests.configs + [extra] {
            for seed in UInt64(1)...6 {
                var s = Generator.candidate(config, seed: seed)
                result.append(s)
                for step in 0..<6 {
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
        var rng = SplitMix64(seed: 7)
        for s in Self.randomStates() {
            for _ in 0..<3 {
                var order = Array(s.bottles.indices)
                rng.shuffle(&order)
                #expect(s.permuted(by: order).canonicalKey == s.canonicalKey)
            }
        }
    }

    @Test func pairPathEqualsTheGeneralEncoding() {
        var paired = 0
        for s in Self.randomStates() {
            guard let pair = StateKey.pairCodes(s) else { continue }
            #expect(pair == StateKey.extendedCodes(s), "\(s)")
            paired += 1
        }
        #expect(paired > 100)
        #expect(StateKey.singleWord(for: bub(5, 4)) == StateKey.words(for: bub(5, 4))[0])
    }

    @Test func periodAndPhaseArePartOfTheKey() {
        let base = GameState(bottles: [bottle([0, 1, 1], capacity: 3), bottle([1, 0, 0], capacity: 3), bottle([], capacity: 3)])
        var keys: Set<StateKey> = [base.canonicalKey]
        for (b, every, phase) in [(0, 2, 0), (0, 2, 1), (0, 3, 0), (0, 3, 2), (1, 2, 0), (2, 2, 0), (2, 5, 4)] {
            var s = base
            s.bottles[b].modifiers = [bub(every, phase)]
            keys.insert(s.canonicalKey)
        }
        var two = base
        two.bottles[0].modifiers = [bub(2, 0)]
        two.bottles[1].modifiers = [bub(2, 0)]
        keys.insert(two.canonicalKey)
        #expect(keys.count == 9)
        // The same flask in another position: the same key.
        let a = GameState(bottles: [bottle([0, 1], capacity: 2, [bub(3, 1)]), bottle([1, 0], capacity: 2)])
        let b = GameState(bottles: [bottle([1, 0], capacity: 2), bottle([0, 1], capacity: 2, [bub(3, 1)])])
        #expect(a.canonicalKey == b.canonicalKey)
    }

    @Test func theStepKeepsTheModifierOrderCanonical() throws {
        var s = GameState(bottles: [Bottle(layers: layers([0, 1, 2]), capacity: 3, modifiers: [.sealed(1), .essence(2), bub(2, 0)]),
                                    bottle([0, 0], capacity: 3, [.narrowNeck, bub(3, 2)]), bottle([1, 1], capacity: 3),
                                    Bottle(layers: layers([2, 2, -1]), capacity: 3), bottle([], capacity: 3)])
        for _ in 0..<4 {
            let move = try #require(s.legalMoves().first)
            s = try #require(s.pouring(move))
            for bottle in s.bottles {
                let stored = bottle.modifiers
                #expect(stored == Bottle.normalize(stored))
                #expect(bottle == Bottle(layers: bottle.layers, capacity: 3, modifiers: stored.reversed()))
            }
        }
    }
}

/// Level files, validation and sessions with bubbling flasks.
@Suite struct BubblingLevelTests {
    static let sample = GameState(bottles: [bottle([0, 1, 1], capacity: 3, [bub(2, 1)]), bottle([1, 0, 0], capacity: 3),
                                            bottle([], capacity: 3), bottle([], capacity: 3)])

    @Test func jsonRoundTrip() throws {
        var s = Self.sample
        s.bottles[1].modifiers = [bub(5, 4), .essence(0)]
        let level = LevelDefinition(id: "b1", state: s, meta: LevelMeta(seed: 1, minMoves: 4))
        let pack = LevelPack(name: "Bubbling Bog", kind: .chapter, chapter: 7, location: "Bubbling Bog",
                             introduces: [.bubbling], levels: [level])
        #expect(pack.requiredVersion == 2)
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""type" : "bubbling""#) && text.contains(#""every" : 5"#) && text.contains(#""phase" : 4"#))
        let loaded = try LevelLoader.load(data)
        #expect(loaded.levels == pack.levels && loaded.introduces == [.bubbling])
        #expect(loaded.levels[0].gameState == s)
        #expect(try LevelLoader.encode(loaded) == data)
    }

    @Test func handWrittenJSON() throws {
        let json = #"""
        {"version": 2, "levels": [{"id": "a", "capacity": 2, "bottles": [
          {"layers": [0, 1], "modifiers": [{"type": "bubbling", "every": 3}]}, {"layers": [1, 0]},
          {"layers": []}]}]}
        """#
        let s = try LevelLoader.load(Data(json.utf8)).levels[0].gameState
        #expect(s.bottles[0].bubbling == Bubbling(every: 3, phase: 0))   // phase defaults to 0
        let v1 = json.replacingOccurrences(of: #""version": 2"#, with: #""version": 1"#)
        #expect(throws: LevelLoadError.needsVersion2(id: "a")) { try LevelLoader.load(Data(v1.utf8)) }
    }

    @Test func validation() {
        #expect(Self.sample.validate().isEmpty)
        var s = Self.sample
        s.bottles[0].modifiers = [bub(1, 0)]
        #expect(s.validate() == [.invalidBubblingPeriod(bottle: 0, every: 1)])
        s.bottles[0].modifiers = [bub(6, 0)]
        #expect(s.validate() == [.invalidBubblingPeriod(bottle: 0, every: 6)])
        s.bottles[0].modifiers = [bub(3, 3)]
        #expect(s.validate() == [.invalidBubblingPhase(bottle: 0, phase: 3)])
        s.bottles[0].modifiers = [bub(3, -1)]
        #expect(s.validate() == [.invalidBubblingPhase(bottle: 0, phase: -1)])
        s.bottles[0].modifiers = [bub(3, 0), bub(4, 0)]
        #expect(s.validate() == [.multipleBubbling(bottle: 0)])
        s.bottles[0].modifiers = [bub(3, 0), .tap]
        #expect(s.validate() == [.bubblingWithTap(bottle: 0)])
        s.bottles[0].modifiers = [bub(3, 0), .frozen(layer: 1, turns: 2)]
        #expect(s.validate() == [.bubblingWithIce(bottle: 0)])
        s.bottles[0].modifiers = [bub(3, 0)]
        s.bottles[1].modifiers = [bub(3, 0)]
        s.bottles[2].modifiers = [bub(2, 1)]
        #expect(s.validate() == [.tooManyBubblingFlasks(count: 3)])
        for e in [ValidationError.invalidBubblingPeriod(bottle: 1, every: 9), .invalidBubblingPhase(bottle: 1, phase: 4),
                  .multipleBubbling(bottle: 1), .bubblingWithTap(bottle: 1), .bubblingWithIce(bottle: 1),
                  .tooManyBubblingFlasks(count: 3)] {
            #expect(!e.description.isEmpty)
        }
        // Bubbling with a seal, a rune, a narrow neck or a funnel is fine (an empty flask too).
        let mixed = GameState(bottles: [Bottle(layers: layers([0, 1]), capacity: 2, modifiers: [.sealed(1), .essence(1), bub(2, 0)]),
                                        Bottle(layers: layers([1, -1]), capacity: 2, modifiers: [.narrowNeck, bub(5, 4)]),
                                        Bottle(layers: layers([0]), capacity: 2)])
        #expect(mixed.validate().isEmpty)
        let funnel = GameState(bottles: [bottle([0, 0], capacity: 2, [.funnel, bub(2, 0)]), bottle([], capacity: 2, [bub(3, 2)])])
        #expect(funnel.validate().isEmpty)
    }

    @Test func undoAndRestartRestoreThePhases() throws {
        var session = GameSession(Self.sample)
        let first = session.play(Move(from: 1, to: 2))            // the 0s leave; flask 0 rises
        let turn = try #require(first)
        #expect(turn.events == [.bubbled(bottle: 0)] && session.lastEvents == turn.events)
        #expect(session.state.bottles[0].layers == layers([1, 1, 0]) && session.state.bottles[0].bubbling?.phase == 0)
        session.apply(Move(from: 0, to: 2))                        // its 0 joins them; phase 1
        #expect(session.state.bottles[0].bubbling?.phase == 1 && session.lastEvents.isEmpty)
        session.undo()
        #expect(session.state.bottles[0].layers == layers([1, 1, 0]) && session.state.bottles[0].bubbling?.phase == 0)
        #expect(session.lastEvents.isEmpty)
        session.undo()
        #expect(session.state == Self.sample)
        session.apply(Move(from: 1, to: 2))
        session.apply(Move(from: 0, to: 2))
        session.restart()
        #expect(session.state == Self.sample && session.lastEvents.isEmpty && session.moveCount == 0)
    }

    /// Murky flags with bubbling: the bottom flag rises with its layer, and the risen layer
    /// (now on top) is revealed; undo puts the flags back.
    @Test func murkyMasksFollowTheRise() throws {
        let s = GameState(bottles: [bottle([2, 1, 0, 0], capacity: 4, [bub(2, 1)]), bottle([], capacity: 4),
                                    bottle([0, 0, 1, 1], capacity: 4), bottle([1, 2, 2, 2], capacity: 4)])
        var session = GameSession(s, hidden: true)
        #expect(session.hiddenMasks[0] == [true, true, false, false])
        session.apply(Move(from: 0, to: 1))                        // the 0s leave, then the 2 rises over the 1
        #expect(session.state.bottles[0].layers == layers([1, 2]))
        #expect(session.hiddenMasks[0] == [true, false])           // the 1 is still murky, the 2 revealed
        #expect(session.hiddenMasks[1] == [false, false])
        session.undo()
        #expect(session.hiddenMasks[0] == [true, true, false, false])
        // A rise in a flask the pour didn't touch moves its flags too.
        let other = GameState(bottles: [bottle([2, 1, 0], capacity: 3, [bub(2, 1)]), bottle([1, 2], capacity: 3),
                                        bottle([0, 0], capacity: 3), bottle([1, 2], capacity: 3), bottle([], capacity: 3)])
        var murky = GameSession(other, hidden: true)
        #expect(murky.hiddenMasks[0] == [true, true, false])
        murky.apply(Move(from: 1, to: 4))
        #expect(murky.state.bottles[0].layers == layers([1, 0, 2]))
        #expect(murky.hiddenMasks[0] == [true, false, false])
    }
}

/// Generator options for bubbling flasks.
@Suite struct BubblingGeneratorTests {
    @Test func noBubblingLeavesEveryLevelUnchanged() {
        for seed in UInt64(1)...10 {
            let config = GeneratorConfig(colors: 5, locks: 1, essence: 1, narrowNecks: 1, taps: 1, frozen: 1)
            var bubbling = config
            bubbling.bubbling = 2
            bubbling.bubblingPeriod = 4
            let plain = Generator.candidate(config, seed: seed)
            let marked = Generator.candidate(bubbling, seed: seed)
            #expect(marked.bottles.map(\.layers) == plain.bottles.map(\.layers))
            for (a, b) in zip(plain.bottles, marked.bottles) {
                #expect(b.modifiers.filter { !$0.isTimed } == a.modifiers.filter { !$0.isTimed })
                #expect(b.frozenLayers == a.frozenLayers)
            }
            #expect(!plain.bottles.contains { $0.isBubbling })
        }
    }

    @Test func placementRules() {
        for seed in UInt64(1)...40 {
            let config = GeneratorConfig(colors: 5, emptyBottles: 2, locks: 1, narrowNecks: 1, funnels: 1, taps: 1,
                                         frozen: 1, bubbling: 2, bubblingPeriod: 4)
            let s = Generator.candidate(config, seed: seed)
            let bubbling = s.bottles.filter(\.isBubbling)
            #expect(bubbling.count == 2)
            for b in bubbling {
                #expect(b.layers.count >= 2 && !b.hasTap && !b.isFunnel && !b.hasNarrowNeck && !b.holdsIce)
                #expect(b.bubbling!.every == 4 && (0..<4).contains(b.bubbling!.phase))
            }
            #expect(s.validate().isEmpty)
        }
    }

    @Test func generationIsDeterministicAndBubblingMatters() throws {
        let config = GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, seed: 1, bubbling: 1, bubblingPeriod: 2,
                                     requireBubblingMatter: true, bubblingCost: BubblingImpact.strongCost)
        let a = try Generator.generate(config, count: 2)
        let b = try Generator.generate(config, count: 2)
        #expect(a == b)
        for level in a {
            #expect(BubblingImpact.instances(in: level.state).count == 1)
            #expect(BubblingImpact.everyBubblingMatters(level.state, minMoves: level.report.minMoves,
                                                        cost: BubblingImpact.strongCost))
        }
    }

    @Test func tutorialChecks() {
        // Here the only flask that bubbles holds one color: nothing ever rises that matters.
        let dull = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([1, 0], capacity: 2), bottle([2, 2], capacity: 2, [bub(2, 0)]),
                                       bottle([], capacity: 2)])
        let moves = Solver().solve(dull).moves?.count ?? 0
        #expect(BubblingImpact.solvesWithoutRelocation(dull, in: moves))
        #expect(!BubblingImpact.solvesWithoutRelocation(dull, in: moves, pouringARisenLayer: true))
        #expect(!MechanicImpact.everyFirstMoveSolvable(BubblingPuzzleTests.requires))
        #expect(MechanicImpact.everyFirstMoveSolvable(state([[0, 1], [1, 0], []], capacity: 2)))
    }
}

/// Bubbling Bog (chapter 7).
@Suite struct BubblingBogTests {
    static func pack() throws -> LevelPack { try LevelFileTests.load("chapter_07") }

    @Test func shape() throws {
        let pack = try Self.pack()
        #expect(pack.version == 2 && pack.chapter == 7 && pack.location == "Bubbling Bog")
        #expect(pack.introduces == [.bubbling])
        #expect((28...32).contains(pack.levels.count))
        #expect(pack.levels.map(\.id) == pack.levels.indices.map { String(format: "c7_%03d", $0 + 1) })
        #expect(pack.levels.allSatisfy { $0.mechanics.contains(.bubbling) })
        for level in pack.levels {
            let flasks = level.gameState.bottles.compactMap(\.bubbling)
            #expect((1...Rules.maxBubblingFlasks).contains(flasks.count), "\(level.id)")
            #expect(flasks.allSatisfy { Rules.bubblingPeriods.contains($0.every) }, "\(level.id)")
            #expect(!level.mechanics.contains(.tap) && !level.mechanics.contains(.frozen)
                    && !level.mechanics.contains(.narrowNeck) && !level.mechanics.contains(.funnel), "\(level.id)")
        }
        // Tutorial: a tiny level with one bubbling flask only, whose rise is part of an
        // optimal solution that needs no wait, and no first move is a dead end.
        let tutorial = try #require(pack.levels.first)
        let start = tutorial.gameState
        #expect(tutorial.capacity == 3 && tutorial.mechanics == [.bubbling] && (tutorial.meta?.minMoves ?? 99) <= 8)
        #expect(start.bottles.filter(\.isBubbling).count == 1)
        #expect(BubblingImpact.solvesWithoutRelocation(start, in: tutorial.meta?.minMoves ?? 0, pouringARisenLayer: true))
        #expect(MechanicImpact.everyFirstMoveSolvable(start))
        // Earlier mechanics join only at the end.
        #expect(!pack.levels.prefix(15).contains { $0.mechanics != [.bubbling] })
        #expect(pack.levels.suffix(12).contains { $0.isHidden })
        #expect(pack.levels.suffix(12).contains { $0.mechanics.contains(.sealed) })
        let scores = pack.levels.compactMap { $0.meta?.score }
        #expect(scores.count == pack.levels.count)
        #expect(scores.first! < 22 && scores.first! < scores[1] && scores.max()! >= 50 && scores.max()! <= 60)
    }

    /// Every bubbling flask changes the optimum by 2+ moves either way (or the level can't
    /// be solved without it), the tutorial's too; seals matter as in chapter 2. Small
    /// searches only, like the other shipped-pack tests.
    @Test func everyMechanicMatters() throws {
        var checked = 0
        for level in try Self.pack().levels {
            guard let meta = level.meta, let minMoves = meta.minMoves, (meta.statesExplored ?? 0) <= 20_000 else { continue }
            let s = level.gameState
            #expect(BubblingImpact.everyBubblingMatters(s, minMoves: minMoves, cost: BubblingImpact.strongCost), "\(level.id)")
            #expect(LockImpact.everyLockMatters(s, minMoves: minMoves, cost: LockImpact.strongCost), "\(level.id)")
            checked += 1
        }
        #expect(checked >= 10)
    }
}
