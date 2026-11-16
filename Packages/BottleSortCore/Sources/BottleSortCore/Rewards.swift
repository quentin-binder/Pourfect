import Foundation

// Cosmetic rewards (R7): workbench themes, flask shapes and completion effects, each unlocked by
// a milestone of play (no currency). Pure data and rules; the app draws them and stores the
// player's choice (`GameSettings.cosmetics`). Thresholds: DECISIONS 238.

/// What a reward changes.
public enum CosmeticCategory: String, CaseIterable, Codable, Sendable {
    /// The painted backdrop behind the board (`bg_workbench_*` or a theme painting).
    case theme
    /// The silhouette every flask of the board is drawn with.
    case flask
    /// What bursts out of a flask when it is completed and corked.
    case effect
}

/// The painted workbench behind the board.
public enum WorkbenchTheme: String, CaseIterable, Codable, Sendable {
    case workbench, forestHut, frostLab, dragonLair
}

/// The silhouette of the flasks. Drawing only: capacity, hit areas and layout never change.
public enum FlaskShapeStyle: String, CaseIterable, Codable, Sendable {
    case classic, potionBottle, roundBottom, conical
}

/// What happens when a flask is completed (with motion on; Reduce Motion shows none).
public enum PotionEffect: String, CaseIterable, Codable, Sendable {
    case sparkle, bubbles, fireflies, starburst
}

/// A goal reached by playing. Every non-starter reward names one, and the wardrobe shows it as
/// "how to earn it" with the player's progress.
public enum Milestone: Hashable, Sendable {
    /// Owned from the start.
    case starter
    /// Every recipe of main-path chapter N solved (at least one star each).
    case finishChapter(Int)
    /// Stars on the main path (chapters only; challenge books never count).
    case totalStars(Int)
    /// Gold seals anywhere (chapters and challenge books).
    case goldSeals(Int)
    /// Best Rush score (recipes solved in one run).
    case rushBest(Int)
    /// Best daily streak (consecutive UTC days solved).
    case dailyStreak(Int)

    /// How far `stats` is towards this milestone.
    public func progress(in stats: PlayerStats) -> MilestoneProgress {
        switch self {
        case .starter:
            return MilestoneProgress(current: 1, target: 1)
        case .finishChapter(let number):
            let chapter = stats.chapters[number] ?? MilestoneProgress(current: 0, target: 0)
            // A chapter that doesn't ship can't be finished: target stays above zero.
            return MilestoneProgress(current: chapter.current, target: max(1, chapter.target))
        case .totalStars(let n):
            return MilestoneProgress(current: stats.mainStars, target: n)
        case .goldSeals(let n):
            return MilestoneProgress(current: stats.goldSeals, target: n)
        case .rushBest(let n):
            return MilestoneProgress(current: stats.rushBest, target: n)
        case .dailyStreak(let n):
            return MilestoneProgress(current: stats.bestDailyStreak, target: n)
        }
    }

    public func isReached(by stats: PlayerStats) -> Bool { progress(in: stats).isReached }
}

/// Progress towards a milestone. `current` may exceed `target`.
public struct MilestoneProgress: Hashable, Sendable {
    public var current: Int
    public var target: Int

    public init(current: Int, target: Int) {
        self.current = current
        self.target = target
    }

    public var isReached: Bool { current >= target }
    /// 0…1, for a progress bar.
    public var fraction: Double { target <= 0 ? 1 : min(1, Double(max(0, current)) / Double(target)) }
}

/// Everything the milestones read, gathered from the saved progress. Plain numbers, so the
/// rules are testable without the app.
public struct PlayerStats: Hashable, Sendable {
    /// Per main-path chapter number: recipes solved (≥ 1 star) out of its recipes.
    public var chapters: [Int: MilestoneProgress]
    public var mainStars: Int
    public var goldSeals: Int
    public var rushBest: Int
    public var bestDailyStreak: Int

    public init(chapters: [Int: MilestoneProgress] = [:], mainStars: Int = 0, goldSeals: Int = 0,
                rushBest: Int = 0, bestDailyStreak: Int = 0) {
        self.chapters = chapters
        self.mainStars = mainStars
        self.goldSeals = goldSeals
        self.rushBest = rushBest
        self.bestDailyStreak = bestDailyStreak
    }

    /// Gathers the stats from saved progress.
    /// - `chapters`: the shipped main-path chapters as (number, recipe ids). Only these count for
    ///   stars and chapter goals; stars of challenge books, random brews or the daily never do.
    /// - `sealable`: every shipped recipe id that can hold a gold seal (chapters and books); seals
    ///   of ids that no longer ship are not counted.
    /// - `bonus`: chapter recipes that are bonus recipes (customer orders, R7). As for the chapter
    ///   gate, their stars count but finishing a chapter doesn't need them, so recipes appended to
    ///   a chapter never take back a theme already earned.
    public static func gather(chapters: [(number: Int, recipeIDs: [String])], stars: [String: Int],
                              goldSeals: Set<String>, sealable: [String], rushBest: Int,
                              bestDailyStreak: Int, bonus: Set<String> = []) -> PlayerStats {
        var perChapter: [Int: MilestoneProgress] = [:]
        var mainStars = 0
        for chapter in chapters {
            mainStars += chapter.recipeIDs.map { ChapterGate.clampedStars(stars[$0]) }.reduce(0, +)
            let required = chapter.recipeIDs.filter { !bonus.contains($0) }
            perChapter[chapter.number] = MilestoneProgress(
                current: required.filter { ChapterGate.clampedStars(stars[$0]) > 0 }.count,
                target: required.count)
        }
        return PlayerStats(chapters: perChapter, mainStars: mainStars,
                           goldSeals: Set(sealable).intersection(goldSeals).count,
                           rushBest: max(0, rushBest), bestDailyStreak: max(0, bestDailyStreak))
    }
}

/// One cosmetic reward.
public struct Reward: Identifiable, Hashable, Sendable {
    public enum Item: Hashable, Sendable {
        case theme(WorkbenchTheme)
        case flask(FlaskShapeStyle)
        case effect(PotionEffect)
    }

    public let item: Item
    public let milestone: Milestone

    public init(_ item: Item, milestone: Milestone) {
        self.item = item
        self.milestone = milestone
    }

    /// Stable id, e.g. `theme.forestHut` (saved in the "already announced" set).
    public var id: String {
        switch item {
        case .theme(let t): "theme." + t.rawValue
        case .flask(let f): "flask." + f.rawValue
        case .effect(let e): "effect." + e.rawValue
        }
    }

    public var category: CosmeticCategory {
        switch item {
        case .theme: .theme
        case .flask: .flask
        case .effect: .effect
        }
    }

    public var isStarter: Bool { milestone == .starter }
}

/// The reward table and its rules.
public enum Rewards {
    /// Every reward, by category, starter first, then in the order they are usually earned.
    /// Thresholds spread over the whole game (DECISIONS 238): 10 chapters, 314 main recipes
    /// (942 stars) plus 27 bonus order recipes, 421 sealable recipes (with the challenge books).
    public static let all: [Reward] = [
        Reward(.theme(.workbench), milestone: .starter),
        Reward(.theme(.forestHut), milestone: .finishChapter(3)),
        Reward(.theme(.frostLab), milestone: .finishChapter(6)),
        Reward(.theme(.dragonLair), milestone: .finishChapter(10)),

        Reward(.flask(.classic), milestone: .starter),
        Reward(.flask(.potionBottle), milestone: .totalStars(100)),
        Reward(.flask(.roundBottom), milestone: .goldSeals(10)),
        Reward(.flask(.conical), milestone: .rushBest(10)),

        Reward(.effect(.sparkle), milestone: .starter),
        Reward(.effect(.bubbles), milestone: .dailyStreak(3)),
        Reward(.effect(.fireflies), milestone: .totalStars(400)),
        Reward(.effect(.starburst), milestone: .goldSeals(50)),
    ]

    public static func rewards(in category: CosmeticCategory) -> [Reward] {
        all.filter { $0.category == category }
    }

    public static func reward(for item: Reward.Item) -> Reward {
        // Every item has exactly one entry (tested).
        all.first { $0.item == item } ?? Reward(item, milestone: .starter)
    }

    /// Ids of the rewards `stats` has earned (starters always).
    public static func unlocked(_ stats: PlayerStats) -> Set<String> {
        Set(all.filter { $0.milestone.isReached(by: stats) }.map(\.id))
    }

    /// Earned rewards not announced yet, in table order. Starters are never announced.
    public static func newlyUnlocked(_ unlocked: Set<String>, announced: Set<String>) -> [Reward] {
        all.filter { !$0.isStarter && unlocked.contains($0.id) && !announced.contains($0.id) }
    }
}

/// The player's choice per category. A choice that isn't (or no longer) unlocked falls back to
/// the starter when resolved, so a stored choice can never show a locked reward.
public struct CosmeticSelection: Hashable, Codable, Sendable {
    public var theme: WorkbenchTheme
    public var flask: FlaskShapeStyle
    public var effect: PotionEffect

    public init(theme: WorkbenchTheme = .workbench, flask: FlaskShapeStyle = .classic,
                effect: PotionEffect = .sparkle) {
        self.theme = theme
        self.flask = flask
        self.effect = effect
    }

    public static let starter = CosmeticSelection()

    /// This selection with every locked choice replaced by its category's starter.
    public func resolved(unlocked: Set<String>) -> CosmeticSelection {
        let ok = { (item: Reward.Item) in unlocked.contains(Rewards.reward(for: item).id) || Rewards.reward(for: item).isStarter }
        return CosmeticSelection(theme: ok(.theme(theme)) ? theme : .workbench,
                                 flask: ok(.flask(flask)) ? flask : .classic,
                                 effect: ok(.effect(effect)) ? effect : .sparkle)
    }
}
