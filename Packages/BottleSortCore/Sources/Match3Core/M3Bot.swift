import BottleSortCore

/// How a bot picks its swap. With `randomPercent` % it plays a uniformly random valid swap (a
/// human's slip); otherwise it plays the best one-wave heuristic value (`M3Bot.value`), ties broken
/// uniformly. All of its randomness comes from its OWN stream, never the level's.
public struct M3BotPolicy: Sendable, Hashable, Codable {
    public var name: String
    public var randomPercent: Int

    public init(name: String, randomPercent: Int) {
        self.name = name
        self.randomPercent = randomPercent
    }

    /// Always the best-looking swap (random tie-break).
    public static let greedy = M3BotPolicy(name: "greedy", randomPercent: 0)
    /// The tuning reference: greedy, with 15 % random slips (DECISIONS 260).
    public static let reference = M3BotPolicy(name: "reference", randomPercent: 15)
    /// A careless player: 40 % random.
    public static let novice = M3BotPolicy(name: "novice", randomPercent: 40)
    /// Uniformly random valid swaps.
    public static let random = M3BotPolicy(name: "random", randomPercent: 100)

    public static let all: [M3BotPolicy] = [.greedy, .reference, .novice, .random]

    public static func named(_ name: String) -> M3BotPolicy? { all.first { $0.name == name } }
}

/// One bot game played with a generous move cap.
public struct M3BotRun: Sendable {
    public var won: Bool
    /// Moves until the goals were met (or until the run gave up).
    public var movesUsed: Int
    /// Score when the goals were met (before any finale).
    public var scoreAtWin: Int
    /// The game at the moment of the win (for finales with any move limit).
    public var winState: M3Game?

    /// Whether this run passes with `limit` moves: the bot never looks at the move counter, so a
    /// run with the cap is the same run with any limit up to its win.
    public func passes(limit: Int) -> Bool { won && movesUsed <= limit }

    /// Final score with `limit` moves (the finale uses the leftover moves); nil if it doesn't pass.
    public func finalScore(limit: Int) -> Int? {
        guard passes(limit: limit), var g = winState else { return nil }
        g.setMovesLeft(limit - movesUsed)
        return g.playFinale().finalScore
    }
}

/// Pass-rate summary for one move limit.
public struct M3SimSummary: Sendable, Hashable, CustomStringConvertible {
    public var runs: Int
    public var limit: Int
    public var wins: Int
    /// Percent, rounded down.
    public var passRate: Int { runs == 0 ? 0 : wins * 100 / runs }
    /// Average leftover moves of the winning runs, ×10 (integer maths).
    public var avgMovesLeftTimes10: Int
    /// Final scores of the winning runs (finale included), ascending.
    public var scores: [Int]
    public var stars: [Int]  // count of 0,1,2,3-star results

    public func scorePercentile(_ p: Int) -> Int {
        guard !scores.isEmpty else { return 0 }
        return scores[min(scores.count - 1, max(0, scores.count * p / 100))]
    }

    public var description: String {
        let left = "\(avgMovesLeftTimes10 / 10).\(avgMovesLeftTimes10 % 10)"
        return "pass \(passRate)% (\(wins)/\(runs)) at \(limit) moves, avg left \(left), score p10/p50/p90 "
            + "\(scorePercentile(10))/\(scorePercentile(50))/\(scorePercentile(90)), stars 0-3 \(stars)"
    }
}

public enum M3Bot {
    /// Move cap for tuning runs.
    public static let defaultCap = 99

    /// Heuristic value of wave 1 of a swap for the current goals (integers only).
    public static func value(_ wave: M3Wave, in game: M3Game) -> Int {
        let level = game.level
        var need = [Int](repeating: 0, count: 6)
        var frostGoal = false, crateGoal = false, scoreGoal = false
        for g in level.goals {
            switch g.type {
            case .collect: if let k = g.kind { need[k.index] = max(0, (g.count ?? 0) - game.collected[k.index]) }
            case .frost: frostGoal = true
            case .crates: crateGoal = true
            case .score: scoreGoal = true
            case .drops: break
            }
        }
        var v = 0
        for c in wave.cleared {
            if let k = c.piece.kind, need[k.index] > 0 { v += 10; need[k.index] -= 1 } else { v += 1 }
        }
        v += wave.frostHits.count * (frostGoal ? 12 : 2)
        v += wave.crateHits.count * (crateGoal ? 12 : 2)
        for s in wave.created {
            switch s.piece.special {
            case .row, .column: v += 8
            case .bloom: v += 10
            case .prism: v += 14
            case nil: break
            }
        }
        v += wave.activations.count * 2
        if scoreGoal { v += wave.score / 20 }
        if level.hasDrops {
            // Cells cleared below a flask in its column bring it closer to the bottom.
            let board = game.board
            var flaskRow = [Int](repeating: -1, count: board.width)
            for i in board.cells.indices where board.cells[i].item == .flask {
                let p = board.pos(i)
                flaskRow[p.col] = max(flaskRow[p.col], p.row)
            }
            for c in wave.cleared where flaskRow[c.at.col] >= 0 && c.at.row > flaskRow[c.at.col] { v += 15 }
        }
        return v
    }

    /// The bot's swap (nil if none).
    public static func choose(_ game: M3Game, policy: M3BotPolicy, rng: inout SplitMix64) -> M3Swap? {
        let swaps = game.validSwaps
        if swaps.isEmpty { return nil }
        if policy.randomPercent > 0, rng.nextInt(below: 100) < policy.randomPercent {
            return swaps[rng.nextInt(below: swaps.count)]
        }
        var best: [M3Swap] = []
        var bestValue = Int.min
        for s in swaps {
            guard let wave = game.preview(s) else { continue }
            let v = value(wave, in: game)
            if v > bestValue { bestValue = v; best = [s] } else if v == bestValue { best.append(s) }
        }
        return best.isEmpty ? nil : best[rng.nextInt(below: best.count)]
    }

    /// Plays `level` once with `cap` moves.
    public static func run(_ level: M3Level, policy: M3BotPolicy, botSeed: UInt64, cap: Int = defaultCap) -> M3BotRun {
        var capped = level
        capped.moves = cap
        guard var game = M3Game(level: capped) else { return M3BotRun(won: false, movesUsed: cap, scoreAtWin: 0) }
        var rng = SplitMix64(seed: botSeed)
        while game.status == .playing {
            guard let s = choose(game, policy: policy, rng: &rng) else { break }
            _ = game.play(s)
        }
        if game.status == .won {
            return M3BotRun(won: true, movesUsed: game.movesUsed, scoreAtWin: game.score, winState: game)
        }
        return M3BotRun(won: false, movesUsed: game.movesUsed, scoreAtWin: 0)
    }

    /// `runs` games with bot seeds derived from `botSeed`.
    public static func simulate(_ level: M3Level, policy: M3BotPolicy, runs: Int, botSeed: UInt64 = 1,
                                cap: Int = defaultCap) -> [M3BotRun] {
        (0..<runs).map { i in
            run(level, policy: policy, botSeed: botSeed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15, cap: cap)
        }
    }

    /// Pass rate, moves left and scores of `runs` with move limit `limit` and the given thresholds.
    public static func summarize(_ runs: [M3BotRun], limit: Int, stars: M3StarThresholds) -> M3SimSummary {
        var wins = 0, left = 0
        var scores: [Int] = []
        var starCounts = [0, 0, 0, 0]
        for r in runs {
            guard let score = r.finalScore(limit: limit) else { starCounts[0] += 1; continue }
            wins += 1
            left += limit - r.movesUsed
            scores.append(score)
            starCounts[stars.stars(score: score, won: true)] += 1
        }
        return M3SimSummary(runs: runs.count, limit: limit, wins: wins,
                            avgMovesLeftTimes10: wins == 0 ? 0 : left * 10 / wins, scores: scores.sorted(),
                            stars: starCounts)
    }

    /// The move limit whose pass rate is closest to `targetPercent`: the smallest limit with at least
    /// the target, or one move less if that is closer (ties keep the larger limit). nil if even the
    /// cap passes too few runs.
    public static func suggestMoves(_ runs: [M3BotRun], targetPercent: Int) -> Int? {
        let needed = runs.map { $0.won ? $0.movesUsed : Int.max }.sorted()
        guard !needed.isEmpty else { return nil }
        let k = max(1, (needed.count * targetPercent + 99) / 100)
        let limit = needed[k - 1]
        if limit == Int.max { return nil }
        func rate(_ l: Int) -> Int { needed.filter { $0 <= l }.count * 100 }  // percent × runs
        let target = targetPercent * needed.count
        if limit > 1, abs(rate(limit - 1) - target) < abs(rate(limit) - target) { return limit - 1 }
        return limit
    }

    /// Star thresholds from the winning runs' final scores with `limit` moves: two stars at the 35th
    /// percentile, three at the 80th, rounded down to 50 points (two ≥ 50, three > two).
    public static func suggestStars(_ runs: [M3BotRun], limit: Int) -> M3StarThresholds {
        let scores = runs.compactMap { $0.finalScore(limit: limit) }.sorted()
        guard !scores.isEmpty else { return M3StarThresholds(two: 1000, three: 2000) }
        func pct(_ p: Int) -> Int { scores[min(scores.count - 1, scores.count * p / 100)] / 50 * 50 }
        let two = max(50, pct(35))
        let three = max(two + 50, pct(80))
        return M3StarThresholds(two: two, three: three)
    }
}

extension M3Game {
    /// A helpful swap for the idle hint: the best one-wave value (first in row-major order on ties).
    /// Free and deterministic; nil if no swap is valid.
    public func hint() -> M3Swap? {
        guard status == .playing else { return nil }
        var best: M3Swap?
        var bestValue = Int.min
        for s in validSwaps {
            guard let wave = preview(s) else { continue }
            let v = M3Bot.value(wave, in: self)
            if v > bestValue { bestValue = v; best = s }
        }
        return best
    }
}
