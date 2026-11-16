import Foundation
import Testing
@testable import BottleSortCore

/// Layers from color numbers, with `.key(k)` for negative numbers −k.
private func layers(_ values: [Int]) -> [Layer] {
    values.map { $0 < 0 ? .key(KeyID(-$0)) : .color(ColorID($0)) }
}

private func flask(_ values: [Int], _ capacity: Int, _ modifiers: [BottleModifier] = []) -> Bottle {
    Bottle(layers: layers(values), capacity: capacity, modifiers: modifiers)
}

/// A3 switch flasks and gates: the rule cases.
@Suite struct SwitchRuleTests {
    /// Switch 0 → gate 1, two plain flasks 2 and 3.
    static func board(switch s: [Int], gate g: [Int], _ c: [Int] = [], _ d: [Int] = [], capacity: Int = 3,
                      switchModifiers: [BottleModifier] = [], gateModifiers: [BottleModifier] = []) -> GameState {
        GameState(bottles: [flask(s, capacity, switchModifiers), flask(g, capacity, gateModifiers),
                            flask(c, capacity), flask(d, capacity)],
                  links: [.switchGate(switch: 0, gate: 1)])
    }

    @Test func aClosedGateRefusesPoursInAndOut() {
        let s = Self.board(switch: [0, 0, 1], gate: [1, 2], [2], [])
        #expect(s.isGateClosed(1) && !s.isGateClosed(0) && !s.isGateClosed(2))
        #expect(!s.canPour(Move(from: 1, to: 3)))   // out of the gate
        #expect(!s.canPour(Move(from: 1, to: 2)))   // out of the gate onto its own color
        #expect(!s.canPour(Move(from: 2, to: 1)))   // into the gate
        #expect(!s.canPour(Move(from: 0, to: 1)))   // even from its switch
        // Everything else works as usual, the switch included.
        #expect(s.canPour(Move(from: 0, to: 3)) && s.canPour(Move(from: 2, to: 3)))
    }

    @Test func aCompleteSwitchOpensTheGate() throws {
        let s = Self.board(switch: [0, 0, 0], gate: [1, 2], [2], [])
        #expect(!s.isGateClosed(1))
        #expect(s.canPour(Move(from: 1, to: 2)) && s.canPour(Move(from: 2, to: 1)) && s.canPour(Move(from: 1, to: 3)))
        let next = try #require(s.pouring(Move(from: 1, to: 2)))
        #expect(next.bottles[2].layers == layers([2, 2]) && next.bottles[1].layers == layers([1]))
    }

    @Test func completingTheSwitchOpensTheGateAtOnce() throws {
        let s = Self.board(switch: [0, 0], gate: [1, 2], [2, 0], [])
        #expect(s.isGateClosed(1))
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 2, to: 0))))
        #expect(turn.events == [.gateOpened(switch: 0, gate: 1)])
        #expect(!turn.state.isGateClosed(1) && turn.state.canPour(Move(from: 1, to: 2)))
        // A pour that leaves the switch incomplete reports nothing.
        let other = Self.board(switch: [0], gate: [1, 2], [2, 0], [])
        let quiet = try #require(Rules.resolve(other, afterAction: .pour(Move(from: 2, to: 0))))
        #expect(quiet.events.isEmpty && quiet.state.isGateClosed(1))
    }

    @Test func pouringOutOfTheSwitchClosesTheGate() throws {
        let s = Self.board(switch: [0, 0, 0], gate: [1, 2], [2], [])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 3))))
        #expect(turn.events == [.gateClosed(switch: 0, gate: 1)])
        #expect(turn.state.isGateClosed(1) && !turn.state.canPour(Move(from: 1, to: 2)))
        // Pouring it back reopens the gate.
        let back = try #require(Rules.resolve(turn.state, afterAction: .pour(Move(from: 3, to: 0))))
        #expect(back.events == [.gateOpened(switch: 0, gate: 1)])
        #expect(back.state == s)
    }

    @Test func theSwitchMayPourIntoItsOpenGate() throws {
        // The gate is open when the pour is checked; the pour empties the switch and shuts the
        // gate behind the potion that went in.
        let s = Self.board(switch: [0, 0, 0], gate: [], [1, 1, 1], [])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[1].layers == layers([0, 0, 0]) && turn.state.bottles[0].isEmpty)
        #expect(turn.events == [.gateClosed(switch: 0, gate: 1)] && turn.state.isGateClosed(1))
        // Won: the closed gate is complete and the switch is empty.
        #expect(turn.isWon)
    }

    @Test func aSealedSwitchOpensItsGateWhenUnsealed() throws {
        // Full of one color but sealed: not complete, so the gate is shut until the key goes in
        // (step 2: unseal, then the gates).
        let fourWide = GameState(bottles: [flask([0, 0, 0, 0], 4, [.sealed(1)]), flask([1, 1, 2], 4),
                                           flask([2, 2, 1, -1], 4), flask([], 4)],
                                 links: [.switchGate(switch: 0, gate: 1)])
        #expect(fourWide.isGateClosed(1))
        let turn = try #require(Rules.resolve(fourWide, afterAction: .pour(Move(from: 2, to: 0))))
        #expect(turn.pour?.openedSeal == 1)
        #expect(turn.events == [.gateOpened(switch: 0, gate: 1)] && !turn.state.isGateClosed(1))
    }

    @Test func anIcedSwitchOpensItsGateWhenTheIceThaws() throws {
        // A thaw is a timed effect: the gate opens in step 5, after the `.thawed` event.
        let s = Self.board(switch: [0, 0, 0], gate: [1, 2], [2, 1], [], switchModifiers: [.frozen(layer: 2, turns: 1)])
        #expect(s.isGateClosed(1))
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 2, to: 3))))
        #expect(turn.events == [.thawed(bottle: 0, layer: 2), .gateOpened(switch: 0, gate: 1)])
        #expect(!turn.state.isGateClosed(1))
    }

    @Test func mixingAndGatesAreSeparateEvents() throws {
        // A pour into a cauldron is no link end; a switch elsewhere completes in the same turn only
        // through the pour itself, so a mixing pour reports `.mixed` alone.
        let recipe = Recipe(0, 1, result: 2)
        let s = GameState(bottles: [flask([3, 3], 3), flask([4], 3), flask([1, 0], 3), flask([1], 3, [.cauldron([recipe])]),
                                    flask([3], 3), flask([4, 4, 2], 3)],
                          links: [.switchGate(switch: 0, gate: 1)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 2, to: 3))))
        #expect(turn.events == [.mixed(bottle: 3, recipe: recipe, pairs: 1)])
        let opening = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 4, to: 0))))
        #expect(opening.events == [.gateOpened(switch: 0, gate: 1)])
    }

    @Test func aClosedGateKeepsEvenItsKeyOut() {
        // A sealed gate behind a closed switch: the key can't reach the seal.
        let s = Self.board(switch: [0, 0], gate: [1, 1, 1], [-1], [0], capacity: 3, gateModifiers: [.sealed(1)])
        #expect(!s.canPour(Move(from: 2, to: 1)))
        var open = s
        open.bottles[0] = flask([0, 0, 0], 3)
        open.bottles[3] = flask([], 3)
        #expect(open.canPour(Move(from: 2, to: 1)))
    }

    @Test func theWinIsStandard() {
        // Every flask sorted wins, whatever the gates: an empty switch with a closed, complete gate.
        let closed = Self.board(switch: [], gate: [1, 1, 1], [2, 2, 2], [0, 0, 0])
        #expect(closed.isGateClosed(1) && closed.isSolved)
        // A closed gate that isn't sorted loses nothing yet, but the level isn't won.
        let unsorted = Self.board(switch: [0, 0], gate: [1, 2], [2, 2, 1], [1, 0, 0])
        #expect(!unsorted.isSolved)
    }

    @Test func linkRefusals() {
        let s = Self.board(switch: [0, 0, 1], gate: [1, 2], [2], [])
        let link = Link.switchGate(switch: 0, gate: 1)
        #expect(Rules.linkRefusal(of: Move(from: 1, to: 3), in: s) == link)
        #expect(Rules.linkRefusal(of: Move(from: 2, to: 1), in: s) == link)
        #expect(Rules.linkRefusal(of: Move(from: 1, to: 2), in: s) == link)
        // Illegal for a base reason too (colors differ): not the gate's fault.
        #expect(Rules.linkRefusal(of: Move(from: 0, to: 1), in: s) == nil)
        // Legal moves and other flasks: nil.
        #expect(Rules.linkRefusal(of: Move(from: 2, to: 3), in: s) == nil)
        #expect(Rules.refusal(of: Move(from: 1, to: 3), in: s) == nil)
    }

    @Test func displayHelpers() {
        let s = Self.board(switch: [0, 0, 1], gate: [1, 2], [2], [])
        #expect(s.gate(of: 0) == 1 && s.gate(of: 1) == nil && s.gate(of: 2) == nil)
        #expect(s.switchFlask(of: 1) == 0 && s.switchFlask(of: 0) == nil)
        #expect(s.link(at: 0) == .switchGate(switch: 0, gate: 1))
        #expect(!Rules.isSwitchOn(s.bottles[0]) && Rules.isSwitchOn(flask([2, 2, 2], 3)))
        #expect(!Rules.isSwitchOn(flask([2, 2], 3)) && !Rules.isSwitchOn(flask([], 3)))
        #expect(!Rules.isSwitchOn(flask([2, 2, 2], 3, [.sealed(1)])))
        #expect(!Rules.isSwitchOn(flask([2, 2, 2], 3, [.frozen(layer: 0, turns: 2)])))
        #expect(Rules.isSwitchOn(flask([2, 2, 2], 3, [.narrowNeck])))
        #expect(Rules.isGateClosed(1, in: s) && !Rules.isGateClosed(0, in: s) && !Rules.isGateClosed(9, in: s))
        let plain = GameState(bottles: s.bottles)
        #expect(!plain.isGateClosed(1))
    }

    @Test func legalMovesAgreeWithResolve() {
        let boards = [
            Self.board(switch: [0, 0, 1], gate: [1, 2], [2], []),
            Self.board(switch: [0, 0, 0], gate: [1, 2], [2, 1], []),
            Self.board(switch: [0, 0], gate: [], [1, 1, 0], [2, 2, 2]),
        ]
        for s in boards {
            for from in s.bottles.indices {
                for to in s.bottles.indices {
                    let move = Move(from: from, to: to)
                    #expect(s.canPour(move) == (Rules.resolve(s, afterAction: .pour(move)) != nil))
                }
            }
        }
    }

    @Test func modifiersOnSwitchAndGateStillApply() throws {
        // A narrow-neck gate takes one layer at a time once open; a funnel switch never pours out
        // (once complete it stays complete).
        let s = Self.board(switch: [0, 0, 0], gate: [1], [1, 1], [], switchModifiers: [.funnel], gateModifiers: [.narrowNeck])
        let next = try #require(s.pouring(Move(from: 2, to: 1)))
        #expect(next.bottles[1].layers == layers([1, 1]) && next.bottles[2].layers == layers([1]))
        #expect(!s.canPour(Move(from: 0, to: 3)))
    }
}

/// The solver with switches.
@Suite struct SwitchSolverTests {
    /// A tiny recipe that needs the switch (the c10 tutorial shape): the gate 0 holds the red on
    /// top of two blues, the switch 2 starts with a red under two yellows. Without the lever 5
    /// moves; with it the switch has to be completed first.
    static let needsTheSwitch = GameState(
        bottles: [flask([1, 1, 0], 3), flask([1, 2, 0], 3), flask([0, 2, 2], 3), flask([], 3), flask([], 3)],
        links: [.switchGate(switch: 2, gate: 0)])

    @Test func aRecipeThatNeedsTheSwitch() throws {
        let s = Self.needsTheSwitch
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == referenceMinMoves(s))
        let without = MechanicImpact.removing(.link(.switchGate(switch: 2, gate: 0)), from: s)
        let plain = try #require(Solver().solve(without).moves)
        #expect(moves.count >= plain.count + SwitchImpact.strongCost)
        #expect(SwitchImpact.everySwitchMatters(s, minMoves: moves.count, cost: SwitchImpact.strongCost))
        // The optimal solution opens the gate and then pours out of it.
        let openings = SwitchImpact.gateOpenings(in: s, solution: moves)
        #expect(openings.count >= 1)
        let firstOpen = try #require(openings.first)
        #expect(moves[(firstOpen + 1)...].contains { $0.from == 0 || $0.to == 0 })
        #expect(moves[...firstOpen].allSatisfy { $0.from != 0 && $0.to != 0 })
        #expect(SwitchImpact.everyGateStartsClosedWithLayers(s))
        #expect(SwitchImpact.solvesWithoutWaiting(s, in: moves.count))
        #expect(MechanicImpact.everyFirstMoveSolvable(s))
    }

    @Test func aGateThatCanNeverOpenIsUnsolvable() {
        // The only third red is behind the gate, and the switch can only be completed with red.
        let s = GameState(bottles: [flask([0, 0], 3), flask([1, 1, 0], 3), flask([1], 3), flask([], 3)],
                          links: [.switchGate(switch: 0, gate: 1)])
        #expect(referenceMinMoves(s) == nil)
        if case .unsolvable = Solver().solve(s) {} else { Issue.record("expected unsolvable") }
    }

    static let configs: [GeneratorConfig] = [
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, switches: 1, switchPlacement: .closed),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, switches: 1, switchPlacement: .empty),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, switches: 1, switchPlacement: .emptySwitch),
        GeneratorConfig(colors: 4, capacity: 2, emptyBottles: 2, switches: 2, switchPlacement: .any),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, switches: 1, switchPlacement: .closed),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, essence: 1, switches: 1, switchPlacement: .closed),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, narrowNecks: 1, switches: 1, switchPlacement: .closed),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, frozen: 1, frozenMaxTurns: 3, switches: 1,
                        switchPlacement: .closed),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, bubbling: 1, bubblingPeriod: 2, switches: 1,
                        switchPlacement: .closed),
        GeneratorConfig(colors: 3, capacity: 2, emptyBottles: 3, twins: 1, linkPlacement: .empty, switches: 1,
                        switchPlacement: .any),
    ]

    /// Small switch levels: generator candidates that validate, plus positions on from each.
    static func levels(seeds: ClosedRange<UInt64>) -> [GameState] {
        var result: [GameState] = []
        for config in configs {
            for seed in seeds {
                let s = Generator.candidate(config, seed: seed)
                guard s.validate().isEmpty, s.links.contains(where: { if case .switchGate = $0 { true } else { false } })
                else { continue }
                result.append(s)
            }
        }
        return result
    }

    /// Solver vs. the naive BFS (no pruning, no canonical keys) on many small random levels and
    /// positions a few moves on.
    @Test(arguments: configs.indices)
    func solverMatchesReference(_ index: Int) throws {
        var checked = 0, unsolvable = 0
        for seed in UInt64(1)...20 {
            let s = Generator.candidate(Self.configs[index], seed: seed)
            guard s.validate().isEmpty else { continue }
            #expect(s.links.contains { if case .switchGate = $0 { true } else { false } })
            var starts = [s]
            var walk = s
            for step in 0..<3 {
                let moves = walk.legalMoves()
                guard !moves.isEmpty, let next = walk.pouring(moves[(step * 7 + Int(seed)) % moves.count]) else { break }
                walk = next
                starts.append(walk)
            }
            for start in starts {
                let expected = referenceMinMoves(start)
                let result = Solver().solve(start)
                #expect(result.moves?.count == expected, "\(start)")
                if case .unsolvable = result { #expect(expected == nil); unsolvable += 1 }
                if let moves = result.moves {
                    var replay = start
                    for m in moves { replay = try #require(replay.pouring(m)) }
                    #expect(replay.isSolved)
                    checked += 1
                }
            }
        }
        #expect(checked > 5)
    }

    /// The pruned candidate list reaches the same canonical children as every legal move (pours
    /// that only relocate an unlinked flask give the current key, which is left out).
    @Test func pruningKeepsEveryDistinctChild() {
        for var s in Self.levels(seeds: 1...6) {
            for step in 0..<8 {
                let key = s.canonicalKey
                let all = Set(s.legalMoves().compactMap { s.pouring($0)?.canonicalKey }).subtracting([key])
                let pruned = Set(Solver.candidateMoves(s).compactMap { s.pouring($0)?.canonicalKey }).subtracting([key])
                #expect(all == pruned, "\(s)")
                let moves = s.legalMoves()
                guard !moves.isEmpty else { break }
                s = s.pouring(moves[(step * 5 + 3) % moves.count])!
            }
        }
    }

    /// Every candidate move is legal: the pruned list never offers a pour out of a closed gate
    /// (the plan of an unlinked target alone would allow it).
    @Test func everyCandidateMoveIsLegal() {
        let closed = SwitchRuleTests.board(switch: [0, 0, 1], gate: [1, 2], [2], [])
        #expect(!Solver.candidateMoves(closed).contains(Move(from: 1, to: 3)))
        #expect(!Solver.candidateMoves(closed).contains(Move(from: 1, to: 2)))
        for var s in Self.levels(seeds: 1...6) {
            for step in 0..<8 {
                for move in Solver.candidateMoves(s) { #expect(s.canPour(move), "\(move) in \(s)") }
                let moves = s.legalMoves()
                guard !moves.isEmpty else { break }
                s = s.pouring(moves[(step * 5 + 3) % moves.count])!
            }
        }
    }

    @Test func aCompleteSwitchIsStillASource() {
        // A full one-color switch is never skipped (rule 1): emptying it is a real choice.
        let s = GameState(bottles: [flask([0, 0], 2), flask([1, 2], 2), flask([2, 1], 2), flask([], 2)],
                          links: [.switchGate(switch: 0, gate: 1)])
        #expect(Solver.candidateMoves(s).contains(Move(from: 0, to: 3)))
        // An empty switch is a target of its own: a full flask poured into it completes it.
        let empty = GameState(bottles: [flask([], 2), flask([1, 2], 2), flask([0, 0], 2), flask([2, 1], 2), flask([], 2)],
                              links: [.switchGate(switch: 0, gate: 1)])
        #expect(Solver.candidateMoves(empty).contains(Move(from: 2, to: 0)))
    }
}

/// StateKey, JSON, validation, sessions and the generator with switches.
@Suite struct SwitchLevelTests {
    @Test func keyIsBottleOrderIndependent() {
        var rng = SplitMix64(seed: 7)
        for var s in SwitchSolverTests.levels(seeds: 1...4) {
            for step in 0..<6 {
                for _ in 0..<2 {
                    var order = Array(s.bottles.indices)
                    rng.shuffle(&order)
                    #expect(s.permuted(by: order).canonicalKey == s.canonicalKey)
                }
                let moves = s.legalMoves()
                guard !moves.isEmpty else { break }
                s = s.pouring(moves[(step * 3 + 1) % moves.count])!
            }
        }
    }

    @Test func switchesArePartOfTheKey() {
        let base = SwitchRuleTests.board(switch: [0, 0, 1], gate: [1, 2], [2], [])
        var swapped = base
        swapped.links = [.switchGate(switch: 1, gate: 0)]
        var plain = base
        plain.links = []
        var twins = base
        twins.links = [.twins(0, 1)]
        let keys = [base, swapped, plain, twins].map(\.canonicalKey)
        #expect(Set(keys).count == 4)
        // The general encoding agrees on the distinction.
        #expect(StateKey.extendedCodes(base) != StateKey.extendedCodes(swapped))
    }

    @Test func jsonRoundTrip() throws {
        let level = LevelDefinition(id: "s1", state: SwitchSolverTests.needsTheSwitch)
        let pack = LevelPack(name: "Hoard", kind: .chapter, chapter: 10, introduces: [.switches], levels: [level])
        let data = try LevelLoader.encode(pack)
        let back = try LevelLoader.load(data)
        #expect(back.version == 2 && back.levels == [level])
        #expect(back.levels[0].gameState == SwitchSolverTests.needsTheSwitch)
        #expect(back.levels[0].mechanics == [.switches])
        #expect(String(decoding: data, as: UTF8.self).contains("switchGate"))
    }

    @Test func handWrittenJSON() throws {
        let json = #"""
        {"version": 2, "levels": [{"id": "s", "capacity": 2, "bottles": [{"layers": [0, 1]}, {"layers": [1, 0]}, {"layers": []}],
          "links": [{"type": "switchGate", "switch": 0, "gate": 1}]}]}
        """#
        let pack = try LevelLoader.load(Data(json.utf8))
        #expect(pack.levels[0].gameState.links == [.switchGate(switch: 0, gate: 1)])
        // Version 1 can't hold links.
        let v1 = json.replacingOccurrences(of: #""version": 2"#, with: #""version": 1"#)
        #expect(throws: (any Error).self) { try LevelLoader.load(Data(v1.utf8)) }
    }

    @Test func validation() {
        let good = SwitchSolverTests.needsTheSwitch
        #expect(good.validate().isEmpty)
        var same = good
        same.links = [.switchGate(switch: 1, gate: 1)]
        #expect(same.validate().contains(.invalidLink(.switchGate(switch: 1, gate: 1))))
        var missing = good
        missing.links = [.switchGate(switch: 1, gate: 9)]
        #expect(missing.validate().contains(.invalidLink(.switchGate(switch: 1, gate: 9))))
        var twoLinks = good
        twoLinks.links = [.switchGate(switch: 2, gate: 0), .twins(0, 3)]
        #expect(twoLinks.validate().contains(.flaskInSeveralLinks(bottle: 0)))
        var twoGates = good
        twoGates.links = [.switchGate(switch: 2, gate: 0), .switchGate(switch: 2, gate: 1)]
        #expect(twoGates.validate().contains(.flaskInSeveralLinks(bottle: 2)))
        var tap = good
        tap.bottles[2].modifiers = [.tap]
        #expect(tap.validate() == [.tapSwitch(bottle: 2)])
        var tapGate = good
        tapGate.bottles[0].modifiers = [.tap]
        #expect(tapGate.validate().isEmpty)
        #expect(!good.validate().contains { if case .unsupportedMechanic = $0 { true } else { false } })
    }

    @Test func undoAndRestartRestoreEverything() throws {
        let start = SwitchRuleTests.board(switch: [0, 0], gate: [1, 2], [2, 0], [1, 1, 2])
        var session = GameSession(start)
        let played = session.play(Move(from: 2, to: 0))
        let turn = try #require(played)
        #expect(turn.events == [.gateOpened(switch: 0, gate: 1)] && session.lastEvents == turn.events)
        #expect(!session.state.isGateClosed(1))
        let applied = session.apply(Move(from: 1, to: 2))
        let undone = session.undo() && session.undo()
        #expect(applied && undone)
        #expect(session.state == start && session.state.isGateClosed(1) && session.lastEvents.isEmpty)
        let again = session.apply(Move(from: 2, to: 0))
        #expect(again)
        session.restart()
        #expect(session.state == start && session.moveCount == 0 && session.lastPour == nil)
    }

    @Test func murkyGatesKeepTheirMasks() throws {
        var session = GameSession(SwitchRuleTests.board(switch: [0, 0], gate: [1, 2, 2], [2, 0], [1, 1]), hidden: true)
        #expect(session.hiddenMasks[1] == [true, false, false])
        let first = session.apply(Move(from: 2, to: 0))
        #expect(first && session.hiddenMasks[1] == [true, false, false])
        let second = session.apply(Move(from: 1, to: 2))
        #expect(second)
        #expect(session.hiddenMasks[1] == [false])
    }

    @Test func noSwitchesLeaveEveryLevelUnchanged() {
        for seed in UInt64(1)...10 {
            let config = GeneratorConfig(colors: 5, emptyBottles: 2, locks: 1, essence: 1, twins: 1, linkPlacement: .empty)
            var with = config
            with.switches = 0
            with.switchPlacement = .any
            #expect(Generator.candidate(config, seed: seed) == Generator.candidate(with, seed: seed))
        }
    }

    @Test(arguments: SwitchPlacement.allCases)
    func placementFollowsTheConfig(_ placement: SwitchPlacement) {
        for seed in UInt64(1)...12 {
            let config = GeneratorConfig(colors: 5, emptyBottles: 2, switches: 1, switchPlacement: placement)
            let s = Generator.candidate(config, seed: seed)
            var plain = config
            plain.switches = 0
            // Switches are drawn last: the flasks are those of the level without them.
            #expect(s.bottles == Generator.candidate(plain, seed: seed).bottles)
            guard case let .switchGate(sw, gate)? = s.links.first else { Issue.record("no switch"); continue }
            #expect(s.links.count == 1 && s.validate().isEmpty)
            switch placement {
            case .closed: #expect(!s.bottles[sw].isEmpty && !s.bottles[gate].isEmpty)
            case .empty: #expect(!s.bottles[sw].isEmpty && s.bottles[gate].isEmpty)
            case .emptySwitch: #expect(s.bottles[sw].isEmpty && !s.bottles[gate].isEmpty)
            case .any: break
            }
        }
    }

    @Test func generationIsDeterministicAndSwitchesMatter() throws {
        let config = GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, seed: 30, switches: 1,
                                     switchPlacement: .closed, requireSwitchMatter: true,
                                     switchCost: SwitchImpact.strongCost)
        let a = try Generator.generate(config, count: 2)
        let b = try Generator.generate(config, count: 2)
        #expect(a == b)
        for level in a {
            #expect(SwitchImpact.everySwitchMatters(level.state, minMoves: level.report.minMoves, cost: SwitchImpact.strongCost))
            #expect(level.state.isGateClosed(level.state.links.compactMap { if case let .switchGate(_, g) = $0 { g } else { nil } }[0]))
        }
    }

    @Test func impactWithoutASwitch() {
        let classic = state([[0, 1], [1, 0], []], capacity: 2)
        #expect(SwitchImpact.instances(in: classic).isEmpty)
        #expect(SwitchImpact.everySwitchMatters(classic, minMoves: 3))
        #expect(MechanicImpact.isTwoSided(.link(.switchGate(switch: 0, gate: 1))) == false)
    }
}

/// Dragon's Hoard (chapter 10).
@Suite struct DragonsHoardTests {
    static func pack() throws -> LevelPack { try LevelFileTests.load("chapter_10") }

    static func gates(_ s: GameState) -> [Int] {
        s.links.compactMap { if case let .switchGate(_, g) = $0 { g } else { nil } }
    }

    @Test func shape() throws {
        let pack = try Self.pack()
        #expect(pack.version == 2 && pack.chapter == 10 && pack.location == "Dragon's Hoard")
        #expect(pack.introduces == [.switches])
        #expect((28...32).contains(pack.levels.count))
        #expect(pack.levels.map(\.id) == pack.levels.indices.map { String(format: "c10_%03d", $0 + 1) })
        let allowed: Set<Mechanic> = [.switches, .sealed, .murky, .essence, .narrowNeck, .frozen, .bubbling, .twins]
        for level in pack.levels {
            let s = level.gameState
            #expect((1...2).contains(Self.gates(s).count), "\(level.id)")
            #expect(level.mechanics.last == .switches && level.mechanics.count <= 2, "\(level.id)")
            #expect(Set(level.mechanics).isSubset(of: allowed), "\(level.id)")
            #expect(s.links.allSatisfy { s.bottles[$0.endpoints.0].isPlain && s.bottles[$0.endpoints.1].isPlain }, "\(level.id)")
            // Every gate starts closed (no switch starts complete).
            #expect(Self.gates(s).allSatisfy(s.isGateClosed), "\(level.id)")
        }
        // Tutorial: tiny, one switch only, its gate shut with potion inside, every star without a
        // pure wait, no dead-end first move.
        let tutorial = try #require(pack.levels.first)
        let start = tutorial.gameState
        let minMoves = try #require(tutorial.meta?.minMoves)
        #expect(tutorial.capacity == 3 && tutorial.mechanics == [.switches] && minMoves <= 8)
        #expect(SwitchImpact.everyGateStartsClosedWithLayers(start))
        #expect(SwitchImpact.solvesWithoutWaiting(start, in: minMoves))
        #expect(MechanicImpact.everyFirstMoveSolvable(start))
        // Switches alone first; earlier mechanics only near the end.
        let firstCombo = try #require(pack.levels.firstIndex { $0.mechanics.count > 1 })
        #expect(firstCombo >= 14 && pack.levels[..<firstCombo].allSatisfy { $0.mechanics == [.switches] })
        // The curve rises from ~15, and the last five recipes are the hardest of the main path.
        let scores = pack.levels.compactMap { $0.meta?.score }
        #expect(scores.count == pack.levels.count && scores.first! < 20)
        let earlierBest = try (1...9).flatMap { try LevelFileTests.load(String(format: "chapter_%02d", $0)).levels }
            .compactMap { $0.meta?.score }.max() ?? 0
        #expect(scores.suffix(5).allSatisfy { $0 > earlierBest && $0 <= 72 })
        #expect(scores.dropLast(5).allSatisfy { $0 < scores.suffix(5).min()! })
    }

    /// Every switch matters by 2+ moves (the closed gate changes what optimal play does), and so
    /// does the other mechanic of a combined recipe (seals strong, as in chapter 2); an optimal
    /// solution opens every gate that starts with potion before it pours into or out of it.
    /// Small searches only.
    @Test func everyMechanicMatters() throws {
        var checked = 0
        for level in try Self.pack().levels {
            guard let meta = level.meta, let minMoves = meta.minMoves, (meta.statesExplored ?? 0) <= 6_000 else { continue }
            let s = level.gameState
            #expect(SwitchImpact.everySwitchMatters(s, minMoves: minMoves, cost: SwitchImpact.strongCost), "\(level.id)")
            #expect(LockImpact.everyLockMatters(s, minMoves: minMoves, cost: LockImpact.strongCost), "\(level.id)")
            #expect(MechanicImpact.everyMechanicMatters(s, minMoves: minMoves), "\(level.id)")
            let moves = try #require(Solver().solve(s).moves, "\(level.id)")
            #expect(moves.count == minMoves, "\(level.id)")
            #expect(!SwitchImpact.gateOpenings(in: s, solution: moves).isEmpty, "\(level.id)")
            checked += 1
        }
        #expect(checked >= 15)
    }
}
