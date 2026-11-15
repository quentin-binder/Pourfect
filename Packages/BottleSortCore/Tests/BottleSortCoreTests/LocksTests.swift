import Foundation
import Testing
@testable import BottleSortCore

/// Builds a bottle from tokens: Int = color, "k<n>" = key n.
private func bottle(_ tokens: [Any], capacity: Int = 4, lockedBy: KeyID? = nil) -> Bottle {
    let layers: [Layer] = tokens.map { token in
        if let n = token as? Int { return .color(ColorID(n)) }
        let s = token as! String
        return .key(KeyID(Int(s.dropFirst())!))
    }
    return Bottle(layers: layers, capacity: capacity, lockedBy: lockedBy)
}

@Suite struct KeyRuleTests {
    @Test func keyMovesAloneAndNeverFormsARun() {
        let b = bottle([0, "k1"])
        #expect(Rules.movableRunCount(b) == 1)
        #expect(Rules.movableRunCount(bottle(["k1"])) == 1)
        #expect(Rules.movableRunCount(bottle([1, 1, 1])) == 3)
        #expect(Rules.movableRunCount(bottle([])) == 0)
    }

    @Test func keyOpensMatchingLockAndIsConsumed() throws {
        let s = GameState(bottles: [bottle([0, "k1"]), bottle([1, 2, 1, 2], lockedBy: 1)])
        let next = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(next.bottles[0] == bottle([0]))
        #expect(next.bottles[1] == bottle([1, 2, 1, 2]))   // unlocked, contents unchanged
        #expect(Rules.pourAmount(from: s.bottles[0], to: s.bottles[1]) == 1)
    }

    @Test func keyOpensEmptyLockedBottle() throws {
        let s = GameState(bottles: [bottle(["k1"]), bottle([], lockedBy: 1)])
        let next = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(next == GameState(bottles: [bottle([]), bottle([])]))
    }

    @Test func keyRejectsWrongLock() {
        let s = GameState(bottles: [bottle(["k1"]), bottle([0], lockedBy: 2)])
        #expect(!s.canPour(Move(from: 0, to: 1)))
    }

    @Test func keyRejectsUnlockedBottles() {
        let s = GameState(bottles: [bottle([0, "k1"]), bottle([]), bottle([0])])
        #expect(!s.canPour(Move(from: 0, to: 1)))   // empty
        #expect(!s.canPour(Move(from: 0, to: 2)))   // has room
    }

    @Test func nothingPoursOntoAKey() {
        let s = GameState(bottles: [bottle([0, "k1"]), bottle([0]), bottle(["k2"]), bottle([], lockedBy: 1), bottle([], lockedBy: 2)])
        #expect(!s.canPour(Move(from: 1, to: 0)))   // color onto key
        #expect(!s.canPour(Move(from: 2, to: 0)))   // key onto key
        #expect(!s.canPour(Move(from: 0, to: 2)))
    }

    @Test func keyBelowTopCannotMove() {
        let s = GameState(bottles: [bottle(["k1", 0]), bottle([], lockedBy: 1), bottle([])])
        #expect(!s.canPour(Move(from: 0, to: 1)))
        // The color above it moves alone (never together with the key).
        let next = s.pouring(Move(from: 0, to: 2))
        #expect(next?.bottles[0] == bottle(["k1"]))
        #expect(next?.bottles[2] == bottle([0]))
    }

    @Test func lockedBottleCannotPourOrReceiveColors() {
        let s = GameState(bottles: [bottle([0, 1], lockedBy: 1), bottle([1]), bottle([]), bottle(["k1"])])
        #expect(!s.canPour(Move(from: 0, to: 1)))   // from locked
        #expect(!s.canPour(Move(from: 0, to: 2)))
        #expect(!s.canPour(Move(from: 1, to: 0)))   // color into locked (matching top)
        #expect(s.canPour(Move(from: 3, to: 0)))    // only its key
        #expect(Set(s.legalMoves()) == [Move(from: 1, to: 2), Move(from: 3, to: 0)])
    }

    @Test func layersBecomeReachableAfterUnlock() throws {
        let s = GameState(bottles: [bottle([0, 1], lockedBy: 1), bottle([1]), bottle(["k1"])])
        let open = try #require(s.pouring(Move(from: 2, to: 0)))
        let next = try #require(open.pouring(Move(from: 0, to: 1)))
        #expect(next.bottles[0] == bottle([0]))
        #expect(next.bottles[1] == bottle([1, 1]))
    }

    @Test func winRequiresNoKeysAndNoLocks() {
        #expect(GameState(bottles: [bottle([0, 0, 0, 0]), bottle([])]).isSolved)
        #expect(!GameState(bottles: [bottle([0, 0, 0, 0]), bottle([], lockedBy: 1)]).isSolved)
        #expect(!GameState(bottles: [bottle([0, 0, 0, 0], lockedBy: 1), bottle([])]).isSolved)
        #expect(!GameState(bottles: [bottle([0, 0, 0, 0]), bottle(["k1"])]).isSolved)
        #expect(!bottle(["k1", "k1", "k1", "k1"]).isSolved)
        #expect(!bottle([0, 0, 0, "k1"]).isSolved)
    }

    @Test func colorIDAndDescription() {
        #expect(Layer.key(1).colorID == nil)
        #expect(Layer.key(1).keyID == 1)
        #expect(Layer.color(3).keyID == nil)
        #expect(Layer.key(1).description == "k1")
        #expect(bottle([0, "k1"], lockedBy: 2).description.contains("[0,k1]"))
    }
}

@Suite struct KeyFileTests {
    @Test func layerJSON() throws {
        let layers = try JSONDecoder().decode([Layer].self, from: Data(#"[0, {"key": 1}, 3]"#.utf8))
        #expect(layers == [.color(0), .key(1), .color(3)])
        let encoded = try JSONEncoder().encode(layers)
        #expect(try JSONDecoder().decode([Layer].self, from: encoded) == layers)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Layer].self, from: Data(#"[{"lock": 1}]"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Layer].self, from: Data(#"["x"]"#.utf8)) }
    }

    @Test func levelWithKeyAndLockRoundTrips() throws {
        let json = """
        {"version": 1, "levels": [{"id": "lk", "capacity": 2, "hidden": true,
          "bottles": [{"layers": [1], "lockedBy": 1}, {"layers": [{"key": 1}, 0]}, {"layers": [0, 1]}, {"layers": []}]}]}
        """
        let pack = try LevelLoader.load(Data(json.utf8))
        let level = try #require(pack.levels.first)
        #expect(level.isHidden)
        #expect(level.gameState.bottles[0] == bottle([1], capacity: 2, lockedBy: 1))
        #expect(level.gameState.bottles[1] == bottle(["k1", 0], capacity: 2))
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#"[{"key": 1}, 0]"#))
        #expect(text.contains(#""hidden" : true"#))
        #expect(try LevelLoader.load(data) == pack)
    }

    @Test func hiddenOmittedWhenFalse() throws {
        let level = LevelDefinition(id: "a", state: state([[0, 0]], capacity: 2), hidden: false)
        #expect(level.hidden == nil)
        #expect(!level.isHidden)
        let text = String(decoding: try JSONEncoder().encode(level), as: UTF8.self)
        #expect(!text.contains("hidden"))
    }
}

@Suite struct KeyValidationTests {
    @Test func validLockLevel() {
        let s = GameState(bottles: [bottle([1], capacity: 2, lockedBy: 1), bottle(["k1", 0], capacity: 2),
                                    bottle([0, 1], capacity: 2), bottle([], capacity: 2)])
        #expect(s.validate().isEmpty)
    }

    @Test func keysDoNotCountAsColors() {
        let s = GameState(bottles: [bottle([0, 0, "k1"], capacity: 2), bottle([], capacity: 2, lockedBy: 1)])
        // Overfilled, but no color-count error for the key.
        #expect(s.validate() == [.overfilled(bottle: 0, count: 3, capacity: 2)])
    }

    @Test func duplicateKey() {
        let s = GameState(bottles: [bottle(["k1", 0]), bottle(["k1", 0]), bottle([0, 0], lockedBy: 1)])
        #expect(s.validate() == [.duplicateKey(1)])
    }

    @Test func lockWithoutKeyAndKeyWithoutLock() {
        let s = GameState(bottles: [bottle(["k1", 0, 0, 0, 0], capacity: 5), bottle([], capacity: 5, lockedBy: 2)])
        let errors = s.validate()
        #expect(errors.contains(.keyWithoutLock(1)))
        #expect(errors.contains(.lockWithoutKey(2)))
    }

    @Test func duplicateLock() {
        let s = GameState(bottles: [bottle(["k1", 0, 0, 0, 0], capacity: 4), bottle([], capacity: 4, lockedBy: 1),
                                    bottle([], capacity: 4, lockedBy: 1)])
        #expect(s.validate() == [.overfilled(bottle: 0, count: 5, capacity: 4), .duplicateLock(1)])
    }

    /// Levels the solver can't encode are rejected at load time instead of
    /// failing every hint with `.unsupportedState`.
    @Test func idsAndCapacityMustFitTheSolverEncoding() {
        let bigKey = GameState(bottles: [bottle([0, "k16"], capacity: 2), bottle([0], capacity: 2, lockedBy: 16),
                                         bottle([], capacity: 2)])
        #expect(bigKey.validate() == [.keyOutOfRange(16)])
        let negativeKey = GameState(bottles: [bottle([0, "k-1"], capacity: 2), bottle([0], capacity: 2, lockedBy: -1),
                                              bottle([], capacity: 2)])
        #expect(negativeKey.validate() == [.keyOutOfRange(-1)])
        #expect(state([Array(repeating: 0, count: 10), []], capacity: 10).validate() == [.invalidCapacity(10)])
        #expect(state([[47, 47], []], capacity: 2).validate() == [.colorOutOfRange(47)])
        // The largest encodable values are still accepted.
        let edge = GameState(bottles: [bottle([46, "k15"], capacity: 2), bottle([46], capacity: 2, lockedBy: 15)])
        #expect(edge.validate().isEmpty)
        #expect(StateKey.canEncode(edge))
    }

    @Test func keyInsideItsOwnLockIsRejected() {
        let s = GameState(bottles: [bottle([0, 0], capacity: 2), bottle(["k1"], capacity: 2, lockedBy: 1),
                                    bottle([], capacity: 2)])
        #expect(s.validate() == [.unopenableLock(1)])
        guard case .unsolvable = Solver().solve(s) else { Issue.record("expected unsolvable"); return }
    }

    @Test func lockCycleIsRejected() {
        // Key 1 is behind lock 2 and key 2 behind lock 1; key 3 sits behind that cycle too.
        let s = GameState(bottles: [bottle(["k1", 0], capacity: 2, lockedBy: 2), bottle(["k2", 0], capacity: 2, lockedBy: 1),
                                    bottle(["k3"], capacity: 2, lockedBy: 1), bottle([], capacity: 2, lockedBy: 3),
                                    bottle([], capacity: 2)])
        #expect(s.validate().contains(.unopenableLock(1)))
        #expect(s.validate().contains(.unopenableLock(2)))
        #expect(s.validate().contains(.unopenableLock(3)))
    }

    @Test func keyBehindAnOpenableLockIsAllowed() {
        // Key 2 sits in the bottle locked by 1; key 1 is free (DECISIONS #33).
        let s = GameState(bottles: [bottle(["k1", 0], capacity: 2), bottle(["k2", 0], capacity: 2, lockedBy: 1),
                                    bottle([], capacity: 2, lockedBy: 2), bottle([], capacity: 2)])
        #expect(s.validate().isEmpty)
    }

    @Test func loaderRejectsUnplayableLockLevels() {
        let selfLock = """
        {"version": 1, "levels": [{"id": "x", "capacity": 2,
          "bottles": [{"layers": [0, 0]}, {"layers": [{"key": 1}], "lockedBy": 1}, {"layers": []}]}]}
        """
        #expect(throws: LevelLoadError.invalidLevel(id: "x", errors: [.unopenableLock(1)])) {
            try LevelLoader.load(Data(selfLock.utf8))
        }
        let bigKey = """
        {"version": 1, "levels": [{"id": "y", "capacity": 2,
          "bottles": [{"layers": [0, {"key": 16}]}, {"layers": [0], "lockedBy": 16}, {"layers": []}]}]}
        """
        #expect(throws: LevelLoadError.invalidLevel(id: "y", errors: [.keyOutOfRange(16)])) {
            try LevelLoader.load(Data(bigKey.utf8))
        }
    }
}

@Suite struct KeyCanonicalKeyTests {
    @Test func keyIDsAreDistinguished() {
        let a = GameState(bottles: [bottle([0, "k1"]), bottle([], lockedBy: 1), bottle([], lockedBy: 2)])
        let b = GameState(bottles: [bottle([0, "k2"]), bottle([], lockedBy: 1), bottle([], lockedBy: 2)])
        #expect(a.canonicalKey != b.canonicalKey)
        // A key is not a color with the same number.
        let c = GameState(bottles: [bottle([0, 1]), bottle([], lockedBy: 1), bottle([], lockedBy: 2)])
        #expect(a.canonicalKey != c.canonicalKey)
        // Bottle order still doesn't matter.
        let d = GameState(bottles: [bottle([], lockedBy: 2), bottle([0, "k1"]), bottle([], lockedBy: 1)])
        #expect(a.canonicalKey == d.canonicalKey)
    }

    @Test func lockedEmptyDiffersFromUnlockedEmpty() {
        let a = GameState(bottles: [bottle(["k1"]), bottle([], lockedBy: 1)])
        let b = GameState(bottles: [bottle(["k1"]), bottle([])])
        #expect(a.canonicalKey != b.canonicalKey)
    }

    @Test func encodingLimits() {
        #expect(StateKey.canEncode(GameState(bottles: [bottle([46, "k15"], capacity: 9, lockedBy: 15)])))
        #expect(!StateKey.canEncode(GameState(bottles: [bottle([47], capacity: 9)])))
        #expect(!StateKey.canEncode(GameState(bottles: [bottle(["k16"], capacity: 9)])))
        #expect(!StateKey.canEncode(GameState(bottles: [bottle([], capacity: 9, lockedBy: 16)])))
        #expect(Solver().solve(GameState(bottles: [bottle(["k16"], capacity: 9), bottle([], capacity: 9, lockedBy: 16)]))
                == .unknown(reason: .unsupportedState))
    }
}

@Suite struct KeySolverTests {
    /// Color 1 is half-trapped in the bottle locked by key 1, and key 1 sits
    /// under a color layer. The only way to win: free the key, open the lock.
    ///
    ///     🔒1[1]  [k1,0]  [0,1]  []      (capacity 2)
    ///     1→3 (0 onto empty), 1→0 (key opens lock), 2→0 (1 onto 1), 2→3 (0 onto 0)
    static let needsKey = GameState(bottles: [bottle([1], capacity: 2, lockedBy: 1), bottle(["k1", 0], capacity: 2),
                                              bottle([0, 1], capacity: 2), bottle([], capacity: 2)])

    @Test func solvesPuzzleThatRequiresTheKey() throws {
        let start = Self.needsKey
        #expect(start.validate().isEmpty)
        let moves = try #require(Solver().solve(start).moves)
        #expect(moves.count == 4)
        #expect(referenceMinMoves(start) == 4)
        // The solution uses the key, and replays to a win.
        var s = start
        var usedKey = false
        for move in moves {
            if s.bottles[move.from].topLayer?.isKey == true { usedKey = true }
            s = try #require(s.pouring(move))
        }
        #expect(usedKey)
        #expect(s.isSolved)
    }

    @Test func withoutTheKeyPathItIsUnsolvable() {
        // Same layout, but the key doesn't fit the lock: nothing can open it.
        var wrongKey = Self.needsKey
        wrongKey.bottles[1].layers[0] = .key(2)
        #expect(referenceMinMoves(wrongKey) == nil)
        guard case .unsolvable = Solver().solve(wrongKey) else { Issue.record("expected unsolvable"); return }
        // Same layout, but the key is buried under the lock's own content: also stuck.
        let buried = GameState(bottles: [bottle(["k1", 1], capacity: 2, lockedBy: 1), bottle([0], capacity: 2),
                                         bottle([0, 1], capacity: 2), bottle([], capacity: 2)])
        #expect(referenceMinMoves(buried) == nil)
        guard case .unsolvable = Solver().solve(buried) else { Issue.record("expected unsolvable"); return }
    }

    @Test func lockedEmptyBottleIsStillAKeyTarget() throws {
        // Two empty bottles, one locked: the key must go into the locked one.
        // (Pruning rule 3 must not skip it as "not the first empty bottle".)
        let start = GameState(bottles: [bottle([], capacity: 2), bottle(["k1"], capacity: 2), bottle([], capacity: 2, lockedBy: 1)])
        let moves = try #require(Solver().solve(start).moves)
        #expect(moves == [Move(from: 1, to: 2)])
        #expect(Solver.candidateMoves(start) == [Move(from: 1, to: 2)])
    }

    /// Pruning safety with keys: solver optimum == naive reference BFS on random
    /// small lock levels from the generator, and the moves replay to a win.
    @Test(arguments: [(2, 2, 1, 1), (3, 2, 1, 1), (3, 3, 1, 1), (3, 3, 2, 1), (3, 3, 1, 2), (3, 4, 1, 1), (4, 3, 1, 2)])
    func matchesReferenceOnLockLevels(colors: Int, capacity: Int, empty: Int, locks: Int) {
        let config = GeneratorConfig(colors: colors, capacity: capacity, emptyBottles: empty, locks: locks)
        var solvedCount = 0
        for seed in UInt64(1)...25 {
            let start = Generator.candidate(config, seed: seed)
            #expect(start.validate().isEmpty, "seed \(seed)")
            let reference = referenceMinMoves(start)
            switch Solver().solve(start) {
            case .solved(let moves, _):
                solvedCount += 1
                #expect(moves.count == reference, "seed \(seed)")
                var s = start
                for move in moves {
                    guard let next = s.pouring(move) else { Issue.record("illegal move \(move), seed \(seed)"); return }
                    s = next
                }
                #expect(s.isSolved, "seed \(seed)")
            case .unsolvable:
                #expect(reference == nil, "seed \(seed)")
            case .unknown(let reason):
                Issue.record("unknown \(reason), seed \(seed)")
            }
        }
        #expect(solvedCount > 0)
    }
}

@Suite struct LockGeneratorTests {
    @Test func candidateLayout() {
        let config = GeneratorConfig(colors: 5, capacity: 4, emptyBottles: 2, locks: 1)
        for seed in UInt64(1)...30 {
            let s = Generator.candidate(config, seed: seed)
            #expect(s.validate().isEmpty)
            #expect(s.bottles.count == 5 + 1 + 2)
            let locked = s.bottles.filter { $0.lockedBy != nil }
            #expect(locked.count == 1)
            #expect(locked[0].lockedBy == 1 && locked[0].isFull)
            #expect(locked[0].layers.allSatisfy { $0.colorID != nil })
            // The key is in an unlocked bottle and never on top.
            let keyBottles = s.bottles.filter { $0.layers.contains(.key(1)) }
            #expect(keyBottles.count == 1)
            #expect(keyBottles[0].lockedBy == nil)
            #expect(keyBottles[0].topLayer?.isKey == false)
            #expect(s.bottles.filter(\.isEmpty).count == 2)
        }
    }

    @Test func twoLocks() {
        let s = Generator.candidate(GeneratorConfig(colors: 4, capacity: 3, emptyBottles: 1, locks: 2), seed: 9)
        #expect(s.validate().isEmpty)
        #expect(Set(s.bottles.compactMap(\.lockedBy)) == [1, 2])
        for bottle in s.bottles { #expect(bottle.topLayer?.isKey != true) }
    }

    @Test func classicLayoutUnchangedWithZeroLocks() {
        // locks = 0 must reproduce existing levels exactly (chapter_01 seeds).
        let a = Generator.candidate(GeneratorConfig(colors: 5), seed: 12)
        let b = Generator.candidate(GeneratorConfig(colors: 5, locks: 0), seed: 12)
        #expect(a == b)
        #expect(a.bottles.count == 7)
    }

    @Test func deterministicWithLocks() throws {
        let config = GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, locks: 1, seed: 5)
        #expect(Generator.candidate(config, seed: 3) == Generator.candidate(config, seed: 3))
        let a = try Generator.generate(config, count: 2)
        let b = try Generator.generate(config, count: 2)
        #expect(a == b)
        for level in a {
            #expect(level.state.bottles.contains { $0.lockedBy != nil })
            #expect(Solver().solve(level.state).moves?.count == level.report.minMoves)
        }
    }

    @Test func rejectsPresolvedLockedBottle() {
        let s = GameState(bottles: [bottle([1, 1], capacity: 2, lockedBy: 1), bottle([0, "k1"], capacity: 2),
                                    bottle([0], capacity: 2), bottle([], capacity: 2)])
        let config = GeneratorConfig(colors: 2, capacity: 2, emptyBottles: 1, locks: 1)
        #expect(Generator.evaluate(s, config: config, seed: 0) == nil)
    }
}
