/// Stars earned in one chapter (or any pack) out of the possible maximum.
public struct ChapterProgress: Sendable, Hashable {
    public var stars: Int
    public var maxStars: Int

    public init(stars: Int, maxStars: Int) {
        self.stars = stars
        self.maxStars = maxStars
    }

    public init(stars: Int, recipeCount: Int) {
        self.init(stars: stars, maxStars: ChapterGate.maxStars(recipeCount: recipeCount))
    }

    /// At least half of the possible stars: the next chapter opens.
    public var opensNextChapter: Bool { ChapterGate.meetsGate(stars: stars, maxStars: maxStars) }

    /// Stars still missing before the next chapter opens (0 once it is open).
    public var starsToOpenNext: Int { max(0, ChapterGate.requiredStars(maxStars: maxStars) - stars) }
}

/// Main-path progression (DECISIONS.md #63): chapter 1 is always open; chapter n > 1 opens
/// when chapter n − 1 has at least half of its possible stars (3 per recipe). Inside a chapter,
/// recipe 1 is open and each further recipe opens when the one before it is cleared.
/// Challenge packs are never gated.
public enum ChapterGate {
    public static let starsPerRecipe = 3

    public static func maxStars(recipeCount: Int) -> Int { starsPerRecipe * max(0, recipeCount) }

    /// Saved stars for one recipe, clamped to 0...3 (nil = never cleared).
    public static func clampedStars(_ stars: Int?) -> Int { min(max(stars ?? 0, 0), starsPerRecipe) }

    /// `stars × 2 ≥ maxStars`, i.e. at least 50 % (exactly half counts).
    public static func meetsGate(stars: Int, maxStars: Int) -> Bool { stars * 2 >= maxStars }

    /// Fewest stars that meet the gate: ⌈maxStars / 2⌉.
    public static func requiredStars(maxStars: Int) -> Int { (max(0, maxStars) + 1) / 2 }

    /// Whether chapter `number` (1-based) is open, given the previous chapter's progress.
    /// Chapter 1 ignores `previous`; for later chapters a missing `previous` means locked.
    public static func isChapterUnlocked(_ number: Int, previous: ChapterProgress?) -> Bool {
        if number <= 1 { return true }
        return previous?.opensNextChapter ?? false
    }

    /// Open flags for chapters 1…n, in order. A chapter also needs every earlier chapter open,
    /// so stars left over in a chapter that is locked again (e.g. after a content update) don't skip ahead.
    public static func unlockedChapters(_ progress: [ChapterProgress]) -> [Bool] {
        var result: [Bool] = []
        for i in progress.indices {
            let open = i == 0 || (result[i - 1] && isChapterUnlocked(i + 1, previous: progress[i - 1]))
            result.append(open)
        }
        return result
    }

    /// Whether the recipe at `index` (0-based) inside a chapter is open: the first always is,
    /// later ones once the previous recipe is cleared.
    public static func isRecipeUnlocked(at index: Int, previousCleared: Bool) -> Bool {
        index <= 0 || previousCleared
    }

    /// Same rule over a chapter's recipe ids; `isCleared(id)` tells whether a recipe was finished.
    /// A recipe that is itself cleared always stays open, so its stars never hide behind a lock.
    public static func isRecipeUnlocked(at index: Int, in recipeIDs: [String], isCleared: (String) -> Bool) -> Bool {
        guard index > 0 else { return true }
        if recipeIDs.indices.contains(index), isCleared(recipeIDs[index]) { return true }
        guard recipeIDs.indices.contains(index - 1) else { return false }
        return isCleared(recipeIDs[index - 1])
    }
}

/// One entry on the chapter map, shipped or not.
public struct ChapterOutline: Sendable, Hashable {
    public var number: Int
    public var location: String
    /// Mechanics the chapter introduces (the planned ones for chapters not shipped yet).
    public var introduces: [Mechanic]

    public init(number: Int, location: String, introduces: [Mechanic]) {
        self.number = number
        self.location = location
        self.introduces = introduces
    }

    /// The planned main path (MECHANICS.md §3). Chapters 1–6 ship as `Levels/chapter_0N.json`;
    /// the app shows the rest as "coming soon" until a pack with that chapter number exists.
    public static let plan: [ChapterOutline] = [
        ChapterOutline(number: 1, location: "Apprentice Cellar", introduces: [.basic]),
        ChapterOutline(number: 2, location: "Rune Vault", introduces: [.sealed]),
        ChapterOutline(number: 3, location: "Misty Marsh", introduces: [.murky]),
        ChapterOutline(number: 4, location: "Glyph Library", introduces: [.essence]),
        ChapterOutline(number: 5, location: "Glass Works", introduces: [.narrowNeck, .funnel, .tap]),
        ChapterOutline(number: 6, location: "Frost Peak", introduces: [.frozen]),
        ChapterOutline(number: 7, location: "Bubbling Bog", introduces: ["bubbling"]),
        ChapterOutline(number: 8, location: "Twin Towers", introduces: ["twin", "overflow"]),
        ChapterOutline(number: 9, location: "Alchemist's Hall", introduces: ["cauldron"]),
        ChapterOutline(number: 10, location: "Dragon's Hoard", introduces: ["switch"]),
    ]
}
