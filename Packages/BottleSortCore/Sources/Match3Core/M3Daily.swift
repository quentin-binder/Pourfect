import BottleSortCore

/// The weekday flavour of the daily match-3 level.
public enum M3DailyTier: String, Sendable, Hashable, Codable, CaseIterable {
    case gentle, steady, frost, crates, flasks, tricky, grand

    /// English name; the app localizes its own labels.
    public var name: String {
        switch self {
        case .gentle: "Gentle"
        case .steady: "Steady"
        case .frost: "Frosty"
        case .crates: "Sealed Crates"
        case .flasks: "Flask Drop"
        case .tricky: "Tricky"
        case .grand: "Grand Gathering"
        }
    }
}

/// What a weekday's daily match-3 level looks like.
public struct M3DailySpec: Sendable, Hashable {
    public var weekday: Weekday
    public var tier: M3DailyTier
    public var kinds: Int
    public var frost: Bool
    public var crates: Bool
    public var flasks: Bool
    /// Target pass rate of the reference bot, percent.
    public var targetPercent: Int
    /// Accepted move limits.
    public var moveRange: ClosedRange<Int>

    /// "Monday · Gentle"
    public var label: String { "\(weekday.name) · \(tier.name)" }
}

public struct M3DailyGeneration: Sendable {
    public var date: DailyDate
    public var spec: M3DailySpec
    public var level: M3Level
    /// Measured pass rate (percent) of the reference bot at the level's move limit.
    public var passRate: Int
    /// Candidates built (1 = the first was accepted).
    public var candidates: Int
}

/// Daily match-3 level, generator id "m3daily-v1" (separate from the Daily Brew, which is untouched).
/// Everything derives from the UTC date: candidate boards from a date-seeded stream, tuned by the
/// reference bot with a fixed bot stream; integer maths only, so every device builds the same level.
public enum M3Daily {
    public static let algorithmVersion = "m3daily-v1"
    /// Bot games per candidate.
    public static let runs = 40
    public static let maxCandidates = 6
    /// Collect-count rescaling rounds per candidate.
    public static let tuneIterations = 4
    /// The measured pass rate must be within this many points of the target.
    public static let passWindow = 15

    public static func levelID(for date: DailyDate) -> String { "m3daily-\(date.isoString)" }

    public static func spec(for date: DailyDate) -> M3DailySpec { spec(for: date.weekday) }

    public static func spec(for weekday: Weekday) -> M3DailySpec {
        switch weekday {
        case .monday: M3DailySpec(weekday: weekday, tier: .gentle, kinds: 5, frost: false, crates: false, flasks: false,
                                  targetPercent: 85, moveRange: 16...30)
        case .tuesday: M3DailySpec(weekday: weekday, tier: .steady, kinds: 5, frost: false, crates: false, flasks: false,
                                   targetPercent: 75, moveRange: 18...32)
        case .wednesday: M3DailySpec(weekday: weekday, tier: .frost, kinds: 5, frost: true, crates: false, flasks: false,
                                     targetPercent: 72, moveRange: 18...34)
        case .thursday: M3DailySpec(weekday: weekday, tier: .crates, kinds: 5, frost: false, crates: true, flasks: false,
                                    targetPercent: 70, moveRange: 18...34)
        case .friday: M3DailySpec(weekday: weekday, tier: .flasks, kinds: 5, frost: false, crates: false, flasks: true,
                                  targetPercent: 68, moveRange: 18...38)
        case .saturday: M3DailySpec(weekday: weekday, tier: .tricky, kinds: 6, frost: true, crates: true, flasks: false,
                                    targetPercent: 62, moveRange: 20...40)
        case .sunday: M3DailySpec(weekday: weekday, tier: .grand, kinds: 5, frost: true, crates: true, flasks: true,
                                  targetPercent: 58, moveRange: 22...42)
        }
    }

    public static func baseSeed(for date: DailyDate) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(algorithmVersion)|\(date.isoString)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        var mixer = SplitMix64(seed: hash)
        return mixer.next()
    }

    public static func level(for date: DailyDate) -> M3Level { generate(for: date).level }

    /// Builds up to `maxCandidates` candidates; the first whose tuned move limit is in the spec's
    /// range and whose pass rate is within `passWindow` of the target wins, else the candidate whose
    /// pass rate is closest to the target.
    public static func generate(for date: DailyDate) -> M3DailyGeneration {
        let spec = spec(for: date)
        var rng = SplitMix64(seed: baseSeed(for: date))
        var best: (M3TuneResult, Int)?
        for n in 1...maxCandidates {
            let levelSpec = candidate(spec, date: date, rng: &rng)
            guard let result = M3Tuner.tune(levelSpec, runs: runs, botSeed: 0xDA11, maxIterations: tuneIterations) else { continue }
            let distance = abs(result.summary.passRate - spec.targetPercent)
            let ok = spec.moveRange.contains(result.level.moves) && distance <= passWindow
            if ok { return M3DailyGeneration(date: date, spec: spec, level: result.level, passRate: result.summary.passRate, candidates: n) }
            if best == nil || distance < abs(best!.0.summary.passRate - spec.targetPercent) { best = (result, n) }
        }
        if let (result, _) = best {
            return M3DailyGeneration(date: date, spec: spec, level: result.level, passRate: result.summary.passRate,
                                     candidates: maxCandidates)
        }
        // Unreachable in practice: a plain board always tunes.
        let fallback = M3LevelSpec(id: levelID(for: date), title: spec.label, layout: Array(repeating: "ooooooo", count: 7),
                                   kinds: Array(M3Kind.allCases.prefix(5)), goals: [.collect(.mushroom, 20)],
                                   targetPercent: 80, moveRange: 16...30, seed: 1)
        let result = M3Tuner.tune(fallback, runs: runs, botSeed: 0xDA11)!
        return M3DailyGeneration(date: date, spec: spec, level: result.level, passRate: result.summary.passRate,
                                 candidates: maxCandidates + 1)
    }

    static let shapes: [[String]] = [
        Array(repeating: "oooooooo", count: 8),
        [".oooooo.", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", ".oooooo."],
        ["oooooooo", "oooooooo", "oooooooo", "ooo..ooo", "ooo..ooo", "oooooooo", "oooooooo", "oooooooo"],
        ["..oooo..", "..oooo..", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "..oooo..", "..oooo.."],
        Array(repeating: "ooooooo", count: 7),
        ["..ooo..", ".ooooo.", "ooooooo", "ooooooo", "ooooooo", ".ooooo.", "..ooo.."],
    ]

    /// One candidate, drawn from the stream in this order: shape, frost cells, crate rows, flask
    /// columns, kinds' collect goals, level seed.
    static func candidate(_ spec: M3DailySpec, date: DailyDate, rng: inout SplitMix64) -> M3LevelSpec {
        var grid = shapes[rng.nextInt(below: shapes.count)].map(Array.init)
        let h = grid.count, w = grid[0].count
        func set(_ r: Int, _ c: Int, _ ch: Character) {
            guard r >= 0, r < h, c >= 0, c < w, grid[r][c] == "o" else { return }
            grid[r][c] = ch
        }
        var goals: [M3Goal] = []
        if spec.frost {
            // Mirror-symmetric frost in the middle rows.
            let cells = 3 + rng.nextInt(below: 3)
            let layers: Character = rng.nextInt(below: 2) == 0 ? "1" : "2"
            for _ in 0..<cells {
                let r = 1 + rng.nextInt(below: max(1, h - 4))
                let c = rng.nextInt(below: (w + 1) / 2)
                set(r, c, layers)
                set(r, w - 1 - c, layers)
            }
            goals.append(.frost)
        }
        if spec.crates {
            let rows = 1 + rng.nextInt(below: 2)
            let hits: Character = rng.nextInt(below: 2) == 0 ? "A" : "B"
            for r in (h - rows)..<h {
                for c in 0..<w { set(r, c, hits) }
            }
            goals.append(.crates)
        }
        var drops: M3Drops?
        if spec.flasks {
            let total = 2 + rng.nextInt(below: 2)
            let col = 1 + rng.nextInt(below: w - 2)
            set(0, col, "F")
            if grid[0][col] != "F" { set(1, col, "F") }
            drops = M3Drops(total: total, maxOnBoard: 1)
            goals.append(.drops(total))
        }
        let kinds = Array(M3Kind.allCases.prefix(spec.kinds))
        let collectGoals = spec.frost || spec.crates || spec.flasks ? 1 : 2
        var pool = kinds
        for _ in 0..<collectGoals {
            let k = pool.remove(at: rng.nextInt(below: pool.count))
            let count = (collectGoals == 2 ? 18 : 14) + rng.nextInt(below: 8)
            goals.append(.collect(k, count))
        }
        let seed = rng.next() & 0x1F_FFFF_FFFF_FFFF
        return M3LevelSpec(id: levelID(for: date), title: spec.label, layout: grid.map { String($0) }, kinds: kinds,
                           goals: goals, drops: drops, targetPercent: spec.targetPercent, moveRange: spec.moveRange,
                           seed: seed)
    }
}
