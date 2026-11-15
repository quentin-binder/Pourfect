// All game rules live in this file. New mechanics add a case to the hook switches
// here (`apply(_:as:to:)`, `blocksSolved(_:)`, the steps of `resolve`) rather than
// scattering checks across the codebase. See Mechanics.swift for the types.

/// A player action. Today the only one is a pour; items (R5+) become further cases.
public enum Action: Hashable, Sendable {
    case pour(Move)
}

/// The result of one resolved turn: the new state and whether its goal is met.
public struct Turn: Hashable, Sendable {
    public var state: GameState
    public var isWon: Bool
}

/// Which end of a pour a modifier sits on.
public enum PourSide: Sendable {
    case source
    case target
}

/// One pour being worked out between two bottles. Modifier hooks may veto it or change
/// it (`Rules.apply(_:as:to:)`) before the base rule moves the layers.
public struct PourPlan: Hashable, Sendable {
    /// The layer that leaves the source first (its top layer).
    public var layer: Layer
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
    /// or changes a pour. Source modifiers run first, then target modifiers.
    ///
    /// - `.sealed(k)`: a sealed flask can't be poured from. As a target it accepts only
    ///   key `k`, which opens it (needs no free slot); nothing else goes in.
    ///
    /// R5 plan (one arm each): `.essence(c)` target → veto unless `layer == .color(c)`;
    /// `.narrowNeck` either side → `limit = 1`; `.funnel` source → veto; `.tap` target →
    /// veto, source → pour from the bottom (needs a `fromBottom` flag on the plan);
    /// `.frozen(i, _)` source → `limit` = layers above `i` (veto at 0); `.cauldron` target →
    /// also accept a recipe partner (mixing is an immediate effect in `resolve`).
    public static func apply(_ modifier: BottleModifier, as side: PourSide, to plan: inout PourPlan) -> Bool {
        switch (modifier, side) {
        case (.sealed, .source):
            return false
        case (.sealed(let key), .target):
            guard plan.layer == .key(key) else { return false }
            plan.opensSeal = key
            return true
        case (.essence, _), (.narrowNeck, _), (.funnel, _), (.tap, _), (.frozen, _), (.bubbling, _), (.cauldron, _):
            // Not implemented yet: levels using them fail validation and the solver refuses them.
            return true
        }
    }

    /// Runs `apply` for every modifier of `bottle` (none for a plain flask).
    @inline(__always)
    static func applyModifiers(of bottle: Bottle, as side: PourSide, to plan: inout PourPlan) -> Bool {
        switch bottle.storage {
        case .none:
            return true
        case .sealed(let key):
            return apply(.sealed(key), as: side, to: &plan)
        case .list(let list):
            for modifier in list where !apply(modifier, as: side, to: &plan) { return false }
            return true
        }
    }

    /// Step 1 of a turn for a pour from `source` into `target`, or nil if it's illegal.
    ///
    /// - Color top run: moves onto an empty or same-colored target with free space; as
    ///   many layers as fit (partial pours allowed).
    /// - Key top layer: moves alone, only into the flask sealed by that key (see `apply`).
    /// - Nothing can be poured onto a key (a key top never matches a color).
    static func transfer(from source: Bottle, to target: Bottle) -> Transfer? {
        guard let plan = plan(from: source, to: target) else { return nil }
        var newSource = source
        newSource.layers.removeLast(plan.amount)
        if let key = plan.opensSeal {
            return Transfer(source: newSource, target: target, openedSeal: key)
        }
        var newTarget = target
        newTarget.layers.append(contentsOf: source.layers.suffix(plan.amount))
        return Transfer(source: newSource, target: newTarget, openedSeal: nil)
    }

    /// The legality half of `transfer`: the finished plan (with `amount`), or nil if the
    /// pour is illegal. Builds no bottles, so legality checks stay cheap.
    @inline(__always)
    static func plan(from source: Bottle, to target: Bottle) -> PourPlan? {
        guard let top = source.topLayer else { return nil }
        var plan = PourPlan(layer: top)
        guard applyModifiers(of: source, as: .source, to: &plan),
              applyModifiers(of: target, as: .target, to: &plan) else { return nil }
        if plan.opensSeal != nil {
            plan.amount = 1
            return plan
        }
        // Base rule. A key only ever goes into its own seal (handled above).
        guard !top.isKey else { return nil }
        guard target.freeSpace > 0 else { return nil }
        if let targetTop = target.topLayer, targetTop != top { return nil }
        plan.amount = min(min(movableRunCount(source), target.freeSpace), plan.limit)
        return plan.amount > 0 ? plan : nil
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

    // MARK: - Turn order (MECHANICS.md §4)

    /// Applies a player action and then every rule that follows it, in the fixed order
    /// of MECHANICS.md §4. This is the only place that order is defined; the game
    /// (`GameState.pouring`), the solver and the generator all go through it.
    ///
    /// 1. The action (a pour; R5: twins / overflow extend it here).
    /// 2. Immediate effects: unseal (A1). R5: mixing (E1), switch gates (A3). Murky
    ///    reveals (B1) are display state in `GameSession`.
    /// 3. `moveCount += 1`, only if the state stores a move counter.
    /// 4. Timed effects: corks (A2) → thaw (D1) → bubbling (D2) → evaporation (D4) →
    ///    conveyor (D3). None is implemented yet.
    /// 5. Immediate effects again if a timed effect changed anything.
    /// 6. Goal check.
    ///
    /// Returns nil if the action is illegal.
    public static func resolve(_ state: GameState, afterAction action: Action) -> Turn? {
        var next = state
        // 1. The player's action.
        var opened: (bottle: Int, key: KeyID)?
        switch action {
        case .pour(let move):
            guard move.from != move.to,
                  state.bottles.indices.contains(move.from),
                  state.bottles.indices.contains(move.to),
                  let t = transfer(from: state.bottles[move.from], to: state.bottles[move.to]) else { return nil }
            next.bottles[move.from] = t.source
            next.bottles[move.to] = t.target
            if let key = t.openedSeal { opened = (move.to, key) }
        }
        // 2. Immediate effects.
        if let opened { unseal(&next.bottles[opened.bottle], key: opened.key) }
        // 3. Move counter.
        if let n = next.moveCount { next.moveCount = n + 1 }
        // 4. + 5. Timed effects, then immediate effects again.
        if applyTimedEffects(&next) { applyImmediateEffects(&next) }
        // 6. Goal.
        return Turn(state: next, isWon: isWon(next))
    }

    /// Whether `move` is legal in `state` (step 1 of `resolve` succeeds).
    public static func isLegal(_ move: Move, in state: GameState) -> Bool {
        guard move.from != move.to,
              state.bottles.indices.contains(move.from),
              state.bottles.indices.contains(move.to) else { return false }
        // R5: links that can veto a pour (twins) are checked here.
        return plan(from: state.bottles[move.from], to: state.bottles[move.to]) != nil
    }

    /// Unseal (A1): the key poured into a seal opens it.
    static func unseal(_ bottle: inout Bottle, key: KeyID) {
        if case .sealed(key) = bottle.storage {
            bottle.storage = .none
        } else {
            bottle.modifiers.removeAll { $0 == .sealed(key) }
        }
    }

    /// Immediate effects that follow from the state alone (step 2/5 of `resolve`).
    /// Unseal is driven by the pour itself, so this has nothing to do yet.
    /// R5: mixing (E1), switch gates (A3).
    static func applyImmediateEffects(_ state: inout GameState) {}

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
