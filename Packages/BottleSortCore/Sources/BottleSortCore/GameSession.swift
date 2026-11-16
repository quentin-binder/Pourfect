/// A play session: current state plus undo history.
///
/// Hidden layers (murky potions, B1; display only — the rules and the solver ignore them):
/// in hidden mode every layer carries a hidden flag (`hiddenMasks`, per bottle, bottom →
/// top). A layer is *in view* while it belongs to a run its flask can pour: the top run
/// (`Rules.movableRunCount`), and for a tap flask (C4) also the bottom run it pours from
/// (`Rules.movableBottomRunCount`). At the start everything not in view is hidden; after
/// every move the flags follow their layers (`Turn.pour` says which layers left which end
/// of the source and how many landed on the target), layers poured into a flask land
/// visible, and every layer in view is revealed. A revealed layer never hides again.
///
/// The flags move *with* the layers, so a tap draining a flask from the bottom keeps
/// the right layers hidden as the stack above slides down (DECISIONS 130 c, 148). The
/// masks are stored with the undo history, so undo and restart restore them exactly,
/// together with the full `GameState` (modifiers, seals and any counter).
public struct GameSession: Sendable {
    public let initialState: GameState
    public private(set) var state: GameState
    public private(set) var history: [GameState] = []
    /// Whether this session hides layers below each bottle's top run.
    public let hidden: Bool
    /// Per bottle, per layer (0 = bottom): whether that layer is shown as "?". All false
    /// when not hidden. Always as long as the bottle's layer list.
    public private(set) var hiddenMasks: [[Bool]]
    /// What the last applied move did (for the app's animation: which end of the source
    /// the layers left, how many, whether a key opened a seal). nil after undo or restart.
    public private(set) var lastPour: PourEvent?
    private let initialHiddenMasks: [[Bool]]
    private var hiddenHistory: [[[Bool]]] = []

    public init(_ initialState: GameState, hidden: Bool = false) {
        self.initialState = initialState
        self.state = initialState
        self.hidden = hidden
        let masks = initialState.bottles.map { bottle in
            hidden ? GameSession.revealingLayersInView(of: bottle, in: Array(repeating: true, count: bottle.layers.count))
                   : Array(repeating: false, count: bottle.layers.count)
        }
        self.hiddenMasks = masks
        self.initialHiddenMasks = masks
    }

    /// Number of moves currently applied (undo decreases it).
    public var moveCount: Int { history.count }
    public var canUndo: Bool { !history.isEmpty }
    public var isSolved: Bool { state.isSolved }

    /// Per bottle: how many of its layers are hidden. Without taps the hidden layers are
    /// always the bottom ones, so this is also how many bottom layers show "?"; with a tap
    /// they may not be (its bottom run is in view): use `isHidden(bottle:layer:)` or
    /// `hiddenMasks` to draw.
    public var hiddenDepths: [Int] {
        hiddenMasks.map { mask in mask.reduce(0) { $0 + ($1 ? 1 : 0) } }
    }

    /// Whether layer `layer` (0 = bottom) of bottle `bottle` is shown as "?".
    public func isHidden(bottle: Int, layer: Int) -> Bool {
        guard hiddenMasks.indices.contains(bottle), hiddenMasks[bottle].indices.contains(layer) else { return false }
        return hiddenMasks[bottle][layer]
    }

    /// Applies `move` if legal. Returns whether it was applied.
    @discardableResult
    public mutating func apply(_ move: Move) -> Bool {
        play(move) != nil
    }

    /// Applies `move` if legal and returns the resolved turn (new state, win, and the pour
    /// event the app animates from); nil if the move is illegal (nothing changes).
    @discardableResult
    public mutating func play(_ move: Move) -> Turn? {
        guard let turn = Rules.resolve(state, afterAction: .pour(move)) else { return nil }
        history.append(state)
        hiddenHistory.append(hiddenMasks)
        state = turn.state
        lastPour = turn.pour
        hiddenMasks = GameSession.masks(hiddenMasks, after: turn)
        return turn
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast(), let masks = hiddenHistory.popLast() else { return false }
        state = previous
        hiddenMasks = masks
        lastPour = nil
        return true
    }

    public mutating func restart() {
        state = initialState
        hiddenMasks = initialHiddenMasks
        lastPour = nil
        history.removeAll()
        hiddenHistory.removeAll()
    }

    /// The hidden flags after `turn`: the poured layers leave the source at the end the
    /// event names, land visible on the target (unless a key opened its seal and was used
    /// up), then every layer in view is revealed. A bottle whose layer count no longer
    /// matches (a later mechanic changing layers some other way) keeps its flags from the
    /// bottom and shows any new layer.
    static func masks(_ old: [[Bool]], after turn: Turn) -> [[Bool]] {
        var masks = old
        if let pour = turn.pour, masks.indices.contains(pour.move.from), masks.indices.contains(pour.move.to) {
            let amount = min(pour.amount, masks[pour.move.from].count)
            if pour.fromBottom {
                masks[pour.move.from].removeFirst(amount)
            } else {
                masks[pour.move.from].removeLast(amount)
            }
            if pour.openedSeal == nil {
                masks[pour.move.to] += Array(repeating: false, count: pour.amount)
            }
        }
        for (i, bottle) in turn.state.bottles.enumerated() where masks.indices.contains(i) {
            let count = bottle.layers.count
            if masks[i].count > count { masks[i].removeLast(masks[i].count - count) }
            if masks[i].count < count { masks[i] += Array(repeating: false, count: count - masks[i].count) }
            masks[i] = revealingLayersInView(of: bottle, in: masks[i])
        }
        return masks
    }

    /// `mask` with the layers in view revealed: the top run, and a tap's bottom run.
    static func revealingLayersInView(of bottle: Bottle, in mask: [Bool]) -> [Bool] {
        var mask = mask
        let count = bottle.layers.count
        for i in (count - Rules.movableRunCount(bottle))..<count { mask[i] = false }
        if bottle.hasTap {
            for i in 0..<Rules.movableBottomRunCount(bottle) { mask[i] = false }
        }
        return mask
    }
}
