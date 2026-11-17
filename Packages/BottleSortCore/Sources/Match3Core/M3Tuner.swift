import BottleSortCore

/// A level before tuning: everything but the move limit and the star thresholds. Collect and score
/// goal counts are scaled by the tuner so the suggested move limit lands in `moveRange`.
public struct M3LevelSpec: Sendable, Hashable {
    public var id: String
    public var title: String
    public var layout: [String]
    public var kinds: [M3Kind]
    public var goals: [M3Goal]
    public var drops: M3Drops?
    /// Target pass rate of the reference bot, percent.
    public var targetPercent: Int
    public var moveRange: ClosedRange<Int>
    public var seed: UInt64

    public init(id: String, title: String, layout: [String], kinds: [M3Kind], goals: [M3Goal], drops: M3Drops? = nil,
                targetPercent: Int, moveRange: ClosedRange<Int>, seed: UInt64) {
        self.id = id
        self.title = title
        self.layout = layout
        self.kinds = kinds
        self.goals = goals
        self.drops = drops
        self.targetPercent = targetPercent
        self.moveRange = moveRange
        self.seed = seed
    }

    /// The level with collect and score counts scaled by `scale` %: collect counts rounded to a multiple of 5
    /// (at least 10), score targets to a multiple of 500 (at least 1000).
    public func level(scale: Int, seed: UInt64, moves: Int = 30,
                      stars: M3StarThresholds = M3StarThresholds(two: 1000, three: 2000)) -> M3Level {
        let goals = goals.map { g -> M3Goal in
            guard let c = g.count, g.type == .collect || g.type == .score else { return g }
            var s = g
            let scaled = c * scale / 100
            s.count = g.type == .score ? max(1000, (scaled + 250) / 500 * 500) : max(10, (scaled + 2) / 5 * 5)
            return s
        }
        return M3Level(id: id, title: title, seed: seed, layout: layout, kinds: kinds, moves: moves, goals: goals,
                       stars: stars, drops: drops)
    }
}

public struct M3TuneResult: Sendable {
    public var level: M3Level
    public var summary: M3SimSummary
    /// Collect-goal scale used, percent.
    public var scale: Int
    public var iterations: Int
}

public enum M3Tuner {
    /// Tunes a spec: plays `runs` reference-bot games (bot stream `botSeed`), sets the move limit to
    /// the smallest one at which ≥ target % of the runs pass, and the star thresholds from the
    /// winners' final scores. If the limit falls outside `moveRange`, collect and score counts are rescaled
    /// (proportionally, up to `maxIterations` rounds) and the level is re-measured. A seed whose start board can't
    /// be built moves on to the next seed. Integer maths only, so the result is reproducible.
    public static func tune(_ spec: M3LevelSpec, runs: Int, botSeed: UInt64 = 1,
                            policy: M3BotPolicy = .reference, maxIterations: Int = 8) -> M3TuneResult? {
        var scale = 100
        var seed = spec.seed
        var best: M3TuneResult?
        for iteration in 1...maxIterations {
            var level = spec.level(scale: scale, seed: seed)
            if M3Game(level: level) == nil { seed &+= 1; continue }
            let results = M3Bot.simulate(level, policy: policy, runs: runs, botSeed: botSeed)
            guard let limit = M3Bot.suggestMoves(results, targetPercent: spec.targetPercent) else {
                scale = max(10, scale * 60 / 100)
                continue
            }
            let moves = min(99, limit)
            level.moves = moves
            level.stars = M3Bot.suggestStars(results, limit: moves)
            let summary = M3Bot.summarize(results, limit: moves, stars: level.stars)
            level.tuning = M3Tuning(target: spec.targetPercent, passRate: summary.passRate, runs: runs)
            best = M3TuneResult(level: level, summary: summary, scale: scale, iterations: iteration)
            let scalable = spec.goals.contains { $0.type == .collect || $0.type == .score }
            if spec.moveRange.contains(limit) || !scalable { break }
            let mid = (spec.moveRange.lowerBound + spec.moveRange.upperBound) / 2
            let next = max(10, min(400, scale * mid / max(1, limit)))
            if next == scale { break }
            scale = next
        }
        return best
    }
}
