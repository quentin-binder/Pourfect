import BottleSortCore
import Foundation
import Testing
@testable import Match3Core

@Suite struct M3LevelFormatTests {
    static let valid = M3Level(
        id: "m3-x-1", title: "X", seed: 123,
        layout: [".oooooo.", "ooFooooo", "oo1122oo", "oooooooo", "oooooooo", "oooooooo", "ABCooooo", "oooooooo"],
        kinds: fiveKinds, moves: 25,
        goals: [.collect(.mushroom, 20), .frost, .crates, .drops(2), .score(5000)],
        stars: M3StarThresholds(two: 8000, three: 12000), drops: M3Drops(total: 2, maxOnBoard: 1, columns: [2, 3]),
        pieces: [M3PlacedPiece(row: 3, col: 3, kind: .crystal, special: .bloom), M3PlacedPiece(row: 2, col: 2, kind: .ember),
                 M3PlacedPiece(row: 4, col: 4, kind: nil, special: .prism)])

    @Test func jsonRoundTrip() throws {
        let file = M3EpisodeFile(episode: M3Episode(number: 3, name: "N", subtitle: "S", followsChapter: 3), levels: [Self.valid])
        let data = try file.encoded()
        let back = try M3EpisodeFile.decode(data)
        #expect(back == file)
        #expect(try back.encoded() == data)
        #expect(file.validate().isEmpty)
    }

    @Test func decodesHandWrittenJSON() throws {
        let json = """
        {"format": "pourfect-match3", "version": 1,
         "episode": {"number": 1, "name": "Mushroom Hollow", "subtitle": "s", "followsChapter": 1},
         "levels": [{"id": "a", "title": "A", "seed": 7, "layout": ["ooooo", "ooooo", "ooooo", "ooooo"],
                     "kinds": ["mushroom", "crystal", "feather", "moonflower"], "moves": 20,
                     "goals": [{"type": "collect", "kind": "mushroom", "count": 12}],
                     "stars": {"two": 1000, "three": 2000}}]}
        """
        let file = try M3EpisodeFile.decode(Data(json.utf8))
        #expect(file.validate().isEmpty)
        #expect(file.levels[0].goals == [.collect(.mushroom, 12)])
        #expect(file.levels[0].drops == nil)
    }

    @Test func startBoardFollowsTheLayoutAndIsPlayable() {
        let g = M3Game(level: Self.valid)!
        let b = g.board
        #expect(!b[0, 0].exists && !b[0, 7].exists)
        #expect(b[1, 2].item == .flask)
        #expect(b[6, 0].crate == 1 && b[6, 1].crate == 2 && b[6, 2].crate == 3)
        #expect(b[2, 2].piece == M3Piece(kind: .ember, frost: 1))
        #expect(b[2, 4].piece?.frost == 2)
        #expect(b[3, 3].piece == M3Piece(kind: .crystal, special: .bloom))
        #expect(b[4, 4].piece == .prism())
        #expect(!M3Rules.hasMatch(b))
        #expect(M3Rules.hasValidSwap(b))
        #expect(g.startFrost == 6)
        #expect(g.startCrates == 6)
        #expect(g.flasksSpawned == 1)
        // Same seed, same board; another seed, another board.
        #expect(M3Game(level: Self.valid)!.board == b)
        var other = Self.valid
        other.seed = 124
        #expect(M3Game(level: other)!.board != b)
    }

    @Test func startBoardsHaveNoMatchAndASwapForManySeeds() {
        for seed in UInt64(0)..<200 {
            let level = testLevel(width: 6, height: 6, kinds: [.mushroom, .crystal, .feather], seed: seed)
            guard let g = M3Game(level: level) else { Issue.record("no start for seed \(seed)"); continue }
            #expect(!M3Rules.hasMatch(g.board))
            #expect(M3Rules.hasValidSwap(g.board))
        }
    }

    @Test func validationReportsEachProblem() {
        func errors(_ change: (inout M3Level) -> Void) -> [M3ValidationError] {
            var level = Self.valid
            change(&level)
            return level.validate()
        }
        #expect(Self.valid.validate().isEmpty)
        #expect(errors { $0.layout = ["oo", "oo"] } == [.badSize(width: 2, height: 2)])
        #expect(errors { $0.layout = Array(repeating: "ooooooooo", count: 4) } == [.badSize(width: 9, height: 4)])
        #expect(errors { $0.layout[3] = "ooooooo" } == [.raggedLayout])
        #expect(errors { $0.layout[3] = "ooooxooo" } == [.unknownLayoutCharacter("x")])
        #expect(errors { $0.layout = ["...", ".o.", "..."]; $0.goals = [.score(10)]; $0.drops = nil; $0.pieces = nil }
                .contains(.tooFewCells(1)))
        #expect(errors { $0.kinds = [.mushroom, .crystal] }.contains(.kindCount(2)))
        #expect(errors { $0.kinds = [.mushroom, .crystal, .mushroom, .ember] }.contains(.duplicateKinds))
        #expect(errors { $0.moves = 0 }.contains(.moves(0)))
        #expect(errors { $0.goals = [] }.contains(.noGoals))
        #expect(errors { $0.goals.append(.collect(.mushroom, 5)) }.contains(.duplicateGoal(.collect)))
        #expect(errors { $0.goals = [.collect(.mushroom, 0)] }.contains(.goalCount(.collect)))
        #expect(errors { $0.goals = [M3Goal(type: .collect, count: 4)] }.contains(.collectKindMissing))
        #expect(errors { $0.goals = [.collect(.drop, 4)] }.contains(.collectKindNotInLevel(.drop)))
        #expect(errors { $0.layout[2] = "oooooooo" }.contains(.frostGoalWithoutFrost))
        #expect(errors { $0.layout[6] = "oooooooo" }.contains(.crateGoalWithoutCrates))
        #expect(errors { $0.drops = nil }.contains(.dropsGoalWithoutDrops))
        #expect(errors { $0.drops = M3Drops(total: 3, maxOnBoard: 1, columns: [2, 3]) }.contains(.dropsGoalMismatch(goal: 2, total: 3)))
        #expect(errors { $0.drops = M3Drops(total: 2, maxOnBoard: 0) }.contains(.dropsConfig))
        #expect(errors { $0.drops = M3Drops(total: 2, maxOnBoard: 1, columns: [9]) }.contains(.dropsConfig))
        #expect(errors { $0.layout[7] = "oooFoooo" }.contains(.flaskAtBottom(M3Pos(7, 3))))
        #expect(errors { $0.stars = M3StarThresholds(two: 500, three: 500) }.contains(.starThresholds))
        #expect(errors { $0.pieces = [M3PlacedPiece(row: 9, col: 0, kind: .mushroom)] }.contains(.placedPieceOutside(M3Pos(9, 0))))
        #expect(errors { $0.pieces = [M3PlacedPiece(row: 6, col: 0, kind: .mushroom)] }
                .contains(.placedPieceNotOnPieceCell(M3Pos(6, 0))))
        #expect(errors { $0.pieces = [M3PlacedPiece(row: 3, col: 0, kind: .drop)] }.contains(.placedPieceKind(M3Pos(3, 0))))
        #expect(errors { $0.pieces = [M3PlacedPiece(row: 3, col: 0, kind: .mushroom, special: .prism)] }
                .contains(.placedPieceKind(M3Pos(3, 0))))
        #expect(errors { $0.pieces = [M3PlacedPiece(row: 3, col: 0, kind: .mushroom), M3PlacedPiece(row: 3, col: 0, kind: .ember)] }
                .contains(.duplicatePlacedPiece(M3Pos(3, 0))))
        #expect(errors { $0.pieces = (0..<3).map { M3PlacedPiece(row: 5, col: $0, kind: .ember) } } == [.placedPiecesMatch])
        let file = M3EpisodeFile(episode: M3Episode(number: 11, name: "", subtitle: "", followsChapter: 11), levels: [Self.valid, Self.valid])
        #expect(file.validate() == [.badEpisode(11), .duplicateID("m3-x-1")])
    }

    @Test func aBoardWithoutAnySwapIsNotPlayable() {
        // Two rows of holes between single cells: nothing can ever line up.
        let level = M3Level(id: "x", title: "X", seed: 1, layout: ["o.o.o", ".o.o.", "o.o.o", ".o.o."], kinds: fiveKinds, moves: 10,
                            goals: [.score(100)], stars: M3StarThresholds(two: 1, three: 2))
        #expect(level.validate() == [.noPlayableStart])
        #expect(M3Game(level: level) == nil)
    }
}

@Suite struct ShippedEpisodeTests {
    @Test func everyEpisodeLoadsAndValidates() throws {
        var ids = Set<String>()
        for n in 1...10 {
            let file = try loadEpisode(n)
            #expect(file.validate().isEmpty, "episode \(n): \(file.validate())")
            #expect(file.episode.number == n)
            #expect(file.episode.followsChapter == n)
            #expect(file.levels.count == M3Content.levelsPerEpisode)
            for (i, level) in file.levels.enumerated() {
                #expect(ids.insert(level.id).inserted)
                #expect(level.id == M3Content.episodes[n - 1].specs[i].id)
                #expect(level.seed == M3Content.seed(episode: n, level: i + 1) || level.seed > M3Content.seed(episode: n, level: i + 1))
                #expect(level.tuning?.target == M3Content.targetPercent(episode: n, level: i + 1))
                #expect((15...40).contains(level.moves), "\(level.id) has \(level.moves) moves")
                #expect(M3Game(level: level) != nil)
                // The curve: frost from episode 3, crates from 5, flasks from 7; four kinds only early in episode 1.
                if n < 3 { #expect(!level.hasFrost) }
                if n < 5 { #expect(!level.hasCrates) }
                if n < 7 { #expect(!level.hasDrops) }
                if level.kinds.count == 4 { #expect(n == 1) }
                #expect((4...6).contains(level.kinds.count))
                // Collect goals use the episode's ingredients.
                for g in level.goals where g.type == .collect { #expect(level.kinds.contains(g.kind!)) }
            }
        }
        #expect(ids.count == 80)
        // Targets fall from 90 % to 55 %.
        #expect(M3Content.targetPercent(episode: 1, level: 1) == 90)
        #expect(M3Content.targetPercent(episode: 10, level: 8) == 55)
    }

    @Test(.enabled(if: heavyTestsEnabled)) func passRatesStayNearTheirTargets() throws {
        // A small sample with a bot stream the tuner never used (the full check is `m3gen report`).
        for n in [1, 4, 7, 10] {
            let file = try loadEpisode(n)
            for level in [file.levels[0], file.levels[5]] {
                let runs = M3Bot.simulate(level, policy: .reference, runs: 40, botSeed: 4_242)
                let rate = M3Bot.summarize(runs, limit: level.moves, stars: level.stars).passRate
                #expect(abs(rate - level.tuning!.target) <= 25, "\(level.id): \(rate)% vs \(level.tuning!.target)%")
            }
        }
    }

    @Test(.enabled(if: heavyTestsEnabled)) func thePresetTunesReproducibly() throws {
        // The first level of episode 1 re-tunes to exactly what is shipped.
        let spec = M3Content.episodes[0].specs[0]
        let tuned = M3Tuner.tune(spec, runs: M3Content.tuningRuns)!
        #expect(tuned.level == (try loadEpisode(1)).levels[0])
    }
}

@Suite struct BotTests {
    @Test func botsAreDeterministicAndOnlyPlayValidSwaps() throws {
        let level = try loadEpisode(2).levels[0]
        let a = M3Bot.simulate(level, policy: .reference, runs: 5, botSeed: 9)
        let b = M3Bot.simulate(level, policy: .reference, runs: 5, botSeed: 9)
        #expect(a.map(\.movesUsed) == b.map(\.movesUsed))
        #expect(a.map(\.scoreAtWin) == b.map(\.scoreAtWin))
        var g = M3Game(level: level)!
        var rng = SplitMix64(seed: 1)
        for _ in 0..<10 {
            guard let s = M3Bot.choose(g, policy: .novice, rng: &rng) else { break }
            #expect(g.isValidSwap(s))
            _ = play(&g, s)
        }
    }

    @Test func greedyBeatsRandom() throws {
        let level = try loadEpisode(1).levels[2]
        let greedy = M3Bot.summarize(M3Bot.simulate(level, policy: .greedy, runs: 30), limit: level.moves, stars: level.stars)
        let random = M3Bot.summarize(M3Bot.simulate(level, policy: .random, runs: 30), limit: level.moves, stars: level.stars)
        #expect(greedy.passRate > random.passRate)
    }

    @Test func suggestionsMatchTheirDefinition() throws {
        let level = try loadEpisode(1).levels[0]
        let runs = M3Bot.simulate(level, policy: .reference, runs: 50)
        let moves = M3Bot.suggestMoves(runs, targetPercent: 80)!
        let rate = M3Bot.summarize(runs, limit: moves, stars: level.stars).passRate
        let below = M3Bot.summarize(runs, limit: moves - 1, stars: level.stars).passRate
        #expect(abs(rate - 80) <= abs(below - 80) || below < 80)
        let stars = M3Bot.suggestStars(runs, limit: moves)
        #expect(stars.two > 0 && stars.three > stars.two)
        #expect(stars.two % 50 == 0 && stars.three % 50 == 0)
    }
}

@Suite struct M3DailyTests {
    @Test(.enabled(if: heavyTestsEnabled)) func goldenDays() {
        let expected: [(String, String, Int, String)] = [
            ("2026-11-16", "Monday · Gentle", 23, "2b68c1426c4ff4ff"),
            ("2026-11-22", "Sunday · Grand Gathering", 33, "3d46367d7c7eb9b7"),
            ("2027-02-28", "Sunday · Grand Gathering", 28, "c97181a6ecd8ff69"),
        ]
        for (iso, label, moves, fingerprint) in expected {
            let date = DailyDate(isoString: iso)!
            let gen = M3Daily.generate(for: date)
            #expect(gen.spec.label == label)
            #expect(gen.level.id == "m3daily-\(iso)")
            #expect(gen.level.moves == moves)
            #expect(gen.level.fingerprint == fingerprint, "\(iso)")
            #expect(gen.level.validate().isEmpty)
        }
    }

    @Test func weekdayCurve() {
        let specs = Weekday.allCases.map(M3Daily.spec(for:))
        #expect(specs.map(\.tier) == M3DailyTier.allCases)
        #expect(zip(specs, specs.dropFirst()).allSatisfy { $0.targetPercent >= $1.targetPercent })
        #expect(!specs[0].frost && !specs[0].crates && !specs[0].flasks)
        #expect(specs[6].frost && specs[6].crates && specs[6].flasks)
        #expect(M3Daily.algorithmVersion == "m3daily-v1")
    }

    @Test(.enabled(if: heavyTestsEnabled)) func dailyLevelsMatchTheirSpec() {
        let start = DailyDate(isoString: "2026-12-01")!
        for d in 0..<7 {
            let date = start.adding(days: d)
            let gen = M3Daily.generate(for: date)
            #expect(gen.level.validate().isEmpty)
            #expect(gen.level.hasFrost == gen.spec.frost)
            #expect(gen.level.hasCrates == gen.spec.crates)
            #expect(gen.level.hasDrops == gen.spec.flasks)
            #expect(gen.level.kinds.count == gen.spec.kinds)
            #expect(abs(gen.passRate - gen.spec.targetPercent) <= M3Daily.passWindow || gen.candidates > M3Daily.maxCandidates - 1)
        }
    }

    @Test func dailyResultsUseTheStreakRules() {
        let date = DailyDate(isoString: "2026-11-16")!
        let three = M3Daily.result(date: date, movesUsed: 20, stars: 3, solvedAt: date.startDate.addingTimeInterval(60))
        let two = M3Daily.result(date: date.next, movesUsed: 20, stars: 2, solvedAt: date.next.startDate.addingTimeInterval(60))
        #expect(three.isPerfect && !two.isPerfect)
        let stats = DailyStreaks.stats([three, two], today: date.next)
        #expect(stats.currentStreak == 2)
        #expect(stats.perfectCount == 1)
    }
}

@Suite struct M3ProgressionTests {
    @Test func episodesFollowTheChapterGate() {
        let open = [true, true, true, false, false, false, false, false, false, false]  // chapters 1–3 open
        #expect(M3Progression.isEpisodeUnlocked(1, chapterUnlocked: open, finalChapterComplete: false))
        #expect(M3Progression.isEpisodeUnlocked(2, chapterUnlocked: open, finalChapterComplete: false))
        #expect(!M3Progression.isEpisodeUnlocked(3, chapterUnlocked: open, finalChapterComplete: false))
        let all = Array(repeating: true, count: 10)
        #expect(M3Progression.isEpisodeUnlocked(9, chapterUnlocked: all, finalChapterComplete: false))
        #expect(!M3Progression.isEpisodeUnlocked(10, chapterUnlocked: all, finalChapterComplete: false))
        #expect(M3Progression.isEpisodeUnlocked(10, chapterUnlocked: all, finalChapterComplete: true))
        #expect(!M3Progression.isEpisodeUnlocked(0, chapterUnlocked: all, finalChapterComplete: true))
        #expect(!M3Progression.isEpisodeUnlocked(11, chapterUnlocked: all, finalChapterComplete: true))
    }

    @Test func levelsOpenInOrder() {
        #expect(M3Progression.isLevelUnlocked(0, won: []))
        #expect(!M3Progression.isLevelUnlocked(1, won: [false]))
        #expect(M3Progression.isLevelUnlocked(1, won: [true]))
        #expect(!M3Progression.isLevelUnlocked(3, won: [true, true]))
    }

    @Test func openingScenePlaysOnce() {
        #expect(M3Progression.sceneOnOpening(episode: 4, seen: []) == "gathering.4")
        #expect(M3Progression.sceneOnOpening(episode: 4, seen: ["gathering.4"]) == nil)
        #expect(M3Progression.sceneOnOpening(episode: 12, seen: []) == nil)
        // The app plays these as `StoryScene.gathering(n)`, saved in the same seen set.
        #expect(Array(M3Progression.episodes) == Array(Story.gatherings))
        for n in M3Progression.episodes { #expect(StoryScene.gathering(n).id == M3Progression.sceneID(episode: n)) }
    }

    @Test func flasksNeedAColumnWithAnOpenCell() {
        // Column 0 is all holes: flasks allowed only there could never spawn, so the goal could never be met.
        func level(columns: [Int]?, layout: [String] = Array(repeating: ".oooo", count: 5)) -> M3Level {
            M3Level(id: "x", title: "X", seed: 1, layout: layout, kinds: fiveKinds, moves: 30, goals: [.drops(1)],
                    stars: M3StarThresholds(two: 1, three: 2), drops: M3Drops(total: 1, maxOnBoard: 1, columns: columns))
        }
        #expect(level(columns: [0]).validate() == [.dropsConfig])
        #expect(level(columns: [0, 2]).validate() == [])
        #expect(level(columns: nil).validate() == [])
        // A column of crates counts: the crates break and the cells open.
        let crates = ["Aoooo", "Aoooo", "Aoooo", "Aoooo", "Aoooo"]
        #expect(level(columns: [0], layout: crates).validate() == [])
    }
}
