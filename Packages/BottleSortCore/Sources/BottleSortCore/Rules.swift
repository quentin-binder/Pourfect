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
/// Switches (A3) add their cases here.
public enum TurnEvent: Hashable, Sendable {
    /// E1: the pour into cauldron `bottle` mixed: `pairs` of the poured layers (the pour's
    /// `layer`) each combined with one layer of the run they landed on into two layers of
    /// `recipe.result` (`Rules.mixed`). Always the first event of its turn (mixing is part
    /// of the pour, before every timed effect). The cauldron as the pour left it, before it
    /// mixed, is `Rules.beforeMixing(_:poured:amount:recipe:pairs:)` of its layers after the
    /// turn (for the app's swirl from the unmixed stack to the result).
    case mixed(bottle: Int, recipe: Recipe, pairs: Int)
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
    /// Where else the poured layers landed, besides `move.to` (F1, F2): the twin of the
    /// target (`.twin`: half of the pour), or the far end of the target's overflow pipe
    /// (`.overflow`: what didn't fit into the target). Empty for a pour between two bottles.
    public var shares: [PourShare]

    public init(move: Move, layer: Layer, amount: Int, fromBottom: Bool = false, openedSeal: KeyID? = nil,
                shares: [PourShare] = []) {
        self.move = move
        self.layer = layer
        self.amount = amount
        self.fromBottom = fromBottom
        self.openedSeal = openedSeal
        self.shares = shares
    }

    /// Indices (0 = bottom) the moved layers occupied in the source before the pour.
    public func sourceRange(sourceCountBefore count: Int) -> Range<Int> {
        fromBottom ? 0..<amount : (count - amount)..<count
    }

    /// How many of the `amount` layers landed in `move.to` (all of them, unless some went on
    /// to a twin or through an overflow pipe; 0 when an overflow pour found the target full).
    /// A key that opened a seal is counted here although it never lands (`openedSeal`).
    public var targetAmount: Int { amount - shares.reduce(0) { $0 + $1.amount } }

    /// Every bottle the pour filled and how many layers landed there: the target first (if
    /// anything landed there), then the shares in order. Empty when a key opened a seal.
    public var landings: [(bottle: Int, amount: Int)] {
        guard openedSeal == nil else { return [] }
        let direct = targetAmount
        return (direct > 0 ? [(move.to, direct)] : []) + shares.map { ($0.bottle, $0.amount) }
    }
}

/// F1 / F2: part of a pour that landed in a bottle other than the one poured into.
public struct PourShare: Hashable, Sendable {
    public enum Route: Hashable, Sendable {
        /// The twin of the target (F1): the pour was split evenly between the two.
        case twin
        /// Through the target's overflow pipe (F2): what didn't fit into the full target.
        case overflow
    }
    /// The bottle the layers landed in.
    public var bottle: Int
    /// How many layers landed there.
    public var amount: Int
    public var route: Route

    public init(bottle: Int, amount: Int, route: Route) {
        self.bottle = bottle
        self.amount = amount
        self.route = route
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
    /// Bit 0: `fromBottom`. Bits 2...7: E1 mixing, the recipe index + 1 (0 = no mixing).
    /// One byte where `fromBottom` used to be a `Bool`: any extra stored field made the plan
    /// bigger, and the solver ~10 % slower (it builds a plan per candidate pour; DECISIONS 197).
    var flags: UInt8 = 0
    /// Set by a source's tap (C4): the source pours its bottom run instead of its top run.
    public var fromBottom: Bool {
        get { flags & 1 != 0 }
        set { flags = newValue ? flags | 1 : flags & ~1 }
    }
    /// Set by a target cauldron (E1) when `layer` and the target's top layer are the two
    /// ingredients of one of its recipes: that recipe's index in the target's `recipes`
    /// (nil = no mixing). The base rule then accepts the mismatched color and the pour mixes
    /// (`Rules.mixed`); how many pairs is `min(amount, the target's top run)`.
    public var mixIndex: Int? {
        get { flags >> 2 == 0 ? nil : Int(flags >> 2) - 1 }
        set { flags = flags & 3 | UInt8(truncatingIfNeeded: newValue.map { min($0, 62) + 1 } ?? 0) << 2 }
    }
    /// Most layers that may move, as limited by modifiers (e.g. a narrow neck: 1).
    /// The base rule also limits it by the movable run and the target's free space.
    public var limit: Int = .max
    /// Set by a target's seal when `layer` is its key: the key is used up and the seal
    /// opens (immediate effect), so it needs no free slot.
    public var opensSeal: KeyID?
    /// How many layers leave the source; set last, by the base rule (1 for a key).
    public var amount: Int = 0
    /// Set by a link (F1 twins, F2 overflow, `Rules.linkedPlan`): the part of `amount` that
    /// lands in another bottle than the target. Empty for a pour between two bottles.
    public var shares: [PourShare] = []

    /// Whether the pour mixes in its target cauldron (E1).
    public var mixes: Bool { flags >> 2 != 0 }
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
    /// - `.cauldron(recipes)` (E1): as a target, when the plan's layer is a color `x`, the
    ///   cauldron's top layer is another color `y` and one recipe mixes `x` with `y`, it sets
    ///   `plan.mixIndex` to that recipe: the base rule then accepts `x` on `y` (the only way a
    ///   color lands on another one) and `transfer` mixes (`mixed`). Otherwise (empty, same
    ///   color, no recipe, a key) it changes nothing. As a source it changes nothing: a
    ///   cauldron pours out like a plain flask.
    ///
    /// Links act on more than two bottles: twins (F1) and overflow pipes (F2) are worked out
    /// in `linkedPlan(for:link:in:)`, which runs these same hooks for every bottle that
    /// receives (switch gates, A3, will go there too). A cauldron is never a link end
    /// (`validate()`), so a linked pour never mixes.
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
        case (.cauldron, .source):
            return true
        case (.cauldron(let recipes), .target):
            markMixing(&plan, recipes: recipes, target: target)
            return true
        }
    }

    /// The target hook of `.cauldron`: sets `plan.mixIndex` when the plan's color and the
    /// target's top color are a recipe's ingredients. Out of line, so `apply` (inlined into
    /// every legality check) stays small.
    @inline(never)
    static func markMixing(_ plan: inout PourPlan, recipes: [Recipe], target: Bottle) {
        guard case .color(let x) = plan.layer, case .color(let y)? = target.topLayer, x != y,
              let index = recipes.firstIndex(where: { $0.mixes(x, y) }), index < 63 else { return }
        plan.mixIndex = index
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
    ///   Onto another color only into a cauldron whose recipe mixes the two (`plan.mixIndex`),
    ///   and then the layers mix as they land (`mixed`).
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
        if plan.mixes { return Transfer(source: newSource, target: mixing(plan, into: target), openedSeal: nil) }
        var newTarget = target
        // The moved layers are a run of `plan.layer` (or one key), whichever end they left.
        newTarget.layers.append(contentsOf: repeatElement(plan.layer, count: plan.amount))
        return Transfer(source: newSource, target: newTarget, openedSeal: nil)
    }

    /// The target of a mixing pour (E1) after `plan` lands in it. Kept out of line, so the
    /// common two-bottle `transfer` stays small enough to inline into the solver's loop.
    @inline(never)
    static func mixing(_ plan: PourPlan, into target: Bottle) -> Bottle {
        var result = target
        let recipe = target.recipes[plan.mixIndex ?? 0]
        mix(&result.layers, pouring: plan.layer, amount: plan.amount, pairs: mixPairs(plan, into: target), result: recipe.result)
        return result
    }

    /// E1: how many pairs a mixing `plan` mixes in `target` (the cauldron before the pour):
    /// `min(amount, the target's top run)`; 0 if the plan doesn't mix.
    public static func mixPairs(_ plan: PourPlan, into target: Bottle) -> Int {
        plan.mixes ? min(plan.amount, target.topRunCount) : 0
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
        if let targetTop = target.topLayer, targetTop != plan.layer, !plan.mixes { return nil }
        let run = plan.fromBottom ? movableBottomRunCount(source) : movableRunCount(source)
        plan.amount = min(min(run, target.freeSpace), plan.limit)
        return plan.amount > 0 ? plan : nil
    }

    /// Step 1 of `resolve` for a pour: the finished plan for `move` in `state`, or nil if
    /// the move is illegal. This is the single legality check: `resolve` and `isLegal`
    /// (hence `canPour` and `legalMoves`) both use it, so they can't disagree. Links that
    /// veto or extend a pour into their flask (twins, overflow) are worked out here
    /// (`linkedPlan`); a pour into any other flask is the two-bottle `plan`.
    @inline(__always)
    static func actionPlan(for move: Move, in state: GameState) -> PourPlan? {
        guard move.from != move.to,
              state.bottles.indices.contains(move.from),
              state.bottles.indices.contains(move.to) else { return nil }
        if state.hasLinks, let link = state.link(at: move.to) {
            return linkedPlan(for: move, link: link, in: state)
        }
        return plan(from: state.bottles[move.from], to: state.bottles[move.to])
    }

    /// Whether `layer` may land on `bottle` by the base rule: the flask is empty or its top
    /// layer is the same. (Free space and modifiers are checked separately.)
    @inline(__always)
    static func stacks(_ layer: Layer, on bottle: Bottle) -> Bool {
        bottle.topLayer.map { $0 == layer } ?? true
    }

    /// The layers a pour may take from `source` under `plan` (its run from the end the plan
    /// pours from, a key alone), as limited by the plan's `limit`.
    @inline(__always)
    static func run(of source: Bottle, under plan: PourPlan) -> Int {
        min(plan.fromBottom ? movableBottomRunCount(source) : movableRunCount(source), plan.limit)
    }

    /// Step 1 for a pour into a flask that is part of `link` (F1, F2): the finished plan, with
    /// `shares` for the layers that land elsewhere, or nil if the pour is illegal. Every
    /// bottle that receives runs its target hooks (`apply`) on its own copy of the plan after
    /// the source hooks, so a seal, rune, funnel, tap or ice on it vetoes as usual, and a
    /// narrow neck limits what goes into *that* flask.
    ///
    /// - `.twins(a, b)` (F1), pouring into one of them: the pour is split evenly. Both twins
    ///   must accept the layer (empty or the same top, no veto); with `run` the source's
    ///   movable run (after source limits), `k = min(run / 2, free space of each twin, each
    ///   twin's own limit)`; `2k` layers leave the source and `k` land in each twin. Illegal if
    ///   `k` is 0 (a single layer, a key, a full twin), and from one twin into the other. A
    ///   key never splits, so a sealed twin could never open (`validate()` rejects it).
    /// - `.overflow(from: a, to: b)` (F2), pouring into `a`: the pour into `a` must be legal
    ///   except for space (a key into `a`'s seal opens it as usual). As many layers as fit go
    ///   into `a`; when that is fewer than `run` because `a` is full, the rest flows on into
    ///   `b`, as many as `b` legally takes (empty or the same top, no veto, free space, its own
    ///   limit), and anything left stays in the source. One hop only: `b`'s own pipe (if any)
    ///   is never followed, and nothing flows back into the source. Illegal if nothing moves.
    ///   A pour into `b` is an ordinary pour.
    static func linkedPlan(for move: Move, link: Link, in state: GameState) -> PourPlan? {
        let source = state.bottles[move.from], target = state.bottles[move.to]
        guard let top = source.topLayer else { return nil }
        var plan = PourPlan(layer: top)
        switch link {
        case let .twins(a, b):
            let partner = a == move.to ? b : a
            guard partner != move.from, state.bottles.indices.contains(partner) else { return nil }
            let twin = state.bottles[partner]
            guard applyModifiers(as: .source, to: &plan, source: source, target: target) else { return nil }
            var intoTarget = plan, intoTwin = plan
            guard applyModifiers(as: .target, to: &intoTarget, source: source, target: target),
                  applyModifiers(as: .target, to: &intoTwin, source: source, target: twin),
                  intoTarget.opensSeal == nil, intoTwin.opensSeal == nil, !plan.layer.isKey,
                  stacks(plan.layer, on: target), stacks(plan.layer, on: twin) else { return nil }
            let k = min(run(of: source, under: plan) / 2, target.freeSpace, twin.freeSpace,
                        intoTarget.limit, intoTwin.limit)
            guard k > 0 else { return nil }
            plan.amount = 2 * k
            plan.shares = [PourShare(bottle: partner, amount: k, route: .twin)]
            return plan
        case let .overflow(from: pipeStart, to: pipeEnd):
            guard pipeStart == move.to else { return Self.plan(from: source, to: target) }
            guard applyModifiers(as: .source, to: &plan, source: source, target: target) else { return nil }
            let sourcePlan = plan
            guard applyModifiers(as: .target, to: &plan, source: source, target: target) else { return nil }
            if plan.opensSeal != nil {
                plan.amount = 1
                return plan
            }
            guard !plan.layer.isKey, stacks(plan.layer, on: target) else { return nil }
            let run = run(of: source, under: plan)
            let direct = min(run, target.freeSpace)
            var spilled = 0
            if direct < run, pipeEnd != move.from, state.bottles.indices.contains(pipeEnd) {
                let end = state.bottles[pipeEnd]
                var intoEnd = sourcePlan
                if applyModifiers(as: .target, to: &intoEnd, source: source, target: end),
                   intoEnd.opensSeal == nil, stacks(plan.layer, on: end) {
                    spilled = max(0, min(run - direct, end.freeSpace, intoEnd.limit))
                }
            }
            guard direct + spilled > 0 else { return nil }
            plan.amount = direct + spilled
            if spilled > 0 { plan.shares = [PourShare(bottle: pipeEnd, amount: spilled, route: .overflow)] }
            return plan
        case .switchGate:
            // Not implemented yet: levels using it fail validation and the solver refuses them.
            return Self.plan(from: source, to: target)
        }
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

    // MARK: - Mixing (E1)

    /// Most recipes a cauldron carries, and a level holds in all (`validate()`).
    public static let maxRecipes = 2

    /// The cauldron mixing step on `layers` (the cauldron before the pour): `amount` layers of
    /// `poured` land on the top run of the other ingredient (`pairs` = `min(amount, run)`
    /// pairs mix). Each mixing pair takes one layer of the run and one poured layer and makes
    /// two layers of `result`. The result sits where the mixed part of the run was, the rest
    /// of the run stays below it, and unmixed poured layers stay on top:
    /// `[…, y × m] + x × n` → `[…, y × (m − p), z × 2p, x × (n − p)]` with `p = min(n, m)`.
    /// Layers are conserved. Nothing chains: the new layers never mix again with what lies
    /// below or above them until another pour lands on them.
    static func mix(_ layers: inout [Layer], pouring poured: Layer, amount: Int, pairs: Int, result: ColorID) {
        layers.removeLast(pairs)
        layers.append(contentsOf: repeatElement(.color(result), count: 2 * pairs))
        layers.append(contentsOf: repeatElement(poured, count: amount - pairs))
    }

    /// E1 for the app and tests: `layers` (a cauldron before the pour) after `amount` layers
    /// of color `poured` land on it, with `recipe` mixing them with the top run, and how many
    /// pairs mixed. Without a matching recipe (or if `poured` is the top color) the layers
    /// just stack, with 0 pairs.
    public static func mixed(_ layers: [Layer], pouring poured: ColorID, amount: Int,
                             recipe: Recipe) -> (layers: [Layer], pairs: Int) {
        var result = layers
        guard let top = layers.last?.colorID, top != poured, recipe.mixes(poured, top) else {
            result.append(contentsOf: repeatElement(.color(poured), count: amount))
            return (result, 0)
        }
        var run = 0
        for layer in layers.reversed() {
            guard layer == .color(top) else { break }
            run += 1
        }
        let pairs = min(amount, run)
        mix(&result, pouring: .color(poured), amount: amount, pairs: pairs, result: recipe.result)
        return (result, pairs)
    }

    /// E1, the inverse of the mixing step for the app's swirl: the cauldron's layers as the
    /// pour left them before it mixed, given its layers `after` the turn (`TurnEvent.mixed`
    /// gives `recipe` and `pairs`; the pour's `layer` and `targetAmount` give `poured` and
    /// `amount`): the `amount − pairs` unmixed poured layers on top and the `2 × pairs` result
    /// layers below them go, the `pairs` layers of the other ingredient come back, then all
    /// `amount` poured layers sit on top. Returns `after` unchanged if it doesn't fit.
    public static func beforeMixing(_ after: [Layer], poured: Layer, amount: Int, recipe: Recipe, pairs: Int) -> [Layer] {
        guard let color = poured.colorID, let other = recipe.partner(of: color), pairs >= 0, amount >= pairs,
              after.count >= amount + pairs else { return after }
        let leftover = amount - pairs
        let top = after.suffix(leftover + 2 * pairs)
        guard top.prefix(2 * pairs).allSatisfy({ $0 == .color(recipe.result) }),
              top.suffix(leftover).allSatisfy({ $0 == poured }) else { return after }
        var before = Array(after.dropLast(leftover + 2 * pairs))
        before.append(contentsOf: repeatElement(.color(other), count: pairs))
        before.append(contentsOf: repeatElement(poured, count: amount))
        return before
    }

    /// E1: how many pairs each of `recipes` must mix so that every color ends with exactly
    /// 0 or `capacity` layers, starting from `counts` layers per color (the first such
    /// amounts, smallest first in recipe order), or nil if there are none. Each pair of
    /// recipe `a + b → z` takes one `a` and one `b` and makes two `z`. A necessary condition
    /// for a cauldron level to be winnable (`validate()`); the order of the pours is the
    /// solver's business. At most `Rules.maxRecipes` recipes are searched exhaustively.
    public static func finalColorCounts(_ counts: [ColorID: Int], recipes: [Recipe], capacity: Int) -> [Int]? {
        let colors = Array(Set(counts.keys).union(recipes.flatMap { [$0.a, $0.b, $0.result] }))
        let total = counts.values.reduce(0, +)
        var pairs = [Int](repeating: 0, count: recipes.count)
        func balanced() -> Bool {
            colors.allSatisfy { color in
                var n = counts[color] ?? 0
                for (r, recipe) in recipes.enumerated() {
                    if recipe.a == color || recipe.b == color { n -= pairs[r] }
                    if recipe.result == color { n += 2 * pairs[r] }
                }
                return n == 0 || n == capacity
            }
        }
        func search(_ r: Int) -> Bool {
            if r == recipes.count { return balanced() }
            for p in 0...max(0, total / 2) {
                pairs[r] = p
                if search(r + 1) { return true }
            }
            return false
        }
        return search(0) ? pairs : nil
    }

    /// E1: whether cauldron `bottle` holds a color directly on a recipe partner (an unmixed
    /// pair). Play never makes one: a color only lands on its partner by a mixing pour,
    /// layers only leave from the top, and a result is never an ingredient (`validate()`
    /// rejects chained recipes), so neither a result nor a leftover poured layer ever sits on
    /// a partner. A level may not start with one either (`validate()`).
    public static func holdsUnmixedPair(_ bottle: Bottle) -> Bool {
        let recipes = bottle.recipes
        guard !recipes.isEmpty, bottle.layers.count > 1 else { return false }
        for i in 1..<bottle.layers.count {
            guard case .color(let x) = bottle.layers[i], case .color(let y) = bottle.layers[i - 1], x != y else { continue }
            if recipes.contains(where: { $0.mixes(x, y) }) { return true }
        }
        return false
    }

    /// E1: the recipe that would mix color `color` poured into `bottle` (a cauldron whose top
    /// layer is the other ingredient), or nil. For the app's preview of a pour.
    public static func recipe(mixing color: ColorID, into bottle: Bottle) -> Recipe? {
        var plan = PourPlan(layer: .color(color))
        for modifier in bottle.modifiers {
            if case .cauldron = modifier { _ = apply(modifier, as: .target, to: &plan, source: Bottle(capacity: 0), target: bottle) }
        }
        return plan.mixIndex.map { bottle.recipes[$0] }
    }

    // MARK: - Turn order (MECHANICS.md §4)

    /// Applies a player action and then every rule that follows it, in the fixed order
    /// of MECHANICS.md §4. This is the only place that order is defined; the game
    /// (`GameState.pouring`), the solver and the generator all go through it.
    ///
    /// 1. The action (a pour, from the top or, through a tap, from the bottom; a pour into a
    ///    twin is split with its twin, a pour into a full flask with an overflow pipe runs on
    ///    into the pipe's far end, `linkedPlan`). The turn reports it as a `PourEvent`, with
    ///    the extra destinations in `shares`.
    ///    A pour into a cauldron whose recipe mixes the poured color with its top layer mixes
    ///    as it lands (E1, `mixed`; `TurnEvent.mixed`, the turn's first event): mixing is
    ///    driven by the pour (how many layers landed on which run), so it is applied with it,
    ///    before every later step.
    /// 2. Immediate effects: unseal (A1). R5: switch gates (A3). Murky reveals (B1) are
    ///    display state in `GameSession` (mixing only touches the cauldron's top run and the
    ///    layers that just landed, which are all in view).
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
        var events: [TurnEvent] = []
        switch action {
        case .pour(let move):
            guard let plan = actionPlan(for: move, in: state) else { return nil }
            if plan.shares.isEmpty {
                let t = transfer(plan, from: state.bottles[move.from], to: state.bottles[move.to])
                next.bottles[move.from] = t.source
                next.bottles[move.to] = t.target
                if let key = t.openedSeal { opened = (move.to, key) }
                // E1: the pour mixed as it landed (an immediate effect of the pour, before any timer).
                if plan.mixes { events.append(mixedEvent(plan, into: move.to, of: state)) }
            } else {
                // A linked pour (F1, F2): the layers leave the source once and land in several bottles.
                if plan.fromBottom {
                    next.bottles[move.from].layers.removeFirst(plan.amount)
                } else {
                    next.bottles[move.from].layers.removeLast(plan.amount)
                }
                var direct = plan.amount
                for share in plan.shares {
                    next.bottles[share.bottle].layers.append(contentsOf: repeatElement(plan.layer, count: share.amount))
                    direct -= share.amount
                }
                next.bottles[move.to].layers.append(contentsOf: repeatElement(plan.layer, count: direct))
            }
            event = PourEvent(move: move, layer: plan.layer, amount: plan.amount, fromBottom: plan.fromBottom,
                              openedSeal: plan.opensSeal, shares: plan.shares)
        }
        // 2. Immediate effects (unseal, then everything that follows from the state).
        applyImmediateEffects(&next, opened: opened)
        // 3. Move counter.
        if let n = next.moveCount, n < moveCountLimit(next) { next.moveCount = n + 1 }
        // 4. + 5. Timed effects, then immediate effects again.
        if applyTimedEffects(&next, events: &events) { applyImmediateEffects(&next, opened: nil) }
        // 6. Goal.
        return Turn(state: next, isWon: isWon(next), pour: event, events: events)
    }

    /// `TurnEvent.mixed` for a mixing pour into bottle `index` of `state` (out of line, like
    /// `mixing`).
    @inline(never)
    static func mixedEvent(_ plan: PourPlan, into index: Int, of state: GameState) -> TurnEvent {
        let target = state.bottles[index]
        return .mixed(bottle: index, recipe: target.recipes[plan.mixIndex ?? 0], pairs: mixPairs(plan, into: target))
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

    /// The link that refuses `move`, for the app's feedback ("twins share every pour"): a
    /// twin link when the pour into one twin is illegal although it would be legal between
    /// the two bottles alone (from one twin into the other, a single layer that can't be
    /// split, a twin that is full or has another color on top). nil if the move is legal or
    /// illegal for a base or modifier reason. An overflow pipe never refuses a pour (it only
    /// takes what a full flask can't).
    public static func linkRefusal(of move: Move, in state: GameState) -> Link? {
        guard move.from != move.to, state.bottles.indices.contains(move.from), state.bottles.indices.contains(move.to),
              let link = state.link(at: move.to), case .twins = link,
              !isLegal(move, in: state),
              plan(from: state.bottles[move.from], to: state.bottles[move.to]) != nil else { return nil }
        return link
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
    /// its seal; nil in step 5). Switch gates (A3) go after it. Mixing (E1) is driven by
    /// the pour too, but needs what landed where, so `transfer` applies it in step 1.
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
    // A cauldron (E1) doesn't block either: it ends empty or full of one color like any flask.

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
