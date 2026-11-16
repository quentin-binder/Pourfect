// All game rules live in this file. New mechanics add a case to the hook switches
// here (`apply(_:as:to:)`, `blocksSolved(_:)`, the steps of `resolve`) rather than
// scattering checks across the codebase. See Mechanics.swift for the types.

/// A player action. Today the only one is a pour; items (R5+) become further cases.
public enum Action: Hashable, Sendable {
    case pour(Move)
}

/// The result of one resolved turn: the new state, whether its goal is met, and what
/// the player's pour did (for the app's animation).
public struct Turn: Hashable, Sendable {
    public var state: GameState
    public var isWon: Bool
    /// The pour of step 1 as applied. nil only for actions that aren't pours (none yet).
    public var pour: PourEvent?
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
    /// R5 plan: `.frozen(i, _)` source → `limit` = `source.layers.count - 1 - i` layers
    /// above it (veto at 0; with a tap: decided with D1, DECISIONS 122). `.cauldron`
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
            plan.limit = 1
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
        case (.frozen, _), (.bubbling, _), (.cauldron, _):
            // Not implemented yet: levels using them fail validation and the solver refuses them.
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
    ///    conveyor (D3). None is implemented yet.
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
        if applyTimedEffects(&next) { applyImmediateEffects(&next, opened: nil) }
        // 6. Goal.
        return Turn(state: next, isWon: isWon(next), pour: event)
    }

    /// The flask modifier that refuses `move`, for the app's feedback (e.g. "this essence
    /// flask only takes its own color", "a funnel never pours out", "a tap never fills"):
    /// the bottle and the first modifier of the pipeline
    /// (source side, then target side) that vetoes the pour, provided the pour would be legal
    /// without that modifier (so the modifier is *the* reason). nil if the move is legal, or
    /// illegal for a base reason too (same flask, empty source, full target, colors differ):
    /// a full essence flask refuses every pour for being full, not for its rune.
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
                return legalWithout ? (bottle, modifier) : nil
            }
        }
        return nil
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

    /// Step 4 of `resolve`. Returns whether anything changed. Each timed mechanic
    /// becomes one step here, run only when the state carries its modifier.
    static func applyTimedEffects(_ state: inout GameState) -> Bool {
        false
    }

    // MARK: - Solved / goal

    /// Whether `modifier` keeps its flask from counting as solved. A seal does.
    static func blocksSolved(_ modifier: BottleModifier) -> Bool {
        switch modifier {
        case .sealed: return true
        case .essence, .narrowNeck, .funnel, .tap, .frozen, .bubbling, .cauldron: return false
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
