import Foundation
import Testing
@testable import BottleSortCore

/// Layers from color numbers, with `.key(k)` for negative numbers −k.
private func layers(_ values: [Int]) -> [Layer] {
    values.map { $0 < 0 ? .key(KeyID(-$0)) : .color(ColorID($0)) }
}

private func ice(_ layer: Int, _ turns: Int) -> BottleModifier { .frozen(layer: layer, turns: turns) }

/// D1 frozen layers: the rule cases.
@Suite struct FrozenRuleTests {
    @Test func onlyTheLayersAboveTheIceMove() throws {
        // A run of three 0s, the lowest of them frozen: two move.
        let s = GameState(bottles: [bottle([1, 0, 0, 0], capacity: 4, [ice(1, 3)]), bottle([], capacity: 4)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[0].layers == layers([1, 0]))
        #expect(turn.state.bottles[1].layers == layers([0, 0]))
        #expect(turn.pour == PourEvent(move: Move(from: 0, to: 1), layer: .color(0), amount: 2))
        #expect(Rules.outlet(of: s.bottles[0])! == (2..<4, false))
        // Then the frozen layer is on top: nothing leaves.
        #expect(!turn.state.canPour(Move(from: 0, to: 1)))
        #expect(Rules.outlet(of: turn.state.bottles[0]) == nil)
        // A frozen bottom layer pins nothing else.
        #expect(Rules.pourAmount(from: bottle([1, 0, 0], capacity: 4, [ice(0, 2)]), to: bottle([], capacity: 4)) == 2)
    }

    @Test func iceOnTopShutsTheFlask() {
        let s = GameState(bottles: [bottle([0, 1, 1], capacity: 4, [ice(2, 2)]), bottle([1], capacity: 4),
                                    bottle([], capacity: 4)])
        #expect(!s.canPour(Move(from: 0, to: 1)) && !s.canPour(Move(from: 0, to: 2)))   // nothing leaves
        #expect(!s.canPour(Move(from: 1, to: 0)))                                       // nothing goes in, same color too
        #expect(s.bottles[0].isIcedOver && s.bottles[0].holdsIce)
        // The ice is the reason, whatever the other flask holds (closed side).
        #expect(Rules.refusal(of: Move(from: 0, to: 2), in: s)! == (0, ice(2, 2)))
        #expect(Rules.refusal(of: Move(from: 1, to: 0), in: s)! == (0, ice(2, 2)))
        var full = s
        full.bottles[1].layers = layers([0, 0, 0, 1])
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: full)! == (0, ice(2, 2)))
        // Ice lower down doesn't stop pours in.
        let lower = GameState(bottles: [bottle([0, 1], capacity: 4, [ice(0, 2)]), bottle([1], capacity: 4)])
        #expect(lower.canPour(Move(from: 1, to: 0)) && Rules.refusal(of: Move(from: 1, to: 0), in: lower) == nil)
        var plan = PourPlan(layer: .color(1))
        #expect(Rules.apply(ice(0, 2), as: .target, to: &plan, source: lower.bottles[1], target: lower.bottles[0]))
        #expect(!Rules.apply(ice(1, 2), as: .target, to: &plan, source: lower.bottles[1], target: lower.bottles[0]))
    }

    @Test func countersTickAfterEveryMoveAndTheLayerThaws() throws {
        let s = GameState(bottles: [bottle([0, 1, 1], capacity: 3, [ice(1, 2)]), bottle([1], capacity: 3),
                                    bottle([0, 0], capacity: 3), bottle([2, 2, 2], capacity: 3, [ice(0, 1)]),
                                    bottle([], capacity: 3)])
        // Pour 0→1: the 1 above the ice moves; both counters tick, the bottom ice of 3 thaws.
        let first = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(first.state.bottles[0].modifiers == [ice(1, 1)])
        #expect(first.state.bottles[3].modifiers.isEmpty)
        #expect(first.events == [.thawed(bottle: 3, layer: 0)])
        #expect(!first.isWon)
        // The ice is now on top of flask 0: it is shut. Any legal move elsewhere ticks the
        // last counter to 0.
        #expect(!first.state.canPour(Move(from: 0, to: 4)) && !first.state.canPour(Move(from: 1, to: 0)))
        let move = try #require(first.state.legalMoves().first)
        let second = try #require(Rules.resolve(first.state, afterAction: .pour(move)))
        #expect(second.events == [.thawed(bottle: 0, layer: 1)])
        #expect(!second.state.bottles[0].holdsIce)
        // A turn with nothing timed reports no events.
        let plain = GameState(bottles: [bottle([0, 1], capacity: 2), bottle([], capacity: 2)])
        #expect(Rules.resolve(plain, afterAction: .pour(Move(from: 0, to: 1)))?.events == [])
    }

    @Test func aTapCantPourWhileItsFlaskHoldsIce() throws {
        let s = GameState(bottles: [bottle([0, 1, 2], capacity: 3, [.tap, ice(2, 1)]), bottle([0, 0], capacity: 3),
                                    bottle([2, 2], capacity: 3), bottle([1, 1], capacity: 3)])
        #expect(!s.canPour(Move(from: 0, to: 1)))   // the bottom is pinned
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: s)! == (0, ice(2, 1)))
        #expect(Rules.outlet(of: s.bottles[0]) == nil)
        // With a spare flask, one move elsewhere thaws the ice and the tap pours again.
        var spare = s
        spare.bottles.append(bottle([], capacity: 3))
        let waited = try #require(spare.pouring(Move(from: 1, to: 4)))
        #expect(!waited.bottles[0].holdsIce)
        let turn = try #require(Rules.resolve(waited, afterAction: .pour(Move(from: 0, to: 4))))
        #expect(turn.pour?.fromBottom == true && turn.state.bottles[0].layers == layers([1, 2]))
        // Ice anywhere in a tap flask blocks it, even its bottom layer.
        let bottomIce = bottle([0, 1], capacity: 3, [.tap, ice(0, 3)])
        #expect(Rules.pourAmount(from: bottomIce, to: bottle([], capacity: 3)) == 0)
    }

    @Test func iceOnTopRefusesEvenTheSealsKey() {
        let s = GameState(bottles: [Bottle(layers: layers([-1]), capacity: 2),
                                    Bottle(layers: layers([0, 0]), capacity: 2, modifiers: [.sealed(1), ice(1, 2)]),
                                    Bottle(layers: layers([]), capacity: 2)])
        #expect(!s.canPour(Move(from: 0, to: 1)))
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: s)! == (1, ice(1, 2)))
        var lower = s
        lower.bottles[1].modifiers = [.sealed(1), ice(0, 2)]
        #expect(lower.canPour(Move(from: 0, to: 1)))
        #expect(lower.pouring(Move(from: 0, to: 1))?.bottles[1].modifiers == [ice(0, 1)])
    }

    @Test func narrowNeckAndIceBothLimit() {
        let neck = bottle([0, 0, 0, 0], capacity: 4, [.narrowNeck, ice(1, 2)])
        #expect(Rules.pourAmount(from: neck, to: bottle([], capacity: 4)) == 1)
        let wide = bottle([0, 0, 0, 0], capacity: 4, [ice(1, 2)])
        #expect(Rules.pourAmount(from: wide, to: bottle([], capacity: 4)) == 2)
        #expect(Rules.pourAmount(from: wide, to: bottle([0, 0, 0], capacity: 4)) == 1)   // free space
    }

    @Test func iceKeepsTheRecipeUnwonUntilItThaws() throws {
        let s = GameState(bottles: [bottle([0, 0], capacity: 2, [ice(0, 2)]), bottle([1, 1], capacity: 2),
                                    bottle([], capacity: 2)])
        #expect(!Rules.isSolved(s.bottles[0]) && !s.isSolved)
        #expect(Rules.isSolved(bottle([0, 0], capacity: 2)))
        // Two "wait" moves (relocating the 1s) let the ice thaw.
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 2 && referenceMinMoves(s) == 2)
        var current = s
        for m in moves { current = try #require(current.pouring(m)) }
        #expect(current.isSolved)
        #expect(Rules.isCompleted(bottle([0, 0], capacity: 2)) && !Rules.isCompleted(s.bottles[0]))
    }

    @Test func displayHelpers() {
        let b = bottle([0, 1, 2, 3], capacity: 4, [ice(3, 2), ice(1, 5)])
        #expect(b.frozenLayers == [FrozenLayer(layer: 1, turns: 5), FrozenLayer(layer: 3, turns: 2)])
        #expect(b.thawTurns(atLayer: 1) == 5 && b.thawTurns(atLayer: 3) == 2 && b.thawTurns(atLayer: 0) == nil)
        #expect(b.holdsIce && b.isIcedOver)
        let plain = bottle([0], capacity: 4)
        #expect(plain.frozenLayers.isEmpty && !plain.holdsIce && !plain.isIcedOver)
        #expect(!bottle([], capacity: 4).isIcedOver)
        let sealed = Bottle(layers: layers([0, 1]), capacity: 4, lockedBy: 2)
        #expect(!sealed.holdsIce && sealed.frozenLayers.isEmpty)
        let level = LevelDefinition(id: "f", state: GameState(bottles: [b, sealed]), hidden: true)
        #expect(level.mechanics == [.sealed, .murky, .frozen])
        #expect(ChapterOutline.plan[5].introduces == [.frozen] && ChapterOutline.plan[5].location == "Frost Peak")
        #expect(Mechanic.frozen.rawValue == "frozen" && ice(0, 1).isImplemented)
        #expect(Rules.maxThawTurns == 5 && Rules.maxFrozenLayers == 2)
    }

    @Test func legalMovesAgreeWithResolve() {
        for s in FrozenKeyTests.randomStates() {
            for from in s.bottles.indices {
                for to in s.bottles.indices {
                    let move = Move(from: from, to: to)
                    #expect(s.canPour(move) == (Rules.resolve(s, afterAction: .pour(move)) != nil))
                }
            }
        }
    }
}

/// Hand-made puzzles where the ice decides the solution.
@Suite struct FrozenPuzzleTests {
    /// The 1 on top of flask 0 is frozen for 3 moves, and the 0s under it can't join their
    /// partner before it leaves: the player must spend the three moves elsewhere (here only
    /// by moving the lone 0 back and forth), then finish in two. Without the ice: 2 moves.
    @Test func waitingForTheThawIsRequired() throws {
        let s = GameState(bottles: [bottle([0, 0, 1], capacity: 3, [ice(2, 3)]), bottle([1, 1], capacity: 3),
                                    bottle([0], capacity: 3), bottle([], capacity: 3)])
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 5)
        #expect(referenceMinMoves(s) == 5)
        let without = MechanicImpact.removing(.modifier(bottle: 0, ice(2, 3)), from: s)
        #expect(Solver().solve(without).moves?.count == 2)
        #expect(FrozenImpact.everyFrozenMatters(s, minMoves: 5, cost: FrozenImpact.strongCost))
        // The waits are relocations, which the solver normally prunes: kept while ice remains.
        #expect(Solver.candidateMoves(s).contains(Move(from: 2, to: 3)))
        var replay = s
        for m in moves { replay = try #require(replay.pouring(m)) }
        #expect(replay.isSolved)
        // With one empty flask fewer the ice can never thaw (no move is left): unsolvable.
        let stuck = GameState(bottles: Array(s.bottles.prefix(3)))
        #expect(stuck.legalMoves().isEmpty)
        if case .unsolvable = Solver().solve(stuck) {} else { Issue.record("expected unsolvable") }
    }

    /// The ice pins the 1 under it: the 0 above must go first, and the 1s can only be
    /// joined after the thaw, which changes the order of the whole solution.
    @Test func pinnedLayerChangesThePlan() throws {
        let s = GameState(bottles: [bottle([2, 1, 0], capacity: 3, [ice(1, 4)]), bottle([0, 1, 2], capacity: 3),
                                    bottle([1, 0, 2], capacity: 3), bottle([], capacity: 3), bottle([], capacity: 3)])
        let moves = try #require(Solver().solve(s).moves)
        #expect(referenceMinMoves(s) == moves.count)
        let without = MechanicImpact.removing(.modifier(bottle: 0, ice(1, 4)), from: s)
        let plain = try #require(Solver().solve(without).moves)
        #expect(plain.count <= moves.count)
        var replay = s
        for m in moves { replay = try #require(replay.pouring(m)) }
        #expect(replay.isSolved)
    }

    @Test func frozenIsOneSided() {
        #expect(!MechanicImpact.isTwoSided(.modifier(bottle: 0, ice(0, 1))))
        #expect(MechanicImpact.minimumCost(of: .modifier(bottle: 0, ice(0, 1))) == FrozenImpact.minimumCost)
        #expect(FrozenImpact.strongCost == 2)
    }
}

/// The solver with frozen layers: exact, and its pruning stays safe.
@Suite struct FrozenSolverTests {
    static let configs = [
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, frozen: 1, frozenMaxTurns: 3),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, frozen: 2, frozenMaxTurns: 5),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, frozen: 1, frozenMaxTurns: 5),
        GeneratorConfig(colors: 3, capacity: 2, emptyBottles: 2, frozen: 2, frozenMaxTurns: 4),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, taps: 1, frozen: 1, frozenMaxTurns: 3),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, narrowNecks: 1, funnels: 1, frozen: 2, frozenMaxTurns: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, frozen: 1, frozenMaxTurns: 4),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, essence: 1, frozen: 2, frozenMaxTurns: 3),
        GeneratorConfig(colors: 4, capacity: 2, emptyBottles: 1, frozen: 2, frozenMaxTurns: 5),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, locks: 1, taps: 1, frozen: 2, frozenMaxTurns: 5),
    ]

    /// Solver vs. the naive BFS (no pruning, no canonical keys) on many small random levels.
    @Test(arguments: configs.indices)
    func solverMatchesReference(_ index: Int) throws {
        let config = Self.configs[index]
        var checked = 0
        for seed in UInt64(1)...25 {
            let s = Generator.candidate(config, seed: seed)
            #expect(s.validate().isEmpty, "\(s)")
            #expect(s.bottles.contains { $0.holdsIce }, "\(s)")
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
    /// (no exception for no-ops while ice remains: a relocation ticks the counters).
    @Test func pruningKeepsEveryDistinctChild() {
        for config in Self.configs {
            for seed in UInt64(1)...10 {
                var s = Generator.candidate(config, seed: seed)
                for step in 0..<6 {
                    let all = Set(s.legalMoves().compactMap { s.pouring($0)?.canonicalKey })
                    let pruned = Set(Solver.candidateMoves(s).compactMap { s.pouring($0)?.canonicalKey })
                    if s.bottles.contains { $0.holdsIce } {
                        #expect(all == pruned, "\(s)")
                    } else {
                        #expect(all.subtracting(pruned).isSubset(of: [s.canonicalKey]), "\(s)")
                    }
                    let moves = s.legalMoves()
                    guard !moves.isEmpty else { break }
                    s = s.pouring(moves[(Int(seed) + step) % moves.count])!
                }
            }
        }
    }

    /// Rules 1 and 2 (relocations) are off while ice remains, rule 3 stays.
    @Test func relocationsAreKeptWhileIceRemains() {
        let s = GameState(bottles: [bottle([0, 0], capacity: 2, [ice(0, 2)]), bottle([1, 1], capacity: 2),
                                    bottle([], capacity: 2), bottle([], capacity: 2)])
        let moves = Solver.candidateMoves(s)
        #expect(moves.contains(Move(from: 1, to: 2)))      // rule 1 off: a full flask may "wait"
        #expect(!moves.contains(Move(from: 1, to: 3)))     // rule 3: only the first empty flask
        var thawed = s
        thawed.bottles[0].modifiers = []
        #expect(Solver.candidateMoves(thawed).isEmpty)     // all rules back once it thawed
    }
}

/// StateKey with frozen layers.
@Suite struct FrozenKeyTests {
    static func randomStates() -> [GameState] {
        var result: [GameState] = []
        let extra = GeneratorConfig(colors: 6, emptyBottles: 2, locks: 1, essence: 1, taps: 1, frozen: 2, frozenMaxTurns: 5)
        for config in FrozenSolverTests.configs + [extra] {
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
        var rng = SplitMix64(seed: 6)
        for s in Self.randomStates() {
            for _ in 0..<3 {
                var order = Array(s.bottles.indices)
                rng.shuffle(&order)
                #expect(s.permuted(by: order).canonicalKey == s.canonicalKey)
            }
        }
    }

    @Test func pairPathEqualsTheGeneralEncoding() {
        // Flasks with two modifiers (ice and a tap, two ice layers) take the general path.
        var paired = 0
        for s in Self.randomStates() {
            guard let pair = StateKey.pairCodes(s) else { continue }
            #expect(pair == StateKey.extendedCodes(s), "\(s)")
            paired += 1
        }
        #expect(paired > 100)
        #expect(StateKey.singleWord(for: ice(3, 4)) == StateKey.words(for: ice(3, 4))[0])
    }

    @Test func counterAndLayerArePartOfTheKey() {
        let base = GameState(bottles: [bottle([0, 1, 1], capacity: 3), bottle([1, 0, 0], capacity: 3), bottle([], capacity: 3)])
        var keys: Set<StateKey> = [base.canonicalKey]
        for (b, layer, turns) in [(0, 0, 1), (0, 0, 2), (0, 1, 1), (0, 2, 1), (1, 0, 1), (1, 1, 5)] {
            var s = base
            s.bottles[b].modifiers = [ice(layer, turns)]
            keys.insert(s.canonicalKey)
        }
        var two = base
        two.bottles[0].modifiers = [ice(0, 1)]
        two.bottles[1].modifiers = [ice(0, 1)]
        keys.insert(two.canonicalKey)
        var both = base
        both.bottles[0].modifiers = [ice(0, 1), ice(2, 1)]
        keys.insert(both.canonicalKey)
        #expect(keys.count == 9)
        // The same ice on the same content in another position: the same key.
        let a = GameState(bottles: [bottle([0, 1], capacity: 2, [ice(1, 3)]), bottle([1, 0], capacity: 2)])
        let b = GameState(bottles: [bottle([1, 0], capacity: 2), bottle([0, 1], capacity: 2, [ice(1, 3)])])
        #expect(a.canonicalKey == b.canonicalKey)
    }

    @Test func thawKeepsTheModifierOrderCanonical() throws {
        // Two ice layers and a tap in one flask: after each tick the stored list equals the
        // normalized one, so equality and keys stay set-like.
        var s = GameState(bottles: [bottle([0, 1, 2], capacity: 3, [.tap, ice(2, 2), ice(1, 3)]),
                                    bottle([0, 0], capacity: 3), bottle([1, 1], capacity: 3), bottle([2, 2], capacity: 3),
                                    bottle([], capacity: 3)])
        for _ in 0..<3 {
            let move = try #require(s.legalMoves().first)
            s = try #require(s.pouring(move))
            let stored = s.bottles[0].modifiers
            #expect(stored == Bottle.normalize(stored))
            #expect(s.bottles[0] == Bottle(layers: s.bottles[0].layers, capacity: 3, modifiers: stored.reversed()))
        }
        #expect(s.bottles[0].modifiers == [.tap])
    }
}

/// Level files, validation and sessions with frozen layers.
@Suite struct FrozenLevelTests {
    static let sample = GameState(bottles: [bottle([0, 1, 1], capacity: 3, [ice(1, 2)]), bottle([1, 0, 0], capacity: 3),
                                            bottle([], capacity: 3), bottle([], capacity: 3)])

    @Test func jsonRoundTrip() throws {
        var s = Self.sample
        s.bottles[1].modifiers = [ice(2, 5), .narrowNeck]
        let level = LevelDefinition(id: "f1", state: s, meta: LevelMeta(seed: 1, minMoves: 4))
        let pack = LevelPack(name: "Frost Peak", kind: .chapter, chapter: 6, location: "Frost Peak",
                             introduces: [.frozen], levels: [level])
        #expect(pack.requiredVersion == 2)
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""type" : "frozen""#) && text.contains(#""turns" : 5"#) && text.contains(#""layer" : 2"#))
        let loaded = try LevelLoader.load(data)
        #expect(loaded.levels == pack.levels && loaded.introduces == [.frozen])
        #expect(loaded.levels[0].gameState == s)
        #expect(try LevelLoader.encode(loaded) == data)
    }

    @Test func handWrittenJSON() throws {
        let json = #"""
        {"version": 2, "levels": [{"id": "a", "capacity": 2, "bottles": [
          {"layers": [0, 1], "modifiers": [{"type": "frozen", "layer": 1, "turns": 3}]}, {"layers": [1, 0]},
          {"layers": []}]}]}
        """#
        let s = try LevelLoader.load(Data(json.utf8)).levels[0].gameState
        #expect(s.bottles[0].frozenLayers == [FrozenLayer(layer: 1, turns: 3)])
        let v1 = json.replacingOccurrences(of: #""version": 2"#, with: #""version": 1"#)
        #expect(throws: LevelLoadError.needsVersion2(id: "a")) { try LevelLoader.load(Data(v1.utf8)) }
    }

    @Test func validation() {
        #expect(Self.sample.validate().isEmpty)
        var s = Self.sample
        s.bottles[0].modifiers = [ice(3, 2)]
        #expect(s.validate() == [.frozenLayerOutOfRange(bottle: 0, layer: 3)])
        s.bottles[0].modifiers = [ice(0, 0)]
        #expect(s.validate() == [.invalidThawTurns(bottle: 0, turns: 0)])
        s.bottles[0].modifiers = [ice(0, 6)]
        #expect(s.validate() == [.invalidThawTurns(bottle: 0, turns: 6)])
        s.bottles[0].modifiers = [ice(1, 2), ice(1, 3)]
        #expect(s.validate() == [.duplicateFrozenLayer(bottle: 0, layer: 1)])
        s.bottles[0].modifiers = [ice(0, 2), ice(1, 3)]
        s.bottles[1].modifiers = [ice(0, 1)]
        #expect(s.validate() == [.tooManyFrozenLayers(count: 3)])
        s.bottles[2].modifiers = [ice(0, 1)]   // an empty flask can't hold ice
        #expect(s.validate().contains(.frozenLayerOutOfRange(bottle: 2, layer: 0)))
        for e in [ValidationError.frozenLayerOutOfRange(bottle: 1, layer: 4), .invalidThawTurns(bottle: 1, turns: 9),
                  .duplicateFrozenLayer(bottle: 1, layer: 2), .tooManyFrozenLayers(count: 3)] {
            #expect(!e.description.isEmpty)
        }
        // Ice with every earlier modifier is fine.
        let mixed = GameState(bottles: [Bottle(layers: layers([0, -1]), capacity: 2, modifiers: [.tap, ice(0, 2)]),
                                        Bottle(layers: layers([0, 1]), capacity: 2, modifiers: [.sealed(1), ice(1, 5)]),
                                        Bottle(layers: layers([1]), capacity: 2, modifiers: [.essence(1)])])
        #expect(mixed.validate().isEmpty)
    }

    @Test func undoAndRestartRestoreTheCounters() throws {
        var session = GameSession(Self.sample)
        let first = session.play(Move(from: 0, to: 2))             // the top 1 leaves
        #expect(first != nil)
        #expect(session.state.bottles[0].frozenLayers == [FrozenLayer(layer: 1, turns: 1)])
        #expect(session.lastEvents.isEmpty)
        let played = session.play(Move(from: 1, to: 3))            // the ice thaws
        let turn = try #require(played)
        #expect(turn.events == [.thawed(bottle: 0, layer: 1)] && session.lastEvents == turn.events)
        #expect(!session.state.bottles[0].holdsIce)
        session.undo()
        #expect(session.state.bottles[0].frozenLayers == [FrozenLayer(layer: 1, turns: 1)])
        #expect(session.lastEvents.isEmpty)
        session.undo()
        #expect(session.state == Self.sample)
        session.apply(Move(from: 0, to: 2))
        session.apply(Move(from: 1, to: 3))
        session.restart()
        #expect(session.state == Self.sample && session.lastEvents.isEmpty && session.moveCount == 0)
        // A refused move changes nothing (no tick).
        var iced = GameSession(GameState(bottles: [bottle([0, 1], capacity: 2, [ice(1, 2)]), bottle([], capacity: 2)]))
        let refused = iced.play(Move(from: 0, to: 1))
        #expect(refused == nil && iced.state.bottles[0].thawTurns(atLayer: 1) == 2)
    }

    /// Murky flags with ice: frozen layers never move, so the flags keep matching their layers.
    @Test func murkyMasksWithIce() throws {
        let s = GameState(bottles: [bottle([2, 1, 0, 0], capacity: 4, [ice(1, 2)]), bottle([], capacity: 4),
                                    bottle([0, 0, 1, 1], capacity: 4), bottle([1, 2, 2, 2], capacity: 4)])
        var session = GameSession(s, hidden: true)
        #expect(session.hiddenMasks[0] == [true, true, false, false])
        session.apply(Move(from: 0, to: 1))
        #expect(session.hiddenMasks[0] == [true, false] && session.state.bottles[0].thawTurns(atLayer: 1) == 1)
        session.undo()
        #expect(session.hiddenMasks[0] == [true, true, false, false])
    }
}

/// Generator options for frozen layers.
@Suite struct FrozenGeneratorTests {
    @Test func noIceLeavesEveryLevelUnchanged() {
        for seed in UInt64(1)...10 {
            let config = GeneratorConfig(colors: 5, locks: 1, essence: 1, narrowNecks: 1, taps: 1)
            var frozen = config
            frozen.frozen = 2
            frozen.frozenMaxTurns = 5
            let plain = Generator.candidate(config, seed: seed)
            let marked = Generator.candidate(frozen, seed: seed)
            #expect(marked.bottles.map(\.layers) == plain.bottles.map(\.layers))
            for (a, b) in zip(plain.bottles, marked.bottles) {
                #expect(b.modifiers.filter { !$0.isTimed } == a.modifiers)
            }
            #expect(!plain.bottles.contains { $0.holdsIce })
        }
    }

    @Test func placementRules() {
        for seed in UInt64(1)...40 {
            let config = GeneratorConfig(colors: 5, emptyBottles: 2, locks: 1, funnels: 1, frozen: 2, frozenMaxTurns: 5)
            let s = Generator.candidate(config, seed: seed)
            let ice = s.bottles.flatMap(\.frozenLayers)
            #expect(ice.count == 2)
            #expect(ice.allSatisfy { (3...5).contains($0.turns) })
            for b in s.bottles where b.holdsIce {
                #expect(b.frozenLayers.count == 1 && !b.isFunnel)
                #expect(b.frozenLayers[0].layer >= b.layers.count / 2)
            }
            #expect(s.validate().isEmpty)
        }
        let small = GeneratorConfig(colors: 3, frozen: 1, frozenMaxTurns: 1)
        #expect(Generator.candidate(small, seed: 1).bottles.flatMap(\.frozenLayers).map(\.turns) == [1])
        // A full flask of one color under ice is pre-solved (it would thaw into a sorted flask).
        #expect(Generator.isPresolved(bottle([1, 1, 1, 1], capacity: 4, [ice(3, 4)])))
    }

    @Test func generationIsDeterministicAndIceMatters() throws {
        let config = GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, seed: 1, frozen: 2, frozenMaxTurns: 3,
                                     requireFrozenMatter: true, frozenCost: FrozenImpact.strongCost)
        let a = try Generator.generate(config, count: 2)
        let b = try Generator.generate(config, count: 2)
        #expect(a == b)
        for level in a {
            #expect(FrozenImpact.instances(in: level.state).count == 2)
            #expect(FrozenImpact.everyFrozenMatters(level.state, minMoves: level.report.minMoves, cost: FrozenImpact.strongCost))
        }
    }
}
