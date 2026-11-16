/// "Perfect brewer" (R6): a recipe solved in exactly its solver minimum without a hint
/// earns a gold seal, stored per recipe apart from its stars (DECISIONS 224).
///
/// Three stars already mean "the fewest moves"; the seal adds "on your own": a hint shown
/// while playing the recipe forfeits it for that solve (the same rule as the daily's
/// "perfect", DECISIONS 109). Undo is allowed: only the final move count counts, as for stars.
public enum GoldSeal {
    /// Whether a solve in `moves` earns the seal. Needs a known minimum.
    public static func isEarned(moves: Int, minMoves: Int?, usedHint: Bool) -> Bool {
        guard let minMoves, minMoves > 0, !usedHint else { return false }
        return moves <= minMoves
    }

    /// Seals earned among `ids` (a chapter or book's recipes, in any order). Seals of ids
    /// that don't ship any more are never counted.
    public static func progress(of ids: [String], sealed: Set<String>) -> GoldSealProgress {
        GoldSealProgress(earned: ids.filter(sealed.contains).count, total: ids.count)
    }
}

/// Gold seals earned in one chapter or challenge book.
public struct GoldSealProgress: Sendable, Hashable {
    public var earned: Int
    public var total: Int

    public init(earned: Int, total: Int) {
        self.earned = earned
        self.total = total
    }

    /// Every recipe has its seal (and there is at least one recipe).
    public var isComplete: Bool { total > 0 && earned >= total }
}
