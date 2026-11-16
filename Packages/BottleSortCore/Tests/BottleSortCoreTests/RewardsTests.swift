import Foundation
import Testing
@testable import BottleSortCore

/// R7: cosmetic rewards unlocked by milestones, and the story scene rules.
@Suite("Rewards & milestones")
struct RewardsTests {
    @Test func everyItemHasExactlyOneRewardAndOneStarterPerCategory() {
        let items = Rewards.all.map(\.item)
        #expect(Set(items).count == items.count)
        #expect(Set(Rewards.all.map(\.id)).count == Rewards.all.count)
        for theme in WorkbenchTheme.allCases { #expect(items.contains(.theme(theme))) }
        for flask in FlaskShapeStyle.allCases { #expect(items.contains(.flask(flask))) }
        for effect in PotionEffect.allCases { #expect(items.contains(.effect(effect))) }
        for category in CosmeticCategory.allCases {
            let starters = Rewards.rewards(in: category).filter(\.isStarter)
            #expect(starters.count == 1)
            #expect(Rewards.rewards(in: category).first?.isStarter == true)
        }
        // The starters are the selection's defaults.
        let starter = CosmeticSelection.starter
        #expect(Rewards.reward(for: .theme(starter.theme)).isStarter)
        #expect(Rewards.reward(for: .flask(starter.flask)).isStarter)
        #expect(Rewards.reward(for: .effect(starter.effect)).isStarter)
    }

    @Test func freshPlayerOwnsOnlyTheStarters() {
        let unlocked = Rewards.unlocked(PlayerStats())
        #expect(unlocked == Set(Rewards.all.filter(\.isStarter).map(\.id)))
        #expect(Rewards.newlyUnlocked(unlocked, announced: []).isEmpty)
    }

    @Test func milestonesUnlockAtTheirThresholds() {
        var stats = PlayerStats(mainStars: 99, goldSeals: 9, rushBest: 9, bestDailyStreak: 2)
        #expect(!Milestone.totalStars(100).isReached(by: stats))
        #expect(!Milestone.goldSeals(10).isReached(by: stats))
        #expect(!Milestone.rushBest(10).isReached(by: stats))
        #expect(!Milestone.dailyStreak(3).isReached(by: stats))
        stats.mainStars = 100; stats.goldSeals = 10; stats.rushBest = 10; stats.bestDailyStreak = 3
        let unlocked = Rewards.unlocked(stats)
        #expect(unlocked.isSuperset(of: ["flask.potionBottle", "flask.roundBottom", "flask.conical", "effect.bubbles"]))
        #expect(!unlocked.contains("effect.fireflies"))
        #expect(!unlocked.contains("theme.forestHut"))
        #expect(Milestone.totalStars(400).progress(in: stats) == MilestoneProgress(current: 100, target: 400))
        #expect(Milestone.totalStars(400).progress(in: stats).fraction == 0.25)
    }

    @Test func finishingAChapterNeedsEveryRecipeSolved() {
        let ids = (1...3).map { "c3_\($0)" }
        let chapters: [(number: Int, recipeIDs: [String])] = [(3, ids)]
        var stars = ["c3_1": 3, "c3_2": 1]
        var stats = PlayerStats.gather(chapters: chapters, stars: stars, goldSeals: [], sealable: ids,
                                       rushBest: 0, bestDailyStreak: 0)
        #expect(Milestone.finishChapter(3).progress(in: stats) == MilestoneProgress(current: 2, target: 3))
        #expect(!Rewards.unlocked(stats).contains("theme.forestHut"))
        stars["c3_3"] = 1
        stats = PlayerStats.gather(chapters: chapters, stars: stars, goldSeals: [], sealable: ids,
                                   rushBest: 0, bestDailyStreak: 0)
        #expect(Rewards.unlocked(stats).contains("theme.forestHut"))
        // A chapter that isn't shipped can never be finished.
        #expect(!Milestone.finishChapter(11).isReached(by: stats))
    }

    @Test func gatherCountsOnlyMainStarsAndShippedSeals() {
        let chapters: [(number: Int, recipeIDs: [String])] = [(1, ["a", "b"]), (2, ["c"])]
        let stars = ["a": 3, "b": 9, "c": 2, "challenge_x": 3, "daily": 3]   // 9 is clamped to 3
        let stats = PlayerStats.gather(chapters: chapters, stars: stars, goldSeals: ["a", "challenge_x", "gone"],
                                       sealable: ["a", "b", "c", "challenge_x"], rushBest: -1, bestDailyStreak: 4)
        #expect(stats.mainStars == 8)
        #expect(stats.goldSeals == 2)
        #expect(stats.rushBest == 0)
        #expect(stats.bestDailyStreak == 4)
        #expect(stats.chapters[1] == MilestoneProgress(current: 2, target: 2))
    }

    @Test func announcementsAreNewEarnedNonStartersInTableOrder() {
        let unlocked: Set<String> = ["theme.workbench", "effect.fireflies", "theme.forestHut", "flask.conical"]
        let fresh = Rewards.newlyUnlocked(unlocked, announced: ["flask.conical"])
        #expect(fresh.map(\.id) == ["theme.forestHut", "effect.fireflies"])
    }

    @Test func lockedChoicesFallBackToTheStarter() {
        let wanted = CosmeticSelection(theme: .dragonLair, flask: .conical, effect: .fireflies)
        let unlocked: Set<String> = ["flask.conical"]
        #expect(wanted.resolved(unlocked: unlocked) == CosmeticSelection(theme: .workbench, flask: .conical, effect: .sparkle))
        #expect(CosmeticSelection.starter.resolved(unlocked: []) == .starter)
        #expect(wanted.resolved(unlocked: Set(Rewards.all.map(\.id))) == wanted)
    }

    /// Every threshold is reachable with the shipped chapters and books.
    @Test func thresholdsAreReachableInTheShippedGame() throws {
        let chapters = try LevelFileTests.shippedPacks.filter { $0.hasPrefix("chapter_") }.map { name in
            let pack = try LevelFileTests.load(name)
            return (number: pack.chapter ?? 0, recipeIDs: pack.levels.map(\.id))
        }
        let books = try LevelFileTests.shippedPacks.filter { $0.hasPrefix("challenge_") }
            .flatMap { try LevelFileTests.load($0).levels.map(\.id) }
        let all = chapters.flatMap(\.recipeIDs) + books
        let perfect = PlayerStats.gather(chapters: chapters, stars: Dictionary(uniqueKeysWithValues: all.map { ($0, 3) }),
                                         goldSeals: Set(all), sealable: all, rushBest: 1000, bestDailyStreak: 1000)
        for reward in Rewards.all { #expect(reward.milestone.isReached(by: perfect), "\(reward.id)") }
        // The star goals need at most half of the main path's stars (942): no grinding for 3 stars.
        let starGoals = Rewards.all.compactMap { if case .totalStars(let n) = $0.milestone { n } else { nil } }
        #expect(starGoals.allSatisfy { 2 * $0 <= perfect.mainStars })
    }
}

/// Settings keep the cosmetic choice; older saves load with the starters.
@Suite struct CosmeticSettingsTests {
    @Test func cosmeticsRoundTripAndOldSavesLoadStarters() {
        let name = "BottleSortCoreTests.cosmetics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        defaults.set(false, forKey: UserDefaultsSettingsStore.Key.sound)   // a pre-R7 save
        #expect(store.load().cosmetics == .starter)
        var settings = store.load()
        settings.cosmetics = CosmeticSelection(theme: .frostLab, flask: .potionBottle, effect: .bubbles)
        store.save(settings)
        #expect(UserDefaultsSettingsStore(defaults: defaults).load() == settings)
        defaults.set("teapot", forKey: UserDefaultsSettingsStore.Key.flaskShape)
        #expect(store.load().cosmetics.flask == .classic)
        #expect(store.load().cosmetics.theme == .frostLab)
    }
}

@Suite("Story scenes")
struct StoryTests {
    @Test func openingScenesPlayOncePerChapter() {
        #expect(Story.sceneOnOpening(chapter: 1, seen: []) == .chapter(1))
        #expect(Story.sceneOnOpening(chapter: 10, seen: []) == .chapter(10))
        #expect(Story.sceneOnOpening(chapter: 4, seen: ["chapter.4"]) == nil)
        #expect(Story.sceneOnOpening(chapter: 4, seen: ["chapter.3", "ending"]) == .chapter(4))
        #expect(Story.sceneOnOpening(chapter: 0, seen: []) == nil)
        #expect(Story.sceneOnOpening(chapter: 11, seen: []) == nil)
    }

    @Test func endingPlaysAfterTheFinalRecipeOnce() {
        #expect(Story.sceneAfterWin(recipeID: "c10_32", finalRecipeID: "c10_32", seen: []) == .ending)
        #expect(Story.sceneAfterWin(recipeID: "c10_31", finalRecipeID: "c10_32", seen: []) == nil)
        #expect(Story.sceneAfterWin(recipeID: "c10_32", finalRecipeID: "c10_32", seen: ["ending"]) == nil)
        #expect(Story.sceneAfterWin(recipeID: "x", finalRecipeID: nil, seen: []) == nil)
    }

    @Test func idsRoundTripAndReplays() {
        for scene in Story.chapters.map(StoryScene.chapter) + [.ending] {
            #expect(StoryScene(id: scene.id) == scene)
        }
        #expect(StoryScene(id: "chapter.11") == nil)
        #expect(StoryScene(id: "chapter.x") == nil)
        #expect(Story.replayable(chapter: 3, seen: ["ending"]) == [.chapter(3)])
        #expect(Story.replayable(chapter: 10, seen: []) == [.chapter(10)])
        #expect(Story.replayable(chapter: 10, seen: ["ending"]) == [.chapter(10), .ending])
        #expect(Story.replayable(chapter: 12, seen: []).isEmpty)
    }

    /// The final chapter ships and is the last main-path chapter.
    @Test func finalChapterShips() throws {
        let numbers = try LevelFileTests.shippedPacks.filter { $0.hasPrefix("chapter_") }
            .compactMap { try LevelFileTests.load($0).chapter }
        #expect(numbers.max() == Story.finalChapter)
        #expect(Set(numbers) == Set(Story.chapters))
    }
}
