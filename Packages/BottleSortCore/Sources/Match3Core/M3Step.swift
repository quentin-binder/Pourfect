/// What one swap did, in the exact order the app animates it (DECISIONS 258).

public enum M3Status: String, Sendable, Hashable, Codable {
    case playing, won, lost
}

/// One matched group of same-kind pieces (runs of 3+ that share cells are one group).
public struct M3MatchGroup: Sendable, Hashable {
    public enum Shape: String, Sendable, Hashable {
        /// A single run of 3.
        case three
        /// A single run of 4 → comet (row/column).
        case four
        /// Crossing runs (L, T or +) without a run of 5 → bloom.
        case cross
        /// A run of 5+ → prism.
        case five
    }

    public var kind: M3Kind
    /// Every cell of the group, row-major.
    public var cells: [M3Pos]
    public var shape: Shape
    /// The special the group creates, if any, and where.
    public var creates: M3Special?
    public var createdAt: M3Pos?
}

/// The area a special (or a combo of two) reaches.
public enum M3Effect: Sendable, Hashable {
    /// The whole row through the cell (comet).
    case row
    /// The whole column through the cell (comet).
    case column
    /// The (2r+1)×(2r+1) square around the cell: r = 1 bloom, r = 2 bloom + bloom.
    case square(radius: Int)
    /// Rows and columns through the cell, `width` 1 (comet + comet) or 3 (comet + bloom).
    case cross(width: Int)
    /// Every piece of one kind (prism).
    case kind(M3Kind)
    /// Every cell (prism + prism).
    case board
}

/// A special firing (or a combo of two specials) at `at`.
public struct M3Activation: Sendable, Hashable {
    public var at: M3Pos
    /// The special that fired (for a combo: the dragged piece's special).
    public var special: M3Special
    public var effect: M3Effect
    /// Existing cells the effect reaches, row-major.
    public var cells: [M3Pos]
}

/// A piece that left the board.
public struct M3Cleared: Sendable, Hashable {
    public enum Cause: String, Sendable, Hashable {
        /// Part of a match group.
        case match
        /// Reached by an activation.
        case blast
        /// One of the two specials (or the prism) used up by a special swap.
        case combo
    }

    public var at: M3Pos
    public var piece: M3Piece
    public var cause: Cause
    /// The activation that cleared it (index into `M3Wave.activations`) when `cause == .blast`.
    public var activation: Int?
}

/// One hit on frost or a crate; `remaining` is what is left after it (0 = gone).
public struct M3Damage: Sendable, Hashable {
    public var at: M3Pos
    public var remaining: Int
}

/// A new special piece placed by a match group, or a piece turned into a special by a prism combo.
public struct M3SpecialPiece: Sendable, Hashable {
    public var at: M3Pos
    public var piece: M3Piece
}

/// One clear wave: wave 1 is the swap's own; waves 2, 3… are cascades.
/// Animate in field order: groups → conversions → activations (in order) → cleared → damage → created.
public struct M3Wave: Sendable, Hashable {
    /// 1 for the swap, 2+ for cascades (the score multiplier is min(cascade, 5)).
    public var cascade: Int
    public var groups: [M3MatchGroup]
    /// Pieces a prism + comet/bloom combo turned into specials before they fire.
    public var conversions: [M3SpecialPiece]
    public var activations: [M3Activation]
    public var cleared: [M3Cleared]
    public var frostHits: [M3Damage]
    public var crateHits: [M3Damage]
    public var created: [M3SpecialPiece]
    public var score: Int
}

/// A piece or flask moving down its column.
public struct M3Fall: Sendable, Hashable {
    public var from: M3Pos
    public var to: M3Pos
    public var item: M3Item
}

/// A new item entering a column from above. In a column with `columnCount` new items, rank 0 is the
/// lowest (it enters first); it starts `columnCount - rank` cells above the column's top open cell.
public struct M3Spawn: Sendable, Hashable {
    public var at: M3Pos
    public var item: M3Item
    public var rank: Int
    public var columnCount: Int
}

/// Gravity and refill after a wave or a collection.
public struct M3Settle: Sendable, Hashable {
    public var falls: [M3Fall]
    public var spawns: [M3Spawn]
}

/// Pieces moved by a reshuffle; `rerolled` lists cells whose piece was replaced (only when no
/// rearrangement worked).
public struct M3Reshuffle: Sendable, Hashable {
    public var moves: [M3Fall]
    public var rerolled: [M3SpecialPiece]
}

public enum M3Phase: Sendable, Hashable {
    /// The two pieces trade places (always the first phase of an accepted swap).
    case swap(M3Swap)
    case wave(M3Wave)
    case settle(M3Settle)
    /// Flasks that reached their column's bottom cell and were collected.
    case collect([M3Pos])
    /// No valid swap was left: the board was rearranged.
    case reshuffle(M3Reshuffle)
}

/// The result of `M3Game.play(_:)`.
public struct M3StepResult: Sendable, Hashable {
    public var swap: M3Swap
    /// false: the swap was refused (swap and swap back; no move used, nothing changed).
    public var accepted: Bool
    public var phases: [M3Phase]
    public var scoreGained: Int
    public var movesLeft: Int
    public var status: M3Status

    public var waves: [M3Wave] { phases.compactMap { if case .wave(let w) = $0 { return w } else { return nil } } }
}

/// One finale burst: a leftover move turned a piece into a special that fires at once.
public struct M3FinaleBurst: Sendable, Hashable {
    public var at: M3Pos
    public var special: M3Special
    public var phases: [M3Phase]
    public var scoreGained: Int
}

/// The "Bubbling Over" finale after a win.
public struct M3Finale: Sendable, Hashable {
    public var bursts: [M3FinaleBurst]
    public var scoreGained: Int
    public var finalScore: Int
    public var stars: Int
}
