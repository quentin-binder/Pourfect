/// A play session: current state plus undo history.
public struct GameSession: Sendable {
    public let initialState: GameState
    public private(set) var state: GameState
    public private(set) var history: [GameState] = []

    public init(_ initialState: GameState) {
        self.initialState = initialState
        self.state = initialState
    }

    /// Number of moves currently applied (undo decreases it).
    public var moveCount: Int { history.count }
    public var canUndo: Bool { !history.isEmpty }
    public var isSolved: Bool { state.isSolved }

    /// Applies `move` if legal. Returns whether it was applied.
    @discardableResult
    public mutating func apply(_ move: Move) -> Bool {
        guard let next = state.pouring(move) else { return false }
        history.append(state)
        state = next
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        state = previous
        return true
    }

    public mutating func restart() {
        state = initialState
        history.removeAll()
    }
}
