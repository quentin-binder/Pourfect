// All game rules live in this file. New mechanics (keys, locks, …) add cases
// here rather than scattering checks across the codebase.

public enum Rules {
    /// How many layers would move when pouring `source` into `target`.
    /// Returns 0 if the pour is illegal. This is the single legality check.
    public static func pourAmount(from source: Bottle, to target: Bottle) -> Int {
        // Locked bottles can't be poured from or into.
        guard source.lockedBy == nil, target.lockedBy == nil else { return 0 }
        // Source must be non-empty.
        guard let top = source.topLayer else { return 0 }
        // Target must have room.
        guard target.freeSpace > 0 else { return 0 }
        // Target must be empty or have a matching top layer.
        if let targetTop = target.topLayer, targetTop != top { return 0 }
        // Move the whole top run, limited by the free space (partial pours allowed).
        return min(movableRunCount(source), target.freeSpace)
    }

    /// Number of layers at the top of `bottle` that move together in one pour.
    public static func movableRunCount(_ bottle: Bottle) -> Int {
        bottle.topRunCount
    }

    /// A bottle is solved when it is empty, or full with a single color.
    public static func isSolved(_ bottle: Bottle) -> Bool {
        if bottle.lockedBy != nil { return false }
        guard let first = bottle.layers.first else { return true }
        guard bottle.isFull, first.colorID != nil else { return false }
        return bottle.layers.allSatisfy { $0 == first }
    }

    /// The puzzle is won when every bottle is solved.
    public static func isWon(_ state: GameState) -> Bool {
        state.bottles.allSatisfy(isSolved)
    }
}

extension GameState {
    public func canPour(_ move: Move) -> Bool {
        guard move.from != move.to,
              bottles.indices.contains(move.from),
              bottles.indices.contains(move.to) else { return false }
        return Rules.pourAmount(from: bottles[move.from], to: bottles[move.to]) > 0
    }

    /// The state after `move`, or nil if the move is illegal.
    public func pouring(_ move: Move) -> GameState? {
        guard move.from != move.to,
              bottles.indices.contains(move.from),
              bottles.indices.contains(move.to) else { return nil }
        let amount = Rules.pourAmount(from: bottles[move.from], to: bottles[move.to])
        guard amount > 0 else { return nil }
        var next = self
        let moved = next.bottles[move.from].layers.suffix(amount)
        next.bottles[move.from].layers.removeLast(amount)
        next.bottles[move.to].layers.append(contentsOf: moved)
        return next
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

    public var isSolved: Bool { Rules.isWon(self) }
}
