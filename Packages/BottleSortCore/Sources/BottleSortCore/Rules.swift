// All game rules live in this file. New mechanics add a case to the hook switches
// here (`apply(_:as:to:)`, `blocksSolved(_:)`, the steps of `resolve`) rather than
// scattering checks across the codebase. See Mechanics.swift for the types.

/// A player action. Today the only one is a pour; items (R5+) become further cases.
public enum Action: Hashable, Sendable {
    case pour(Move)
}

/// The result of one resolved turn: the new state, whether its goal is met, what the
/// player's pour did and what happened on its own afterwards (for the app's animation).
public struct Turn: Hashable, Sendable {
    public var state: GameState
    public var isWon: Bool
    /// The pour of step 1 as applied. nil only for actions that aren't pours (none yet).
    public var pour: PourEvent?
    /// The automatic effects of steps 2–5 that the app shows *after* the pour lands, in
    /// the order they were applied (e.g. a frozen layer thawing). Empty for most turns
    /// (no allocation). Unseal is part of `pour` (`openedSeal`), not repeated here.
    public var events: [TurnEvent] = []
}

/// An automatic effect of a turn (a timed or immediate rule, not the player's pour).
/// Mixing (E1) and switches (A3) add their cases here.
public enum TurnEvent: Hashable, Sendable {
    /// D1: the frozen layer `layer` (0 = bottom) of bottle `bottle` thawed (its counter
    /// reached 0) and is a normal layer from now on.
    case thawed(bottle: Int, layer: Int)
    /// D2: bubbling flask `bottle` bubbled up: its bottom layer rose to the top (the stack
    /// above slid down by one). Reported only when that changed the layers (not for an
    /// empty flask, one layer, or one color); the phase resets either way. The layers
    /// before the rise are `Rules.sunk(_:)` of the flask's layers after the turn.
    case bubbled(bottle: Int)
}

/// What one pour moved, as `Rules.resolve` applied it: the app animates from this instead
/// of diffing states, because a tap pours from the bottom of its flask (DECISIONS 130 b, 146).
public struct PourEvent: Hashable, Sendable {
    public var move: Move
    /// The layer that moved (all `amount` moved layers are equal: a run, or one key).
    public var layer: Layer
    /// How many layers left the source.
    public var amount: Int
    /// The layers left from the source's bottom (a tap, C4): the stack above slides down.
    /// Otherwise they left from the top.
    public var fromBottom: Bool
    /// The key opened the target's seal (A1): it was used up and never lands in the target.
    public var openedSeal: KeyID?

    public init(move: Move, layer: Layer, amount: Int, fromBottom: Bool = false, openedSeal: KeyID? = nil) {
        self.move = move
        self.layer = layer
        self.amount = amount
        self.fromBottom = fromBottom
        self.openedSeal = openedSeal
    }

    /// Indices (0 = bottom) the moved layers occupied in the source before the pour.
    public func sourceRange(sourceCountBefore count: Int) -> Range<Int> {
        fromBottom ? 0..<amount : (count - amount)..<count
    }
}

/// Which end of a pour a modifier sits on.
public enum PourSide: Sendable {
    case source
    case target
}

/// One pour being worked out between two bottles. Modifier hooks may veto it or change
/// it (`Rules.apply(_:as:to:)`) before the base rule moves the layers.
public struct PourPlan: Hashable, Sendable {
    /// The layer that leaves the source first: its top layer, or its bottom layer when
    /// `fromBottom` is set.
    public var layer: Layer
    /// Set by a source's tap (C4): the source pours its bottom run instead of its top run.
    public var fromBottom = false
    /// Most layers that may move, as limited by modifiers (e.g. a narrow neck: 1).
    /// The base rule also limits it by the movable run and the target's free space.
    public var limit: Int = .max
    /// Set by a target's seal when `layer` is its key: the key is used up and the seal
    /// opens (immediate effect), so it needs no free slot.
    public var opensSeal: KeyID?
    /// How many layers leave the source; set last, by the base rule (1 for a key).
    public var amount: Int = 0
}

public enum Rules {
    // MARK: - Pours between two bottles

    /// What a pour moves between two bottles, before any immediate effect.
    struct Transfer {
        var source: Bottle
        var target: Bottle
        /// A key that was poured into the target's seal (opened in step 2 of `resolve`).
        var openedSeal: KeyID?
    }

    /// The modifier pipeline: the one place where each modifier vetoes (returns false)
    /// or changes a pour. Source modifiers run first, then target modifiers. A hook sees
    /// both bottles of the pour (`source`, `target`, before it) and the plan so far; the
    /// base rule then reads the plan (`layer`, `limit`, `opensSeal`), not the bottles' tops.
    ///
    /// - `.sealed(k)`: a sealed flask can't be poured from. As a target it accepts only
    ///   key `k`, which opens it (needs no free slot); nothing else goes in.
    /// - `.essence(c)` (C1): as a target it receives only color `c`: any other color and
    ///   any key is vetoed, except the key of its own seal, which the seal (earlier in
    ///   the canonical order) has already accepted. As a source it changes nothing: it
    ///   may start with other colors, which are poured out normally.
    ///
    /// - `.narrowNeck` (C2): on either side, `limit = 1`: exactly one layer moves, however
    ///   long the run and however much room the target has.
    /// - `.funnel` (C4): as a source it vetoes every pour; as a target it changes nothing.
    /// - `.tap` (C4): as a source the pour starts at the *bottom*: `layer` becomes the
    ///   bottom layer and `fromBottom` is set, so the base rule moves the bottom run (a key
    ///   alone) and `transfer` takes it from the bottom. Target hooks run after source
    ///   hooks, so they judge the bottom layer. As a target it vetoes everything, keys too.
    ///
    /// - `.frozen(i, _)` (D1): as a source only the layers *above* layer `i` may move:
    ///   `limit` = `source.layers.count - 1 - i` (veto at 0: the top layer is frozen). A tap
    ///   (which runs first) is vetoed outright: the frozen layer pins everything below it,
    ///   the bottom included. As a target it vetoes every pour, keys too, while `i` is the
    ///   top layer (ice on top seals the flask); a frozen layer lower down changes nothing.
    ///   Frozen layers never move, so the index stays valid (pours only change layers
    ///   above it, a tap can't pour); the counter is the timed step `thaw`.
    /// - `.bubbling` (D2): changes no pour on either side (a bubbling flask pours and
    ///   receives like a plain one); its rise is the timed step `bubble`.
    ///
    /// R5 plan: `.cauldron`
    /// (target → accept a recipe partner on top: an `acceptsMismatch` flag; mixing itself
    /// is an immediate effect). Links (twins, overflow into a full flask, gates) act on
    /// more than two bottles; they belong in `actionPlan(for:in:)` and `Transfer` becomes a
    /// list of bottle changes then (DECISIONS 130).
    public static func apply(_ modifier: BottleModifier, as side: PourSide, to plan: inout PourPlan,
                             source: Bottle, target: Bottle) -> Bool {
        switch (modifier, side) {
        case (.sealed, .source):
            return false
        case (.sealed(let key), .target):
            guard plan.layer == .key(key) else { return false }
            plan.opensSeal = key
            return true
        case (.essence, .source):
            return true
        case (.essence(let color), .target):
            // A seal runs first (canonical order): its own key opens it and needs no slot.
            // Otherwise only the essence color goes in (no other color, no key).
            return plan.opensSeal != nil || plan.layer == .color(color)
        case (.narrowNeck, _):
            plan.limit = min(plan.limit, 1)
            return true
        case (.funnel, .source):
            return false
        case (.funnel, .target):
            return true
        case (.tap, .source):
            guard let bottom = source.layers.first else { return false }
            plan.layer = bottom
            plan.fromBottom = true
            return true
        case (.tap, .target):
            return false
        case (.frozen(let layer, _), .source):
            if plan.fromBottom { return false }   // a tap: the bottom is pinned
            let above = source.layers.count - 1 - layer
            guard above > 0 else { return false }
            plan.limit = min(plan.limit, above)
            return true
        case (.frozen(let layer, _), .target):
            return layer != target.layers.count - 1
        case (.bubbling, _):
            // D2 changes no pour: its effect is the timed step `bubble` of `resolve`.
            return true
        case (.cauldron, _):
            // Not implemented yet: levels using it fail validation and the solver refuses them.
            return true
        }
    }

    /// Runs `apply` for every modifier of the bottle on `side` (none for a plain flask).
    @inline(__always)
    static func applyModifiers(as side: PourSide, to plan: inout PourPlan, source: Bottle, target: Bottle) -> Bool {
        switch (side == .source ? source.storage : target.storage) {
        case .none:
            return true
        case .sealed(let key):
            return apply(.sealed(key), as: side, to: &plan, source: source, target: target)
        case .list(let list):
            for modifier in list where !apply(modifier, as: side, to: &plan, source: source, target: target) {
                return false
            }
            return true
        }
    }

    /// Step 1 of a turn for a pour from `source` into `target`, or nil if it's illegal.
    ///
    /// - Color top run (bottom run from a tap): moves onto an empty or same-colored target
    ///   with free space; as many layers as fit (partial pours allowed), at most `limit`.
    /// - Key top layer: moves alone, only into the flask sealed by that key (see `apply`).
    /// - Nothing can be poured onto a key (a key top never matches a color).
    static func transfer(from source: Bottle, to target: Bottle) -> Transfer? {
        guard let plan = plan(from: source, to: target) else { return nil }
        return transfer(plan, from: source, to: target)
    }

    /// Carries out a finished plan (from `plan(from:to:)`) between its two bottles.
    @inline(__always)
    static func transfer(_ plan: PourPlan, from source: Bottle, to target: Bottle) -> Transfer {
        var newSource = source
        if plan.fromBottom {
            newSource.layers.removeFirst(plan.amount)
        } else {
            newSource.layers.removeLast(plan.amount)
        }
        if let key = plan.opensSeal {
            return Transfer(source: newSource, target: target, openedSeal: key)
        }
        var newTarget = target
        // The moved layers are a run of `plan.layer` (or one key), whichever end they left.
        newTarget.layers.append(contentsOf: repeatElement(plan.layer, count: plan.amount))
        return Transfer(source: newSource, target: newTarget, openedSeal: nil)
    }

    /// The legality half of `transfer`: the finished plan (with `amount`), or nil if the
    /// pour is illegal. Builds no bottles, so legality checks stay cheap.
    @inline(__always)
    static func plan(from source: Bottle, to target: Bottle) -> PourPlan? {
        guard let top = source.topLayer else { return nil }
        var plan = PourPlan(layer: top)
        guard applyModifiers(as: .source, to: &plan, source: source, target: target),
              applyModifiers(as: .target, to: &plan, source: source, target: target) else { return nil }
        if plan.opensSeal != nil {
            plan.amount = 1
            return plan
        }
        // Base rule, on the plan's layer. A key only ever goes into its own seal (above).
        guard !plan.layer.isKey else { return nil }
        guard target.freeSpace > 0 else { return nil }
        if let targetTop = target.topLayer, targetTop != plan.layer { return nil }
        let run = plan.fromBottom ? movableBottomRunCount(source) : movableRunCount(source)
        plan.amount = min(min(run, target.freeSpace), plan.limit)
        return plan.amount > 0 ? plan : nil
    }

    /// Step 1 of `resolve` for a pour: the finished plan for `move` in `state`, or nil if
    /// the move is illegal. This is the single legality check: `resolve` and `isLegal`
    /// (hence `canPour` and `legalMoves`) both use it, so they can't disagree. R5 links
    /// that veto or extend a pour (twins, overflow, gates) are checked here.
    @inline(__always)
    static func actionPlan(for move: Move, in state: GameState) -> PourPlan? {
        guard move.from != move.to,
              state.bottles.indices.contains(move.from),
              state.bottles.indices.contains(move.to) else { return nil }
        return plan(from: state.bottles[move.from], to: state.bottles[move.to])
    }

    /// The source and target bottles after pouring `source` into `target`, or nil if
    /// the pour is illegal: the two-bottle view of a turn (step 1 plus the immediate
    /// effects on these two bottles). Links and timed effects need the whole state, see
    /// `resolve(_:afterAction:)`; for a state without them both agree exactly.
    public static func pour(from source: Bottle, to target: Bottle) -> (source: Bottle, target: Bottle)? {
        guard let t = transfer(from: source, to: target) else { return nil }
        var newTarget = t.target
        if let key = t.openedSeal { unseal(&newTarget, key: key) }
        return (t.source, newTarget)
    }

    /// How many layers leave `source` when pouring into `target` (0 = illegal).
    /// Derived from `pour(from:to:)`; for a key this is 1.
    public static func pourAmount(from source: Bottle, to target: Bottle) -> Int {
        guard let result = pour(from: source, to: target) else { return 0 }
        return source.layers.count - result.source.layers.count
    }

    /// Number of layers at the top of `bottle` that move together in one pour.
    /// A key never forms a run: it always moves alone.
    public static func movableRunCount(_ bottle: Bottle) -> Int {
        guard let top = bottle.topLayer else { return 0 }
        if top.isKey { return 1 }
        return bottle.topRunCount
    }

    /// The same at the bottom of `bottle` (what a tap pours): a key alone, else the bottom run.
    public static func movableBottomRunCount(_ bottle: Bottle) -> Int {
        guard let bottom = bottle.layers.first else { return 0 }
        if bottom.isKey { return 1 }
        return bottle.bottomRunCount
    }

    /// What a pour *out of* `bottle` would take, whatever the target (for the app: which
    /// layers to lift or highlight, where the stream starts): the layer indices (0 = bottom)
    /// of the layers that leave if the target has room, and whether they leave from the
    /// bottom (a tap). nil if the flask can't be poured from at all (empty, sealed, a
    /// funnel). A narrow neck gives one layer; a target may still take fewer (free space).
    public static func outlet(of bottle: Bottle) -> (layers: Range<Int>, fromBottom: Bool)? {
        guard let top = bottle.topLayer else { return nil }
        var plan = PourPlan(layer: top)
        guard applyModifiers(as: .source, to: &plan, source: bottle, target: Bottle(capacity: 0)) else { return nil }
        let run = plan.fromBottom ? movableBottomRunCount(bottle) : movableRunCount(bottle)
        let amount = min(run, plan.limit)
        let count = bottle.layers.count
        return (plan.fromBottom ? 0..<amount : (count - amount)..<count, plan.fromBottom)
    }

    /// Why nothing can be poured out of `bottle`, whatever the target (for the app's
    /// refusal when a flask can't be picked up): the first source-side modifier of the
    /// pipeline that vetoes, in the order `outlet` runs them. A seal comes before ice, so a
    /// sealed flask with a frozen top is refused by its seal (it stays shut after the thaw).
    /// nil if the flask is empty or something can leave it (`outlet` is non-nil).
    public static func outletBlocker(of bottle: Bottle) -> BottleModifier? {
        guard let top = bottle.topLayer else { return nil }
        var plan = PourPlan(layer: top)
        let target = Bottle(capacity: 0)
        for modifier in bottle.modifiers where !apply(modifier, as: .source, to: &plan, source: bottle, target: target) {
            return modifier
        }
        return nil
    }

    // MARK: - Turn order (MECHANICS.md §4)

    /// Applies a player action and then every rule that follows it, in the fixed order
    /// of MECHANICS.md §4. This is the only place that order is defined; the game
    /// (`GameState.pouring`), the solver and the generator all go through it.
    ///
    /// 1. The action (a pour, from the top or, through a tap, from the bottom; R5: twins /
    ///    overflow extend it here). The turn reports it as a `PourEvent`.
    /// 2. Immediate effects: unseal (A1). R5: mixing (E1), switch gates (A3). Murky
    ///    reveals (B1) are display state in `GameSession`.
    /// 3. `moveCount += 1`, only if the state stores a move counter, and only up to
    ///    `moveCountLimit` (a counter past every limit a rule reads is one dead value, so
    ///    the state graph stays finite).
    /// 4. Timed effects: corks (A2) → thaw (D1) → bubbling (D2) → evaporation (D4) →
    ///    conveyor (D3). Thaw is implemented: every frozen layer's counter goes down by 1,
    ///    and at 0 the layer thaws (`TurnEvent.thawed`). Bubbling is implemented: every
    ///    bubbling flask's phase goes up by 1, and when it reaches the period the bottom
    ///    layer rises to the top and the phase resets (`TurnEvent.bubbled`). Only player
    ///    actions count: the counters tick once per turn, after the pour.
    /// 5. Immediate effects again if a timed effect changed anything.
    /// 6. Goal check.
    ///
    /// Returns nil if the action is illegal.
    public static func resolve(_ state: GameState, afterAction action: Action) -> Turn? {
        var next = state
        // 1. The player's action (`actionPlan` is also what `isLegal` checks).
        var opened: (bottle: Int, key: KeyID)?
        let event: PourEvent
        switch action {
        case .pour(let move):
            guard let plan = actionPlan(for: move, in: state) else { return nil }
            let t = transfer(plan, from: state.bottles[move.from], to: state.bottles[move.to])
            next.bottles[move.from] = t.source
            next.bottles[move.to] = t.target
            if let key = t.openedSeal { opened = (move.to, key) }
            event = PourEvent(move: move, layer: plan.layer, amount: plan.amount, fromBottom: plan.fromBottom,
                              openedSeal: plan.opensSeal)
        }
        // 2. Immediate effects (unseal, then everything that follows from the state).
        applyImmediateEffects(&next, opened: opened)
        // 3. Move counter.
        if let n = next.moveCount, n < moveCountLimit(next) { next.moveCount = n + 1 }
        // 4. + 5. Timed effects, then immediate effects again.
        var events: [TurnEvent] = []
        if applyTimedEffects(&next, events: &events) { applyImmediateEffects(&next, opened: nil) }
        // 6. Goal.
        return Turn(state: next, isWon: isWon(next), pour: event, events: events)
    }

    /// The flask modifier that refuses `move`, for the app's feedback (e.g. "this essence
    /// flask only takes its own color", "a funnel never pours out", "a tap never fills"):
    /// the bottle and the first modifier of the pipeline
    /// (source side, then target side) that vetoes the pour, provided the pour would be legal
    /// without that modifier (so the modifier is *the* reason). nil if the move is legal, or
    /// illegal for a base reason too (same flask, empty source, full target, colors differ):
    /// a full essence flask refuses every pour for being full, not for its rune.
    /// Exception: a modifier that shuts its side for good (`closesSide`: a tap never
    /// receives, a funnel never pours) is always the reason, even when the base rule would
    /// also refuse; a full tap flask is still "a tap never fills", not "it is full".
    public static func refusal(of move: Move, in state: GameState) -> (bottle: Int, modifier: BottleModifier)? {
        guard move.from != move.to, state.bottles.indices.contains(move.from), state.bottles.indices.contains(move.to),
              let top = state.bottles[move.from].topLayer else { return nil }
        let source = state.bottles[move.from], target = state.bottles[move.to]
        var plan = PourPlan(layer: top)
        for (side, bottle) in [(PourSide.source, move.from), (.target, move.to)] {
            for modifier in state.bottles[bottle].modifiers
            where !apply(modifier, as: side, to: &plan, source: source, target: target) {
                var without = state.bottles[bottle]
                without.modifiers.removeAll { $0 == modifier }
                let legalWithout = side == .source ? Self.plan(from: without, to: target) != nil
                                                   : Self.plan(from: source, to: without) != nil
                return legalWithout || closesSide(modifier, side) ? (bottle, modifier) : nil
            }
        }
        return nil
    }

    /// Whether `modifier`, when it refuses a pour on `side`, refuses it whatever the other
    /// flask holds, so it is the reason even when the base rule refuses too: a funnel never
    /// pours out, a tap never receives, and a frozen layer only refuses when its own flask
    /// is shut (its top layer is frozen, or a tap would pour from under the ice).
    static func closesSide(_ modifier: BottleModifier, _ side: PourSide) -> Bool {
        switch (modifier, side) {
        case (.funnel, .source), (.tap, .target), (.frozen, _): return true
        default: return false
        }
    }

    /// Whether `move` is legal in `state`: step 1 of `resolve` succeeds (same check).
    public static func isLegal(_ move: Move, in state: GameState) -> Bool {
        actionPlan(for: move, in: state) != nil
    }

    /// The value at which `GameState.moveCount` stops counting: one past the largest
    /// count any rule of `state` distinguishes. Rescue (R7): `withinMoves + 1` (every
    /// count beyond means "too late"). With no rule reading the counter it is 0, so a
    /// stored counter never changes. A new rule that reads the counter (corks, A2)
    /// raises this to its own bound; an unbounded counter would make every position
    /// reached at a different depth a new state, so the solver could never prove a
    /// level unsolvable.
    public static func moveCountLimit(_ state: GameState) -> Int {
        switch state.goal {
        case .rescue(let n): return n < Int.max ? n + 1 : n
        case .standard, .order, .pattern: return 0
        }
    }

    /// Unseal (A1): the key poured into a seal opens it.
    static func unseal(_ bottle: inout Bottle, key: KeyID) {
        if case .sealed(key) = bottle.storage {
            bottle.storage = .none
        } else {
            bottle.modifiers.removeAll { $0 == .sealed(key) }
        }
    }

    /// Immediate effects, steps 2 and 5 of `resolve` (both run this same function, so an
    /// effect added here applies after every pour, not only after timed effects).
    /// Unseal (A1) is driven by the pour (`opened`: the bottle and the key poured into
    /// its seal; nil in step 5). R5: mixing (E1) and switch gates (A3) go after it.
    @inline(__always)
    static func applyImmediateEffects(_ state: inout GameState, opened: (bottle: Int, key: KeyID)?) {
        if let opened { unseal(&state.bottles[opened.bottle], key: opened.key) }
    }

    /// Step 4 of `resolve`. Returns whether anything changed, and appends what the app
    /// shows to `events`. Each timed mechanic becomes one step here, run only on flasks
    /// that carry its modifier (a plain or sealed flask is skipped by one switch).
    ///
    /// 1. Thaw (D1): every `.frozen(layer:turns:)` counts down by 1; at 0 the modifier is
    ///    removed (the layer is a normal layer from then on) and `.thawed` is reported.
    /// 2. Bubbling (D2), after every thaw: every `.bubbling(every:phase:)` advances its
    ///    phase; at `every` the flask's bottom layer rises to the top and the phase resets
    ///    to 0 (`bubble`).
    @inline(__always)
    static func applyTimedEffects(_ state: inout GameState, events: inout [TurnEvent]) -> Bool {
        var changed = false
        var bubbling = false
        for i in state.bottles.indices {
            guard case .list(let list) = state.bottles[i].storage else { continue }
            var frozen = false
            for modifier in list {
                switch modifier {
                case .frozen: frozen = true
                case .bubbling: bubbling = true
                default: break
                }
            }
            if frozen {
                thaw(&state.bottles[i], list: list, bottle: i, events: &events)
                changed = true
            }
        }
        if bubbling {
            for i in state.bottles.indices {
                guard case .list(let list) = state.bottles[i].storage,
                      list.contains(where: { if case .bubbling = $0 { return true } else { return false } }) else { continue }
                bubble(&state.bottles[i], list: list, bottle: i, events: &events)
            }
            changed = true
        }
        return changed
    }

    /// The bubbling step for one flask whose modifiers are `list`: its phase goes up by 1;
    /// when it reaches the period, the bottom layer rises to the top (`bubbledUp`) and the
    /// phase is 0 again. A flask whose rise changes nothing (empty, one layer, one color)
    /// still counts its phase but reports no event. A flask that holds ice never rotates
    /// (its frozen indices must stay valid; `validate()` rejects ice on a bubbling flask
    /// anyway). Replacing the phase keeps the canonical order when the flask has one
    /// bubbling modifier (the only valid case); otherwise the list is normalized again.
    static func bubble(_ bottle: inout Bottle, list: [BottleModifier], bottle index: Int, events: inout [TurnEvent]) {
        var updated = list
        var count = 0
        var rises = false
        for (k, modifier) in list.enumerated() {
            guard case let .bubbling(every, phase) = modifier else { continue }
            count += 1
            let next = phase + 1
            if next >= every {
                updated[k] = .bubbling(every: every, phase: 0)
                rises = true
            } else {
                updated[k] = .bubbling(every: every, phase: next)
            }
        }
        if rises && !bottle.holdsIce {
            let before = bottle.layers
            bottle.layers = bubbledUp(before)
            if bottle.layers != before { events.append(.bubbled(bottle: index)) }
        }
        bottle.storage = count == 1 ? .list(updated) : Bottle.ModifierStorage(Bottle.normalize(updated))
    }

    /// D2: `layers` (bottom → top) after one rise: the bottom layer moves to the top.
    public static func bubbledUp<T>(_ layers: [T]) -> [T] {
        guard layers.count > 1 else { return layers }
        var result = layers
        result.append(result.removeFirst())
        return result
    }

    /// D2: the inverse of `bubbledUp`: the layers before a rise, given the layers after it
    /// (the top layer goes back to the bottom). For the app's bubble-up animation, which
    /// starts from the flask as the pour left it.
    public static func sunk<T>(_ layers: [T]) -> [T] {
        guard layers.count > 1 else { return layers }
        var result = layers
        result.insert(result.removeLast(), at: 0)
        return result
    }

    /// The bubbling periods a level may use (MECHANICS.md D2; `validate()`), and the most
    /// bubbling flasks per level (their phases multiply the states the solver sees).
    public static let bubblingPeriods = 2...5
    public static let maxBubblingFlasks = 2

    /// The thaw step for one flask whose modifiers are `list`. Counting down keeps the
    /// canonical order (frozen modifiers are ordered by layer first, and a flask never has
    /// two on one layer), so the list is stored as is, without re-sorting.
    static func thaw(_ bottle: inout Bottle, list: [BottleModifier], bottle index: Int, events: inout [TurnEvent]) {
        var kept: [BottleModifier] = []
        kept.reserveCapacity(list.count)
        for modifier in list {
            guard case let .frozen(layer, turns) = modifier else {
                kept.append(modifier)
                continue
            }
            if turns > 1 {
                kept.append(.frozen(layer: layer, turns: turns - 1))
            } else {
                events.append(.thawed(bottle: index, layer: layer))
            }
        }
        bottle.storage = Bottle.ModifierStorage(kept)
    }

    /// Most frozen layers a level may hold, and the largest thaw counter (MECHANICS.md D1:
    /// counters multiply the states the solver sees, so both are capped; `validate()`).
    public static let maxFrozenLayers = 2
    public static let maxThawTurns = 5

    // MARK: - Solved / goal

    /// Whether `modifier` keeps its flask from counting as solved. A seal does, and so does
    /// a frozen layer (D1): a recipe isn't won while ice remains, even if its flask is
    /// full of one color; the player makes another move and it thaws. Bubbling (D2) doesn't:
    /// a full one-color flask stays the same when it bubbles.
    static func blocksSolved(_ modifier: BottleModifier) -> Bool {
        switch modifier {
        case .sealed, .frozen: return true
        case .essence, .narrowNeck, .funnel, .tap, .bubbling, .cauldron: return false
        }
    }

    /// A bottle is solved when it is unsealed and empty, or full with a single
    /// color. A bottle that is sealed or contains a key is never solved.
    public static func isSolved(_ bottle: Bottle) -> Bool {
        switch bottle.storage {
        case .none: break
        case .sealed: return false
        case .list(let list): if list.contains(where: blocksSolved) { return false }
        }
        guard let first = bottle.layers.first else { return true }
        guard bottle.isFull, first.colorID != nil else { return false }
        return bottle.layers.allSatisfy { $0 == first }
    }

    /// Whether `state` meets `goal`. Only `.standard` is implemented: every bottle is
    /// solved, which implies no key layers remain and no bottle is sealed.
    public static func isMet(_ goal: Goal, by state: GameState) -> Bool {
        switch goal {
        case .standard: return state.bottles.allSatisfy(isSolved)
        case .order, .pattern, .rescue: return false   // R7
        }
    }

    /// The puzzle is won when its goal is met.
    public static func isWon(_ state: GameState) -> Bool {
        state.hasStandardGoal ? state.bottles.allSatisfy(isSolved) : isMet(state.goal, by: state)
    }

    /// A bottle is *completed* when it is solved and not empty: full with a single color.
    public static func isCompleted(_ bottle: Bottle) -> Bool {
        !bottle.isEmpty && isSolved(bottle)
    }

    /// Indices (ascending) of bottles that are completed in `after` but weren't in `before`,
    /// e.g. the target of a pour that filled it with its last matching layer. Bottles that
    /// were already completed, or that don't exist in `before`, are not reported.
    public static func completedBottles(before: GameState, after: GameState) -> [Int] {
        after.bottles.indices.filter { i in
            isCompleted(after.bottles[i])
                && !(before.bottles.indices.contains(i) && isCompleted(before.bottles[i]))
        }
    }

    // MARK: - Supported mechanics

    /// Whether every mechanic in `state` is implemented by these rules. Levels that use
    /// one that isn't fail validation, and the solver returns `.unsupportedState`.
    public static func isSupported(_ state: GameState) -> Bool {
        state.goal.isImplemented
            && state.links.allSatisfy(\.isImplemented)
            && state.bottles.allSatisfy { $0.modifiers.allSatisfy(\.isImplemented) }
    }
}

extension GameState {
    public func canPour(_ move: Move) -> Bool {
        Rules.isLegal(move, in: self)
    }

    /// The state after `move` (a fully resolved turn), or nil if the move is illegal.
    public func pouring(_ move: Move) -> GameState? {
        Rules.resolve(self, afterAction: .pour(move))?.state
    }

    public func legalMoves() -> [Move] {
        var moves: [Move] = []
        for from in bottles.indices {
            for to in bottles.indices where canPour(Move(from: from, to: to)) {
                moves.append(Move(from: from, to: to))
            }
        }
        return moves
    }

    /// Whether the goal is met (`Rules.isWon`).
    public var isSolved: Bool { Rules.isWon(self) }
}
