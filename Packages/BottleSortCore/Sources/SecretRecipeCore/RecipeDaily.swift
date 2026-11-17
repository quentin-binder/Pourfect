import BottleSortCore

/// Where secrets come from: the daily recipe (generator id "recipe-daily-v1", the same for every
/// player on a UTC date) and practice recipes (any seed).
public enum RecipeDaily {
    public static let algorithmVersion = "recipe-daily-v1"
    /// Draws before a tray-ordered secret is accepted anyway (never reached in practice).
    static let maxDraws = 16

    /// FNV-1a of "recipe-daily-v1|YYYY-MM-DD", mixed once by SplitMix64 (like the other dailies).
    public static func seed(for date: DailyDate) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(algorithmVersion)|\(date.isoString)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        var mixer = SplitMix64(seed: hash)
        return mixer.next()
    }

    public static func secret(for date: DailyDate) -> RecipeCode { secret(seed: seed(for: date)) }

    /// A uniformly drawn recipe from the seed's stream, redrawn while it follows the tray order
    /// strictly up or down (112 of 6720: the guesses a player makes by just reading the tray).
    public static func secret(seed: UInt64) -> RecipeCode {
        var rng = SplitMix64(seed: seed)
        var recipe = RecipeCode.all[rng.nextInt(below: RecipeCode.permutationCount)]
        var draws = 1
        while recipe.isTrayOrdered, draws < maxDraws {
            recipe = RecipeCode.all[rng.nextInt(below: RecipeCode.permutationCount)]
            draws += 1
        }
        return recipe
    }

    public static func game(for date: DailyDate) -> RecipeGame { RecipeGame(secret: secret(for: date)) }
}

/// Practice recipes: unlimited, from any seed; never stored, never counted.
public enum RecipePractice {
    /// Seeds are mixed apart from the daily stream, so practice seed N is not a daily's recipe.
    public static func secret(seed: UInt64) -> RecipeCode {
        var mixer = SplitMix64(seed: seed ^ 0x5EC2_E7AE_C1BE_0001)
        return RecipeDaily.secret(seed: mixer.next())
    }

    public static func game(seed: UInt64) -> RecipeGame { RecipeGame(secret: secret(seed: seed)) }
}

/// The spoiler-free share text: one row of drops per guess, never the ingredients.
public enum RecipeShare {
    public static let gold = "🟡"
    public static let silver = "⚪"
    public static let empty = "⚫"

    /// "🟡🟡⚪⚫⚫": gold for in place, silver for in the recipe elsewhere, black for the rest.
    public static func row(_ feedback: RecipeFeedback) -> String {
        String(repeating: gold, count: feedback.exact) + String(repeating: silver, count: feedback.misplaced)
            + String(repeating: empty, count: max(0, RecipeCode.length - feedback.common))
    }

    public static func grid(_ turns: [RecipeTurn]) -> String {
        turns.map { row($0.feedback) }.joined(separator: "\n")
    }

    /// "4/8", or "X/8" for a lost game ("…/8" while still playing).
    public static func score(_ game: RecipeGame) -> String {
        switch game.status {
        case .won: "\(game.turns.count)/\(RecipeGame.maxGuesses)"
        case .lost: "X/\(RecipeGame.maxGuesses)"
        case .playing: "…/\(RecipeGame.maxGuesses)"
        }
    }

    /// A header line (the app passes a localized one) followed by the grid.
    public static func text(header: String, game: RecipeGame) -> String {
        header + "\n" + grid(game.turns)
    }

    /// English default: "Pourfect Secret Recipe 2026-11-17 4/8" and the grid.
    public static func dailyText(date: DailyDate, game: RecipeGame) -> String {
        text(header: "Pourfect Secret Recipe \(date.isoString) \(score(game))", game: game)
    }
}
