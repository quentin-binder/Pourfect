import Foundation
@testable import BottleSortCore

func state(_ bottles: [[Int]], capacity: Int = 4) -> GameState {
    GameState(bottles: bottles.map { Bottle($0, capacity: capacity) })
}

/// Naive reference BFS: no pruning, no canonicalization. Returns the optimal
/// number of moves, or nil if unsolvable. Only for small puzzles.
func referenceMinMoves(_ start: GameState) -> Int? {
    if start.isSolved { return 0 }
    var seen: Set<GameState> = [start]
    var frontier = [start]
    var depth = 0
    while !frontier.isEmpty {
        depth += 1
        var next: [GameState] = []
        for s in frontier {
            for m in s.legalMoves() {
                let child = s.pouring(m)!
                if child.isSolved { return depth }
                if seen.insert(child).inserted { next.append(child) }
            }
        }
        frontier = next
    }
    return nil
}

/// Slow tests (long performance runs) are opt-in: `LP_SLOW_TESTS=1 swift test`.
/// The default `swift test` stays fast for development; run the slow ones before a release.
let slowTestsEnabled = ProcessInfo.processInfo.environment["LP_SLOW_TESTS"] == "1"
