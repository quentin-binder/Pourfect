/// Which mechanics the daily puzzle uses.
public enum DailyMode: String, Sendable, Hashable, Codable, CaseIterable {
    case classic
    /// Sealed flasks & keys.
    case sealed
    /// Murky (hidden) layers.
    case murky
    /// Murky layers and a sealed flask.
    case murkySealed

    public var hasSeals: Bool { self == .sealed || self == .murkySealed }
    public var isMurky: Bool { self == .murky || self == .murkySealed }

    public var mechanics: [Mechanic] {
        switch self {
        case .classic: return [.basic]
        case .sealed: return [.sealed]
        case .murky: return [.murky]
        case .murkySealed: return [.murky, .sealed]
        }
    }
}

/// The difficulty name of a weekday's puzzle ("Monday · Gentle").
public enum DailyTier: String, Sendable, Hashable, Codable, CaseIterable {
    case gentle, steady, sealed, murky, tricky, deepSeal, grand

    /// English name; the app localizes its own labels.
    public var name: String {
        switch self {
        case .gentle: return "Gentle"
        case .steady: return "Steady"
        case .sealed: return "Sealed"
        case .murky: return "Murky"
        case .tricky: return "Tricky"
        case .deepSeal: return "Deep Seal"
        case .grand: return "Grand Brew"
        }
    }
}

/// What a day's puzzle looks like. Pure data, derived from the weekday only.
public struct DailySpec: Sendable, Hashable {
    public var weekday: Weekday
    public var tier: DailyTier
    public var mode: DailyMode
    public var colors: Int
    public var capacity: Int
    public var emptyBottles: Int
    /// Sealed flasks (0 unless the mode has seals).
    public var locks: Int
    /// Accepted optimal solution lengths for the first generation phase.
    public var minMoves: ClosedRange<Int>

    public var hidden: Bool { mode.isMurky }
    /// English label, e.g. "Monday · Gentle".
    public var label: String { "\(weekday.name) · \(tier.name)" }

    /// Generator settings (state cap only, no timeout; seals must matter at the minimum cost).
    func generatorConfig(window: ClosedRange<Int>?) -> GeneratorConfig {
        GeneratorConfig(colors: colors, capacity: capacity, emptyBottles: emptyBottles, locks: locks,
                        minMoves: window, requireLocksMatter: locks > 0, lockCost: LockImpact.minimumCost,
                        solverLimits: DailyPuzzle.solverLimits)
    }
}

/// The weekly difficulty curve: Monday easy → Sunday hardest.
public enum DailyPlan {
    /// Spec for a date. Depends only on its weekday.
    public static func spec(for date: DailyDate) -> DailySpec { spec(for: date.weekday) }

    /// Sealed days use one empty flask: the seal check then needs far smaller searches
    /// (measured per candidate on an M-series Mac, release: 5–7 colors + seal with 1 empty
    /// ≈ 2–20 ms, with 2 empties 40–400 ms). 7 colors classic ≈ 15 ms, 4–5 colors < 10 ms.
    public static func spec(for weekday: Weekday) -> DailySpec {
        switch weekday {
        case .monday:
            return DailySpec(weekday: weekday, tier: .gentle, mode: .classic, colors: 4, capacity: 4,
                             emptyBottles: 2, locks: 0, minMoves: 9...12)
        case .tuesday:
            return DailySpec(weekday: weekday, tier: .steady, mode: .classic, colors: 5, capacity: 4,
                             emptyBottles: 2, locks: 0, minMoves: 13...16)
        case .wednesday:
            return DailySpec(weekday: weekday, tier: .sealed, mode: .sealed, colors: 5, capacity: 4,
                             emptyBottles: 1, locks: 1, minMoves: 15...18)
        case .thursday:
            return DailySpec(weekday: weekday, tier: .murky, mode: .murky, colors: 5, capacity: 4,
                             emptyBottles: 2, locks: 0, minMoves: 13...17)
        case .friday:
            return DailySpec(weekday: weekday, tier: .tricky, mode: .classic, colors: 7, capacity: 4,
                             emptyBottles: 2, locks: 0, minMoves: 20...24)
        case .saturday:
            return DailySpec(weekday: weekday, tier: .deepSeal, mode: .sealed, colors: 7, capacity: 4,
                             emptyBottles: 1, locks: 1, minMoves: 20...24)
        case .sunday:
            return DailySpec(weekday: weekday, tier: .grand, mode: .murkySealed, colors: 7, capacity: 4,
                             emptyBottles: 1, locks: 1, minMoves: 20...24)
        }
    }
}

/// How a daily level was found.
public enum DailyGenerationPhase: Int, Sendable, Hashable, Codable {
    /// The day's spec with its minMoves window.
    case spec = 1
    /// The day's spec without the window.
    case relaxed
    /// A known-easy classic config (4 colors, 2 empty flasks).
    case easyFallback
    /// The built-in fixed level (never expected in practice).
    case fixedFallback
}

public struct DailyGeneration: Sendable, Hashable {
    public var date: DailyDate
    public var spec: DailySpec
    public var level: LevelDefinition
    public var phase: DailyGenerationPhase
    /// Candidates tried in total (all phases).
    public var attempts: Int
}

/// The daily puzzle: one level per UTC day, generated on device, the same for every
/// player worldwide.
///
/// Algorithm (version `algorithmVersion`):
/// 1. `baseSeed(for:)` = SplitMix64 finalizer of FNV-1a 64 over the UTF-8 bytes of
///    "<algorithmVersion>|<YYYY-MM-DD>".
/// 2. Phase `.spec`: candidates `Generator.candidate(spec config, seed: base + i)` for
///    i in 0..<`specAttempts`; a candidate passes `Generator`'s checks (no presolved flask,
///    solved within `solverLimits`, minMoves in the spec window, every seal matters at
///    `LockImpact.minimumCost`).
/// 3. Phase `.relaxed`: the same config without the window, seeds base + 1000 + i.
/// 4. Phase `.easyFallback`: 4 colors / size 4 / 2 empty classic (murky if the day is),
///    seeds base + 2000 + i, any solvable candidate.
/// 5. Phase `.fixedFallback`: a built-in level, so generation never fails.
///
/// Only state caps are used (no wall-clock timeout), no Dictionary/Set iteration
/// order and no system RNG, so a date gives a byte-identical level on every device.
/// **Any change to the plan, the generator, the solver's result for a state, or this
/// procedure must bump `algorithmVersion`** (the golden test fails as a reminder) —
/// otherwise players on different app versions get different puzzles for the same day.
public enum DailyPuzzle {
    public static let algorithmVersion = "daily-v2"
    /// Per-solve state cap. Daily configs solve in far fewer states; this only bounds
    /// pathological candidates. Deterministic (no timeout).
    public static let solverLimits = SolverLimits(maxStates: 300_000)
    public static let specAttempts = 60
    public static let relaxedAttempts = 60
    public static let fallbackAttempts = 100

    public static func levelID(for date: DailyDate) -> String { "daily-\(date.isoString)" }

    public static func baseSeed(for date: DailyDate) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(algorithmVersion)|\(date.isoString)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        var mixer = SplitMix64(seed: hash)
        return mixer.next()
    }

    /// The level for `date`. Throws `CancellationError` if the calling task is cancelled
    /// (a cancelled solve would otherwise change which candidate is accepted).
    public static func level(for date: DailyDate) throws -> LevelDefinition {
        try generate(for: date).level
    }

    public static func generate(for date: DailyDate) throws -> DailyGeneration {
        let spec = DailyPlan.spec(for: date)
        let base = baseSeed(for: date)
        var attempts = 0

        func search(_ config: GeneratorConfig, from offset: UInt64, count: Int) throws -> (GameState, UInt64, Int, Int)? {
            for i in 0..<count {
                let seed = base &+ offset &+ UInt64(i)
                let candidate = Generator.candidate(config, seed: seed)
                attempts += 1
                let found = accept(candidate, config: config)
                if Task.isCancelled { throw CancellationError() }
                if let (minMoves, explored) = found { return (candidate, seed, minMoves, explored) }
            }
            return nil
        }

        let phases: [(DailyGenerationPhase, GeneratorConfig, UInt64, Int)] = [
            (.spec, spec.generatorConfig(window: spec.minMoves), 0, specAttempts),
            (.relaxed, spec.generatorConfig(window: nil), 1_000, relaxedAttempts),
            (.easyFallback, GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, solverLimits: solverLimits),
             2_000, fallbackAttempts),
        ]
        for (phase, config, offset, count) in phases {
            if let (state, seed, minMoves, explored) = try search(config, from: offset, count: count) {
                let level = LevelDefinition(id: levelID(for: date), state: state, hidden: spec.hidden,
                                            meta: LevelMeta(seed: seed, minMoves: minMoves, statesExplored: explored))
                return DailyGeneration(date: date, spec: spec, level: level, phase: phase, attempts: attempts)
            }
        }
        return DailyGeneration(date: date, spec: spec, level: fixedLevel(for: date, hidden: spec.hidden),
                               phase: .fixedFallback, attempts: attempts)
    }

    /// (minMoves, statesExplored) if the candidate passes, else nil.
    static func accept(_ state: GameState, config: GeneratorConfig) -> (Int, Int)? {
        if state.bottles.contains(where: Generator.isPresolved) { return nil }
        guard case .solved(let moves, let explored) = Solver().solve(state, limits: config.solverLimits) else { return nil }
        if let range = config.minMoves, !range.contains(moves.count) { return nil }
        if config.requireLocksMatter,
           !LockImpact.everyLockMatters(state, minMoves: moves.count, cost: config.lockCost,
                                        limits: config.solverLimits) { return nil }
        return (moves.count, explored)
    }

    /// Built-in last resort: 4 colors, size 4, 2 empty flasks, solvable in 13 moves.
    static func fixedLevel(for date: DailyDate, hidden: Bool) -> LevelDefinition {
        let s = GameState(bottles: [
            Bottle([0, 1, 2, 3], capacity: 4),
            Bottle([1, 2, 3, 0], capacity: 4),
            Bottle([2, 3, 0, 1], capacity: 4),
            Bottle([3, 0, 1, 2], capacity: 4),
            Bottle(capacity: 4),
            Bottle(capacity: 4),
        ])
        return LevelDefinition(id: levelID(for: date), state: s, hidden: hidden,
                               meta: LevelMeta(seed: nil, minMoves: fixedLevelMinMoves))
    }

    static let fixedLevelMinMoves = 13
}
