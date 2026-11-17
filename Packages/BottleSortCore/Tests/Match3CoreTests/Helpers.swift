import BottleSortCore
import Foundation
@testable import Match3Core

let fiveKinds: [M3Kind] = [.mushroom, .crystal, .feather, .moonflower, .ember]

func testLevel(width: Int, height: Int, kinds: [M3Kind] = fiveKinds, goals: [M3Goal] = [.score(1_000_000)],
               moves: Int = 20, drops: M3Drops? = nil, seed: UInt64 = 42) -> M3Level {
    M3Level(id: "t", title: "Test", seed: seed, layout: Array(repeating: String(repeating: "o", count: width), count: height),
            kinds: kinds, moves: moves, goals: goals, stars: M3StarThresholds(two: 1000, three: 2000), drops: drops)
}

/// A game on an exact board (see `M3Board.picture` for the tokens).
func game(_ picture: String, kinds: [M3Kind] = fiveKinds, goals: [M3Goal] = [.score(1_000_000)], moves: Int = 20,
          drops: M3Drops? = nil, seed: UInt64 = 42) -> M3Game {
    let board = M3Board(picture: picture)
    return M3Game(level: testLevel(width: board.width, height: board.height, kinds: kinds, goals: goals, moves: moves,
                                   drops: drops, seed: seed), board: board)
}

func P(_ r: Int, _ c: Int) -> M3Pos { M3Pos(r, c) }
func S(_ r1: Int, _ c1: Int, _ r2: Int, _ c2: Int) -> M3Swap { M3Swap(P(r1, c1), P(r2, c2)) }

/// Plays a swap and returns the result (keeps `#expect` free of mutating calls).
func play(_ g: inout M3Game, _ s: M3Swap) -> M3StepResult { g.play(s) }

/// The repo's Levels/match3 folder.
let match3LevelsURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Levels/match3")

func loadEpisode(_ n: Int) throws -> M3EpisodeFile {
    try M3EpisodeFile.decode(Data(contentsOf: match3LevelsURL.appendingPathComponent(M3Content.fileName(n))))
}

/// Bot-heavy tests (daily goldens, pass-rate samples, preset re-tuning) take ~5 s optimized but minutes in a
/// debug build: they run in `scripts/test-fast.sh` (optimized) and in debug only with LP_SLOW_TESTS=1.
let heavyTestsEnabled: Bool = {
    #if DEBUG
    return ProcessInfo.processInfo.environment["LP_SLOW_TESTS"] == "1"
    #else
    return true
    #endif
}()
