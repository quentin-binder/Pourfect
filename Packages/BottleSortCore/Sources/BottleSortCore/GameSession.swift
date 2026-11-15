/// A play session: current state plus undo history.
///
/// Hidden layers (display only — the rules and the solver ignore them): in
/// hidden mode each bottle has a `hiddenDepth`, the number of its bottom
/// layers still shown as "?". It starts at `layers.count − movableRunCount`
/// (everything below the top run is hidden) and after every move becomes
/// `min(old, layers.count − movableRunCount)`, so it only ever decreases: a
/// layer that has once been part of its bottle's top run stays revealed, and
/// layers poured into a bottle always land above the hidden part. The depths
/// are stored with the undo history, so undo and restart restore them exactly.
public struct GameSession: Sendable {
    public let initialState: GameState
    public private(set) var state: GameState
    public private(set) var history: [GameState] = []
    /// Whether this session hides layers below each bottle's top run.
    public let hidden: Bool
    /// Per bottle: how many bottom layers are still hidden (all 0 when not hidden).
    public private(set) var hiddenDepths: [Int]
    private let initialHiddenDepths: [Int]
    private var hiddenHistory: [[Int]] = []

    public init(_ initialState: GameState, hidden: Bool = false) {
        self.initialState = initialState
        self.state = initialState
        self.hidden = hidden
        let depths = initialState.bottles.map { hidden ? GameSession.layersBelowTopRun($0) : 0 }
        self.hiddenDepths = depths
        self.initialHiddenDepths = depths
    }

    /// Number of moves currently applied (undo decreases it).
    public var moveCount: Int { history.count }
    public var canUndo: Bool { !history.isEmpty }
    public var isSolved: Bool { state.isSolved }

    /// Whether layer `layer` (0 = bottom) of bottle `bottle` is shown as "?".
    public func isHidden(bottle: Int, layer: Int) -> Bool {
        guard hiddenDepths.indices.contains(bottle) else { return false }
        return layer >= 0 && layer < hiddenDepths[bottle]
    }

    /// Applies `move` if legal. Returns whether it was applied.
    @discardableResult
    public mutating func apply(_ move: Move) -> Bool {
        guard let next = state.pouring(move) else { return false }
        history.append(state)
        hiddenHistory.append(hiddenDepths)
        state = next
        for i in hiddenDepths.indices {
            hiddenDepths[i] = min(hiddenDepths[i], GameSession.layersBelowTopRun(next.bottles[i]))
        }
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast(), let depths = hiddenHistory.popLast() else { return false }
        state = previous
        hiddenDepths = depths
        return true
    }

    public mutating func restart() {
        state = initialState
        hiddenDepths = initialHiddenDepths
        history.removeAll()
        hiddenHistory.removeAll()
    }

    /// Layers below the top run (which may be hidden); a key's run is 1.
    private static func layersBelowTopRun(_ bottle: Bottle) -> Int {
        bottle.layers.count - Rules.movableRunCount(bottle)
    }
}
