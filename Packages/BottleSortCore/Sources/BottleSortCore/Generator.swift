public struct GeneratorConfig: Sendable, Hashable {
    public var colors: Int
    public var capacity: Int
    public var emptyBottles: Int
    /// Number of locked bottles (each with one key). 0 = classic level.
    /// Must be less than `colors`. See `Generator.candidate` for the layout.
    public var locks: Int
    /// First seed to try; attempt i uses `seed + i`.
    public var seed: UInt64
    /// Accept only levels whose optimal length is in this range.
    public var minMoves: ClosedRange<Int>?
    /// Accept only levels whose score is in this range.
    public var score: ClosedRange<Double>?
    /// Reject lock levels where some lock doesn't matter (see `LockImpact.everyLockMatters`).
    public var requireLocksMatter: Bool
    /// Moves each lock must add for `requireLocksMatter` (see `LockImpact.lockMatters`).
    public var lockCost: Int
    /// Number of essence flasks (C1), each marked with a different color. 0 = none.
    /// See `Generator.candidate` for the placement.
    public var essence: Int
    /// How many of the `essence` flasks are empty ones (the rest are filled flasks marked
    /// with their bottom color). nil = any mix, as the shuffle falls.
    public var essenceEmpty: Int?
    /// The level will be played murky (only each flask's top run visible). Rune colors then
    /// never depend on hidden layers: a filled flask gets a random free color instead of
    /// its bottom one, which the player can't see. Only rune placement reads it.
    public var hidden: Bool
    /// Reject levels where some essence flask doesn't matter (`MechanicImpact`, cost
    /// `essenceCost`).
    public var requireEssenceMatter: Bool
    /// Moves each essence flask must add for `requireEssenceMatter`
    /// (`EssenceImpact.minimumCost` or `.strongCost`).
    public var essenceCost: Int
    /// Narrow-neck flasks (C2): one layer per pour, in or out. 0 = none. See
    /// `Generator.candidate` (step 6) for the placement of all glass modifiers.
    public var narrowNecks: Int
    /// Funnel flasks (C4, receive only), placed on empty flasks. 0 = none.
    public var funnels: Int
    /// Tap flasks (C4, pour from the bottom, never receive), placed on filled flasks. 0 = none.
    public var taps: Int
    /// Reject levels where some narrow neck, funnel or tap doesn't matter (`GlassImpact`,
    /// cost `glassCost`).
    public var requireGlassMatter: Bool
    /// Moves each glass modifier must change for `requireGlassMatter`
    /// (`GlassImpact.minimumCost` or `.strongCost`).
    public var glassCost: Int
    /// Frozen layers (D1), at most `Rules.maxFrozenLayers`. 0 = none. See
    /// `Generator.candidate` (step 7) for the placement.
    public var frozen: Int
    /// Largest thaw counter a frozen layer gets (1...`Rules.maxThawTurns`); each layer
    /// draws from the upper half, `(frozenMaxTurns + 1) / 2 ... frozenMaxTurns`.
    public var frozenMaxTurns: Int
    /// Reject levels where some frozen layer doesn't matter (`FrozenImpact`, cost `frozenCost`).
    public var requireFrozenMatter: Bool
    /// Moves each frozen layer must add for `requireFrozenMatter`
    /// (`FrozenImpact.minimumCost` or `.strongCost`).
    public var frozenCost: Int
    /// Bubbling flasks (D2), at most `Rules.maxBubblingFlasks`. 0 = none. See
    /// `Generator.candidate` (step 8) for the placement.
    public var bubbling: Int
    /// The period of every bubbling flask (`Rules.bubblingPeriods`): its bottom layer rises
    /// every `bubblingPeriod` moves. Each flask starts at a random phase.
    public var bubblingPeriod: Int
    /// Reject levels where some bubbling flask doesn't matter (`BubblingImpact`, cost
    /// `bubblingCost`, either way).
    public var requireBubblingMatter: Bool
    /// Moves each bubbling flask must change for `requireBubblingMatter`
    /// (`BubblingImpact.minimumCost` or `.strongCost`).
    public var bubblingCost: Int
    /// Twin pairs (F1). 0 = none. See `Generator.candidate` (step 9) for the placement.
    public var twins: Int
    /// Overflow pipes (F2). 0 = none. Placed after the twins (step 9).
    public var overflow: Int
    /// Where links go: `.any` plain flask, only `.filled` ones, or only `.empty` ones.
    public var linkPlacement: LinkPlacement
    /// Reject levels where some link doesn't matter (`LinkImpact`, cost `linkCost`, either way).
    public var requireLinksMatter: Bool
    /// Moves each link must change for `requireLinksMatter` (`LinkImpact.minimumCost` or `.strongCost`).
    public var linkCost: Int
    public var maxAttempts: Int
    public var solverLimits: SolverLimits

    public init(colors: Int, capacity: Int = 4, emptyBottles: Int = 2, locks: Int = 0, seed: UInt64 = 1,
                minMoves: ClosedRange<Int>? = nil, score: ClosedRange<Double>? = nil,
                requireLocksMatter: Bool = false, lockCost: Int = LockImpact.minimumCost,
                essence: Int = 0, essenceEmpty: Int? = nil, requireEssenceMatter: Bool = false,
                essenceCost: Int = EssenceImpact.minimumCost, hidden: Bool = false,
                narrowNecks: Int = 0, funnels: Int = 0, taps: Int = 0, requireGlassMatter: Bool = false,
                glassCost: Int = GlassImpact.minimumCost,
                frozen: Int = 0, frozenMaxTurns: Int = 3, requireFrozenMatter: Bool = false,
                frozenCost: Int = FrozenImpact.minimumCost,
                bubbling: Int = 0, bubblingPeriod: Int = 3, requireBubblingMatter: Bool = false,
                bubblingCost: Int = BubblingImpact.minimumCost,
                twins: Int = 0, overflow: Int = 0, linkPlacement: LinkPlacement = .any,
                requireLinksMatter: Bool = false, linkCost: Int = LinkImpact.minimumCost,
                maxAttempts: Int = 2_000, solverLimits: SolverLimits = .default) {
        self.colors = colors
        self.capacity = capacity
        self.emptyBottles = emptyBottles
        self.locks = locks
        self.seed = seed
        self.minMoves = minMoves
        self.score = score
        self.requireLocksMatter = requireLocksMatter
        self.lockCost = lockCost
        self.essence = essence
        self.essenceEmpty = essenceEmpty
        self.requireEssenceMatter = requireEssenceMatter
        self.essenceCost = essenceCost
        self.hidden = hidden
        self.narrowNecks = narrowNecks
        self.funnels = funnels
        self.taps = taps
        self.requireGlassMatter = requireGlassMatter
        self.glassCost = glassCost
        self.frozen = frozen
        self.frozenMaxTurns = frozenMaxTurns
        self.requireFrozenMatter = requireFrozenMatter
        self.frozenCost = frozenCost
        self.bubbling = bubbling
        self.bubblingPeriod = bubblingPeriod
        self.requireBubblingMatter = requireBubblingMatter
        self.bubblingCost = bubblingCost
        self.twins = twins
        self.overflow = overflow
        self.linkPlacement = linkPlacement
        self.requireLinksMatter = requireLinksMatter
        self.linkCost = linkCost
        self.maxAttempts = maxAttempts
        self.solverLimits = solverLimits
    }
}

/// Which flasks the generator links (twins, overflow pipes; `GeneratorConfig.linkPlacement`).
public enum LinkPlacement: String, Sendable, Hashable, CaseIterable {
    /// Any plain flask, filled or empty.
    case any
    /// Only flasks that start with layers.
    case filled
    /// Only empty flasks.
    case empty
    /// Twins on empty flasks; an overflow pipe from a filled flask into an empty one.
    case mixed
}

public struct GeneratedLevel: Sendable, Hashable {
    public var state: GameState
    public var seed: UInt64
    public var report: DifficultyReport
}

public enum GeneratorError: Error, Hashable, CustomStringConvertible {
    case noLevelFound(attempts: Int)
    public var description: String {
        switch self {
        case .noLevelFound(let n): return "no level matched the constraints after \(n) attempts"
        }
    }
}

/// Random-shuffle + rejection-sampling level generator.
public enum Generator {
    /// The raw (unfiltered) level for `seed`.
    ///
    /// Classic (`locks == 0`): all `colors × capacity` color layers are
    /// shuffled into `colors` full bottles, plus `emptyBottles` empty ones.
    ///
    /// With `locks = L` (1 ≤ L < colors), using the same shuffled color layers:
    /// 1. Locked bottles: the first `L × capacity` shuffled layers fill `L`
    ///    bottles, locked by keys 1...L (so those colors are trapped inside).
    /// 2. The remaining `(colors − L) × capacity` color layers plus the `L` keys
    ///    are laid out in sequence and dealt into unlocked bottles of
    ///    `capacity` layers each, the last one partly filled (for L < capacity
    ///    it holds L layers). This adds exactly one bottle compared to classic,
    ///    and its free space is what makes room for the keys.
    /// 3. Key positions: a slot is "top" if it is the last slot of its bottle.
    ///    The non-top slots are shuffled and the first L of them (in sequence
    ///    order) become keys 1...L; the color layers fill the other slots in
    ///    their shuffled order. So every key sits below at least one layer.
    /// 4. `emptyBottles` empty bottles are appended.
    ///
    /// Essence flasks (`essence = E`), drawn after all of the above from the same random
    /// stream, so the layout is exactly the one without essence flasks:
    /// 5. The bottle indices are shuffled. Walking that order, an empty flask gets a random
    ///    color no other essence flask has; a filled flask gets the color of its bottom
    ///    layer (skipped if that is a key or already taken), so it is the color the flask
    ///    naturally ends with once the layers above are poured out. Sealed flasks qualify
    ///    too (seal and rune together). `essenceEmpty` fixes how many are empty flasks.
    ///    For a murky level (`hidden`) a filled flask gets a random free color too, like an
    ///    empty one: its bottom layer is hidden, and a rune of that color would reveal it.
    ///    Fewer than `E` flasks are marked only if the level has too few candidates.
    ///
    /// Glass modifiers (`narrowNecks`, `funnels`, `taps`), drawn after step 5 from the same
    /// stream (nothing is drawn when all three are 0, so every older level is unchanged):
    /// 6. The bottle indices are shuffled again. Walking that order over flasks without any
    ///    modifier (no seal, no rune; one glass modifier per flask): a filled flask gets a
    ///    tap while taps are left, an empty flask a funnel while funnels are left (a funnel
    ///    never pours out, so it must start empty), and any other such flask a narrow neck
    ///    while necks are left. Placement reads only which flasks are empty, never colors,
    ///    so it tells nothing about murky layers. Fewer are placed only if the level has too
    ///    few candidates.
    ///
    /// Frozen layers (`frozen = F`, D1), drawn after step 6 from the same stream (nothing
    /// is drawn when F is 0, so every older level is unchanged):
    /// 7. The bottle indices are shuffled again. Walking that order over filled flasks that
    ///    hold no ice yet and aren't funnels (one frozen layer per flask): the flask gets a
    ///    frozen layer at a random index in its upper half (`count / 2 ..< count`: a frozen
    ///    bottom layer pins nothing and almost never matters) with a thaw counter
    ///    drawn from `(frozenMaxTurns + 1) / 2 ... frozenMaxTurns`. Placement reads only
    ///    layer counts, never colors (murky levels give nothing away). Fewer are placed only
    ///    if the level has too few filled flasks.
    ///
    /// Bubbling flasks (`bubbling = B`, D2), drawn after step 7 from the same stream (nothing
    /// is drawn when B is 0, so every older level is unchanged):
    /// 8. The bottle indices are shuffled again. Walking that order over flasks with at least
    ///    two layers and no tap, funnel, narrow neck or ice (a seal or a rune may stay), the
    ///    flask bubbles every `bubblingPeriod` moves, starting at a random phase
    ///    (`0..<bubblingPeriod`). Placement reads only layer counts and modifiers, never
    ///    colors (murky-safe). Fewer are placed only if the level has too few such flasks.
    ///
    /// Links (`twins = T`, `overflow = O`, F1 / F2), drawn after step 8 from the same stream
    /// (nothing is drawn when both are 0, so every older level is unchanged):
    /// 9. The bottle indices are shuffled again. Walking that order over plain flasks (no
    ///    modifier at all: links stay on flasks that read at a glance) that aren't linked
    ///    yet and fit `linkPlacement`, the first two make a twin pair, T times, then the next
    ///    two an overflow pipe (from the first to the second), O times. `.mixed` puts twins on
    ///    empty flasks and runs each pipe from a filled flask into an empty one. Placement reads
    ///    only which flasks are empty, never colors (murky-safe). Fewer links are placed only
    ///    if the level has too few such flasks.
    public static func candidate(_ config: GeneratorConfig, seed: UInt64) -> GameState {
        var rng = SplitMix64(seed: seed)
        let capacity = config.capacity
        var layers: [Layer] = []
        for color in 0..<config.colors {
            layers += Array(repeating: .color(ColorID(color)), count: capacity)
        }
        rng.shuffle(&layers)
        var bottles: [Bottle] = []
        if config.locks <= 0 {
            for i in 0..<config.colors {
                let slice = layers[(i * capacity)..<((i + 1) * capacity)]
                bottles.append(Bottle(layers: Array(slice), capacity: capacity))
            }
        } else {
            let locks = config.locks
            precondition(locks < config.colors, "locks must be less than colors")
            // 1. Locked bottles.
            for j in 0..<locks {
                let slice = layers[(j * capacity)..<((j + 1) * capacity)]
                bottles.append(Bottle(layers: Array(slice), capacity: capacity, lockedBy: KeyID(j + 1)))
            }
            // 2. + 3. Unlocked sequence with keys in non-top slots.
            var colors = Array(layers[(locks * capacity)...])
            let total = colors.count + locks
            let isTop = { (i: Int) in i % capacity == capacity - 1 || i == total - 1 }
            var nonTop = (0..<total).filter { !isTop($0) }
            precondition(nonTop.count >= locks, "not enough non-top slots for the keys")
            rng.shuffle(&nonTop)
            let keySlots = nonTop.prefix(locks).sorted()
            var sequence: [Layer] = []
            colors.reverse()  // pop from the end in original order
            var nextKey = 1
            for i in 0..<total {
                if keySlots.contains(i) {
                    sequence.append(.key(KeyID(nextKey)))
                    nextKey += 1
                } else {
                    sequence.append(colors.removeLast())
                }
            }
            for start in stride(from: 0, to: total, by: capacity) {
                bottles.append(Bottle(layers: Array(sequence[start..<min(total, start + capacity)]), capacity: capacity))
            }
        }
        // 4. Empty bottles.
        bottles += Array(repeating: Bottle(capacity: capacity), count: config.emptyBottles)
        // 5. Essence flasks.
        if config.essence > 0 { markEssence(&bottles, config: config, rng: &rng) }
        // 6. Glass modifiers.
        if config.narrowNecks > 0 || config.funnels > 0 || config.taps > 0 { markGlass(&bottles, config: config, rng: &rng) }
        // 7. Frozen layers.
        if config.frozen > 0 { markFrozen(&bottles, config: config, rng: &rng) }
        // 8. Bubbling flasks.
        if config.bubbling > 0 { markBubbling(&bottles, config: config, rng: &rng) }
        // 9. Links.
        var links: [Link] = []
        if config.twins > 0 || config.overflow > 0 { links = makeLinks(bottles, config: config, rng: &rng) }
        return GameState(bottles: bottles, links: links)
    }

    /// Step 9 of `candidate`.
    static func makeLinks(_ bottles: [Bottle], config: GeneratorConfig, rng: inout SplitMix64) -> [Link] {
        var order = Array(bottles.indices)
        rng.shuffle(&order)
        var used = Set<Int>()
        func take(empty: Bool?) -> Int? {
            guard let i = order.first(where: { i in
                !used.contains(i) && bottles[i].isPlain && (empty.map { bottles[i].isEmpty == $0 } ?? true)
            }) else { return nil }
            used.insert(i)
            return i
        }
        let wanted: Bool? = {
            switch config.linkPlacement {
            case .any: return nil
            case .filled: return false
            case .empty, .mixed: return true
            }
        }()
        var links: [Link] = []
        for _ in 0..<max(0, config.twins) {
            guard let a = take(empty: wanted) else { break }
            guard let b = take(empty: wanted) else { used.remove(a); break }
            links.append(.twins(a, b))
        }
        for _ in 0..<max(0, config.overflow) {
            let fromKind: Bool? = config.linkPlacement == .mixed ? false : wanted
            guard let a = take(empty: fromKind) else { break }
            guard let b = take(empty: wanted) else { used.remove(a); break }
            links.append(.overflow(from: a, to: b))
        }
        return links
    }

    /// Step 8 of `candidate`.
    static func markBubbling(_ bottles: inout [Bottle], config: GeneratorConfig, rng: inout SplitMix64) {
        precondition(config.bubbling <= Rules.maxBubblingFlasks, "at most \(Rules.maxBubblingFlasks) bubbling flasks")
        precondition(Rules.bubblingPeriods.contains(config.bubblingPeriod), "bubblingPeriod must be in \(Rules.bubblingPeriods)")
        var order = Array(bottles.indices)
        rng.shuffle(&order)
        var left = config.bubbling
        for i in order where left > 0 {
            let b = bottles[i]
            guard b.layers.count >= 2, !b.hasTap, !b.isFunnel, !b.hasNarrowNeck, !b.holdsIce, !b.isBubbling else { continue }
            let phase = rng.nextInt(below: config.bubblingPeriod)
            bottles[i].modifiers.append(.bubbling(every: config.bubblingPeriod, phase: phase))
            left -= 1
        }
    }

    /// Step 7 of `candidate`.
    static func markFrozen(_ bottles: inout [Bottle], config: GeneratorConfig, rng: inout SplitMix64) {
        precondition(config.frozen <= Rules.maxFrozenLayers, "at most \(Rules.maxFrozenLayers) frozen layers")
        precondition((1...Rules.maxThawTurns).contains(config.frozenMaxTurns), "frozenMaxTurns must be 1...\(Rules.maxThawTurns)")
        var order = Array(bottles.indices)
        rng.shuffle(&order)
        let lowest = max(1, (config.frozenMaxTurns + 1) / 2)
        var left = config.frozen
        for i in order where left > 0 && !bottles[i].isEmpty && !bottles[i].isFunnel && !bottles[i].holdsIce {
            let count = bottles[i].layers.count
            let layer = count / 2 + rng.nextInt(below: count - count / 2)
            let turns = lowest + rng.nextInt(below: config.frozenMaxTurns - lowest + 1)
            bottles[i].modifiers.append(.frozen(layer: layer, turns: turns))
            left -= 1
        }
    }

    /// Step 6 of `candidate`.
    static func markGlass(_ bottles: inout [Bottle], config: GeneratorConfig, rng: inout SplitMix64) {
        var order = Array(bottles.indices)
        rng.shuffle(&order)
        var necks = config.narrowNecks, funnels = config.funnels, taps = config.taps
        for i in order where bottles[i].isPlain {
            let modifier: BottleModifier
            if !bottles[i].isEmpty && taps > 0 {
                modifier = .tap
                taps -= 1
            } else if bottles[i].isEmpty && funnels > 0 {
                modifier = .funnel
                funnels -= 1
            } else if necks > 0 {
                modifier = .narrowNeck
                necks -= 1
            } else {
                continue
            }
            bottles[i].modifiers.append(modifier)
        }
    }

    /// Step 5 of `candidate`.
    static func markEssence(_ bottles: inout [Bottle], config: GeneratorConfig, rng: inout SplitMix64) {
        var order = Array(bottles.indices)
        rng.shuffle(&order)
        var used: Set<ColorID> = []
        var emptyLeft = config.essenceEmpty ?? Int.max
        var filledLeft = config.essenceEmpty.map { config.essence - $0 } ?? Int.max
        var marked = 0
        /// A random color no rune has yet (independent of every layer), nil if none is left.
        func freeColor() -> ColorID? {
            let free = (0..<config.colors).map { ColorID($0) }.filter { !used.contains($0) }
            return free.isEmpty ? nil : free[rng.nextInt(below: free.count)]
        }
        for i in order where marked < config.essence {
            let color: ColorID
            if bottles[i].isEmpty {
                guard emptyLeft > 0, let free = freeColor() else { continue }
                color = free
                emptyLeft -= 1
            } else if config.hidden {
                guard filledLeft > 0, let free = freeColor() else { continue }
                color = free
                filledLeft -= 1
            } else {
                guard filledLeft > 0, let bottom = bottles[i].layers.first?.colorID, !used.contains(bottom) else { continue }
                color = bottom
                filledLeft -= 1
            }
            used.insert(color)
            bottles[i].modifiers.append(.essence(color))
            marked += 1
        }
    }

    /// Whether `bottle` holds content that is already sorted: solved and
    /// non-empty, or would be once its lock is removed or its ice thaws. Judged on the
    /// layers alone (no other modifier keeps a flask from counting as solved).
    static func isPresolved(_ bottle: Bottle) -> Bool {
        let layersOnly = Bottle(layers: bottle.layers, capacity: bottle.capacity)
        return !layersOnly.isEmpty && layersOnly.isSolved
    }

    /// Checks a candidate; returns its report if it passes every filter.
    public static func evaluate(_ state: GameState, config: GeneratorConfig, seed: UInt64) -> DifficultyReport? {
        // Reject: any bottle already solved (full with one color), locked or not.
        if state.bottles.contains(where: isPresolved) { return nil }
        // Reject: unsolvable or unknown.
        guard case .solved(let moves, let explored) = Solver().solve(state, limits: config.solverLimits) else { return nil }
        // Cheap filter before the (more expensive) full report.
        if let range = config.minMoves, !range.contains(moves.count) { return nil }
        if config.requireLocksMatter,
           !LockImpact.everyLockMatters(state, minMoves: moves.count, cost: config.lockCost,
                                        limits: config.solverLimits) { return nil }
        if config.requireEssenceMatter,
           !EssenceImpact.everyEssenceMatters(state, minMoves: moves.count, cost: config.essenceCost,
                                              limits: config.solverLimits) { return nil }
        if config.requireGlassMatter,
           !GlassImpact.everyGlassMatters(state, minMoves: moves.count, cost: config.glassCost,
                                          limits: config.solverLimits) { return nil }
        if config.requireFrozenMatter,
           !FrozenImpact.everyFrozenMatters(state, minMoves: moves.count, cost: config.frozenCost,
                                            limits: config.solverLimits) { return nil }
        if config.requireBubblingMatter,
           !BubblingImpact.everyBubblingMatters(state, minMoves: moves.count, cost: config.bubblingCost,
                                                limits: config.solverLimits) { return nil }
        if config.requireLinksMatter,
           !LinkImpact.everyLinkMatters(state, minMoves: moves.count, cost: config.linkCost,
                                        limits: config.solverLimits) { return nil }
        let report = Difficulty.analyze(state, solution: moves, statesExplored: explored, sampleSeed: seed)
        if let range = config.score, !range.contains(report.score) { return nil }
        return report
    }

    /// First passing level, trying seeds `config.seed`, `config.seed + 1`, …
    public static func generate(_ config: GeneratorConfig) throws -> GeneratedLevel {
        guard let level = try generate(config, count: 1).first else { throw GeneratorError.noLevelFound(attempts: config.maxAttempts) }
        return level
    }

    /// `count` passing levels, using consecutive seeds. `maxAttempts` applies per level.
    public static func generate(_ config: GeneratorConfig, count: Int,
                                progress: ((GeneratedLevel) -> Void)? = nil) throws -> [GeneratedLevel] {
        var result: [GeneratedLevel] = []
        var seed = config.seed
        while result.count < count {
            var found: GeneratedLevel?
            for _ in 0..<config.maxAttempts {
                let candidate = candidate(config, seed: seed)
                defer { seed &+= 1 }
                if let report = evaluate(candidate, config: config, seed: seed) {
                    found = GeneratedLevel(state: candidate, seed: seed, report: report)
                    break
                }
            }
            guard let found else { throw GeneratorError.noLevelFound(attempts: config.maxAttempts) }
            result.append(found)
            progress?(found)
        }
        return result
    }
}

/// One instance of a mechanic in a level, as something that can be taken out of it.
public enum MechanicInstance: Hashable, Sendable, CustomStringConvertible {
    /// A seal and its key (A1).
    case seal(KeyID)
    /// One modifier (other than a seal) on bottle `bottle`.
    case modifier(bottle: Int, BottleModifier)
    /// One link.
    case link(Link)
    /// A non-standard goal (removing it means the standard goal).
    case goal(Goal)

    public var description: String {
        switch self {
        case .seal(let k): return "seal \(k.rawValue)"
        case let .modifier(b, m): return "\(m) on \(b)"
        case .link(let l): return "link \(l)"
        case .goal(let g): return "goal \(g.name)"
        }
    }
}

/// The "must matter" check, for every mechanic: re-solve the level with one mechanic
/// instance removed and compare.
///
/// An instance *matters* when the level without it is unsolvable, or the level with it
/// needs at least `cost` more moves. A narrow neck or a tap (`isTwoSided`) also matters
/// when the level with it needs at least `cost` *fewer* moves: both take options away
/// and add one (a narrow neck splits a run, a tap reaches the bottom layer), and an
/// optimal solution that relies on the new option uses the flask as much as one that
/// works around it. A funnel (which in practice never changes the optimal length: whatever
/// goes into it can always be completed there) also matters when it sets a trap
/// (`trapDepth(of:in:)`): a position one pour from a solvable one that is lost only because
/// the flask is a funnel. The default cost is `minimumCost(of:)`: the
/// instance's inherent cost (what it costs even when it changes nothing: a seal always
/// costs the key pour, 1 move; everything else 0) plus one. A caller may ask for more
/// (stronger locks: `LockImpact.strongCost`, DECISIONS 104). An undecided solve (limits
/// hit) counts as "doesn't matter".
public enum MechanicImpact {
    /// Every mechanic instance in `state`, in a stable order: seals by key, then other
    /// modifiers by bottle, then links, then the goal.
    public static func instances(in state: GameState) -> [MechanicInstance] {
        var result: [MechanicInstance] = Set(state.bottles.compactMap(\.lockedBy)).sorted().map(MechanicInstance.seal)
        for (i, bottle) in state.bottles.enumerated() {
            result += Bottle.splitSeal(bottle.modifiers).others.map { .modifier(bottle: i, $0) }
        }
        result += state.links.map(MechanicInstance.link)
        if state.goal != .standard { result.append(.goal(state.goal)) }
        return result
    }

    /// `state` with `instance` removed. A seal: its bottle starts unsealed and its key
    /// layer is gone.
    public static func removing(_ instance: MechanicInstance, from state: GameState) -> GameState {
        var result = state
        switch instance {
        case .seal(let key):
            for i in result.bottles.indices {
                if result.bottles[i].lockedBy == key { result.bottles[i].lockedBy = nil }
                result.bottles[i].layers.removeAll { $0.keyID == key }
            }
        case let .modifier(bottle, modifier):
            if result.bottles.indices.contains(bottle) { result.bottles[bottle].modifiers.removeAll { $0 == modifier } }
        case .link(let link):
            if let i = result.links.firstIndex(of: link) { result.links.remove(at: i) }
        case .goal:
            result.goal = .standard
        }
        return result
    }

    /// Moves the instance costs even when it changes nothing (a seal: the key pour).
    public static func inherentCost(of instance: MechanicInstance) -> Int {
        if case .seal = instance { return 1 }
        return 0
    }

    /// Smallest cost that counts as "matters": the inherent cost plus one move
    /// (2 for a seal = `LockImpact.minimumCost`, 1 otherwise).
    public static func minimumCost(of instance: MechanicInstance) -> Int {
        inherentCost(of: instance) + 1
    }

    /// Whether `instance` matters in a level whose optimal solution has `minMoves` moves:
    /// without it the level is unsolvable, or solves in at least `cost` fewer moves
    /// (`nil` = `minimumCost(of:)`).
    public static func matters(_ instance: MechanicInstance, in state: GameState, minMoves: Int,
                               cost: Int? = nil, limits: SolverLimits = .default) -> Bool {
        let cost = cost ?? minimumCost(of: instance)
        switch Solver().solve(removing(instance, from: state), limits: limits) {
        case .unsolvable: return true
        case .solved(let moves, _):
            let saved = minMoves - moves.count
            if (isTwoSided(instance) ? abs(saved) : saved) >= cost { return true }
            // A funnel never changes the optimal length; it matters by the trap it sets.
            if case .modifier(_, .funnel) = instance { return trapDepth(of: instance, in: state) != nil }
            // Nor does an overflow pipe in practice; it matters by the spill it can force.
            if case .link(.overflow) = instance { return spillDepth(of: instance, in: state) != nil }
            return false
        case .unknown: return false
        }
    }

    /// Whether the instance can make a level shorter as well as longer (`matters` then
    /// counts the change either way): a narrow neck, a tap, a bubbling flask (a rise can
    /// bring the needed color up as well as bury it), twins (a split adds a pour no plain
    /// flask makes, and closes the twins to every other pour) or an overflow pipe (it saves a
    /// pour, or spills what the player wanted to keep in the source).
    public static func isTwoSided(_ instance: MechanicInstance) -> Bool {
        switch instance {
        case .modifier(_, .narrowNeck), .modifier(_, .tap), .modifier(_, .bubbling),
             .link(.twins), .link(.overflow): return true
        default: return false
        }
    }

    /// Whether every mechanic instance in the level matters at its minimum cost (true for a
    /// classic level).
    public static func everyMechanicMatters(_ state: GameState, minMoves: Int, limits: SolverLimits = .default) -> Bool {
        instances(in: state).allSatisfy { matters($0, in: state, minMoves: minMoves, limits: limits) }
    }
}

/// Whether a lock changes a level (the "must matter" check for sealed flasks).
///
/// Winning always needs every key, so "the key is used" holds trivially. The real test
/// compares with the same level *without* that lock: the bottle unlocked from the start
/// and its key layer removed. The lock matters when that level is unsolvable, or when the
/// locked level needs at least `cost` more moves (the key pour plus a detour), i.e. the
/// seal forces the player to dig for the key or to plan around the closed flask.
/// This is the seal case of `MechanicImpact` (same results as before it existed).
public enum LockImpact {
    /// `state` with lock `key` removed: its bottle starts unlocked, its key layer is gone.
    public static func removingLock(_ key: KeyID, from state: GameState) -> GameState {
        MechanicImpact.removing(.seal(key), from: state)
    }

    /// Smallest lock cost that counts as "matters": the key pour plus at least one more move.
    public static let minimumCost = 2
    /// Cost required in the chapter recipes after the tutorial: the key pour plus a detour
    /// of at least two moves (user decision: stronger locks).
    public static let strongCost = 3

    /// Whether lock `key` matters in a level whose optimal solution has `minMoves` moves:
    /// the level without that lock (and its key) is unsolvable, or solves in at least
    /// `cost` fewer moves. An undecided solve (limits hit) counts as "doesn't matter".
    public static func lockMatters(_ key: KeyID, in state: GameState, minMoves: Int,
                                   cost: Int = minimumCost, limits: SolverLimits = .default) -> Bool {
        MechanicImpact.matters(.seal(key), in: state, minMoves: minMoves, cost: cost, limits: limits)
    }

    /// Whether every lock in the level matters (true for a level without locks).
    public static func everyLockMatters(_ state: GameState, minMoves: Int, cost: Int = minimumCost,
                                        limits: SolverLimits = .default) -> Bool {
        let keys = Set(state.bottles.compactMap(\.lockedBy)).sorted()
        return keys.allSatisfy { lockMatters($0, in: state, minMoves: minMoves, cost: cost, limits: limits) }
    }
}

/// Whether an essence flask changes a level (the "must matter" check for C1).
///
/// An essence flask only takes moves away (it refuses what a plain flask would take), so
/// the level without the rune is never harder: the check is how many moves the rune adds.
/// It is the `.modifier(_, .essence)` case of `MechanicImpact`.
public enum EssenceImpact {
    /// Smallest cost that counts as "matters": one extra move (`MechanicImpact.minimumCost`).
    public static let minimumCost = 1
    /// Cost required in the chapter 4 recipes after the tutorial: the rune forces a detour
    /// of at least two moves.
    public static let strongCost = 2

    /// The essence instances of `state` (one per marked flask).
    public static func instances(in state: GameState) -> [MechanicInstance] {
        MechanicImpact.instances(in: state).filter {
            if case .modifier(_, .essence) = $0 { return true }
            return false
        }
    }

    /// Whether every essence flask matters (true for a level without one).
    public static func everyEssenceMatters(_ state: GameState, minMoves: Int, cost: Int = minimumCost,
                                           limits: SolverLimits = .default) -> Bool {
        instances(in: state).allSatisfy { MechanicImpact.matters($0, in: state, minMoves: minMoves, cost: cost, limits: limits) }
    }
}

/// Whether a narrow neck, funnel or tap changes a level (the "must matter" check for C2 and
/// C4): the `.modifier(_, .narrowNeck / .funnel / .tap)` cases of `MechanicImpact`.
///
/// A funnel only takes moves away (it never pours out), so the level without it is never
/// longer; in practice it is never shorter either, so a funnel matters by the trap it sets
/// (`MechanicImpact.trapDepth(of:in:)`), whatever the cost. A narrow neck or a tap can also make a level shorter (`MechanicImpact.isTwoSided`),
/// so for them the change counts either way.
public enum GlassImpact {
    /// Smallest cost that counts as "matters": one move (`MechanicImpact.minimumCost`).
    public static let minimumCost = 1
    /// Cost required in the chapter 5 recipes after the tutorial: the flask changes the
    /// optimal solution by at least two moves.
    public static let strongCost = 2

    /// The narrow-neck, funnel and tap instances of `state` (one per marked flask).
    public static func instances(in state: GameState) -> [MechanicInstance] {
        MechanicImpact.instances(in: state).filter {
            switch $0 {
            case .modifier(_, .narrowNeck), .modifier(_, .funnel), .modifier(_, .tap): return true
            default: return false
            }
        }
    }

    /// Whether every narrow neck, funnel and tap matters (true for a level without one).
    public static func everyGlassMatters(_ state: GameState, minMoves: Int, cost: Int = minimumCost,
                                         limits: SolverLimits = .default) -> Bool {
        instances(in: state).allSatisfy { MechanicImpact.matters($0, in: state, minMoves: minMoves, cost: cost, limits: limits) }
    }
}

/// Whether a frozen layer changes a level (the "must matter" check for D1): the
/// `.modifier(_, .frozen)` case of `MechanicImpact`.
///
/// A frozen layer only takes moves away (it pins layers and shuts its flask for a while; the
/// layers themselves are the same), and the level can't be won before it thaws, so the level
/// without it is never longer: the check is how many moves the ice adds. Removing the
/// instance means the layer starts thawed.
public enum FrozenImpact {
    /// Smallest cost that counts as "matters": one extra move (`MechanicImpact.minimumCost`).
    public static let minimumCost = 1
    /// Cost required in the chapter 6 recipes: the ice forces a detour (or a wait) of at
    /// least two moves, like a strong lock's detour (DECISIONS 104).
    public static let strongCost = 2

    /// The frozen-layer instances of `state` (one per frozen layer).
    public static func instances(in state: GameState) -> [MechanicInstance] {
        MechanicImpact.instances(in: state).filter {
            if case .modifier(_, .frozen) = $0 { return true }
            return false
        }
    }

    /// Whether every frozen layer matters (true for a level without one).
    public static func everyFrozenMatters(_ state: GameState, minMoves: Int, cost: Int = minimumCost,
                                          limits: SolverLimits = .default) -> Bool {
        instances(in: state).allSatisfy { MechanicImpact.matters($0, in: state, minMoves: minMoves, cost: cost, limits: limits) }
    }

    /// Whether `move` only relocates a flask: all of it goes into an empty flask, so the
    /// position is the same with two flasks swapped and the move just spends a turn (a
    /// "wait" while the ice thaws).
    public static func isRelocation(_ move: Move, in state: GameState) -> Bool {
        guard state.bottles.indices.contains(move.from), state.bottles.indices.contains(move.to),
              state.bottles[move.to].isEmpty, let next = state.pouring(move) else { return false }
        return next.bottles[move.from].isEmpty
    }

    /// Whether `state` can be solved in `moves` moves or fewer without a relocation
    /// (`isRelocation`), so the optimal play never needs a pure wait (for a tutorial: a
    /// player who never "parks" a flask still gets every star). With `pouringAboveIce`, the
    /// solution must also pour out of a flask while it holds ice (the potion above the ice
    /// is part of the play, not only a trap). Breadth-first, at most `maxStates` states;
    /// false if the budget runs out.
    public static func solvesWithoutRelocation(_ state: GameState, in moves: Int, pouringAboveIce: Bool = false,
                                               maxStates: Int = 200_000) -> Bool {
        struct Node: Hashable { let key: StateKey; let poured: Bool }
        if state.isSolved { return !pouringAboveIce }
        var seen: Set<Node> = [Node(key: state.canonicalKey, poured: !pouringAboveIce)]
        var frontier = [(state, !pouringAboveIce)]
        for _ in 0..<moves {
            var next: [(GameState, Bool)] = []
            for (current, poured) in frontier {
                for move in current.legalMoves() where !isRelocation(move, in: current) {
                    guard let child = current.pouring(move) else { continue }
                    let childPoured = poured || current.bottles[move.from].holdsIce
                    if child.isSolved {
                        if childPoured { return true }
                        continue
                    }
                    guard seen.insert(Node(key: child.canonicalKey, poured: childPoured)).inserted else { continue }
                    if seen.count > maxStates { return false }
                    next.append((child, childPoured))
                }
            }
            if next.isEmpty { return false }
            frontier = next
        }
        return false
    }

    /// Whether every frozen layer has a layer above it, so the potion above the ice can be
    /// poured (the tutorial shows both halves of the rule: what the ice holds and what
    /// still moves).
    public static func everyIceHasALayerAbove(_ state: GameState) -> Bool {
        state.bottles.allSatisfy { bottle in bottle.frozenLayers.allSatisfy { $0.layer < bottle.layers.count - 1 } }
    }
}

/// Whether a bubbling flask changes a level (the "must matter" check for D2): the
/// `.modifier(_, .bubbling)` case of `MechanicImpact`. Removing the instance means a plain
/// flask with the same layers.
///
/// A rise can bury a color the player wanted on top as well as bring a needed one up for
/// free, so the level without it may be longer or shorter: the change counts either way
/// (`MechanicImpact.isTwoSided`), like a narrow neck or a tap.
public enum BubblingImpact {
    /// Smallest change that counts as "matters": one move (`MechanicImpact.minimumCost`).
    public static let minimumCost = 1
    /// Change required in the chapter 7 recipes: the bubbling changes the optimal solution
    /// by at least two moves (or the level can't be solved without it).
    public static let strongCost = 2

    /// The bubbling instances of `state` (one per bubbling flask).
    public static func instances(in state: GameState) -> [MechanicInstance] {
        MechanicImpact.instances(in: state).filter {
            if case .modifier(_, .bubbling) = $0 { return true }
            return false
        }
    }

    /// Whether every bubbling flask matters (true for a level without one).
    public static func everyBubblingMatters(_ state: GameState, minMoves: Int, cost: Int = minimumCost,
                                            limits: SolverLimits = .default) -> Bool {
        instances(in: state).allSatisfy { MechanicImpact.matters($0, in: state, minMoves: minMoves, cost: cost, limits: limits) }
    }

    /// Whether `state` can be solved in `moves` moves or fewer without a relocation
    /// (`FrozenImpact.isRelocation`: a pure wait), so a player who never parks a flask still
    /// gets every star. With `pouringARisenLayer`, the solution must also pour a layer out of
    /// a bubbling flask right after it rose there (the risen layer still on top, nothing
    /// poured onto it since): the rise is part of the play. Breadth-first over exact states
    /// (bottle indices matter for the "risen" marks), at most `maxStates`; false if the
    /// budget runs out. For tutorial-sized levels.
    public static func solvesWithoutRelocation(_ state: GameState, in moves: Int, pouringARisenLayer: Bool = false,
                                               maxStates: Int = 200_000) -> Bool {
        struct Node: Hashable { let state: GameState; let risen: UInt64; let used: Bool }
        if state.isSolved { return !pouringARisenLayer }
        let start = Node(state: state, risen: 0, used: !pouringARisenLayer)
        var seen: Set<Node> = [start]
        var frontier = [start]
        for _ in 0..<moves {
            var next: [Node] = []
            for node in frontier {
                let current = node.state
                for move in current.legalMoves() where !FrozenImpact.isRelocation(move, in: current) {
                    guard let turn = Rules.resolve(current, afterAction: .pour(move)) else { continue }
                    var risen = node.risen
                    var used = node.used
                    if move.from < 64 && risen & (1 << UInt64(move.from)) != 0 {
                        used = true
                        risen &= ~(1 << UInt64(move.from))
                    }
                    if move.to < 64 { risen &= ~(1 << UInt64(move.to)) }
                    for event in turn.events {
                        if case .bubbled(let b) = event, b < 64 { risen |= 1 << UInt64(b) }
                    }
                    if turn.isWon {
                        if used { return true }
                        continue
                    }
                    let child = Node(state: turn.state, risen: risen, used: used)
                    guard seen.insert(child).inserted else { continue }
                    if seen.count > maxStates { return false }
                    next.append(child)
                }
            }
            if next.isEmpty { return false }
            frontier = next
        }
        return false
    }
}

extension MechanicImpact {
    /// Whether no first move of `state` is a dead end: every legal move leaves a position
    /// the solver can still solve within `limits` (for a tutorial: the obvious first pour
    /// must not lose the recipe).
    public static func everyFirstMoveSolvable(_ state: GameState, limits: SolverLimits = .default) -> Bool {
        state.legalMoves().allSatisfy { move in
            guard let next = state.pouring(move) else { return false }
            if case .solved = Solver().solve(next, limits: limits) { return true }
            return false
        }
    }

    /// The shallowest *trap* `instance` sets in `state`: a position one pour away from a
    /// still-solvable one, that is a dead end with the instance but solvable without it
    /// (the same layers, the instance removed). Returns its depth (moves from the start),
    /// or nil if none was found within the budget: the reachable graph must have at most
    /// `maxStates` states, and at most `maxChecks` dead ends (shallowest first) are
    /// re-solved without the instance, each within `checkLimits`.
    ///
    /// This is how a funnel matters (DECISIONS 150): it never changes the optimal length
    /// (whatever goes into a funnel can always be completed there), but pouring the wrong
    /// potion in at the wrong time can lose a level that a plain flask would have saved.
    public static func trapDepth(of instance: MechanicInstance, in state: GameState, maxStates: Int = 300_000,
                                 maxChecks: Int = 40,
                                 checkLimits: SolverLimits = SolverLimits(maxStates: 200_000)) -> Int? {
        guard let graph = StateGraph.explore(from: state, maxStates: maxStates, keepStates: true) else { return nil }
        let solvable = graph.solvableFlags()
        guard solvable.first == true else { return nil }
        // Depths by BFS over the graph (node 0 is the start).
        var depth = [Int](repeating: -1, count: graph.nodeCount)
        depth[0] = 0
        var queue = [0], head = 0
        var traps: [Int] = []   // dead ends entered from a solvable node, in BFS order
        while head < queue.count {
            let node = queue[head]
            head += 1
            for e in Int(graph.edgeStart[node])..<Int(graph.edgeStart[node + 1]) {
                let child = Int(graph.edges[e])
                guard depth[child] < 0 else { continue }
                depth[child] = depth[node] + 1
                queue.append(child)
                if solvable[node] && !solvable[child] { traps.append(child) }
            }
        }
        for node in traps.prefix(maxChecks) {
            let without = removing(instance, from: graph.states[node])
            if case .solved = Solver().solve(without, limits: checkLimits) { return depth[node] }
        }
        return nil
    }

    /// The shallowest *spill* `instance` sets in `state`: a pour from a still-solvable
    /// position that loses the level, while the same pour from the same position without the
    /// instance doesn't (its result is still solvable). Returns the depth of the position
    /// after the pour (moves from the start), or nil if none was found within the budget
    /// (the reachable graph must have at most `maxStates` states; at most `maxChecks` losing
    /// pours, shallowest first, are re-played and re-solved without the instance, each within
    /// `checkLimits`).
    ///
    /// This is how an overflow pipe matters (DECISIONS 181): it never makes a level shorter
    /// in practice (a pour split between a flask and its pipe is never part of an optimal
    /// solution, see there), but a pour into its flask can spill the rest of a run where the
    /// player can't afford it. Unlike `trapDepth` it compares the *pour* with and without the
    /// instance, because the pipe changes what the pour does, not the position it leaves.
    public static func spillDepth(of instance: MechanicInstance, in state: GameState, maxStates: Int = 300_000,
                                  maxChecks: Int = 40,
                                  checkLimits: SolverLimits = SolverLimits(maxStates: 200_000)) -> Int? {
        guard let graph = StateGraph.explore(from: state, maxStates: maxStates, keepStates: true) else { return nil }
        let solvable = graph.solvableFlags()
        guard solvable.first == true else { return nil }
        var depth = [Int](repeating: -1, count: graph.nodeCount)
        depth[0] = 0
        var queue = [0], head = 0
        var checks = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            let first = Int(graph.edgeStart[node]), last = Int(graph.edgeStart[node + 1])
            // Edges were added in `Solver.candidateMoves` order (every candidate is legal).
            let moves = solvable[node] && first < last ? Solver.candidateMoves(graph.states[node]) : []
            for e in first..<last {
                let child = Int(graph.edges[e])
                if depth[child] < 0 {
                    depth[child] = depth[node] + 1
                    queue.append(child)
                }
                guard solvable[node], !solvable[child], moves.count == last - first else { continue }
                let move = moves[e - first]
                let without = removing(instance, from: graph.states[node])
                // A pour the instance doesn't change leaves the same position either way.
                guard let next = without.pouring(move), next != graph.states[node].pouring(move) else { continue }
                guard checks < maxChecks else { return nil }
                checks += 1
                if case .solved = Solver().solve(next, limits: checkLimits) { return depth[node] + 1 }
            }
        }
        return nil
    }
}

/// Whether a twin chain or an overflow pipe changes a level (the "must matter" check for F1
/// and F2): the `.link(.twins / .overflow)` cases of `MechanicImpact`. Removing the instance
/// means the same flasks without the link.
///
/// Both are two-sided (`MechanicImpact.isTwoSided`): twins add a pour no plain flask can make
/// (a run split in two) and refuse every pour that can't be split; a pipe saves the second
/// pour of a full flask's leftovers but also spills what the player would keep in the source.
public enum LinkImpact {
    /// Smallest change that counts as "matters": one move (`MechanicImpact.minimumCost`).
    public static let minimumCost = 1
    /// Change required in the chapter 8 recipes: the link changes the optimal solution by at
    /// least two moves (or the level can't be solved without it).
    public static let strongCost = 2

    /// The twin and overflow instances of `state` (one per link).
    public static func instances(in state: GameState) -> [MechanicInstance] {
        MechanicImpact.instances(in: state).filter {
            switch $0 {
            case .link(.twins), .link(.overflow): return true
            default: return false
            }
        }
    }

    /// Whether every twin chain and overflow pipe matters (true for a level without one).
    public static func everyLinkMatters(_ state: GameState, minMoves: Int, cost: Int = minimumCost,
                                        limits: SolverLimits = .default) -> Bool {
        instances(in: state).allSatisfy { MechanicImpact.matters($0, in: state, minMoves: minMoves, cost: cost, limits: limits) }
    }

    /// Whether `state` can be solved in `moves` moves or fewer without a relocation
    /// (`FrozenImpact.isRelocation`: a pure wait or park), with every link of the level used
    /// on the way: a pour split between twins, and a pour that ran through each overflow pipe
    /// (for a tutorial: an optimal solution shows the mechanic, and a player who never parks a
    /// flask still gets every star). Breadth-first over exact states (which links were used is
    /// part of the node), at most `maxStates`; false if the budget runs out.
    public static func solvesUsingEveryLink(_ state: GameState, in moves: Int, maxStates: Int = 200_000) -> Bool {
        struct Node: Hashable { let state: GameState; let used: UInt64 }
        let links = state.links
        guard links.count <= 64 else { return false }
        let all: UInt64 = links.isEmpty ? 0 : (links.count == 64 ? ~0 : (1 << UInt64(links.count)) - 1)
        if state.isSolved { return all == 0 }
        let start = Node(state: state, used: 0)
        var seen: Set<Node> = [start]
        var frontier = [start]
        for _ in 0..<moves {
            var next: [Node] = []
            for node in frontier {
                let current = node.state
                for move in current.legalMoves() where !FrozenImpact.isRelocation(move, in: current) {
                    guard let turn = Rules.resolve(current, afterAction: .pour(move)), let pour = turn.pour else { continue }
                    var used = node.used
                    if !pour.shares.isEmpty, let link = current.link(at: move.to), let i = links.firstIndex(of: link) {
                        used |= 1 << UInt64(i)
                    }
                    if turn.isWon {
                        if used == all { return true }
                        continue
                    }
                    let child = Node(state: turn.state, used: used)
                    guard seen.insert(child).inserted else { continue }
                    if seen.count > maxStates { return false }
                    next.append(child)
                }
            }
            if next.isEmpty { return false }
            frontier = next
        }
        return false
    }
}
