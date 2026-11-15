/// Game modes offered by the "Random Level" button.
public enum GameMode: String, Sendable, Hashable, Codable, CaseIterable {
    case classic
    case locksAndKeys
    case hidden
}

/// Options for one random level. Use `clamped` (done automatically by
/// `RandomLevel.generate`) to bring values into the supported ranges.
public struct RandomLevelOptions: Sendable, Hashable {
    public var mode: GameMode
    public var colors: Int
    public var capacity: Int
    public var emptyBottles: Int
    /// Only used in `.locksAndKeys` mode.
    public var locks: Int

    public static let colorRange = 2...12      // the app palette has 12 colors
    public static let capacityRange = 2...6
    public static let emptyRange = 0...4
    public static let lockRange = 1...2

    public init(mode: GameMode = .classic, colors: Int = 5, capacity: Int = 4, emptyBottles: Int = 2, locks: Int = 1) {
        self.mode = mode
        self.colors = colors
        self.capacity = capacity
        self.emptyBottles = emptyBottles
        self.locks = locks
    }

    /// The same options with every value clamped into its supported range.
    /// Locks are additionally kept below `colors` (the generator needs at
    /// least one unlocked color bottle).
    public var clamped: RandomLevelOptions {
        func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }
        var o = self
        o.colors = clamp(colors, Self.colorRange)
        o.capacity = clamp(capacity, Self.capacityRange)
        o.emptyBottles = clamp(emptyBottles, Self.emptyRange)
        o.locks = min(clamp(locks, Self.lockRange), o.colors - 1)
        return o
    }

    /// Generator settings for these (already clamped) options.
    func generatorConfig(limits: SolverLimits) -> GeneratorConfig {
        GeneratorConfig(colors: colors, capacity: capacity, emptyBottles: emptyBottles,
                        locks: mode == .locksAndKeys ? locks : 0, solverLimits: limits)
    }
}

/// What happened to one random-level attempt.
public enum RandomLevelOutcome: Sendable, Hashable {
    case accepted(minMoves: Int)
    /// A bottle was already sorted (full with one color, locked or not).
    case presolvedBottle
    case unsolvable
    /// The solver hit its state or time limit.
    case unknown
}

public struct RandomLevelAttempt: Sendable, Hashable {
    /// 1-based attempt number.
    public var number: Int
    /// Generator seed used for this attempt (`seed + number − 1`).
    public var seed: UInt64
    public var outcome: RandomLevelOutcome
}

public struct RandomLevelResult: Sendable, Hashable {
    /// The level, or nil if every attempt failed.
    public var level: LevelDefinition?
    /// One entry per attempt, in order.
    public var attempts: [RandomLevelAttempt]
    /// The clamped options actually used.
    public var options: RandomLevelOptions
}

/// Random level generation for the app (no difficulty filtering).
public enum RandomLevel {
    public static let defaultMaxAttempts = 6
    /// Default solver limits per attempt: a state cap only, no wall-clock timeout, so the
    /// result for a seed is the same on every device (about 5 s per attempt at worst in
    /// release on an M-series Mac). Callers stop a long run by cancelling the task.
    public static let defaultLimits = SolverLimits(maxStates: 1_000_000)

    /// Tries up to `maxAttempts` generator candidates (seeds `seed`, `seed + 1`, …).
    /// A candidate is rejected if any bottle is already sorted, or the solver
    /// finds it unsolvable or gives up. The first accepted candidate becomes a
    /// `LevelDefinition` with id `random-<seed>`, `hidden` set in `.hidden`
    /// mode, and meta (attempt seed, minMoves, score — scored with the cheaper
    /// `DifficultyBudget.quick`, so it may differ slightly from `levelgen`'s score).
    ///
    /// `progress` is called before each attempt with (attempt number, maxAttempts),
    /// e.g. to show "attempt 2/6".
    ///
    /// Deterministic for a seed as long as `limits` has no timeout and the task is not
    /// cancelled. If the calling task is cancelled, the running solve stops (its attempt
    /// counts as `.unknown`) and no further attempts are made.
    public static func generate(_ options: RandomLevelOptions, seed: UInt64,
                                maxAttempts: Int = defaultMaxAttempts,
                                limits: SolverLimits = defaultLimits,
                                progress: (@Sendable (_ attempt: Int, _ maxAttempts: Int) -> Void)? = nil) -> RandomLevelResult {
        let options = options.clamped
        let config = options.generatorConfig(limits: limits)
        var attempts: [RandomLevelAttempt] = []
        for i in 0..<max(0, maxAttempts) {
            if Task.isCancelled { break }
            progress?(i + 1, maxAttempts)
            let attemptSeed = seed &+ UInt64(i)
            let state = Generator.candidate(config, seed: attemptSeed)
            let outcome: RandomLevelOutcome
            var level: LevelDefinition?
            if state.bottles.contains(where: Generator.isPresolved) {
                outcome = .presolvedBottle
            } else {
                switch Solver().solve(state, limits: limits) {
                case .solved(let moves, let explored):
                    outcome = .accepted(minMoves: moves.count)
                    let report = Difficulty.analyze(state, solution: moves, statesExplored: explored,
                                                    sampleSeed: attemptSeed, budget: .quick)
                    level = LevelDefinition(id: "random-\(seed)", state: state, hidden: options.mode == .hidden,
                                            meta: LevelMeta(seed: attemptSeed, report: report))
                case .unsolvable:
                    outcome = .unsolvable
                case .unknown:
                    outcome = .unknown
                }
            }
            attempts.append(RandomLevelAttempt(number: i + 1, seed: attemptSeed, outcome: outcome))
            if let level { return RandomLevelResult(level: level, attempts: attempts, options: options) }
        }
        return RandomLevelResult(level: nil, attempts: attempts, options: options)
    }
}
