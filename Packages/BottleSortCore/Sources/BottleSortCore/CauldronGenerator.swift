// Generator and must-matter check for mixing cauldrons (E1). The rules themselves live in
// Rules.swift (`Rules.apply` for `.cauldron`, `Rules.mixed`); this file only builds levels
// and measures them.

/// Where a recipe's ingredients come from in a generated cauldron level
/// (`GeneratorConfig.ingredients`).
public enum CauldronIngredients: String, Sendable, Hashable, CaseIterable {
    /// The ingredients are extra colors that only exist to be brewed: every layer of them must
    /// be mixed away, and the result ends as one full flask (red + blue → purple, and no red
    /// or blue flask at the end).
    case fresh
    /// The ingredients are sorted colors of their own: each ends as one full flask too, so
    /// exactly the un-mixed pairs must be brewed and any extra mix loses the recipe.
    case sorted
}

extension Generator {
    /// Recipes the generator draws from: `a + b → result` as mixing paints would, in the
    /// app's palette ids (0 red, 1 blue, 2 yellow, 3 green, 4 purple, 5 orange, 6 cyan,
    /// 7 pink, 9 lime, 10 navy, 11 grey), so the recipe card reads at a glance. Every recipe
    /// shares no color with at least one other, so two recipes can always be drawn.
    public static let naturalRecipes: [Recipe] = [
        Recipe(0, 1, result: 4),   // red + blue → purple
        Recipe(0, 2, result: 5),   // red + yellow → orange
        Recipe(1, 2, result: 3),   // blue + yellow → green
        Recipe(2, 3, result: 9),   // yellow + green → lime
        Recipe(1, 3, result: 6),   // blue + green → cyan
        Recipe(0, 11, result: 7),  // red + grey → pink
        Recipe(1, 11, result: 10), // blue + grey → navy
    ]

    /// Color ids a generated level may use (the app's palette).
    public static let paletteSize = 12

    /// A cauldron level for `seed`, built backwards from a solved board (MECHANICS.md E1;
    /// the one generator that isn't a shuffle, PLAN R5):
    ///
    /// 1. Recipes: `recipes` of `naturalRecipes` in a random order, no color shared between
    ///    two of them. Final colors: each recipe's result (with `.sorted` ingredients also both
    ///    ingredients), then random other palette colors up to `colors` (the number of full
    ///    flasks at the end).
    /// 2. The solved board: one full flask per final color, `emptyBottles` empty flasks and
    ///    one empty cauldron with the recipes.
    /// 3. A reverse walk of `scramble` steps (longer, up to 6×, until every recipe has
    ///    `mixPairs` un-mixed pairs). Each step lists every *predecessor* of the position: a
    ///    reverse pour (`k` layers of the top run of a flask `T` go back onto a flask `S`), or
    ///    an un-mix in the cauldron (`2q` result layers on top become `q` layers of one
    ///    ingredient in the cauldron and `q` of the other on a flask `S`), and keeps one only
    ///    if the forward pour `S → T` (or `S → cauldron`) from it gives exactly the current
    ///    position (`Rules.resolve`: the rules decide, so every step is a real move and the
    ///    level is solvable by construction). Positions already visited are skipped, and so
    ///    are positions whose cauldron holds a color on its recipe partner (play never makes
    ///    one, `Rules.holdsUnmixedPair`).
    ///
    ///    While pairs are missing the walk works towards the un-mixes, in this order: an
    ///    un-mix whenever one exists (the most pairs at once, preferably one that doesn't put
    ///    the ingredient on a result that still has to go back); if the cauldron's top is no
    ///    wanted result, a reverse pour that takes layers out of it (making room), with
    ///    probability 3/4; a reverse pour that leaves the longest run of a wanted result on
    ///    top of the cauldron that is two or more and at most two per missing pair (ready to
    ///    un-mix, nothing left over), with probability 7/8; one that puts a wanted result
    ///    back there at all, with probability 1/2. Meanwhile no other color goes into the
    ///    cauldron: on the way back a layer that landed on another color could never leave
    ///    it again. Otherwise (and once every pair is done) the walk takes the most scrambled
    ///    (`disorder`) of three random reverse pours. A position without an unvisited
    ///    predecessor is a dead end: the walk steps back to the position before it (the step
    ///    still counts) and goes on from there.
    /// 4. `locks` seals (A1), after the walk: random filled flasks other than the cauldron are
    ///    sealed, and each key goes into another unsealed flask with room, below at least one
    ///    layer. The solver then decides whether the level is still solvable.
    ///
    /// The solver verifies every candidate as usual (`evaluate`), so the walk only shapes
    /// the start; minimum moves and score are measured, not assumed. The bottles come out in
    /// a fixed order (final colors, empties, cauldron); the app shuffles them anyway.
    public static func cauldronCandidate(_ config: GeneratorConfig, seed: UInt64) -> GameState {
        var rng = SplitMix64(seed: seed)
        let capacity = config.capacity
        // 1. Recipes and colors.
        var table = naturalRecipes
        rng.shuffle(&table)
        var recipes: [Recipe] = []
        for recipe in table where recipes.count < max(1, config.recipes) {
            let used = Set(recipes.flatMap { [$0.a, $0.b, $0.result] })
            if [recipe.a, recipe.b, recipe.result].allSatisfy({ !used.contains($0) }) { recipes.append(recipe) }
        }
        var finals: [ColorID] = recipes.map(\.result)
        if config.ingredients == .sorted { finals += recipes.flatMap { [$0.a, $0.b] } }
        let reserved = Set(recipes.flatMap { [$0.a, $0.b, $0.result] })
        var others = (0..<paletteSize).map { ColorID($0) }.filter { !reserved.contains($0) }
        rng.shuffle(&others)
        finals += others.prefix(max(0, config.colors - finals.count))
        // 2. The solved board.
        var bottles = finals.map { Bottle(layers: Array(repeating: .color($0), count: capacity), capacity: capacity) }
        bottles += Array(repeating: Bottle(capacity: capacity), count: config.emptyBottles)
        let cauldron = bottles.count
        bottles.append(Bottle(capacity: capacity, modifiers: [.cauldron(recipes)]))
        var state = GameState(bottles: bottles)
        // 3. The reverse walk.
        var missing = recipes.map { _ in max(0, config.mixPairs) }
        var seen: Set<StateKey> = [state.canonicalKey]
        var trail: [(state: GameState, missing: [Int])] = []   // for backtracking out of dead ends
        var steps = 0
        while steps < 6 * max(1, config.scramble) {
            if steps >= config.scramble && missing.allSatisfy({ $0 == 0 }) { break }
            steps += 1
            let unmixes = unmixPredecessors(of: state, cauldron: cauldron, recipes: recipes, missing: missing)
                .filter { !seen.contains($0.state.canonicalKey) && !Rules.holdsUnmixedPair($0.state.bottles[cauldron]) }
            let wanting = missing.contains { $0 > 0 }
            // Results of recipes that still miss pairs.
            let results = Set(recipes.indices.filter { missing[$0] > 0 }.map { Layer.color(recipes[$0].result) })
            // While pairs are missing, nothing but a wanted result goes back into the cauldron: a
            // layer that lands there on another color can never leave it again on the way back
            // (only a pour onto its own color can be undone), and would shut the cauldron for
            // the un-mixes still to come.
            let pours = pourPredecessors(of: state).filter { p in
                let pot = p.bottles[cauldron]
                return !seen.contains(p.canonicalKey) && !Rules.holdsUnmixedPair(pot)
                    && (!wanting || pot.layers.count <= state.bottles[cauldron].layers.count
                        || pot.topLayer.map(results.contains) == true)
            }
            var next: GameState?
            var nextMissing = missing
            if wanting, !unmixes.isEmpty {
                // As many pairs as possible at once, preferably without burying a result that
                // still has to go back into the cauldron.
                let most = unmixes.map(\.pairs).max() ?? 1
                let biggest = unmixes.filter { $0.pairs == most }
                let clean = biggest.filter { u in
                    !u.state.bottles.indices.contains { i in
                        i != cauldron && u.state.bottles[i].layers.count > state.bottles[i].layers.count
                            && state.bottles[i].topLayer.map(results.contains) == true
                    }
                }
                let options = clean.isEmpty ? biggest : clean
                let pick = options[rng.nextInt(below: options.count)]
                nextMissing[pick.recipe] -= pick.pairs
                next = pick.state
            } else if !pours.isEmpty {
                // Refills: reverse pours that put a recipe's result back on top of the cauldron;
                // strong ones leave a run of two or more there, ready to un-mix (the longest run
                // is taken).
                let refills = pours.filter { p in
                    p.bottles[cauldron].layers.count > state.bottles[cauldron].layers.count
                        && p.bottles[cauldron].topLayer.map(results.contains) == true
                }
                // A strong refill brings at most the result layers still to un-mix (two per missing
                // pair): any more would stay behind under the ingredient and shut the cauldron.
                func fits(_ p: GameState) -> Bool {
                    let pot = p.bottles[cauldron]
                    guard let top = pot.topLayer?.colorID, let r = recipes.firstIndex(where: { $0.result == top }) else { return false }
                    return (2...max(2, 2 * missing[r])).contains(pot.topRunCount)
                }
                let fitting = refills.filter(fits)
                let longest = fitting.map { $0.bottles[cauldron].topRunCount }.max() ?? 0
                let strong = fitting.filter { $0.bottles[cauldron].topRunCount == longest }
                // Drains: reverse pours that take layers out of the cauldron, making room for the
                // next refill.
                let drains = pours.filter { $0.bottles[cauldron].layers.count < state.bottles[cauldron].layers.count }
                let topWanted = state.bottles[cauldron].topLayer.map(results.contains) == true
                if wanting, !topWanted, !drains.isEmpty, rng.nextInt(below: 4) != 0 {
                    next = drains[rng.nextInt(below: drains.count)]
                } else if wanting, !strong.isEmpty, rng.nextInt(below: 8) != 0 {
                    next = strong[rng.nextInt(below: strong.count)]
                } else if wanting, !refills.isEmpty, rng.nextInt(below: 2) == 0 {
                    next = refills[rng.nextInt(below: refills.count)]
                } else {
                    // Tournament of three: the most scrambled of three random predecessors, so
                    // the walk breaks runs up instead of wandering among sorted positions.
                    var best = pours[rng.nextInt(below: pours.count)]
                    for _ in 0..<2 {
                        let other = pours[rng.nextInt(below: pours.count)]
                        if disorder(other) > disorder(best) { best = other }
                    }
                    next = best
                }
            } else if !unmixes.isEmpty {
                let pick = unmixes[rng.nextInt(below: unmixes.count)]
                nextMissing[pick.recipe] -= pick.pairs
                next = pick.state
            }
            guard let next else {
                // A dead end (every predecessor visited or excluded): step back and try another way.
                guard let previous = trail.popLast() else { break }
                (state, missing) = previous
                continue
            }
            trail.append((state, missing))
            (state, missing) = (next, nextMissing)
            seen.insert(state.canonicalKey)
        }
        // 4. Seals.
        if config.locks > 0 { addSeals(&state, count: config.locks, cauldron: cauldron, rng: &rng) }
        return state
    }

    /// How scrambled a position is: the number of neighbouring layers of different colors,
    /// over all flasks.
    static func disorder(_ state: GameState) -> Int {
        state.bottles.reduce(0) { total, bottle in
            total + zip(bottle.layers, bottle.layers.dropFirst()).filter { $0 != $1 }.count
        }
    }

    /// Whether a cauldron candidate balances with exactly `mixPairs` pairs per recipe
    /// (`Rules.finalColorCounts`): the backwards walk un-mixed all of them.
    static func hasItsMixPairs(_ state: GameState, config: GeneratorConfig) -> Bool {
        guard let capacity = state.bottles.first?.capacity else { return false }
        let recipes = state.bottles.flatMap(\.recipes)
        var counts: [ColorID: Int] = [:]
        for bottle in state.bottles {
            for case .color(let c) in bottle.layers { counts[c, default: 0] += 1 }
        }
        return Rules.finalColorCounts(counts, recipes: recipes, capacity: capacity)
            == Array(repeating: max(0, config.mixPairs), count: recipes.count)
    }

    /// Step 3 of `cauldronCandidate`: every position from which one ordinary pour (no mixing)
    /// leads to `state`.
    static func pourPredecessors(of state: GameState) -> [GameState] {
        var result: [GameState] = []
        let bottles = state.bottles
        for t in bottles.indices {
            guard let top = bottles[t].topLayer, top.colorID != nil else { continue }
            for k in 1...bottles[t].topRunCount {
                for s in bottles.indices where s != t && bottles[s].freeSpace >= k {
                    var before = state
                    before.bottles[t].layers.removeLast(k)
                    before.bottles[s].layers.append(contentsOf: repeatElement(top, count: k))
                    guard let turn = Rules.resolve(before, afterAction: .pour(Move(from: s, to: t))),
                          turn.events.isEmpty, turn.state.bottles == bottles else { continue }
                    result.append(before)
                }
            }
        }
        return result
    }

    /// Step 3 of `cauldronCandidate`: every position from which one mixing pour into the
    /// cauldron leads to `state`, for recipes that still miss pairs (`missing`), with the
    /// recipe's index and the pairs it un-mixes.
    static func unmixPredecessors(of state: GameState, cauldron: Int, recipes: [Recipe],
                                  missing: [Int]) -> [(state: GameState, recipe: Int, pairs: Int)] {
        var result: [(GameState, Int, Int)] = []
        let pot = state.bottles[cauldron]
        guard let top = pot.topLayer?.colorID else { return [] }
        for (r, recipe) in recipes.enumerated() where recipe.result == top && missing[r] > 0 {
            for q in stride(from: 1, through: min(pot.topRunCount / 2, missing[r]), by: 1) {
                for (poured, below) in [(recipe.a, recipe.b), (recipe.b, recipe.a)] {
                    for s in state.bottles.indices where s != cauldron && state.bottles[s].freeSpace >= q {
                        var before = state
                        before.bottles[cauldron].layers.removeLast(2 * q)
                        before.bottles[cauldron].layers.append(contentsOf: repeatElement(.color(below), count: q))
                        before.bottles[s].layers.append(contentsOf: repeatElement(.color(poured), count: q))
                        guard let turn = Rules.resolve(before, afterAction: .pour(Move(from: s, to: cauldron))),
                              turn.events == [.mixed(bottle: cauldron, recipe: recipe, pairs: q)],
                              turn.state.bottles == state.bottles else { continue }
                        result.append((before, r, q))
                    }
                }
            }
        }
        return result
    }

    /// Step 4 of `cauldronCandidate`.
    static func addSeals(_ state: inout GameState, count: Int, cauldron: Int, rng: inout SplitMix64) {
        var order = Array(state.bottles.indices)
        rng.shuffle(&order)
        var key = 1
        for i in order where key <= count {
            guard i != cauldron, !state.bottles[i].isEmpty, !state.bottles[i].isSealed else { continue }
            let homes = state.bottles.indices.filter { j in
                j != i && j != cauldron && !state.bottles[j].isSealed && state.bottles[j].freeSpace > 0
                    && !state.bottles[j].isEmpty
            }
            guard !homes.isEmpty else { break }
            let home = homes[rng.nextInt(below: homes.count)]
            let slot = rng.nextInt(below: state.bottles[home].layers.count)   // below at least one layer
            state.bottles[home].layers.insert(.key(KeyID(key)), at: slot)
            state.bottles[i].lockedBy = KeyID(key)
            key += 1
        }
    }
}

/// Whether a mixing cauldron changes a level (the "must matter" check for E1): the
/// `.modifier(_, .cauldron)` case of `MechanicImpact`. Removing the instance means a plain
/// flask with the same layers.
///
/// Mixing is the only rule that changes color counts. A cauldron level whose colors can't
/// all end with a multiple of `capacity` layers without mixing (`mixingRequired`) is
/// unsolvable without its cauldron, and *every* solution, optimal or not, has to mix: this is
/// checked by counting, without a search (`MechanicImpact.matters` uses it as a shortcut,
/// because proving such a level unsolvable by search means exploring all of it).
/// `mixedPairs(in:solution:)` replays a solution and counts what it brewed, so the
/// generator can also confirm that optimal play mixes (DECISIONS 195).
public enum CauldronImpact {
    /// The cauldron instances of `state` (one per cauldron).
    public static func instances(in state: GameState) -> [MechanicInstance] {
        MechanicImpact.instances(in: state).filter {
            if case .modifier(_, .cauldron) = $0 { return true }
            return false
        }
    }

    /// Whether no flask of `state` mixes (no cauldron) and some color can't end in full
    /// flasks (its count isn't a multiple of the capacity): then no sequence of pours wins.
    public static func unwinnableByCount(_ state: GameState) -> Bool {
        guard let capacity = state.bottles.first?.capacity, capacity > 0,
              !state.bottles.contains(where: \.isCauldron) else { return false }
        var counts: [ColorID: Int] = [:]
        for bottle in state.bottles {
            for case .color(let c) in bottle.layers { counts[c, default: 0] += 1 }
        }
        return counts.values.contains { $0 % capacity != 0 }
    }

    /// Whether every way to win `state` has to mix: without its cauldrons the color counts
    /// can't all end in full flasks.
    public static func mixingRequired(_ state: GameState) -> Bool {
        var plain = state
        for i in plain.bottles.indices where plain.bottles[i].isCauldron {
            plain.bottles[i].modifiers.removeAll { if case .cauldron = $0 { return true } else { return false } }
        }
        return unwinnableByCount(plain)
    }

    /// Whether every cauldron matters (true for a level without one): removing it makes the
    /// level unsolvable or costs at least one move (`MechanicImpact.matters`), and some
    /// solution has to mix (`mixingRequired`).
    public static func everyCauldronMatters(_ state: GameState, minMoves: Int, limits: SolverLimits = .default) -> Bool {
        let all = instances(in: state)
        return all.isEmpty || (mixingRequired(state)
            && all.allSatisfy { MechanicImpact.matters($0, in: state, minMoves: minMoves, limits: limits) })
    }

    /// How many pairs `solution` mixes when played from `state` (its `TurnEvent.mixed`
    /// events), or 0 if a move is illegal.
    public static func mixedPairs(in state: GameState, solution: [Move]) -> Int {
        var current = state
        var pairs = 0
        for move in solution {
            guard let turn = Rules.resolve(current, afterAction: .pour(move)) else { return 0 }
            for case let .mixed(_, _, n) in turn.events { pairs += n }
            current = turn.state
        }
        return pairs
    }
}
