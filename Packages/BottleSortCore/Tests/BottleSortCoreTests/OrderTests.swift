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

private func board(_ bottles: [[Int]], capacity: Int = 3, goal: Goal) -> GameState {
    GameState(bottles: bottles.map { flask($0, capacity) }, goal: goal)
}

private func order(_ bottle: Int, _ color: Int, capacity: Int = 3) -> GoalTarget {
    .order(bottle: bottle, color: ColorID(color), capacity: capacity)
}

private func pattern(_ bottle: Int, _ values: [Int]) -> GoalTarget {
    GoalTarget(bottle: bottle, layers: layers(values))
}

/// R7 customer orders and layered recipes: the win rule.
@Suite struct OrderRuleTests {
    @Test func anOrderWantsItsColorInItsFlask() {
        let goal = Goal.order([order(1, 0)])
        #expect(board([[1, 1, 1], [0, 0, 0], []], goal: goal).isSolved)
        // Sorted, but the ordered color sits in another flask.
        #expect(!board([[0, 0, 0], [1, 1, 1], []], goal: goal).isSolved)
        #expect(!board([[0, 0, 0], [], [1, 1, 1]], goal: goal).isSolved)
        // The order is met, but another flask isn't sorted.
        #expect(!board([[1, 1], [0, 0, 0], [1]], goal: goal).isSolved)
        // The same board without a goal is won either way.
        #expect(state([[0, 0, 0], [1, 1, 1], []], capacity: 3).isSolved)
    }

    @Test func aPartialOrderLeavesTheOtherFlasksStandard() {
        // Two of four colors are ordered; the others may end in any flask.
        let goal = Goal.order([order(0, 2), order(3, 1)])
        #expect(board([[2, 2, 2], [0, 0, 0], [], [1, 1, 1], [3, 3, 3]], goal: goal).isSolved)
        #expect(board([[2, 2, 2], [3, 3, 3], [0, 0, 0], [1, 1, 1], []], goal: goal).isSolved)
        #expect(!board([[2, 2, 2], [3, 3, 3], [0, 0, 0], [], [1, 1, 1]], goal: goal).isSolved)
    }

    @Test func aSealOrIceKeepsAnOrderOpen() {
        var s = board([[1, 1, 1], [0, 0, 0], []], goal: .order([order(1, 0)]))
        #expect(s.isSolved && s.isTargetMet(at: 1))
        s.bottles[1].lockedBy = 1
        #expect(!s.isSolved && !s.isTargetMet(at: 1))
        s.bottles[1].modifiers = [.frozen(layer: 2, turns: 1)]
        #expect(!s.isSolved && !s.isTargetMet(at: 1))
        s.bottles[1].modifiers = [.essence(0), .narrowNeck]
        #expect(s.isSolved && s.isTargetMet(at: 1))
    }

    @Test func aLayeredRecipeWantsTheExactPattern() {
        // Flask 2 must hold red, red, blue (bottom first); the rest of red and blue are gathered.
        let goal = Goal.pattern([pattern(2, [0, 0, 1])])
        #expect(board([[0], [1, 1], [0, 0, 1], [2, 2, 2]], goal: goal).isSolved)
        #expect(board([[1, 1], [], [0, 0, 1], [2, 2, 2], [0]], goal: goal).isSolved)
        // Upside down.
        #expect(!board([[0], [1, 1], [1, 0, 0], [2, 2, 2]], goal: goal).isSolved)
        // Remainder of blue split over two flasks.
        #expect(!board([[0], [1], [0, 0, 1], [2, 2, 2], [1]], goal: goal).isSolved)
        // A non-target flask with two colors.
        #expect(!board([[0, 1, 1], [], [0, 0, 1], [2, 2, 2]], goal: goal).isSolved)
        // A full flask of a color the recipe doesn't use may share nothing; a split one is open.
        #expect(!board([[0], [1, 1], [0, 0, 1], [2, 2], [2]], goal: goal).isSolved)
        // A remainder flask under a seal isn't done.
        var sealed = board([[0], [1, 1], [0, 0, 1], [2, 2, 2]], goal: goal)
        sealed.bottles[0].lockedBy = 3
        #expect(!sealed.isSolved)
    }

    @Test func aKeyNeverCompletesAnything() {
        let goal = Goal.pattern([pattern(0, [0, 0, 1])])
        #expect(!board([[0, 0, 1], [1, 1], [-1]], goal: goal).isSolved)
    }

    @Test func metTargetsAndRuns() {
        let goal = Goal.pattern([pattern(0, [0, 0, 1]), order(2, 2)])
        let s = board([[0, 0, 1], [1, 1], [2, 2], [0], [2]], goal: goal)
        #expect(Rules.metTargets(in: s) == [0])
        #expect(s.goalTarget(at: 0)?.isLayered == true && s.goalTarget(at: 2)?.color == 2 && s.goalTarget(at: 1) == nil)
        #expect(goal.targets[0].runs.map(\.color) == [0, 1] && goal.targets[0].runs.map(\.count) == [2, 1])
        #expect(goal.targets[1].runs.map(\.count) == [3])
    }

    @Test func turnsReportTheWinThroughTheGoal() throws {
        let s = board([[1, 1, 1], [0, 0], [0]], goal: .order([order(2, 0)]))
        let wrong = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 2, to: 1))))
        #expect(!wrong.isWon)
        let right = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 1, to: 2))))
        #expect(right.isWon)
    }

    @Test func sessionsUseTheGoal() throws {
        var session = GameSession(board([[1, 1, 1], [0, 0], [0], []], goal: .order([order(3, 1)])))
        let moves = try #require(Solver().solve(session.state).moves)
        for (i, move) in moves.enumerated() {
            #expect(!session.isSolved)
            let applied = session.apply(move)
            #expect(applied)
            if i < moves.count - 1 { #expect(!session.isSolved) }
        }
        #expect(session.isSolved && Rules.metTargets(in: session.state) == [3])
        session.undo()
        #expect(!session.isSolved && session.state.goal == .order([order(3, 1)]))
        session.restart()
        #expect(session.state == session.initialState)
    }

    @Test func mechanicsNameTheGoals() {
        let o = LevelDefinition(id: "o", state: board([[0, 0, 1], [1, 1, 0], []], goal: .order([order(2, 1)])))
        #expect(o.mechanics == [.order])
        let l = LevelDefinition(id: "l", state: board([[0, 0, 1], [1, 1, 0], [], []], goal: .pattern([pattern(2, [0, 1, 1])])))
        #expect(l.mechanics == [.layered])
        #expect(o.isCustomerOrder && l.isCustomerOrder)
        #expect(!LevelDefinition(id: "s", state: state([[0, 1], [1, 0], []], capacity: 2)).isCustomerOrder)
    }
}

/// The solver, its pruning and the reference BFS with orders.
@Suite struct OrderSolverTests {
    /// A full flask of the ordered color must still move into the ordered flask: rule 1 would
    /// skip it as a finished flask.
    @Test func aFinishedFlaskStillMovesForAnOrder() throws {
        let s = board([[0, 0, 0], [1, 2, 1], [2, 1, 2], [], []], goal: .order([order(4, 0)]))
        #expect(Solver.candidateMoves(s).contains(Move(from: 0, to: 4)))
        #expect(!Solver.candidateMoves(s).contains(Move(from: 0, to: 3)))   // a plain relocation stays pruned
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == referenceMinMoves(s))
    }

    /// Two empty flasks are alike only when neither is ordered.
    @Test func anEmptyOrderedFlaskIsATargetOfItsOwn() {
        let s = board([[0, 1, 0], [1, 0, 1], [], [], []], goal: .order([order(3, 1)]))
        let targets = Set(Solver.candidateMoves(s).filter { $0.from == 0 }.map(\.to))
        #expect(targets == [2, 3])
    }

    /// Twins with an ordered twin: pouring into either twin is no longer the same move.
    @Test func anOrderedTwinBreaksTheTwinRule() {
        let s = GameState(bottles: [flask([0, 0], 2), flask([1, 1], 2), flask([], 2), flask([], 2), flask([], 2)],
                          links: [.twins(2, 3)], goal: .order([order(3, 0, capacity: 2)]))
        let into = Set(Solver.candidateMoves(s).filter { $0.from == 0 }.map(\.to))
        #expect(into.contains(2) && into.contains(3))
    }

    static let configs: [GeneratorConfig] = [
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, orders: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, orders: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, layered: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, orders: 1, layered: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, orders: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, essence: 1, orders: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, narrowNecks: 1, funnels: 1, layered: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, frozen: 1, frozenMaxTurns: 3, orders: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, bubbling: 1, bubblingPeriod: 2, layered: 1),
        GeneratorConfig(colors: 3, capacity: 2, emptyBottles: 3, twins: 1, linkPlacement: .empty, orders: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, overflow: 1, linkPlacement: .mixed, orders: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, switches: 1, switchPlacement: .closed, orders: 1),
        GeneratorConfig(colors: 2, capacity: 3, emptyBottles: 1, cauldron: 1, recipes: 1, mixPairs: 1, scramble: 20,
                        orders: 1),
    ]

    /// Small order levels: generator candidates that validate, plus positions on from each.
    static func levels(seeds: ClosedRange<UInt64>) -> [GameState] {
        configs.flatMap { config in
            seeds.map { Generator.candidate(config, seed: $0) }.filter { $0.validate().isEmpty && $0.goal != .standard }
        }
    }

    /// Solver vs. the naive BFS (no pruning, no canonical keys) on small random order levels
    /// and positions a few moves on.
    @Test(arguments: configs.indices)
    func solverMatchesReference(_ index: Int) throws {
        var checked = 0, decided = 0
        for seed in UInt64(1)...14 {
            let s = Generator.candidate(Self.configs[index], seed: seed)
            guard s.validate().isEmpty else { continue }
            #expect(s.goal != .standard)
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
                if case .unsolvable = result { #expect(expected == nil); decided += 1 }
                if let moves = result.moves {
                    var replay = start
                    for m in moves { replay = try #require(replay.pouring(m)) }
                    #expect(replay.isSolved)
                    checked += 1
                }
            }
        }
        #expect(checked > 0 && checked + decided > 3)
    }

    /// The pruned candidate list reaches the same canonical children as every legal move (pours
    /// that only relocate an unmarked flask give the current key, which is left out).
    @Test func pruningKeepsEveryDistinctChild() {
        for var s in Self.levels(seeds: 1...5) {
            for step in 0..<8 {
                let key = s.canonicalKey
                let all = Set(s.legalMoves().compactMap { s.pouring($0)?.canonicalKey }).subtracting([key])
                let pruned = Set(Solver.candidateMoves(s).compactMap { s.pouring($0)?.canonicalKey }).subtracting([key])
                #expect(all == pruned, "\(s) missing \(all.subtracting(pruned).count) extra \(pruned.subtracting(all).count) \(s.legalMoves().filter { m in !Solver.candidateMoves(s).contains(m) })")
                for move in Solver.candidateMoves(s) { #expect(s.canPour(move)) }
                let moves = s.legalMoves()
                guard !moves.isEmpty else { break }
                s = s.pouring(moves[(step * 5 + 3) % moves.count])!
            }
        }
    }
}

/// Keys, JSON, validation and the generator with orders.
@Suite struct OrderLevelTests {
    @Test func keyIsBottleOrderIndependent() {
        var rng = SplitMix64(seed: 11)
        for var s in OrderSolverTests.levels(seeds: 1...3) {
            for step in 0..<5 {
                for _ in 0..<2 {
                    var order = Array(s.bottles.indices)
                    rng.shuffle(&order)
                    let p = s.permuted(by: order)
                    #expect(p.canonicalKey == s.canonicalKey)
                    #expect(p.isSolved == s.isSolved)
                    #expect(Set(Rules.metTargets(in: p).map { order[$0] }) == Set(Rules.metTargets(in: s)))
                }
                let moves = s.legalMoves()
                guard !moves.isEmpty else { break }
                s = s.pouring(moves[(step * 3 + 1) % moves.count])!
            }
        }
    }

    @Test func marksArePartOfTheKey() {
        // Two empty flasks: which one is ordered matters only relative to the contents.
        let base = board([[0, 1, 0], [1, 0, 1], [], []], goal: .order([order(2, 1)]))
        var other = base
        other.goal = .order([order(3, 1)])
        #expect(base.canonicalKey == other.canonicalKey)   // the two empty flasks are alike
        var filled = base
        filled.goal = .order([order(0, 1)])
        var color = base
        color.goal = .order([order(2, 0)])
        var layered = base
        layered.goal = .pattern([pattern(2, [1, 1, 0])])
        var none = base
        none.goal = .standard
        let keys = [base, filled, color, layered, none].map(\.canonicalKey)
        #expect(Set(keys).count == 5)
        // The general encoding agrees.
        #expect(StateKey.extendedCodes(base) != StateKey.extendedCodes(filled))
        // Ties between marked flasks with the same target and content.
        let tied = board([[0, 1, 0], [1, 0, 1], [], [], []], goal: .order([order(2, 0), order(3, 0)]))
        var tiedOther = tied
        tiedOther.goal = .order([order(4, 0), order(2, 0)])
        #expect(tied.canonicalKey == tiedOther.canonicalKey)
    }

    @Test func jsonRoundTrip() throws {
        let o = board([[0, 1, 0], [1, 0, 1], [], []], goal: .order([order(2, 1)]))
        let l = board([[0, 1, 0], [1, 0, 1], [], []], goal: .pattern([pattern(3, [1, 1, 0])]))
        let pack = LevelPack(name: "Orders", kind: .chapter, chapter: 2,
                             levels: [LevelDefinition(id: "o", state: o), LevelDefinition(id: "l", state: l)])
        let data = try LevelLoader.encode(pack)
        let back = try LevelLoader.load(data)
        #expect(back.version == 2 && back.levels == pack.levels)
        #expect(back.levels[0].gameState == o && back.levels[1].gameState == l)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""type" : "order""#) && text.contains(#""type" : "pattern""#))
        let json = #"""
        {"version": 2, "levels": [{"id": "o", "capacity": 2, "bottles": [{"layers": [0, 1]}, {"layers": [1, 0]}, {"layers": []}],
          "goal": {"type": "order", "targets": [{"bottle": 2, "layers": [0, 0]}]}}]}
        """#
        #expect(try LevelLoader.load(Data(json.utf8)).levels[0].gameState.goal == .order([order(2, 0, capacity: 2)]))
        let v1 = json.replacingOccurrences(of: #""version": 2"#, with: #""version": 1"#)
        #expect(throws: (any Error).self) { try LevelLoader.load(Data(v1.utf8)) }
    }

    @Test func validation() {
        let good = board([[0, 1, 0], [1, 0, 1], [], []], goal: .order([order(2, 1)]))
        #expect(good.validate().isEmpty)
        var missing = good
        missing.goal = .order([order(7, 1)])
        #expect(missing.validate() == [.invalidGoalTarget(bottle: 7)])
        var twice = good
        twice.goal = .order([order(2, 1), order(2, 0)])
        #expect(twice.validate().contains(.invalidGoalTarget(bottle: 2)))
        var short = good
        short.goal = .order([GoalTarget(bottle: 2, layers: layers([1, 1]))])
        #expect(short.validate() == [.invalidGoalLayers(bottle: 2)])
        var mixedOrder = good
        mixedOrder.goal = .order([pattern(2, [1, 1, 0])])
        #expect(mixedOrder.validate() == [.invalidGoalLayers(bottle: 2)])
        var key = good
        key.goal = .pattern([pattern(2, [1, -1, 0])])
        #expect(key.validate().contains(.invalidGoalLayers(bottle: 2)))
        var tap = good
        tap.bottles[2].modifiers = [.tap]
        #expect(tap.validate().contains(.goalOnTap(bottle: 2)))
        var shortage = good
        shortage.goal = .pattern([pattern(2, [1, 1, 1]), pattern(3, [1, 0, 0])])
        #expect(shortage.validate().contains(.goalColorShortage(color: 1, wanted: 4, available: 3)))
        // Red 2 + 1 left, blue 1 + 2 left: two remainder flasks plus the target = 3 of 3 flasks.
        let tight = board([[0, 1, 0], [1, 0, 1], []], goal: .pattern([pattern(2, [1, 0, 0])]))
        #expect(tight.validate().isEmpty)
        // A third color with whole flasks needs one more.
        let crowded = board([[0, 1, 0], [1, 0, 1], [2, 2, 2]], goal: .pattern([pattern(2, [1, 0, 0])]))
        #expect(crowded.validate() == [.goalNeedsMoreFlasks(needed: 4, available: 3)])
        var cauldron = GameState(bottles: [flask([0], 2), flask([1], 2), flask([], 2), flask([], 2, [.cauldron([Recipe(0, 1, result: 4)])])])
        cauldron.goal = .order([order(1, 4, capacity: 2)])
        #expect(cauldron.validate().isEmpty)
        cauldron.goal = .pattern([pattern(1, [4, 0])])
        #expect(cauldron.validate().contains(.layeredWithCauldron))
        var rescue = good
        rescue.goal = .rescue(withinMoves: 5)
        #expect(rescue.validate().contains(.unsupportedMechanic("rescue")))
    }

    @Test func noOrdersLeaveEveryLevelUnchanged() {
        for seed in UInt64(1)...5 {
            let plain = GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, locks: 1, essence: 1, switches: 1)
            var ordered = plain
            ordered.orders = 1
            let a = Generator.candidate(plain, seed: seed), b = Generator.candidate(ordered, seed: seed)
            #expect(a.bottles == b.bottles && a.links == b.links && a.goal == .standard && b.goal != .standard)
        }
    }

    @Test func placement() {
        for seed in UInt64(1)...20 {
            let o = Generator.candidate(GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, taps: 1, orders: 2), seed: seed)
            #expect(o.goal.targets.count == 2 && Set(o.goal.targets.compactMap(\.color)).count == 2)
            #expect(o.goal.targets.allSatisfy { !o.bottles[$0.bottle].hasTap })
            if case .order = o.goal {} else { Issue.record("expected an order") }
            let l = Generator.candidate(GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, orders: 1, layered: 1), seed: seed)
            guard case .pattern(let targets) = l.goal else { Issue.record("expected a pattern"); continue }
            #expect(targets.count == 2 && targets[0].isLayered && !targets[1].isLayered)
            #expect((2...3).contains(targets[0].runs.count) && targets[0].layers.count == 4)
            // A bottom part of the flask, topped up with its last color.
            let content = l.bottles[targets[0].bottle].layers
            let kept = targets[0].layers.count - (targets[0].runs.last!.count - 1)
            #expect(Array(content.prefix(kept)) == Array(targets[0].layers.prefix(kept)))
            #expect(l.validate().isEmpty)
        }
        // With a cauldron, the order asks for the brew.
        let config = GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, cauldron: 1, recipes: 1, orders: 1)
        for seed in UInt64(1)...5 {
            let s = Generator.candidate(config, seed: seed)
            let results = Set(s.bottles.flatMap(\.recipes).map(\.result))
            #expect(results.contains(s.goal.targets[0].color!))
        }
    }

    @Test func generationIsDeterministicAndOrdersMatter() throws {
        let config = GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, seed: 50, orders: 1,
                                     requireOrderMatter: true, orderCost: OrderImpact.strongCost)
        let a = try Generator.generate(config, count: 2)
        let b = try Generator.generate(config, count: 2)
        #expect(a == b)
        for level in a {
            let extra = try #require(OrderImpact.extraMoves(level.state, minMoves: level.report.minMoves))
            #expect(extra >= OrderImpact.strongCost)
            #expect(OrderImpact.goalMatters(level.state, minMoves: level.report.minMoves, cost: OrderImpact.strongCost))
            #expect(!OrderImpact.goalMatters(level.state, minMoves: level.report.minMoves, cost: extra + 1))
            #expect(Rules.metTargets(in: level.state).isEmpty)
        }
        let layered = try Generator.generate(GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, seed: 5, layered: 1,
                                                             requireOrderMatter: true), count: 1)[0]
        #expect(MechanicImpact.matters(.goal(layered.state.goal), in: layered.state, minMoves: layered.report.minMoves))
        #expect(MechanicImpact.removing(.goal(layered.state.goal), from: layered.state).goal == .standard)
    }
}

/// The order recipes appended to chapters 2–10 (three per chapter).
@Suite struct ShippedOrderTests {
    static let chapters = 2...10

    @Test(arguments: chapters)
    func orderRecipes(_ chapter: Int) throws {
        let pack = try LevelFileTests.loadAll(String(format: "chapter_%02d", chapter))
        let orders = pack.levels.filter(\.isCustomerOrder)
        #expect(orders.count == 3)
        // Appended: the last three recipes, after every standard one.
        #expect(pack.levels.suffix(3).map(\.id) == orders.map(\.id))
        #expect(pack.version == 2)
        for (i, level) in orders.enumerated() {
            let s = level.gameState
            #expect(s.validate().isEmpty, "\(level.id)")
            #expect(Rules.metTargets(in: s).isEmpty, "\(level.id)")
            let layered = s.goal.targets.contains(where: \.isLayered)
            if chapter < 4 { #expect(!layered, "\(level.id)") }
            if chapter >= 4 && i == 2 { #expect(layered, "\(level.id): the third order is layered") }
            guard let minMoves = level.meta?.minMoves, (level.meta?.statesExplored ?? 0) <= 60_000 else { continue }
            let moves = try #require(Solver().solve(s).moves, "\(level.id)")
            #expect(moves.count == minMoves, "\(level.id)")
            #expect(OrderImpact.goalMatters(s, minMoves: minMoves), "\(level.id)")
        }
    }

    /// Chapter 2's first order is a tiny tutorial: three colors in size-3 flasks, no seal.
    @Test func tutorialOrder() throws {
        let pack = try LevelFileTests.loadAll("chapter_02")
        let orders = pack.levels.filter { $0.isCustomerOrder }
        let first = try #require(orders.first)
        let s = first.gameState
        #expect(s.bottles[0].capacity == 3 && s.goal.targets.count == 1 && !s.goal.targets[0].isLayered)
        let sealed = s.bottles.contains { $0.isSealed }
        #expect(!sealed)
        #expect((first.meta?.minMoves ?? 99) <= 8)
    }
}

/// Order recipes are bonus recipes for the chapter gate: their stars count, the gate stays.
@Suite struct OrderGateTests {
    @Test func bonusRecipesNeverRaiseTheGate() {
        // 30 standard recipes + 3 orders: 45 stars still open the next chapter, as before.
        #expect(ChapterProgress(stars: 45, recipeCount: 33, bonusRecipeCount: 3).opensNextChapter)
        #expect(!ChapterProgress(stars: 44, recipeCount: 33, bonusRecipeCount: 3).opensNextChapter)
        #expect(ChapterProgress(stars: 40, recipeCount: 33, bonusRecipeCount: 3).starsToOpenNext == 5)
        #expect(ChapterProgress(stars: 40, recipeCount: 33, bonusRecipeCount: 3).maxStars == 99)
        // Without the bonus rule the same chapter would need 50.
        #expect(!ChapterProgress(stars: 45, recipeCount: 33).opensNextChapter)
        let standard = (1...4).map { "a\($0)" }, orders = ["o1"]
        let stars: [String: Int] = ["a1": 3, "a2": 3, "o1": 3]
        // 6 of 12 standard stars open the next chapter; the order adds stars on top.
        #expect(ChapterGate.unlockedChapters(recipeIDs: [standard + orders, ["b1"]], bonus: Set(orders)) { stars[$0] ?? 0 }
                == [true, true])
        let fewer: [String: Int] = ["a1": 3, "o1": 2]
        #expect(ChapterGate.unlockedChapters(recipeIDs: [standard + orders, ["b1"]], bonus: Set(orders)) { fewer[$0] ?? 0 }
                == [true, false])
        #expect(ChapterGate.unlockedChapters(recipeIDs: [standard + orders, ["b1"]], bonus: Set(orders)) {
            ["a1": 3, "o1": 3][$0] ?? 0 } == [true, true])
    }
}
