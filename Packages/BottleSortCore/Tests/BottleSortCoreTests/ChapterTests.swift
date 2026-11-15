import Foundation
import Testing
@testable import BottleSortCore

@Suite struct ChapterGateTests {
    @Test func maxStarsIsThreePerRecipe() {
        #expect(ChapterGate.maxStars(recipeCount: 30) == 90)
        #expect(ChapterGate.maxStars(recipeCount: 0) == 0)
        #expect(ChapterGate.maxStars(recipeCount: -2) == 0)
    }

    @Test func firstChapterIsAlwaysOpen() {
        #expect(ChapterGate.isChapterUnlocked(1, previous: nil))
        #expect(ChapterGate.isChapterUnlocked(1, previous: ChapterProgress(stars: 0, recipeCount: 40)))
    }

    @Test func laterChapterNeedsHalfThePreviousStars() {
        // 30 recipes → 90 stars; exactly half (45) opens, 44 doesn't.
        #expect(!ChapterGate.isChapterUnlocked(2, previous: ChapterProgress(stars: 44, recipeCount: 30)))
        #expect(ChapterGate.isChapterUnlocked(2, previous: ChapterProgress(stars: 45, recipeCount: 30)))
        #expect(ChapterGate.isChapterUnlocked(2, previous: ChapterProgress(stars: 90, recipeCount: 30)))
        #expect(!ChapterGate.isChapterUnlocked(2, previous: ChapterProgress(stars: 0, recipeCount: 30)))
        #expect(!ChapterGate.isChapterUnlocked(3, previous: nil))
    }

    @Test func oddMaximumRoundsUp() {
        // 5 recipes → 15 stars: 7.5 needed, so 8.
        #expect(ChapterGate.requiredStars(maxStars: 15) == 8)
        #expect(!ChapterGate.meetsGate(stars: 7, maxStars: 15))
        #expect(ChapterGate.meetsGate(stars: 8, maxStars: 15))
        #expect(ChapterProgress(stars: 7, maxStars: 15).starsToOpenNext == 1)
        #expect(ChapterProgress(stars: 8, maxStars: 15).starsToOpenNext == 0)
        #expect(ChapterProgress(stars: 15, maxStars: 15).starsToOpenNext == 0)
    }

    @Test func emptyPreviousChapterDoesNotBlock() {
        #expect(ChapterGate.isChapterUnlocked(2, previous: ChapterProgress(stars: 0, maxStars: 0)))
    }

    @Test func unlockedChaptersChain() {
        let progress = [
            ChapterProgress(stars: 60, recipeCount: 40),  // 60/120: exactly half → ch. 2 open
            ChapterProgress(stars: 10, recipeCount: 30),  // 10/90 → ch. 3 closed
            ChapterProgress(stars: 90, recipeCount: 30),  // ch. 3 has all stars, but it is closed → ch. 4 closed
            ChapterProgress(stars: 0, recipeCount: 30),
        ]
        #expect(ChapterGate.unlockedChapters(progress) == [true, true, false, false])
        #expect(ChapterGate.isChapterUnlocked(4, previous: progress[2]))  // the single-step rule alone would open it
        #expect(ChapterGate.unlockedChapters([]) == [])
        let all = [ChapterProgress(stars: 0, recipeCount: 0)]
        #expect(ChapterGate.unlockedChapters(all) == [true])
    }

    @Test func recipeUnlockFollowsThePreviousRecipe() {
        let ids = ["c2_001", "c2_002", "c2_003"]
        let cleared: Set<String> = ["c2_001"]
        #expect(ChapterGate.isRecipeUnlocked(at: 0, in: ids) { cleared.contains($0) })
        #expect(ChapterGate.isRecipeUnlocked(at: 1, in: ids) { cleared.contains($0) })
        #expect(!ChapterGate.isRecipeUnlocked(at: 2, in: ids) { cleared.contains($0) })
        #expect(!ChapterGate.isRecipeUnlocked(at: 9, in: ids) { cleared.contains($0) })
        #expect(ChapterGate.isRecipeUnlocked(at: 0, previousCleared: false))
        #expect(!ChapterGate.isRecipeUnlocked(at: 3, previousCleared: false))
        #expect(ChapterGate.isRecipeUnlocked(at: 3, previousCleared: true))
    }

    @Test func packProgressSumsClampedStars() {
        let level = { (id: String) in LevelDefinition(id: id, state: state([[0, 0, 0, 0]])) }
        let pack = LevelPack(kind: .chapter, chapter: 1, levels: ["a", "b", "c", "d"].map(level))
        let saved: [String: Int] = ["a": 3, "b": 2, "c": 7, "x": 3]  // c clamps to 3, x isn't in the pack
        let progress = pack.progress { saved[$0] }
        #expect(progress == ChapterProgress(stars: 8, maxStars: 12))
        #expect(progress.opensNextChapter)
        #expect(pack.maxStars == 12)
        #expect(ChapterGate.clampedStars(-1) == 0)
        #expect(ChapterGate.clampedStars(nil) == 0)
    }

    @Test func planListsTenChapters() {
        #expect(ChapterOutline.plan.map(\.number) == Array(1...10))
        #expect(ChapterOutline.plan[1].location == "Rune Vault")
        #expect(ChapterOutline.plan[2].introduces == [.murky])
    }
}

@Suite struct PackMetadataTests {
    @Test func oldFilesLoadWithoutMetadata() throws {
        let json = #"{"version": 1, "name": "Old", "levels": [{"id": "a", "capacity": 1, "bottles": [{"layers": [0]}]}]}"#
        let pack = try LevelLoader.load(Data(json.utf8))
        #expect(pack.kind == nil && pack.chapter == nil && pack.location == nil && pack.introduces == nil)
        #expect(!pack.isChapter)
    }

    @Test func metadataRoundTrips() throws {
        let pack = LevelPack(name: "Rune Vault", subtitle: "Sealed flasks", kind: .chapter, chapter: 2,
                             location: "Rune Vault", introduces: [.sealed],
                             levels: [LevelDefinition(id: "a", state: state([[0, 0], [1, 1]], capacity: 2))])
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""kind" : "chapter""#))
        #expect(text.contains(#""sealed""#))
        let loaded = try LevelLoader.load(data)
        #expect(loaded == pack)
        #expect(loaded.isChapter)
    }

    @Test func unknownMechanicsStillLoad() throws {
        let json = #"{"version": 1, "kind": "chapter", "chapter": 4, "introduces": ["essence"], "levels": []}"#
        let pack = try LevelLoader.load(Data(json.utf8))
        #expect(pack.introduces == ["essence"])
    }

    @Test func chapterNeedsANumber() {
        let missing = #"{"version": 1, "kind": "chapter", "levels": []}"#
        #expect(throws: LevelLoadError.missingChapterNumber) { try LevelLoader.load(Data(missing.utf8)) }
        let zero = #"{"version": 1, "kind": "chapter", "chapter": 0, "levels": []}"#
        #expect(throws: LevelLoadError.missingChapterNumber) { try LevelLoader.load(Data(zero.utf8)) }
        let challenge = #"{"version": 1, "kind": "challenge", "levels": []}"#
        #expect(throws: Never.self) { try LevelLoader.load(Data(challenge.utf8)) }
    }
}

@Suite struct LockImpactTests {
    /// Key on top, lock on a flask that just needs one more layer: opening it is the only
    /// extra move, so the lock doesn't matter.
    @Test func trivialLockDoesNotMatter() throws {
        let s = GameState(bottles: [
            Bottle(layers: [.color(0), .color(0), .color(0)], capacity: 4, lockedBy: 1),
            Bottle(layers: [.color(0), .key(1)], capacity: 4),
            Bottle([1, 1, 1, 1], capacity: 4),
        ])
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 2)  // key, then 0 into the opened flask
        #expect(!LockImpact.lockMatters(1, in: s, minMoves: moves.count))
        #expect(!LockImpact.everyLockMatters(s, minMoves: moves.count))
        let removed = LockImpact.removingLock(1, from: s)
        #expect(removed.bottles[0].lockedBy == nil)
        #expect(removed.bottles[1].layers == [.color(0)])
    }

    /// Key on top and the sealed flask only needs emptying: the key pour is the only extra
    /// move, so this seal doesn't matter either (3 moves vs. 2 without it).
    @Test func keyOnTopDoesNotMatter() throws {
        let s = GameState(bottles: [
            Bottle(layers: [.color(1), .color(0), .color(0)], capacity: 3, lockedBy: 1),
            Bottle(layers: [.color(0), .key(1)], capacity: 3),
            Bottle([1, 1], capacity: 3),
        ])
        #expect(s.validate().isEmpty)
        #expect(s.legalMoves() == [Move(from: 1, to: 0)])  // only the key can move
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 3)
        #expect(Solver().solve(LockImpact.removingLock(1, from: s)).moves?.count == 2)
        #expect(!LockImpact.everyLockMatters(s, minMoves: moves.count))
    }

    /// The c2_001 tutorial: the key sits under a run, so the seal changes the order of play.
    @Test func tutorialLockMatters() throws {
        let s = GameState(bottles: [
            Bottle(layers: [.color(1), .color(2), .color(0)], capacity: 3, lockedBy: 1),
            Bottle([0, 0, 2], capacity: 3),
            Bottle(layers: [.key(1), .color(1), .color(1)], capacity: 3),
            Bottle([2], capacity: 3),
            Bottle(capacity: 3),
        ])
        #expect(s.validate().isEmpty)
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 6)
        let unsealed = try #require(Solver().solve(LockImpact.removingLock(1, from: s)).moves)
        #expect(moves.count > unsealed.count + 1)
        #expect(LockImpact.everyLockMatters(s, minMoves: moves.count))
    }

    /// Two locks: each is checked on its own.
    @Test func everyLockIsCheckedSeparately() {
        let s = GameState(bottles: [
            Bottle(layers: [.color(1), .color(2), .color(0)], capacity: 3, lockedBy: 1),
            Bottle([0, 0, 2], capacity: 3),
            Bottle(layers: [.key(1), .color(1), .color(1)], capacity: 3),
            Bottle([2], capacity: 3),
            Bottle(capacity: 3),
            Bottle(layers: [.color(3), .color(3)], capacity: 3, lockedBy: 2),
            Bottle(layers: [.color(3), .key(2)], capacity: 3),
        ])
        #expect(s.validate().isEmpty)
        guard let moves = Solver().solve(s).moves else { Issue.record("not solved"); return }
        #expect(LockImpact.lockMatters(1, in: s, minMoves: moves.count))
        #expect(!LockImpact.lockMatters(2, in: s, minMoves: moves.count))
        #expect(!LockImpact.everyLockMatters(s, minMoves: moves.count))
    }

    @Test func noLocksAlwaysPasses() {
        #expect(LockImpact.everyLockMatters(state([[0, 1], [1, 0], []], capacity: 2), minMoves: 3))
    }

    @Test func generatorCanRequireLocksThatMatter() throws {
        let config = GeneratorConfig(colors: 4, emptyBottles: 2, locks: 1, seed: 1, requireLocksMatter: true)
        let levels = try Generator.generate(config, count: 3)
        for level in levels {
            #expect(LockImpact.everyLockMatters(level.state, minMoves: level.report.minMoves))
        }
    }
}
