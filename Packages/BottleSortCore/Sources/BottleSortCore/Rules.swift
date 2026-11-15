// All game rules live in this file. New mechanics (keys, locks, …) add cases
// here rather than scattering checks across the codebase.

public enum Rules {
    /// The source and target bottles after pouring `source` into `target`,
    /// or nil if the pour is illegal. This is the single legality check and
    /// the single definition of what a pour does.
    ///
    /// - Color top run: moves onto an empty or same-colored, unlocked target
    ///   with free space; as many layers as fit (partial pours allowed).
    /// - Key top layer: moves alone, only onto the bottle locked by that key.
    ///   The key is consumed and the bottle becomes unlocked (it needs no free slot).
    /// - Locked bottles can't be poured from, nor into (except by their key).
    /// - Nothing can be poured onto a key (a key top never matches a color,
    ///   and keys only go into locked bottles).
    public static func pour(from source: Bottle, to target: Bottle) -> (source: Bottle, target: Bottle)? {
        // Locked bottles can't be poured from.
        guard source.lockedBy == nil else { return nil }
        // Source must be non-empty.
        guard let top = source.topLayer else { return nil }
        var newSource = source
        var newTarget = target
        switch top {
        case .key(let key):
            // A key only opens the bottle locked by the same id; it is consumed.
            guard target.lockedBy == key else { return nil }
            newSource.layers.removeLast()
            newTarget.lockedBy = nil
        case .color:
            // Colors can't go into locked bottles.
            guard target.lockedBy == nil else { return nil }
            // Target must have room.
            guard target.freeSpace > 0 else { return nil }
            // Target must be empty or have the same top layer (so never a key).
            if let targetTop = target.topLayer, targetTop != top { return nil }
            // Move the whole top run, limited by the free space (partial pours allowed).
            let amount = min(movableRunCount(source), target.freeSpace)
            newTarget.layers.append(contentsOf: source.layers.suffix(amount))
            newSource.layers.removeLast(amount)
        }
        return (newSource, newTarget)
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

    /// A bottle is solved when it is unlocked and empty, or full with a single
    /// color. A bottle that is locked or contains a key is never solved.
    public static func isSolved(_ bottle: Bottle) -> Bool {
        if bottle.lockedBy != nil { return false }
        guard let first = bottle.layers.first else { return true }
        guard bottle.isFull, first.colorID != nil else { return false }
        return bottle.layers.allSatisfy { $0 == first }
    }

    /// The puzzle is won when every bottle is solved. This implies no key
    /// layers remain and no bottle is locked.
    public static func isWon(_ state: GameState) -> Bool {
        state.bottles.allSatisfy(isSolved)
    }
}

extension GameState {
    public func canPour(_ move: Move) -> Bool {
        guard move.from != move.to,
              bottles.indices.contains(move.from),
              bottles.indices.contains(move.to) else { return false }
        return Rules.pour(from: bottles[move.from], to: bottles[move.to]) != nil
    }

    /// The state after `move`, or nil if the move is illegal.
    public func pouring(_ move: Move) -> GameState? {
        guard move.from != move.to,
              bottles.indices.contains(move.from),
              bottles.indices.contains(move.to),
              let (source, target) = Rules.pour(from: bottles[move.from], to: bottles[move.to]) else { return nil }
        var next = self
        next.bottles[move.from] = source
        next.bottles[move.to] = target
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
