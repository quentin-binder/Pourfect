import Foundation
import Testing
@testable import BottleSortCore

/// The rules exactly as they were before modifiers (R2), on plain `(layers, lockedBy)`
/// bottles. Used as the reference for the `.sealed` migration.
enum LegacyRules {
    struct LBottle: Hashable {
        var layers: [Layer]
        var capacity: Int
        var lockedBy: KeyID?
        var freeSpace: Int { max(0, capacity - layers.count) }
        var topRunCount: Int {
            guard let top = layers.last else { return 0 }
            var n = 0
            for layer in layers.reversed() {
                guard layer == top else { break }
                n += 1
            }
            return n
        }
    }

    static func pour(from source: LBottle, to target: LBottle) -> (source: LBottle, target: LBottle)? {
        guard source.lockedBy == nil else { return nil }
        guard let top = source.layers.last else { return nil }
        var newSource = source
        var newTarget = target
        switch top {
        case .key(let key):
            guard target.lockedBy == key else { return nil }
            newSource.layers.removeLast()
            newTarget.lockedBy = nil
        case .color:
            guard target.lockedBy == nil else { return nil }
            guard target.freeSpace > 0 else { return nil }
            if let targetTop = target.layers.last, targetTop != top { return nil }
            let run = top.isKey ? 1 : source.topRunCount
            let amount = min(run, target.freeSpace)
            newTarget.layers.append(contentsOf: source.layers.suffix(amount))
            newSource.layers.removeLast(amount)
        }
        return (newSource, newTarget)
    }

    static func isSolved(_ b: LBottle) -> Bool {
        if b.lockedBy != nil { return false }
        guard let first = b.layers.first else { return true }
        guard b.layers.count >= b.capacity, first.colorID != nil else { return false }
        return b.layers.allSatisfy { $0 == first }
    }

    static func convert(_ state: GameState) -> [LBottle] {
        state.bottles.map { LBottle(layers: $0.layers, capacity: $0.capacity, lockedBy: $0.lockedBy) }
    }

    static func convert(_ bottles: [LBottle]) -> GameState {
        GameState(bottles: bottles.map { Bottle(layers: $0.layers, capacity: $0.capacity, lockedBy: $0.lockedBy) })
    }
}

@Suite struct ModifierPipelineTests {
    let plain = Bottle(capacity: 4)

    @Test func sealVetoesPourOutAndForeignPourIn() {
        var plan = PourPlan(layer: .color(0))
        #expect(!Rules.apply(.sealed(1), as: .source, to: &plan, source: plain, target: plain))
        #expect(!Rules.apply(.sealed(1), as: .target, to: &plan, source: plain, target: plain))
        var keyPlan = PourPlan(layer: .key(2))
        #expect(!Rules.apply(.sealed(1), as: .target, to: &keyPlan, source: plain, target: plain))
        #expect(keyPlan.opensSeal == nil)
    }

    @Test func sealAcceptsItsKeyAndMarksTheUnseal() {
        var plan = PourPlan(layer: .key(1))
        #expect(Rules.apply(.sealed(1), as: .target, to: &plan, source: plain, target: plain))
        #expect(plan.opensSeal == 1)
    }

    @Test func unimplementedModifiersDontTouchThePlan() {
        let modifiers: [BottleModifier] = [.frozen(layer: 0, turns: 1),
                                           .bubbling(every: 2, phase: 0), .cauldron([])]
        for m in modifiers {
            for side in [PourSide.source, .target] {
                var plan = PourPlan(layer: .color(3))
                #expect(Rules.apply(m, as: side, to: &plan, source: plain, target: plain), "\(m)")
                #expect(plan == PourPlan(layer: .color(3)), "\(m)")
            }
            #expect(!m.isImplemented)
        }
        let implemented: [BottleModifier] = [.sealed(0), .essence(0), .narrowNeck, .funnel, .tap]
        #expect(implemented.allSatisfy { $0.isImplemented })
    }

    @Test func keyPourOpensTheSealAsAnImmediateEffect() throws {
        var s = state([[0, 0], [1, 1], []], capacity: 2)
        s.bottles[2].layers = [.key(4)]
        s.bottles[1].lockedBy = 4
        // Step 1 alone moves the key and leaves the seal for step 2.
        let t = try #require(Rules.transfer(from: s.bottles[2], to: s.bottles[1]))
        #expect(t.target.lockedBy == 4 && t.openedSeal == 4 && t.source.isEmpty)
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 2, to: 1))))
        #expect(turn.state.bottles[1].lockedBy == nil)
        #expect(turn.state.bottles[1].modifiers.isEmpty)
        #expect(turn.isWon)
        #expect(turn.state == s.pouring(Move(from: 2, to: 1)))
    }

    @Test func resolveRejectsIllegalActions() {
        let s = state([[0, 1], [1, 0], []], capacity: 2)
        #expect(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 0))) == nil)
        #expect(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 9))) == nil)
        #expect(Rules.resolve(s, afterAction: .pour(Move(from: 2, to: 0))) == nil)
        #expect(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))) == nil)
    }

    @Test func moveCountIsStoredOnlyWhenPresent() throws {
        var s = state([[0, 1], [1, 0], []], capacity: 2)
        let plain = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 2))))
        #expect(plain.state.moveCount == nil)
        s.moveCount = 7
        s.goal = .rescue(withinMoves: 20)   // a rule that reads the counter
        let counted = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 2))))
        #expect(counted.state.moveCount == 8)
        #expect(counted.state.bottles == plain.state.bottles)
        #expect(counted.state.canonicalKey != plain.state.canonicalKey)
    }

    /// The counter stops one past the last value a rule reads, so pouring back and forth
    /// returns to an already seen state (finite state graph).
    @Test func moveCountStopsAtItsLimit() throws {
        var s = state([[0], []], capacity: 2)
        s.goal = .rescue(withinMoves: 3)
        s.moveCount = 0
        #expect(Rules.moveCountLimit(s) == 4)
        var states = [s]
        for i in 0..<10 {
            let move = i.isMultiple(of: 2) ? Move(from: 0, to: 1) : Move(from: 1, to: 0)
            states.append(try #require(states.last?.pouring(move)))
        }
        #expect(states.map { $0.moveCount ?? -1 } == [0, 1, 2, 3, 4, 4, 4, 4, 4, 4, 4])
        #expect(states[6].canonicalKey == states[8].canonicalKey)
        // No rule reads it: a stored counter never changes.
        var plain = state([[0, 1], [1, 0], []], capacity: 2)
        plain.moveCount = 5
        #expect(Rules.moveCountLimit(plain) == 0)
        #expect(plain.pouring(Move(from: 0, to: 2))?.moveCount == 5)
    }

    /// With a stored counter the solver must still prove an unsolvable level unsolvable
    /// (an unbounded counter made every depth a new state: `.unknown(stateLimit)`).
    @Test func solverProvesUnsolvableWithACounter() {
        var s = state([[0], [0, 1], []], capacity: 2)   // color 1 can never fill a flask
        s.moveCount = 0
        guard case .unsolvable = Solver().solve(s, limits: SolverLimits(maxStates: 10_000)) else {
            Issue.record("expected unsolvable")
            return
        }
    }

    /// `isLegal` (`canPour`, `legalMoves`) and `resolve` share one step-1 check, so every
    /// listed move resolves and every other move is rejected, also in lock states.
    @Test func legalityAndResolveAgree() {
        for seed in UInt64(1)...20 {
            var s = Generator.candidate(GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 1, locks: 2), seed: seed)
            for step in 0..<8 {
                for from in -1...s.bottles.count {
                    for to in -1...s.bottles.count {
                        let move = Move(from: from, to: to)
                        #expect(s.canPour(move) == (Rules.resolve(s, afterAction: .pour(move)) != nil), "\(seed) \(move)")
                    }
                }
                let moves = s.legalMoves()
                guard !moves.isEmpty, let next = s.pouring(moves[(Int(seed) + step) % moves.count]) else { break }
                s = next
            }
        }
    }

    @Test func goalDecidesTheWin() {
        var s = state([[0, 0], [1, 1], []], capacity: 2)
        #expect(s.isSolved)
        s.goal = .rescue(withinMoves: 3)
        #expect(!s.isSolved)   // R7 goals aren't implemented: never met
        #expect(!Rules.isSupported(s))
        s.goal = .standard
        #expect(s.isSolved && Rules.isSupported(s))
    }

    @Test func modifiersAreANormalizedSet() {
        var b = Bottle([0], capacity: 4)
        b.modifiers = [.tap, .sealed(2), .essence(1), .tap]
        #expect(b.modifiers == [.sealed(2), .essence(1), .tap])
        #expect(b.lockedBy == 2)
        b.lockedBy = 5
        #expect(b.modifiers == [.sealed(5), .essence(1), .tap])
        b.lockedBy = nil
        #expect(b.modifiers == [.essence(1), .tap])
        #expect(Bottle(layers: [.color(0)], capacity: 4, modifiers: [.essence(1), .tap]) == b)
        let c1 = Bottle(capacity: 4, modifiers: [.cauldron([Recipe(3, 1, result: 2), Recipe(0, 1, result: 4)])])
        let c2 = Bottle(capacity: 4, modifiers: [.cauldron([Recipe(1, 0, result: 4), Recipe(1, 3, result: 2)])])
        #expect(c1 == c2)
        #expect(Bottle([0], capacity: 4, lockedBy: 3) == Bottle(layers: [.color(0)], capacity: 4, modifiers: [.sealed(3)]))
    }

    @Test func sealedDescriptionUnchanged() {
        #expect(Bottle([1, 2], capacity: 4, lockedBy: 3).description == "🔒3[1,2]/4")
        #expect(Bottle(layers: [.color(1)], capacity: 2, modifiers: [.tap]).description == "{tap}[1]/2")
    }
}

/// The `.sealed` modifier behaves exactly like the old `lockedBy` field.
@Suite struct SealMigrationTests {
    /// Small lock levels: generator candidates plus random walks from them.
    static func lockStates() -> [GameState] {
        var result: [GameState] = []
        let configs = [GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1),
                       GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 2, locks: 2),
                       GeneratorConfig(colors: 5, capacity: 4, emptyBottles: 2, locks: 2),
                       GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 1, locks: 3)]
        for config in configs {
            for seed in UInt64(1)...15 {
                var s = Generator.candidate(config, seed: seed)
                var rng = SplitMix64(seed: seed &* 31)
                for _ in 0..<12 {
                    result.append(s)
                    let moves = s.legalMoves()
                    if moves.isEmpty { break }
                    s = s.pouring(moves[rng.nextInt(below: moves.count)])!
                }
            }
        }
        return result
    }

    @Test func legalMovesAndResultsMatchTheOldRules() {
        for s in Self.lockStates() {
            let legacy = LegacyRules.convert(s)
            for from in s.bottles.indices {
                for to in s.bottles.indices where to != from {
                    let move = Move(from: from, to: to)
                    let old = LegacyRules.pour(from: legacy[from], to: legacy[to])
                    let new = s.pouring(move)
                    #expect((old == nil) == (new == nil), "\(s) \(move)")
                    #expect(s.canPour(move) == (old != nil))
                    guard let old, let new else { continue }
                    var expected = legacy
                    expected[from] = old.source
                    expected[to] = old.target
                    #expect(LegacyRules.convert(expected) == new, "\(s) \(move)")
                    #expect(new.isSolved == expected.allSatisfy(LegacyRules.isSolved))
                    let pair = Rules.pour(from: s.bottles[from], to: s.bottles[to])
                    #expect(pair?.source == new.bottles[from] && pair?.target == new.bottles[to])
                }
            }
            #expect(s.isSolved == legacy.allSatisfy(LegacyRules.isSolved))
        }
    }

    /// The v1 key packing, as it was: one word per bottle, lock + 1 in bits 56…
    @Test func classicAndSealedKeysAreV1Words() {
        for s in Self.lockStates() {
            let words = s.bottles.map { b -> UInt64 in
                var code: UInt64 = 0
                for (i, layer) in b.layers.enumerated() { code |= StateKey.token(for: layer) << UInt64(6 * i) }
                if let lock = b.lockedBy { code |= UInt64(lock.rawValue + 1) << 56 }
                return code
            }.sorted()
            #expect(s.canonicalKey.codes == words)
        }
    }

    /// Solver vs naive BFS on small sealed levels.
    @Test func solverMatchesReferenceOnLockLevels() {
        let configs = [GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1),
                       GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, locks: 2),
                       GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 1, locks: 1)]
        for config in configs {
            for seed in UInt64(1)...8 {
                let s = Generator.candidate(config, seed: seed)
                let expected = referenceMinMoves(s)
                let result = Solver().solve(s)
                #expect(result.moves?.count == expected, "\(s)")
                if let moves = result.moves {
                    var replay = s
                    for m in moves { replay = replay.pouring(m)! }
                    #expect(replay.isSolved)
                }
            }
        }
    }

    /// A move counter takes the solver off its classic fast paths (no pruning, v2 keys);
    /// the optimum must not change.
    @Test func solverWithoutPruningAgrees() {
        let configs = [GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1),
                       GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2)]
        for config in configs {
            for seed in UInt64(1)...6 {
                let s = Generator.candidate(config, seed: seed)
                var counted = s
                counted.moveCount = 0
                #expect(Solver.candidateMoves(counted) == counted.legalMoves())
                let expected = referenceMinMoves(s)
                #expect(Solver().solve(counted).moves?.count == expected, "\(s)")
                #expect(Solver().solve(s).moves?.count == expected, "\(s)")
            }
        }
    }

    @Test func lockImpactIsTheSealCaseOfMechanicImpact() throws {
        let config = GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 2, locks: 2)
        for seed in UInt64(1)...6 {
            let s = Generator.candidate(config, seed: seed)
            guard let min = Solver().solve(s).moves?.count else { continue }
            #expect(MechanicImpact.instances(in: s) == [.seal(1), .seal(2)])
            for key in [KeyID(1), KeyID(2)] {
                #expect(LockImpact.removingLock(key, from: s) == MechanicImpact.removing(.seal(key), from: s))
                #expect(LockImpact.lockMatters(key, in: s, minMoves: min)
                        == MechanicImpact.matters(.seal(key), in: s, minMoves: min))
            }
            #expect(LockImpact.everyLockMatters(s, minMoves: min) == MechanicImpact.everyMechanicMatters(s, minMoves: min))
        }
    }
}

@Suite struct MechanicImpactTests {
    @Test func instancesAndRemoval() {
        var s = state([[0, 1], [1, 0], [], []], capacity: 2)
        s.bottles[2].layers = [.key(1)]
        s.bottles[3].lockedBy = 1
        s.bottles[3].modifiers += [.essence(0)]
        s.links = [.twins(0, 1)]
        s.goal = .rescue(withinMoves: 9)
        let all = MechanicImpact.instances(in: s)
        #expect(all == [.seal(1), .modifier(bottle: 3, .essence(0)), .link(.twins(0, 1)), .goal(.rescue(withinMoves: 9))])
        let noSeal = MechanicImpact.removing(.seal(1), from: s)
        #expect(noSeal.bottles[3].modifiers == [.essence(0)] && noSeal.bottles[2].isEmpty)
        #expect(MechanicImpact.removing(.modifier(bottle: 3, .essence(0)), from: s).bottles[3].modifiers == [.sealed(1)])
        #expect(MechanicImpact.removing(.link(.twins(0, 1)), from: s).links.isEmpty)
        #expect(MechanicImpact.removing(.goal(.rescue(withinMoves: 9)), from: s).goal == .standard)
        #expect(MechanicImpact.inherentCost(of: .seal(1)) == 1)
        #expect(MechanicImpact.inherentCost(of: .link(.twins(0, 1))) == 0)
    }

    @Test func classicLevelHasNothingToCheck() {
        let s = state([[0, 1, 0], [1, 0, 1], [], []], capacity: 3)
        #expect(MechanicImpact.instances(in: s).isEmpty)
        #expect(MechanicImpact.everyMechanicMatters(s, minMoves: 5))
    }
}

@Suite struct StateKeyV2Tests {
    /// A rich state: modifiers, ties between identical linked bottles, links, goal targets, counter.
    static func rich() -> GameState {
        var s = state([[0, 1], [1, 0], [], [], [2, 2], [0, 1]], capacity: 4)
        s.bottles[2].modifiers = [.essence(1)]
        s.bottles[3].modifiers = [.essence(1)]
        s.bottles[4].modifiers = [.frozen(layer: 0, turns: 2), .narrowNeck]
        s.bottles[1].lockedBy = 3
        s.links = [.twins(2, 0), .overflow(from: 3, to: 5), .switchGate(switch: 4, gate: 1)]
        s.goal = .order([GoalTarget(bottle: 2, layers: [.color(1)])])
        s.moveCount = 3
        return s
    }

    static func permutations(of n: Int, count: Int, seed: UInt64) -> [[Int]] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in
            var order = Array(0..<n)
            rng.shuffle(&order)
            return order
        }
    }

    @Test func permutationInvariantWithModifiersLinksAndGoal() {
        let s = Self.rich()
        let key = s.canonicalKey
        for order in Self.permutations(of: s.bottles.count, count: 200, seed: 5) {
            let p = s.permuted(by: order)
            #expect(p.canonicalKey == key, "\(order)")
        }
        var rng = SplitMix64(seed: 77)
        #expect(s.shufflingBottles(using: &rng).canonicalKey == key)
    }

    @Test func classicShuffleIsUnchanged() {
        let s = state([[0, 1], [1, 0], [], [2, 2], [3]], capacity: 2)
        var a = SplitMix64(seed: 3)
        var b = SplitMix64(seed: 3)
        #expect(s.shufflingBottles(using: &a).bottles == s.bottles.shuffled(using: &b))
    }

    @Test func everyPartOfTheStateIsInTheKey() {
        let s = Self.rich()
        let key = s.canonicalKey
        var a = s; a.moveCount = 4
        var b = s; b.bottles[4].modifiers = [.frozen(layer: 0, turns: 1), .narrowNeck]
        var c = s; c.links = [.twins(3, 0), .overflow(from: 2, to: 5), .switchGate(switch: 4, gate: 1)]
        var d = s; d.links.removeLast()
        var e = s; e.goal = .standard
        var f = s; f.goal = .order([GoalTarget(bottle: 2, layers: [.color(0)])])
        var g = s; g.bottles[1].lockedBy = 2
        var h = s; h.links = [.twins(2, 0), .overflow(from: 5, to: 3), .switchGate(switch: 4, gate: 1)]
        for (name, other) in [("moveCount", a), ("frozen", b), ("twin partner", c), ("link", d), ("goal", e),
                              ("target", f), ("seal", g), ("overflow direction", h)] {
            #expect(other.canonicalKey != key, "\(name)")
        }
        // Twins are symmetric.
        var t = s; t.links[0] = .twins(0, 2)
        #expect(t.canonicalKey == key)
    }

    /// Two pairs of twins over identical bottles: pairing {A,B},{C,D} vs {A,C},{B,D}.
    @Test func linkPairingIsDistinguishedThroughTies() {
        var s = state([[0], [0], [1], [1]], capacity: 2)
        s.links = [.twins(0, 2), .twins(1, 3)]   // each 0-bottle twinned with a 1-bottle
        var other = s
        other.links = [.twins(0, 1), .twins(2, 3)]   // 0-bottles twinned together
        #expect(s.canonicalKey != other.canonicalKey)
        var same = s
        same.links = [.twins(0, 3), .twins(1, 2)]   // isomorphic to s (swap the two 0-bottles)
        #expect(same.canonicalKey == s.canonicalKey)
        for order in Self.permutations(of: 4, count: 24, seed: 9) {
            #expect(s.permuted(by: order).canonicalKey == s.canonicalKey)
            #expect(other.permuted(by: order).canonicalKey == other.canonicalKey)
        }
    }

    @Test func modifierMovesWithItsBottle() {
        // Same multiset of layer codes, but the essence rune sits on different content.
        var a = state([[0], [1], []], capacity: 2)
        a.bottles[0].modifiers = [.essence(0)]
        var b = a
        b.bottles[0].modifiers = []
        b.bottles[1].modifiers = [.essence(0)]
        #expect(a.canonicalKey != b.canonicalKey)
        #expect(a.permuted(by: [2, 0, 1]).canonicalKey == a.canonicalKey)
    }

    @Test func canEncodeChecksTheNewFields() {
        var s = state([[0], []], capacity: 1)
        #expect(StateKey.canEncode(s))
        s.links = [.twins(0, 5)]
        #expect(!StateKey.canEncode(s))
        s.links = []
        s.bottles[1].modifiers = [.essence(99)]
        #expect(!StateKey.canEncode(s))
        s.bottles[1].modifiers = [.frozen(layer: 0, turns: 300)]
        #expect(!StateKey.canEncode(s))
    }

    /// Huge tie classes saturate the permutation count instead of trapping on overflow
    /// (21! and 4 × 20! overflow Int), and fall back to bottle order.
    @Test func largeTieClassesDontOverflow() {
        #expect(StateKey.tiePermutationCount(classSizes: [3, 2]) == 12)
        #expect(StateKey.tiePermutationCount(classSizes: [6]) == 720)
        #expect(StateKey.tiePermutationCount(classSizes: [7]) == 721)
        #expect(StateKey.tiePermutationCount(classSizes: [2, 2, 25]) == 721)
        #expect(StateKey.tiePermutationCount(classSizes: [21]) == 721)
        let s = GameState(bottles: Array(repeating: Bottle(layers: [], capacity: 4), count: 23), links: [.twins(0, 1)])
        #expect(StateKey.canEncode(s))
        // Past the cap the bottles' own order breaks the tie (no search, no crash).
        #expect(s.canonicalKey.codes.count > 23)
        var other = s
        other.links = [.overflow(from: 0, to: 1)]
        #expect(other.canonicalKey != s.canonicalKey)
    }

    /// Goal targets with nine layers (capacity 9) that differ only in the ninth layer get
    /// different keys (the layer count no longer overlaps the ninth token).
    @Test func nineLayerGoalTargetsDiffer() {
        let eight = Array(repeating: Layer.color(0), count: 8)
        var a = GameState(bottles: Array(repeating: Bottle(layers: [], capacity: 9), count: 3))
        var b = a
        a.goal = .pattern([GoalTarget(bottle: 0, layers: eight + [.color(0)])])
        b.goal = .pattern([GoalTarget(bottle: 0, layers: eight + [.color(8)])])
        #expect(StateKey.canEncode(a) && StateKey.canEncode(b))
        #expect(a.canonicalKey != b.canonicalKey)
        // Two targets, swapped contents (the reviewer's S / S' case).
        var x = GameState(bottles: [Bottle([1, 1], capacity: 9), Bottle([2, 2], capacity: 9), Bottle(capacity: 9)])
        x.goal = .pattern([GoalTarget(bottle: 0, layers: eight + [.color(0)]),
                           GoalTarget(bottle: 1, layers: eight + [.color(7)])])
        var y = x
        y.bottles.swapAt(0, 1)
        #expect(x.canonicalKey != y.canonicalKey)
    }
}
