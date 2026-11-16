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

/// Red (0) + blue (1) → purple (4).
private let purple = Recipe(0, 1, result: 4)

private func cauldron(_ values: [Int], _ capacity: Int, _ recipes: [Recipe] = [purple]) -> Bottle {
    flask(values, capacity, [.cauldron(recipes)])
}

/// E1 mixing cauldron: the rule cases.
@Suite struct CauldronRuleTests {
    /// Source 0, cauldron 1, a spare flask 2.
    static func board(_ source: [Int], _ pot: [Int], capacity: Int = 4, recipes: [Recipe] = [purple],
                      spare: [Int] = []) -> GameState {
        GameState(bottles: [flask(source, capacity), cauldron(pot, capacity, recipes), flask(spare, capacity)])
    }

    @Test func eachPouredLayerMixesWithOneLayerBelow() throws {
        // One red onto two blues: one pair mixes, one blue stays below.
        let turn = try #require(Rules.resolve(Self.board([0], [1, 1]), afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[1].layers == layers([1, 4, 4]))
        #expect(turn.state.bottles[0].isEmpty)
        #expect(turn.events == [.mixed(bottle: 1, recipe: purple, pairs: 1)])
        #expect(turn.pour == PourEvent(move: Move(from: 0, to: 1), layer: .color(0), amount: 1))
        // Two reds onto two blues: everything mixes.
        let all = try #require(Self.board([0, 0], [1, 1]).pouring(Move(from: 0, to: 1)))
        #expect(all.bottles[1].layers == layers([4, 4, 4, 4]) && all.bottles[1].isSolved)
    }

    @Test func leftoverPouredLayersStayOnTop() throws {
        // Three reds onto one blue (over a yellow): one pair, two reds stay on top unmixed.
        let turn = try #require(Rules.resolve(Self.board([0, 0, 0], [2, 1], capacity: 5), afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[1].layers == layers([2, 4, 4, 0, 0]))
        #expect(turn.events == [.mixed(bottle: 1, recipe: purple, pairs: 1)])
        #expect(turn.pour?.amount == 3)
    }

    @Test func eitherIngredientMayBePoured() throws {
        let redOnBlue = try #require(Self.board([0], [1]).pouring(Move(from: 0, to: 1)))
        let blueOnRed = try #require(Self.board([1], [0]).pouring(Move(from: 0, to: 1)))
        #expect(redOnBlue.bottles[1].layers == layers([4, 4]) && blueOnRed.bottles[1].layers == layers([4, 4]))
    }

    @Test func freeSpaceLimitsThePour() throws {
        // Three blues with one free slot: one red goes in and mixes, two stay in the source.
        let turn = try #require(Rules.resolve(Self.board([0, 0, 0], [1, 1, 1]), afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[0].layers == layers([0, 0]))
        #expect(turn.state.bottles[1].layers == layers([1, 1, 4, 4]))
        #expect(turn.events == [.mixed(bottle: 1, recipe: purple, pairs: 1)])
        // A full cauldron takes nothing, not even its partner.
        #expect(!Self.board([0], [1, 1, 1, 1]).canPour(Move(from: 0, to: 1)))
    }

    @Test func noRecipeNoMix() throws {
        // Another color with no recipe is refused like in any flask.
        #expect(!Self.board([2], [1]).canPour(Move(from: 0, to: 1)))
        // The same color stacks; an empty cauldron fills; nothing mixes.
        let same = try #require(Rules.resolve(Self.board([1], [1]), afterAction: .pour(Move(from: 0, to: 1))))
        #expect(same.state.bottles[1].layers == layers([1, 1]) && same.events.isEmpty)
        let empty = try #require(Rules.resolve(Self.board([0, 0], []), afterAction: .pour(Move(from: 0, to: 1))))
        #expect(empty.state.bottles[1].layers == layers([0, 0]) && empty.events.isEmpty)
        // A key never mixes and never goes into an unsealed cauldron.
        #expect(!Self.board([-1], [1]).canPour(Move(from: 0, to: 1)))
        // The result color on its own ingredient doesn't mix either (only the recipe pair does).
        #expect(!Self.board([4], [1]).canPour(Move(from: 0, to: 1)))
    }

    @Test func onlyInsideTheCauldron() {
        // A plain flask never takes red on blue.
        let s = GameState(bottles: [flask([0], 4), flask([1], 4), cauldron([], 4)])
        #expect(!s.canPour(Move(from: 0, to: 1)))
        #expect(Rules.refusal(of: Move(from: 0, to: 1), in: s) == nil)
    }

    @Test func pouringOutOfACauldronIsNormal() throws {
        let s = Self.board([1], [2, 0, 0], spare: [0])
        let out = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 1, to: 2))))
        #expect(out.state.bottles[1].layers == layers([2]) && out.state.bottles[2].layers == layers([0, 0, 0]))
        #expect(out.events.isEmpty)
        // Out of a cauldron onto a plain flask with the partner on top: no mixing there.
        #expect(!Self.board([1], [0]).canPour(Move(from: 1, to: 0)))
        #expect(Rules.outlet(of: s.bottles[1])?.layers == 1..<3)
    }

    @Test func nothingChains() throws {
        // Two recipes (red + blue → purple, yellow + green → lime): the purple made on top of a
        // green stays purple, and the leftover red on it stays red.
        let lime = Recipe(2, 3, result: 9)
        let s = Self.board([0, 0], [3, 1], capacity: 5, recipes: [purple, lime])
        let after = try #require(s.pouring(Move(from: 0, to: 1)))
        #expect(after.bottles[1].layers == layers([3, 4, 4, 0]))
        #expect(!Rules.holdsUnmixedPair(after.bottles[1]))
        // The second recipe works the same way.
        let green = try #require(Self.board([2], [3, 3], recipes: [purple, lime]).pouring(Move(from: 0, to: 1)))
        #expect(green.bottles[1].layers == layers([3, 9, 9]))
    }

    @Test func otherModifiersOnTheSourceStillApply() throws {
        // A tap pours its bottom run: its red mixes with the cauldron's blue.
        let tap = GameState(bottles: [flask([0, 2], 4, [.tap]), cauldron([1, 1], 4), flask([], 4)])
        let tapped = try #require(Rules.resolve(tap, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(tapped.state.bottles[0].layers == layers([2]) && tapped.state.bottles[1].layers == layers([1, 4, 4]))
        #expect(tapped.pour?.fromBottom == true && tapped.events == [.mixed(bottle: 1, recipe: purple, pairs: 1)])
        // A narrow neck lets one layer out: one pair.
        let neck = GameState(bottles: [flask([0, 0], 4, [.narrowNeck]), cauldron([1, 1], 4)])
        #expect(try #require(neck.pouring(Move(from: 0, to: 1))).bottles[1].layers == layers([1, 4, 4]))
        // A seal on the source: nothing leaves.
        let sealed = GameState(bottles: [flask([0], 4, [.sealed(1)]), cauldron([1], 4), flask([-1], 4)])
        #expect(!sealed.canPour(Move(from: 0, to: 1)))
    }

    @Test func mixingComesBeforeEveryTimedEffect() throws {
        let s = GameState(bottles: [flask([0], 4), cauldron([1], 4), flask([2, 3], 4, [.frozen(layer: 1, turns: 1)]),
                                    flask([3, 2], 4, [.bubbling(every: 2, phase: 1)])])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.events == [.mixed(bottle: 1, recipe: purple, pairs: 1), .thawed(bottle: 2, layer: 1), .bubbled(bottle: 3)])
        #expect(turn.state.bottles[1].layers == layers([4, 4]))
    }

    @Test func aCauldronIsSolvedLikeAnyFlask() throws {
        #expect(Rules.isSolved(cauldron([4, 4], 2)) && Rules.isSolved(cauldron([], 2)) && Rules.isSolved(cauldron([1, 1], 2)))
        #expect(!Rules.isSolved(cauldron([1], 2)) && !Rules.isSolved(cauldron([1, 4], 2)))
        // Red and blue brew purple, which is poured home: the standard goal.
        let s = GameState(bottles: [flask([3, 0], 2), flask([3, 1], 2), cauldron([], 2), flask([], 2)])
        let moves = try #require(Solver().solve(s).moves)
        var current = s
        for move in moves { current = try #require(current.pouring(move)) }
        #expect(current.isSolved && current.bottles.filter { $0.layers == layers([4, 4]) }.count == 1)
    }

    @Test func legalMovesAgreeWithResolve() {
        for s in CauldronSolverTests.levels(seeds: 1...4) {
            for from in s.bottles.indices {
                for to in s.bottles.indices {
                    let move = Move(from: from, to: to)
                    #expect(s.canPour(move) == (Rules.resolve(s, afterAction: .pour(move)) != nil))
                }
            }
        }
    }

    /// Mixing conserves layers, and the pure helpers agree with the rules.
    @Test func helpersMatchTheRules() throws {
        var rng = SplitMix64(seed: 5)
        for _ in 0..<300 {
            let capacity = 3 + rng.nextInt(below: 4)
            let run = 1 + rng.nextInt(below: capacity - 1)
            let base = (0..<rng.nextInt(below: capacity - run)).map { _ in [2, 3, 5][rng.nextInt(below: 3)] }
            let partner = rng.nextInt(below: 2) == 0
            let (x, y) = partner ? (0, 1) : (1, 0)
            let pot = base + Array(repeating: y, count: run)
            let free = capacity - pot.count
            let source = Array(repeating: x, count: 1 + rng.nextInt(below: capacity))
            guard free > 0, Rules.holdsUnmixedPair(cauldron(pot, capacity)) == false else { continue }
            let s = GameState(bottles: [flask(source, capacity), cauldron(pot, capacity)])
            let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
            let amount = min(source.count, free)
            let pairs = min(amount, run)
            #expect(turn.pour?.amount == amount)
            #expect(turn.events == [.mixed(bottle: 1, recipe: purple, pairs: pairs)])
            let expected = Rules.mixed(layers(pot), pouring: ColorID(x), amount: amount, recipe: purple)
            #expect(expected.pairs == pairs && turn.state.bottles[1].layers == expected.layers)
            #expect(turn.state.bottles.reduce(0) { $0 + $1.layers.count } == source.count + pot.count)
            #expect(Rules.beforeMixing(turn.state.bottles[1].layers, poured: .color(ColorID(x)), amount: amount,
                                       recipe: purple, pairs: pairs) == layers(pot) + Array(repeating: .color(ColorID(x)), count: amount))
            #expect(Rules.pour(from: s.bottles[0], to: s.bottles[1])?.target == turn.state.bottles[1])
        }
        // No matching recipe: the layers just stack.
        #expect(Rules.mixed(layers([2]), pouring: 0, amount: 2, recipe: purple) == (layers([2, 0, 0]), 0))
        #expect(Rules.beforeMixing(layers([2, 2]), poured: .color(0), amount: 1, recipe: purple, pairs: 1) == layers([2, 2]))
        #expect(Rules.recipe(mixing: 0, into: cauldron([1], 4)) == purple)
        #expect(Rules.recipe(mixing: 1, into: cauldron([0, 2], 4)) == nil)
        #expect(Rules.recipe(mixing: 0, into: flask([1], 4)) == nil)
        #expect(cauldron([], 4).recipes == [purple] && cauldron([], 4).isCauldron && !flask([], 4).isCauldron)
    }

    @Test func unmixedPairs() {
        #expect(Rules.holdsUnmixedPair(cauldron([1, 0], 4)) && Rules.holdsUnmixedPair(cauldron([2, 0, 1, 1], 4)))
        #expect(!Rules.holdsUnmixedPair(cauldron([1, 1, 4, 0], 4)) && !Rules.holdsUnmixedPair(flask([1, 0], 4)))
    }

    @Test func finalColorCounts() {
        // Two reds and two blues in size-4 flasks: both pairs must mix.
        #expect(Rules.finalColorCounts([0: 2, 1: 2], recipes: [purple], capacity: 4) == [2])
        // Sorted ingredients: five reds, five blues, two purples: one pair.
        #expect(Rules.finalColorCounts([0: 5, 1: 5, 4: 2], recipes: [purple], capacity: 4) == [1])
        #expect(Rules.finalColorCounts([0: 3, 1: 2], recipes: [purple], capacity: 4) == nil)
        #expect(Rules.finalColorCounts([0: 4, 2: 4], recipes: [purple], capacity: 4) == [0])
    }

    @Test func validationIsStricterThanTheWin() {
        // Six reds, six blues, four purples: two pairs give 4 / 4 / 8, which the standard win
        // accepts (two full purple flasks), but validation wants every color to end with exactly
        // 0 or `capacity` layers (DECISIONS 194), so it rejects the counts.
        #expect(Rules.finalColorCounts([0: 6, 1: 6, 4: 4], recipes: [purple], capacity: 4) == nil)
        let twoPurples = GameState(bottles: [flask([0, 0, 0, 0], 4), flask([1, 1, 1, 1], 4), flask([4, 4, 4, 4], 4),
                                             cauldron([4, 4, 4, 4], 4), flask([], 4)])
        #expect(twoPurples.isSolved)
        #expect(twoPurples.validate().contains(.unbalancedColors))
    }
}

/// A recipe that needs the cauldron, and the solver on cauldron levels.
@Suite struct CauldronSolverTests {
    /// Size 3: one red and one blue (and a purple) must become three purples, next to a green.
    static let needsMixing = GameState(bottles: [flask([3, 0, 4], 3), flask([1, 3, 3], 3), flask([], 3), cauldron([], 3)])

    @Test func aRecipeThatNeedsTheCauldron() throws {
        let s = Self.needsMixing
        #expect(s.validate().isEmpty)
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == referenceMinMoves(s))
        #expect(CauldronImpact.mixedPairs(in: s, solution: moves) == 1)
        #expect(CauldronImpact.mixingRequired(s))
        var plain = s
        plain.bottles[3].modifiers = []
        #expect(Solver().solve(plain, limits: SolverLimits(maxStates: 100_000)).moves == nil)
        #expect(CauldronImpact.unwinnableByCount(plain))
        #expect(CauldronImpact.everyCauldronMatters(s, minMoves: moves.count))
        #expect(MechanicImpact.matters(.modifier(bottle: 3, .cauldron([purple])), in: s, minMoves: moves.count))
    }

    static let configs = [
        GeneratorConfig(colors: 2, capacity: 3, emptyBottles: 1, cauldron: 1, mixPairs: 1, scramble: 12),
        GeneratorConfig(colors: 2, capacity: 2, emptyBottles: 1, cauldron: 1, mixPairs: 1, scramble: 20),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, cauldron: 1, mixPairs: 1, scramble: 25),
        GeneratorConfig(colors: 3, capacity: 2, emptyBottles: 0, cauldron: 1, ingredients: .sorted, mixPairs: 1, scramble: 25),
        GeneratorConfig(colors: 2, capacity: 4, emptyBottles: 1, cauldron: 1, mixPairs: 2, scramble: 25),
        GeneratorConfig(colors: 3, capacity: 2, emptyBottles: 1, cauldron: 1, recipes: 2, mixPairs: 1, scramble: 25),
        GeneratorConfig(colors: 2, capacity: 3, emptyBottles: 1, locks: 1, cauldron: 1, mixPairs: 1, scramble: 15),
    ]

    /// Small cauldron levels: generator candidates that validate, plus a few positions on
    /// from each (random legal moves).
    static func levels(seeds: ClosedRange<UInt64>) -> [GameState] {
        var result: [GameState] = []
        for config in configs {
            for seed in seeds {
                let s = Generator.candidate(config, seed: seed)
                guard s.validate().isEmpty else { continue }
                result.append(s)
            }
        }
        return result
    }

    /// Solver vs. the naive BFS (no pruning, no canonical keys) on many small random levels.
    @Test(arguments: configs.indices)
    func solverMatchesReference(_ index: Int) throws {
        var checked = 0
        for seed in UInt64(1)...25 {
            let s = Generator.candidate(Self.configs[index], seed: seed)
            guard s.validate().isEmpty else { continue }
            #expect(s.bottles.contains { $0.isCauldron })
            var starts = [s]
            if let move = s.legalMoves().last, let next = s.pouring(move) { starts.append(next) }
            for start in starts {
                let expected = referenceMinMoves(start)
                let result = Solver().solve(start)
                #expect(result.moves?.count == expected, "\(start)")
                if case .unsolvable = result { #expect(expected == nil) }
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

    /// The backwards walk only makes real moves: every candidate that validates is solvable.
    @Test func backwardsBuiltLevelsAreSolvable() {
        var solved = 0
        for config in Self.configs where config.locks == 0 {
            for seed in UInt64(1)...10 {
                let s = Generator.candidate(config, seed: seed)
                guard s.validate().isEmpty else { continue }
                #expect(Solver().solve(s).moves != nil, "\(s)")
                solved += 1
            }
        }
        #expect(solved > 20)
    }

    /// The pruned candidate list reaches the same canonical children as every legal move,
    /// minus pours that only relocate a flask (rule 2, a canonical no-op).
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

    /// Rule 1 is off with a cauldron: a full one-color flask may hold the red the cauldron needs.
    @Test func aFullFlaskMayFeedTheCauldron() {
        let s = GameState(bottles: [flask([0, 0], 2), flask([2, 0], 2), cauldron([1], 2)])
        #expect(Solver.candidateMoves(s).contains(Move(from: 0, to: 2)))
        var plain = s
        plain.bottles[2] = flask([1], 2)
        plain.bottles[1] = flask([2, 1], 2)
        #expect(!Solver.candidateMoves(plain).contains { $0.from == 0 })
    }
}

/// StateKey, JSON, validation and sessions with cauldrons.
@Suite struct CauldronLevelTests {
    static let sample = CauldronSolverTests.needsMixing

    @Test func keyIsBottleOrderIndependent() {
        var rng = SplitMix64(seed: 4)
        for var s in CauldronSolverTests.levels(seeds: 1...5) {
            for step in 0..<6 {
                for _ in 0..<2 {
                    var order = Array(s.bottles.indices)
                    rng.shuffle(&order)
                    #expect(s.permuted(by: order).canonicalKey == s.canonicalKey)
                }
                #expect(StateKey.pairCodes(s) == StateKey.extendedCodes(s))
                let moves = s.legalMoves()
                guard !moves.isEmpty else { break }
                s = s.pouring(moves[(step * 7 + 1) % moves.count])!
            }
        }
    }

    @Test func recipesArePartOfTheKey() {
        let base = GameState(bottles: [flask([0, 1], 2), flask([1, 0], 2), flask([], 2)])
        var keys: Set<StateKey> = [base.canonicalKey]
        for recipes in [[purple], [Recipe(0, 1, result: 5)], [Recipe(0, 2, result: 4)], [purple, Recipe(2, 3, result: 9)],
                        [Recipe(2, 3, result: 9)], [purple, Recipe(2, 3, result: 9), Recipe(5, 6, result: 7)]] {
            var s = base
            s.bottles[2].modifiers = [.cauldron(recipes)]
            keys.insert(s.canonicalKey)
        }
        #expect(keys.count == 7)
        // The cauldron on another flask is another position; recipe order doesn't matter.
        var a = base, b = base, c = base
        a.bottles[2].modifiers = [.cauldron([purple, Recipe(2, 3, result: 9)])]
        b.bottles[2].modifiers = [.cauldron([Recipe(3, 2, result: 9), purple])]
        c.bottles[0].modifiers = [.cauldron([purple, Recipe(2, 3, result: 9)])]
        #expect(a.canonicalKey == b.canonicalKey && a.canonicalKey != c.canonicalKey)
        // The compact word never collides with the long form of three recipes.
        #expect(StateKey.words(for: .cauldron([purple])).count == 1)
        #expect(StateKey.words(for: .cauldron([purple, Recipe(2, 3, result: 9), Recipe(5, 6, result: 7)])).count == 4)
    }

    @Test func jsonRoundTrip() throws {
        let level = LevelDefinition(id: "c1", state: Self.sample, meta: LevelMeta(seed: 1, minMoves: 4))
        let pack = LevelPack(name: "Alchemist's Hall", kind: .chapter, chapter: 9, location: "Alchemist's Hall",
                             introduces: [.cauldron], levels: [level])
        #expect(pack.requiredVersion == 2)
        #expect(level.mechanics == [.cauldron])
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""type" : "cauldron""#) && text.contains(#""result" : 4"#))
        let loaded = try LevelLoader.load(data)
        #expect(loaded.levels == pack.levels && loaded.introduces == [.cauldron])
        #expect(loaded.levels[0].gameState == Self.sample)
        #expect(try LevelLoader.encode(loaded) == data)
    }

    @Test func handWrittenJSON() throws {
        let json = #"""
        {"version": 2, "levels": [{"id": "a", "capacity": 2, "bottles": [
          {"layers": [0, 3]}, {"layers": [1, 3]}, {"layers": []},
          {"layers": [], "modifiers": [{"type": "cauldron", "recipes": [{"a": 1, "b": 0, "result": 4}]}]}]}]}
        """#
        let s = try LevelLoader.load(Data(json.utf8)).levels[0].gameState
        #expect(s.bottles[3].recipes == [purple])
        #expect(s.validate().isEmpty)
        let v1 = json.replacingOccurrences(of: #""version": 2"#, with: #""version": 1"#)
        #expect(throws: LevelLoadError.needsVersion2(id: "a")) { try LevelLoader.load(Data(v1.utf8)) }
    }

    @Test func validation() {
        #expect(Self.sample.validate().isEmpty)
        func with(_ pot: Bottle, links: [Link] = []) -> [ValidationError] {
            var s = Self.sample
            s.bottles[3] = pot
            s.links = links
            return s.validate()
        }
        #expect(with(cauldron([], 3, [Recipe(0, 0, result: 4)])).contains(.invalidRecipe(bottle: 3, recipe: Recipe(0, 0, result: 4))))
        #expect(with(cauldron([], 3, [Recipe(0, 1, result: 1)])).contains(.invalidRecipe(bottle: 3, recipe: Recipe(0, 1, result: 1))))
        #expect(with(cauldron([], 3, [Recipe(0, 1, result: 50)])).contains(.invalidRecipe(bottle: 3, recipe: Recipe(0, 1, result: 50))))
        #expect(with(cauldron([], 3, [])) == [.invalidRecipeCount(bottle: 3, count: 0), .wrongColorCount(color: 0, count: 1, expected: 3),
                                              .wrongColorCount(color: 1, count: 1, expected: 3), .wrongColorCount(color: 4, count: 1, expected: 3)])
        let three = [purple, Recipe(5, 6, result: 7), Recipe(8, 9, result: 10)]
        #expect(with(cauldron([], 3, three)).contains(.invalidRecipeCount(bottle: 3, count: 3)))
        #expect(with(cauldron([], 3, three)).contains(.tooManyRecipes(count: 3)))
        #expect(with(cauldron([], 3, [purple, Recipe(1, 0, result: 5)])).contains(.conflictingRecipes(bottle: 3)))
        #expect(with(flask([], 3, [.cauldron([purple]), .narrowNeck])).contains(.cauldronCombined(bottle: 3)))
        #expect(with(cauldron([], 3), links: [.twins(2, 3)]) == [.linkedCauldron(bottle: 3)])
        #expect(with(cauldron([], 3, [purple, Recipe(4, 3, result: 9)])).contains(.chainedRecipes))
        #expect(with(cauldron([], 3, [purple, Recipe(6, 3, result: 9)])).contains(.unusableRecipe(bottle: 3, recipe: Recipe(6, 3, result: 9))))
        // The counts must balance after some mixing.
        var unbalanced = Self.sample
        unbalanced.bottles[0] = flask([3, 0, 0], 3)
        #expect(unbalanced.validate() == [.unbalancedColors])
        // A cauldron may not start with an unmixed pair.
        var pair = Self.sample
        pair.bottles[0] = flask([3, 4], 3)
        pair.bottles[1] = flask([3, 3], 3)
        pair.bottles[3] = cauldron([1, 0], 3)
        #expect(pair.validate() == [.unmixedPair(bottle: 3)])
        // A rune of a color that only exists once brewed is fine.
        let rune = GameState(bottles: [flask([3, 0], 2), flask([3, 1], 2), flask([], 2, [.essence(4)]), cauldron([], 2)])
        #expect(rune.validate().isEmpty)
        for e in [ValidationError.invalidRecipe(bottle: 1, recipe: purple), .invalidRecipeCount(bottle: 1, count: 0),
                  .conflictingRecipes(bottle: 1), .cauldronCombined(bottle: 1), .linkedCauldron(bottle: 1),
                  .tooManyRecipes(count: 3), .unusableRecipe(bottle: 1, recipe: purple), .chainedRecipes,
                  .unmixedPair(bottle: 1), .unbalancedColors] {
            #expect(!e.description.isEmpty)
        }
    }

    @Test func undoAndRestartRestoreEverything() throws {
        var session = GameSession(Self.sample)
        let illegal = session.play(Move(from: 0, to: 1))                // purple onto green: illegal
        #expect(illegal == nil)
        session.apply(Move(from: 0, to: 2))                              // purple aside
        session.apply(Move(from: 0, to: 3))                              // red into the cauldron
        session.apply(Move(from: 1, to: 0))                              // greens home
        let played = session.play(Move(from: 1, to: 3))                 // blue onto red: mixes
        let turn = try #require(played)
        #expect(turn.events == [.mixed(bottle: 3, recipe: purple, pairs: 1)] && session.lastEvents == turn.events)
        #expect(session.state.bottles[3].layers == layers([4, 4]) && session.state.bottles[1].isEmpty)
        session.undo()
        #expect(session.state.bottles[3].layers == layers([0]) && session.state.bottles[1].layers == layers([1]))
        #expect(session.lastEvents.isEmpty && session.lastPour == nil)
        session.apply(Move(from: 1, to: 3))
        #expect(session.state.bottles[3].layers == layers([4, 4]))
        session.restart()
        #expect(session.state == Self.sample && session.moveCount == 0 && session.lastEvents.isEmpty)
    }

    /// Murky flags: mixing only touches layers in view, and the hidden ones stay hidden.
    @Test func murkyMasksSurviveMixing() throws {
        let s = GameState(bottles: [flask([3, 0], 3), flask([3, 4, 3], 3), flask([1], 3), cauldron([], 3), flask([], 3)])
        #expect(s.validate().isEmpty)
        var session = GameSession(s, hidden: true)
        #expect(session.hiddenMasks[0] == [true, false] && session.hiddenMasks[1] == [true, true, false])
        session.apply(Move(from: 2, to: 3))
        session.apply(Move(from: 0, to: 3))
        #expect(session.state.bottles[3].layers == layers([4, 4]))
        #expect(session.hiddenMasks[3] == [false, false] && session.hiddenMasks[0] == [false] && session.hiddenMasks[2] == [])
        #expect(session.hiddenMasks[1] == [true, true, false])
        session.undo()
        #expect(session.hiddenMasks[3] == [false] && session.hiddenMasks[0] == [true, false])
    }
}

/// Generator options and the must-matter check for cauldrons.
@Suite struct CauldronGeneratorTests {
    @Test func noCauldronLeavesEveryLevelUnchanged() {
        for seed in UInt64(1)...6 {
            let config = GeneratorConfig(colors: 5, locks: 1, essence: 1)
            var other = config
            other.recipes = 2
            other.mixPairs = 3
            other.ingredients = .sorted
            #expect(Generator.candidate(config, seed: seed) == Generator.candidate(other, seed: seed))
        }
    }

    @Test(arguments: CauldronIngredients.allCases)
    func candidatesAreBuiltFromTheRecipes(_ ingredients: CauldronIngredients) {
        var valid = 0
        for seed in UInt64(1)...20 {
            let config = GeneratorConfig(colors: 6, capacity: 4, emptyBottles: 1, cauldron: 1, recipes: 2,
                                         ingredients: ingredients, mixPairs: 2, scramble: 60)
            let s = Generator.candidate(config, seed: seed)
            #expect(s.bottles.count == 8 && s.bottles.filter(\.isCauldron).count == 1)
            let recipes = s.bottles.flatMap(\.recipes)
            #expect(recipes.count == 2 && recipes.allSatisfy { Generator.naturalRecipes.contains($0) })
            #expect(Set(recipes.flatMap { [$0.a, $0.b, $0.result] }).count == 6)
            let colors = Set(s.bottles.flatMap(\.layers).compactMap(\.colorID))
            #expect(colors.allSatisfy { $0.rawValue < Generator.paletteSize })
            #expect(!s.bottles.contains(where: Rules.holdsUnmixedPair))
            if s.validate().isEmpty {
                valid += 1
                #expect(CauldronImpact.mixingRequired(s))
            }
        }
        #expect(valid > 10)
    }

    @Test func generationIsDeterministicAndMixingMatters() throws {
        let config = GeneratorConfig(colors: 3, capacity: 4, emptyBottles: 1, seed: 1, cauldron: 1, mixPairs: 2, scramble: 40,
                                     requireMixing: true)
        let a = try Generator.generate(config, count: 3)
        let b = try Generator.generate(config, count: 3)
        #expect(a == b)
        for level in a {
            #expect(level.state.validate().isEmpty)
            #expect(CauldronImpact.everyCauldronMatters(level.state, minMoves: level.report.minMoves))
            let moves = try #require(Solver().solve(level.state).moves)
            #expect(CauldronImpact.mixedPairs(in: level.state, solution: moves) >= 2)
        }
    }

    @Test func sealsAfterTheWalk() {
        var sealed = 0
        for seed in UInt64(1)...20 {
            let s = Generator.candidate(GeneratorConfig(colors: 4, emptyBottles: 1, locks: 1, cauldron: 1, mixPairs: 2,
                                                        scramble: 60), seed: seed)
            guard s.bottles.contains(where: \.isSealed) else { continue }
            sealed += 1
            #expect(s.bottles.filter { $0.layers.contains(.key(1)) }.count == 1)
            #expect(!s.bottles.contains { $0.isCauldron && ($0.isSealed || $0.layers.contains(.key(1))) })
            #expect(!s.bottles.contains { $0.topLayer?.isKey == true })
        }
        #expect(sealed > 15)
    }

    @Test func impactWithoutACauldron() {
        let classic = state([[0, 1], [1, 0], []], capacity: 2)
        #expect(CauldronImpact.instances(in: classic).isEmpty)
        #expect(CauldronImpact.everyCauldronMatters(classic, minMoves: 3))
        #expect(!CauldronImpact.mixingRequired(classic) && !CauldronImpact.unwinnableByCount(classic))
        #expect(CauldronImpact.unwinnableByCount(state([[0, 1], [0]], capacity: 2)))
    }
}

/// Alchemist's Hall (chapter 9).
@Suite struct AlchemistsHallTests {
    static func pack() throws -> LevelPack { try LevelFileTests.load("chapter_09") }

    /// Every winning end state reachable from `state`, as sorted layer counts per color.
    static func winningCounts(_ state: GameState) -> Set<[ColorID: Int]> {
        var seen: Set<StateKey> = [state.canonicalKey]
        var frontier = [state]
        var wins: Set<[ColorID: Int]> = []
        while let s = frontier.popLast() {
            if s.isSolved {
                var counts: [ColorID: Int] = [:]
                for bottle in s.bottles { for case .color(let c) in bottle.layers { counts[c, default: 0] += 1 } }
                wins.insert(counts)
                continue
            }
            for move in s.legalMoves() {
                if let next = s.pouring(move), seen.insert(next.canonicalKey).inserted { frontier.append(next) }
            }
        }
        return wins
    }

    @Test func sortedIngredientsCanAlsoBeBrewedAway() throws {
        // c9_013 (red + yellow → orange, sorted ingredients): the intended end keeps a red and a
        // yellow flask, but brewing every ingredient away into three orange flasks wins too
        // (always longer, so minMoves and stars don't change; DECISIONS 195).
        let level = try #require(try Self.pack().levels.first { $0.id == "c9_013" })
        let wins = Self.winningCounts(level.gameState)
        let red = ColorID(0), yellow = ColorID(2), orange = ColorID(5)
        #expect(wins.contains { $0[red] == 4 && $0[yellow] == 4 && $0[orange] == 4 })
        #expect(wins.contains { $0[red] == nil && $0[yellow] == nil && $0[orange] == 12 })
        // The shortest solution keeps the ingredients: it brews exactly the one pair.
        let minMoves = try #require(level.meta?.minMoves)
        let moves = try #require(Solver().solve(level.gameState).moves)
        #expect(moves.count == minMoves && CauldronImpact.mixedPairs(in: level.gameState, solution: moves) == 1)
    }

    @Test func shape() throws {
        let pack = try Self.pack()
        #expect(pack.version == 2 && pack.chapter == 9 && pack.location == "Alchemist's Hall")
        #expect(pack.introduces == [.cauldron])
        #expect((28...32).contains(pack.levels.count))
        #expect(pack.levels.map(\.id) == pack.levels.indices.map { String(format: "c9_%03d", $0 + 1) })
        for level in pack.levels {
            let s = level.gameState
            let pots = s.bottles.filter(\.isCauldron)
            #expect(pots.count == 1 && (1...2).contains(pots[0].recipes.count), "\(level.id)")
            #expect(pots.allSatisfy { $0.modifiers.count == 1 } && s.links.isEmpty, "\(level.id)")
            #expect(pots[0].recipes.allSatisfy { Generator.naturalRecipes.contains($0) }, "\(level.id)")
            #expect(level.mechanics.last == .cauldron, "\(level.id)")
            #expect(Set(level.mechanics).isSubset(of: [.cauldron, .sealed, .murky]), "\(level.id)")
            let colors = s.bottles.flatMap(\.layers).compactMap(\.colorID)
            #expect(colors.allSatisfy { $0.rawValue < Generator.paletteSize })
        }
        // Tutorial: tiny, the cauldron only and empty, every star without parking a flask, no dead-end first move.
        let tutorial = try #require(pack.levels.first)
        let start = tutorial.gameState
        #expect(tutorial.capacity == 3 && tutorial.mechanics == [.cauldron] && (tutorial.meta?.minMoves ?? 99) <= 6)
        #expect(start.bottles.allSatisfy { !$0.isCauldron || $0.isEmpty })
        #expect(FrozenImpact.solvesWithoutRelocation(start, in: tutorial.meta?.minMoves ?? 0))
        #expect(MechanicImpact.everyFirstMoveSolvable(start))
        // One recipe first, then two; earlier mechanics only in the last section.
        let firstTwo = try #require(pack.levels.firstIndex { $0.gameState.bottles.flatMap(\.recipes).count == 2 })
        #expect(firstTwo >= 12)
        #expect(pack.levels[..<firstTwo].allSatisfy { $0.mechanics == [.cauldron] })
        #expect(pack.levels.suffix(6).contains { $0.isHidden } && pack.levels.suffix(6).contains { $0.mechanics.contains(.sealed) })
        let last = try #require(pack.levels.last)
        #expect(last.gameState.bottles.flatMap(\.recipes).count == 2)
        let scores = pack.levels.compactMap { $0.meta?.score }
        #expect(scores.count == pack.levels.count)
        #expect(scores.first! < 20 && scores.max()! >= 48 && scores.max()! <= 62)
    }

    /// Every recipe needs its cauldron: the colors can't end in full flasks without mixing
    /// (so every solution mixes, `CauldronImpact.mixingRequired`), the cauldron matters, and an
    /// optimal solution, replayed, brews exactly the pairs the counts call for. Seals must be
    /// strong. Small searches only.
    @Test func everyRecipeNeedsTheCauldron() throws {
        var replayed = 0
        for level in try Self.pack().levels {
            let s = level.gameState
            let minMoves = try #require(level.meta?.minMoves)
            #expect(CauldronImpact.mixingRequired(s), "\(level.id)")
            #expect(CauldronImpact.everyCauldronMatters(s, minMoves: minMoves), "\(level.id)")
            guard (level.meta?.statesExplored ?? 0) <= 8_000 else { continue }
            let moves = try #require(Solver().solve(s).moves, "\(level.id)")
            #expect(moves.count == minMoves, "\(level.id)")
            var counts: [ColorID: Int] = [:]
            for bottle in s.bottles { for case .color(let c) in bottle.layers { counts[c, default: 0] += 1 } }
            let pairs = try #require(Rules.finalColorCounts(counts, recipes: s.bottles.flatMap(\.recipes), capacity: level.capacity))
            #expect(CauldronImpact.mixedPairs(in: s, solution: moves) == pairs.reduce(0, +), "\(level.id)")
            #expect(LockImpact.everyLockMatters(s, minMoves: minMoves, cost: LockImpact.strongCost), "\(level.id)")
            replayed += 1
        }
        #expect(replayed >= 15)
    }
}
