public enum ValidationError: Error, Hashable, Sendable, CustomStringConvertible {
    case noBottles
    case inconsistentCapacity(bottle: Int, capacity: Int, expected: Int)
    case invalidCapacity(Int)
    case overfilled(bottle: Int, count: Int, capacity: Int)
    case wrongColorCount(color: ColorID, count: Int, expected: Int)
    case negativeColor(ColorID)
    /// A color id above `StateKey.maxColorID` (the solver can't encode it).
    case colorOutOfRange(ColorID)
    /// A key or lock id outside `0...StateKey.maxKeyID` (the solver can't encode it).
    case keyOutOfRange(KeyID)
    /// The key for this lock can never be reached: it sits inside the bottle it opens,
    /// or inside another bottle whose lock can't be opened (e.g. key A behind lock B,
    /// key B behind lock A).
    case unopenableLock(KeyID)
    /// The same key id appears as a key layer more than once.
    case duplicateKey(KeyID)
    /// More than one bottle is locked by the same key id.
    case duplicateLock(KeyID)
    /// A bottle is locked but no key layer opens it.
    case lockWithoutKey(KeyID)
    /// A key layer has no bottle locked by it.
    case keyWithoutLock(KeyID)
    /// A flask modifier, link or goal these rules don't implement yet (named by its JSON type).
    case unsupportedMechanic(String)
    /// A flask carries more than one seal (multi-rune seals aren't a rule yet).
    case multipleSeals(bottle: Int)
    /// A link points at a missing bottle, or both ends are the same bottle.
    case invalidLink(Link)
    /// A flask carries more than one essence rune (it could never receive anything).
    case multipleEssences(bottle: Int)
    /// An essence rune names a color the level doesn't contain, so the flask could
    /// never receive anything (also catches out-of-range color ids).
    case essenceColorAbsent(bottle: Int, color: ColorID)
    /// An essence flask starts full of one other color: it would count as sorted while
    /// holding a color it can never receive (the standard goal only asks "full, one color").
    case essenceFullOfOtherColor(bottle: Int, color: ColorID)
    /// A tap flask carries a seal: a tap never receives, so its key could never open it.
    case sealedTap(bottle: Int)
    /// A flask carries both a funnel and a tap: it could neither pour nor receive.
    case funnelWithTap(bottle: Int)
    /// A funnel flask starts with layers it could never be sorted with: nothing ever leaves
    /// a funnel, so it must start empty or with one color only (its rune's, if it has one),
    /// and never with a key.
    case unsortableFunnel(bottle: Int)
    /// A frozen layer (D1) names a layer index the flask doesn't have.
    case frozenLayerOutOfRange(bottle: Int, layer: Int)
    /// A thaw counter outside `1...Rules.maxThawTurns`.
    case invalidThawTurns(bottle: Int, turns: Int)
    /// More than one frozen modifier on the same layer of a flask.
    case duplicateFrozenLayer(bottle: Int, layer: Int)
    /// More than `Rules.maxFrozenLayers` frozen layers in the level.
    case tooManyFrozenLayers(count: Int)
    /// A bubbling period (D2) outside `Rules.bubblingPeriods`.
    case invalidBubblingPeriod(bottle: Int, every: Int)
    /// A bubbling phase outside `0..<every`.
    case invalidBubblingPhase(bottle: Int, phase: Int)
    /// A flask carries more than one bubbling modifier.
    case multipleBubbling(bottle: Int)
    /// A bubbling flask carries a tap (the two would fight over the bottom layer).
    case bubblingWithTap(bottle: Int)
    /// A bubbling flask holds a frozen layer (a rise would move it: frozen indices must
    /// stay valid).
    case bubblingWithIce(bottle: Int)
    /// More than `Rules.maxBubblingFlasks` bubbling flasks in the level.
    case tooManyBubblingFlasks(count: Int)
    /// A flask is an end of more than one link (twins, pressure pipes): each flask has at
    /// most one, so a pour never follows a chain of links.
    case flaskInSeveralLinks(bottle: Int)
    /// A twin flask (F1) is sealed: a key never splits, so the seal could never open.
    case sealedTwin(bottle: Int)
    /// A cauldron (E1) recipe mixes a color with itself, makes one of its own ingredients,
    /// or names a color id outside `0...StateKey.maxColorID`.
    case invalidRecipe(bottle: Int, recipe: Recipe)
    /// A cauldron carries no recipe, or more than `Rules.maxRecipes`.
    case invalidRecipeCount(bottle: Int, count: Int)
    /// Two recipes of a cauldron mix the same pair of colors.
    case conflictingRecipes(bottle: Int)
    /// A cauldron carries another modifier (a seal, a rune, a second cauldron, …): not a
    /// rule yet.
    case cauldronCombined(bottle: Int)
    /// A cauldron is an end of a link: not a rule yet (a linked pour never mixes).
    case linkedCauldron(bottle: Int)
    /// More than `Rules.maxRecipes` different recipes in the level.
    case tooManyRecipes(count: Int)
    /// A recipe can never mix: one of its ingredients is neither in the level nor made by
    /// another recipe.
    case unusableRecipe(bottle: Int, recipe: Recipe)
    /// A recipe's result is an ingredient of another recipe in the level: mixing never
    /// chains (a fresh result would sit unmixed on its partner), so chained recipes aren't a
    /// rule yet.
    case chainedRecipes
    /// A cauldron starts with a color directly on its recipe partner: play never leaves such
    /// an unmixed pair (`Rules.holdsUnmixedPair`), and it would read as a broken rule.
    case unmixedPair(bottle: Int)
    /// With cauldrons: no amount of mixing lets every color end with exactly 0 or
    /// `capacity` layers (replaces `wrongColorCount`, since mixing changes color counts).
    case unbalancedColors
    /// A switch flask (A3) has a tap: a tap never receives, so the switch could never fill up
    /// and its gate could only ever close.
    case tapSwitch(bottle: Int)
    /// R7: a goal target names a missing flask, or a flask that already has a target.
    case invalidGoalTarget(bottle: Int)
    /// R7: a goal target doesn't ask for exactly `capacity` color layers, or an order
    /// (`Goal.order`) asks for more than one color (a pattern of several colors is a layered
    /// recipe, `Goal.pattern`).
    case invalidGoalLayers(bottle: Int)
    /// R7: a goal target sits on a tap flask, which never receives anything.
    case goalOnTap(bottle: Int)
    /// R7: the targets ask for more layers of a color than the level holds.
    case goalColorShortage(color: ColorID, wanted: Int, available: Int)
    /// R7: the targets plus one flask per remaining color (each partly used color's remainder
    /// gathered in one flask) need more flasks than the level has.
    case goalNeedsMoreFlasks(needed: Int, available: Int)
    /// R7: a layered recipe (`Goal.pattern`) in a level with a cauldron: mixing changes color
    /// counts, so the remainder rule isn't defined yet.
    case layeredWithCauldron

    public var description: String {
        switch self {
        case .noBottles: return "level has no bottles"
        case let .inconsistentCapacity(b, c, e): return "bottle \(b) has capacity \(c), expected \(e)"
        case let .invalidCapacity(c): return "invalid capacity \(c)"
        case let .overfilled(b, n, c): return "bottle \(b) holds \(n) layers but capacity is \(c)"
        case let .wrongColorCount(color, n, e): return "color \(color.rawValue) has \(n) layers, expected \(e)"
        case let .negativeColor(c): return "negative color id \(c.rawValue)"
        case let .colorOutOfRange(c): return "color id \(c.rawValue) is above \(StateKey.maxColorID)"
        case let .keyOutOfRange(k): return "key/lock id \(k.rawValue) is outside 0...\(StateKey.maxKeyID)"
        case let .unopenableLock(k): return "lock \(k.rawValue) can never be opened (its key is locked away behind it)"
        case let .duplicateKey(k): return "key \(k.rawValue) appears more than once"
        case let .duplicateLock(k): return "more than one bottle is locked by key \(k.rawValue)"
        case let .lockWithoutKey(k): return "lock \(k.rawValue) has no matching key"
        case let .keyWithoutLock(k): return "key \(k.rawValue) has no matching lock"
        case let .unsupportedMechanic(name): return "mechanic \(name) is not supported yet"
        case let .multipleSeals(b): return "bottle \(b) has more than one seal"
        case let .invalidLink(link): return "link \(link) doesn't connect two different existing bottles"
        case let .multipleEssences(b): return "bottle \(b) has more than one essence rune"
        case let .essenceColorAbsent(b, c): return "bottle \(b) is an essence flask of color \(c.rawValue), which the level doesn't contain"
        case let .essenceFullOfOtherColor(b, c): return "essence flask \(b) starts full of color \(c.rawValue), not its own"
        case let .sealedTap(b): return "tap flask \(b) is sealed, but a tap never receives its key"
        case let .funnelWithTap(b): return "flask \(b) has a funnel and a tap, so it can neither pour nor receive"
        case let .unsortableFunnel(b): return "funnel flask \(b) starts with layers it can never pour out (more than one color, a key, or not its rune's color)"
        case let .frozenLayerOutOfRange(b, l): return "flask \(b) has a frozen layer \(l), but no such layer"
        case let .invalidThawTurns(b, t): return "a frozen layer in flask \(b) thaws after \(t) moves (allowed: 1...\(Rules.maxThawTurns))"
        case let .duplicateFrozenLayer(b, l): return "layer \(l) of flask \(b) is frozen more than once"
        case let .tooManyFrozenLayers(n): return "\(n) frozen layers (at most \(Rules.maxFrozenLayers) per level)"
        case let .invalidBubblingPeriod(b, e): return "bubbling flask \(b) rises every \(e) moves (allowed: \(Rules.bubblingPeriods.lowerBound)...\(Rules.bubblingPeriods.upperBound))"
        case let .invalidBubblingPhase(b, p): return "bubbling flask \(b) has phase \(p), outside 0..<period"
        case let .multipleBubbling(b): return "flask \(b) bubbles more than once"
        case let .bubblingWithTap(b): return "bubbling flask \(b) has a tap"
        case let .bubblingWithIce(b): return "bubbling flask \(b) holds a frozen layer"
        case let .tooManyBubblingFlasks(n): return "\(n) bubbling flasks (at most \(Rules.maxBubblingFlasks) per level)"
        case let .flaskInSeveralLinks(b): return "flask \(b) is an end of more than one link"
        case let .sealedTwin(b): return "twin flask \(b) is sealed, but a key never splits into it"
        case let .invalidRecipe(b, r): return "cauldron \(b) has an invalid recipe \(r) (two different ingredients, a third color as result, ids 0...\(StateKey.maxColorID))"
        case let .invalidRecipeCount(b, n): return "cauldron \(b) has \(n) recipes (allowed: 1...\(Rules.maxRecipes))"
        case let .conflictingRecipes(b): return "cauldron \(b) has two recipes for the same pair of colors"
        case let .cauldronCombined(b): return "cauldron \(b) carries another modifier"
        case let .linkedCauldron(b): return "cauldron \(b) is an end of a link"
        case let .tooManyRecipes(n): return "\(n) different recipes (at most \(Rules.maxRecipes) per level)"
        case let .unusableRecipe(b, r): return "recipe \(r) of cauldron \(b) can never mix (an ingredient is missing)"
        case .chainedRecipes: return "a recipe's result is an ingredient of another recipe"
        case let .unmixedPair(b): return "cauldron \(b) starts with a color directly on its recipe partner"
        case .unbalancedColors: return "no amount of mixing lets every color end with 0 or capacity layers"
        case let .tapSwitch(b): return "switch flask \(b) has a tap, so it could never fill up"
        case let .invalidGoalTarget(b): return "goal target \(b) is not a flask of the level, or has two targets"
        case let .invalidGoalLayers(b): return "goal target \(b) must ask for exactly capacity color layers (one color for an order)"
        case let .goalOnTap(b): return "goal target \(b) is a tap flask, which never receives"
        case let .goalColorShortage(c, w, a): return "the goal wants \(w) layers of color \(c.rawValue), the level has \(a)"
        case let .goalNeedsMoreFlasks(n, a): return "the goal needs \(n) flasks, the level has \(a)"
        case .layeredWithCauldron: return "a layered recipe can't be combined with a cauldron"
        }
    }
}

extension GameState {
    /// Structural checks: consistent capacity (1...`StateKey.maxCapacity`), no
    /// overfilled bottle, every color appears exactly `capacity` times, color and
    /// key ids fit the solver's encoding, keys and locks pair up one-to-one (each
    /// key id at most once as a layer and once as a lock), and every lock's key can
    /// be reached (not behind its own lock, directly or through a cycle of locks).
    /// Mechanics: at most one seal and one essence rune per flask, an essence rune names
    /// a color of the level, an essence flask doesn't start full of another color, a tap
    /// flask carries no seal and no funnel, a funnel flask starts empty or with one color
    /// (its rune's, if any; no key), frozen layers (D1) name an existing layer, at most once
    /// each, with a thaw counter in 1...`Rules.maxThawTurns`, and at most
    /// `Rules.maxFrozenLayers` per level, bubbling flasks (D2) have one period in
    /// `Rules.bubblingPeriods` with a phase below it, no tap and no ice, at most
    /// `Rules.maxBubblingFlasks` per level, links connect two different existing bottles, a
    /// flask is an end of at most one link (so a switch drives one gate and no flask is both),
    /// a twin (F1) is never sealed, a switch (A3) has no tap, and every modifier, link and goal
    /// is implemented by `Rules`.
    ///
    /// Cauldrons (E1): each carries 1...`Rules.maxRecipes` valid recipes (two different
    /// ingredients, a third color as result, no pair twice), no other modifier and no link;
    /// the level holds at most `Rules.maxRecipes` different recipes, none of whose results is
    /// an ingredient of another (no chains), each of whose
    /// ingredients is in the level or made by another recipe, and no cauldron starts with a
    /// color directly on its recipe partner (`Rules.holdsUnmixedPair`). Mixing changes color counts,
    /// so instead of "every color exactly `capacity` times" a level with a cauldron needs
    /// mixing amounts (pairs per recipe, `Rules.finalColorCounts`) after which every color
    /// has exactly 0 or `capacity` layers (`unbalancedColors`). That is not sufficient (the
    /// solver decides whether the mixing can actually be done) and stricter than the win, which
    /// also takes several full flasks of one color (DECISIONS 194).
    public func validate() -> [ValidationError] {
        guard let capacity = bottles.first?.capacity else { return [.noBottles] }
        var errors: [ValidationError] = []
        var unsupported: [String] = []
        for (i, bottle) in bottles.enumerated() {
            if bottle.modifiers.filter(\.isSeal).count > 1 { errors.append(.multipleSeals(bottle: i)) }
            unsupported += bottle.modifiers.filter { !$0.isImplemented }.map(\.name)
        }
        var linkEnds: [Int: Int] = [:]
        for link in links {
            let (a, b) = link.endpoints
            if a == b || !bottles.indices.contains(a) || !bottles.indices.contains(b) { errors.append(.invalidLink(link)) }
            if !link.isImplemented { unsupported.append(link.name) }
            for end in Set([a, b]) { linkEnds[end, default: 0] += 1 }
            if case .twins = link {
                for end in [a, b] where bottles.indices.contains(end) && bottles[end].isSealed {
                    errors.append(.sealedTwin(bottle: end))
                }
            }
            if case .switchGate = link, bottles.indices.contains(a), bottles[a].hasTap { errors.append(.tapSwitch(bottle: a)) }
        }
        for (bottle, n) in linkEnds.sorted(by: { $0.key < $1.key }) where n > 1 {
            errors.append(.flaskInSeveralLinks(bottle: bottle))
        }
        if !goal.isImplemented { unsupported.append(goal.name) }
        var reported = Set<String>()
        for name in unsupported where reported.insert(name).inserted { errors.append(.unsupportedMechanic(name)) }
        if !(1...StateKey.maxCapacity).contains(capacity) { errors.append(.invalidCapacity(capacity)) }
        var counts: [ColorID: Int] = [:]
        var keyCounts: [KeyID: Int] = [:]
        var lockCounts: [KeyID: Int] = [:]
        /// Every key layer with the lock of the bottle it sits in (nil = unlocked bottle).
        var keyHomes: [(key: KeyID, home: KeyID?)] = []
        for (i, bottle) in bottles.enumerated() {
            if bottle.capacity != capacity {
                errors.append(.inconsistentCapacity(bottle: i, capacity: bottle.capacity, expected: capacity))
            }
            if bottle.layers.count > bottle.capacity {
                errors.append(.overfilled(bottle: i, count: bottle.layers.count, capacity: bottle.capacity))
            }
            if let lock = bottle.lockedBy { lockCounts[lock, default: 0] += 1 }
            for layer in bottle.layers {
                if let c = layer.colorID { counts[c, default: 0] += 1 }
                if let k = layer.keyID {
                    keyCounts[k, default: 0] += 1
                    keyHomes.append((k, bottle.lockedBy))
                }
            }
        }
        // E1: recipes (level-wide, deduplicated) and cauldron structure.
        var recipes: [Recipe] = []
        for (i, bottle) in bottles.enumerated() where bottle.isCauldron {
            let cauldrons = bottle.modifiers.filter { if case .cauldron = $0 { return true } else { return false } }
            if bottle.modifiers.count > 1 { errors.append(.cauldronCombined(bottle: i)) }
            if linkEnds[i] != nil { errors.append(.linkedCauldron(bottle: i)) }
            for case .cauldron(let list) in cauldrons {
                if !(1...Rules.maxRecipes).contains(list.count) { errors.append(.invalidRecipeCount(bottle: i, count: list.count)) }
                var pairs = Set<[ColorID]>()
                for recipe in list {
                    let ids = [recipe.a, recipe.b, recipe.result]
                    if recipe.a == recipe.b || recipe.result == recipe.a || recipe.result == recipe.b
                        || ids.contains(where: { !(0...StateKey.maxColorID).contains($0.rawValue) }) {
                        errors.append(.invalidRecipe(bottle: i, recipe: recipe))
                    }
                    if !pairs.insert([recipe.a, recipe.b]).inserted { errors.append(.conflictingRecipes(bottle: i)) }
                    if !recipes.contains(recipe) { recipes.append(recipe) }
                }
            }
        }
        if recipes.count > Rules.maxRecipes { errors.append(.tooManyRecipes(count: recipes.count)) }
        if recipes.contains(where: { r in recipes.contains { $0.a == r.result || $0.b == r.result } }) {
            errors.append(.chainedRecipes)
        }
        for (i, bottle) in bottles.enumerated() where bottle.isCauldron {
            for recipe in bottle.recipes {
                let made = { (c: ColorID) in counts[c] != nil || recipes.contains { $0.result == c && $0 != recipe } }
                if !made(recipe.a) || !made(recipe.b) { errors.append(.unusableRecipe(bottle: i, recipe: recipe)) }
            }
            if Rules.holdsUnmixedPair(bottle) { errors.append(.unmixedPair(bottle: i)) }
        }
        for (i, bottle) in bottles.enumerated() {
            let runes = bottle.modifiers.compactMap { m -> ColorID? in
                if case .essence(let c) = m { return c }
                return nil
            }
            if runes.count > 1 { errors.append(.multipleEssences(bottle: i)) }
            for color in runes where counts[color] == nil && !recipes.contains(where: { $0.result == color }) {
                errors.append(.essenceColorAbsent(bottle: i, color: color))
            }
            if let rune = runes.first, bottle.layers.count == bottle.capacity,
               case .color(let c)? = bottle.layers.first, c != rune, bottle.layers.allSatisfy({ $0 == .color(c) }) {
                errors.append(.essenceFullOfOtherColor(bottle: i, color: c))
            }
            if bottle.hasTap && bottle.isSealed { errors.append(.sealedTap(bottle: i)) }
            if bottle.hasTap && bottle.isFunnel { errors.append(.funnelWithTap(bottle: i)) }
            if bottle.isFunnel, let first = bottle.layers.first {
                let oneColor = first.colorID != nil && bottle.layers.allSatisfy { $0 == first }
                if !oneColor || runes.contains(where: { first != .color($0) }) {
                    errors.append(.unsortableFunnel(bottle: i))
                }
            }
        }
        var frozenCount = 0
        for (i, bottle) in bottles.enumerated() {
            var frozenSeen = Set<Int>()
            for modifier in bottle.modifiers {
                guard case let .frozen(layer, turns) = modifier else { continue }
                frozenCount += 1
                if !bottle.layers.indices.contains(layer) { errors.append(.frozenLayerOutOfRange(bottle: i, layer: layer)) }
                if !(1...Rules.maxThawTurns).contains(turns) { errors.append(.invalidThawTurns(bottle: i, turns: turns)) }
                if !frozenSeen.insert(layer).inserted { errors.append(.duplicateFrozenLayer(bottle: i, layer: layer)) }
            }
        }
        if frozenCount > Rules.maxFrozenLayers { errors.append(.tooManyFrozenLayers(count: frozenCount)) }
        var bubblingCount = 0
        for (i, bottle) in bottles.enumerated() {
            var seen = 0
            for modifier in bottle.modifiers {
                guard case let .bubbling(every, phase) = modifier else { continue }
                seen += 1
                if !Rules.bubblingPeriods.contains(every) { errors.append(.invalidBubblingPeriod(bottle: i, every: every)) }
                if phase < 0 || phase >= max(every, 1) { errors.append(.invalidBubblingPhase(bottle: i, phase: phase)) }
            }
            guard seen > 0 else { continue }
            bubblingCount += 1
            if seen > 1 { errors.append(.multipleBubbling(bottle: i)) }
            if bottle.hasTap { errors.append(.bubblingWithTap(bottle: i)) }
            if bottle.holdsIce { errors.append(.bubblingWithIce(bottle: i)) }
        }
        if bubblingCount > Rules.maxBubblingFlasks { errors.append(.tooManyBubblingFlasks(count: bubblingCount)) }
        for (color, n) in counts.sorted(by: { $0.key < $1.key }) {
            if color.rawValue < 0 { errors.append(.negativeColor(color)) }
            if color.rawValue > StateKey.maxColorID { errors.append(.colorOutOfRange(color)) }
            if n != capacity && recipes.isEmpty { errors.append(.wrongColorCount(color: color, count: n, expected: capacity)) }
        }
        if !recipes.isEmpty && recipes.count <= Rules.maxRecipes
            && Rules.finalColorCounts(counts, recipes: recipes, capacity: capacity) == nil {
            errors.append(.unbalancedColors)
        }
        errors += goalErrors(capacity: capacity, counts: counts, recipes: recipes)
        for (key, n) in keyCounts.sorted(by: { $0.key < $1.key }) {
            if n > 1 { errors.append(.duplicateKey(key)) }
            if lockCounts[key] == nil { errors.append(.keyWithoutLock(key)) }
        }
        for (key, n) in lockCounts.sorted(by: { $0.key < $1.key }) {
            if n > 1 { errors.append(.duplicateLock(key)) }
            if keyCounts[key] == nil { errors.append(.lockWithoutKey(key)) }
        }
        for key in Set(keyCounts.keys).union(lockCounts.keys).sorted()
        where !(0...StateKey.maxKeyID).contains(key.rawValue) {
            errors.append(.keyOutOfRange(key))
        }
        // Locks that can be opened: start from keys in unlocked bottles, then keep
        // adding keys whose bottle's lock is already openable.
        var openable: Set<KeyID> = []
        var changed = true
        while changed {
            changed = false
            for (key, home) in keyHomes where !openable.contains(key) {
                if home.map(openable.contains) ?? true {
                    openable.insert(key)
                    changed = true
                }
            }
        }
        for key in lockCounts.keys.sorted() where keyCounts[key] != nil && !openable.contains(key) {
            errors.append(.unopenableLock(key))
        }
        return errors
    }

    /// R7 order and layered goals (DECISIONS 229): every target names a different existing
    /// flask without a tap and asks for exactly `capacity` color layers (an order: one color);
    /// the targets want no more of a color than the level holds; and the targets plus one
    /// flask per whole `capacity` of each remaining color, plus one for each color's partial
    /// remainder, fit in the level's flasks. With a cauldron the counts change as it brews, so
    /// only the structure is checked there (the solver decides), and a layered recipe is
    /// rejected.
    func goalErrors(capacity: Int, counts: [ColorID: Int], recipes: [Recipe]) -> [ValidationError] {
        let targets = goal.targets
        guard !targets.isEmpty else { return [] }
        var errors: [ValidationError] = []
        var seen = Set<Int>()
        var wanted: [ColorID: Int] = [:]
        let layered: Bool = { if case .pattern = goal { return true } else { return false } }()
        for target in targets {
            guard bottles.indices.contains(target.bottle), seen.insert(target.bottle).inserted else {
                errors.append(.invalidGoalTarget(bottle: target.bottle))
                continue
            }
            if bottles[target.bottle].hasTap { errors.append(.goalOnTap(bottle: target.bottle)) }
            let colors = target.layers.compactMap(\.colorID)
            if target.layers.count != capacity || colors.count != target.layers.count || (!layered && target.color == nil) {
                errors.append(.invalidGoalLayers(bottle: target.bottle))
            }
            for c in colors { wanted[c, default: 0] += 1 }
        }
        if !recipes.isEmpty {
            if layered { errors.append(.layeredWithCauldron) }
            return errors
        }
        for (color, n) in wanted.sorted(by: { $0.key < $1.key }) where n > counts[color] ?? 0 {
            errors.append(.goalColorShortage(color: color, wanted: n, available: counts[color] ?? 0))
        }
        if capacity > 0 {
            var needed = seen.count
            for (color, n) in counts {
                let rest = max(0, n - (wanted[color] ?? 0))
                needed += (rest + capacity - 1) / capacity
            }
            if needed > bottles.count { errors.append(.goalNeedsMoreFlasks(needed: needed, available: bottles.count)) }
        }
        return errors
    }
}
