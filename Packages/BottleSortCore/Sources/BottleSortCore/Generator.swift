public struct GeneratorConfig: Sendable, Hashable {
    public var colors: Int
    public var capacity: Int
    public var emptyBottles: Int
    /// First seed to try; attempt i uses `seed + i`.
    public var seed: UInt64
    /// Accept only levels whose optimal length is in this range.
    public var minMoves: ClosedRange<Int>?
    /// Accept only levels whose score is in this range.
    public var score: ClosedRange<Double>?
    public var maxAttempts: Int
    public var solverLimits: SolverLimits

    public init(colors: Int, capacity: Int = 4, emptyBottles: Int = 2, seed: UInt64 = 1,
                minMoves: ClosedRange<Int>? = nil, score: ClosedRange<Double>? = nil,
                maxAttempts: Int = 2_000, solverLimits: SolverLimits = .default) {
        self.colors = colors
        self.capacity = capacity
        self.emptyBottles = emptyBottles
        self.seed = seed
        self.minMoves = minMoves
        self.score = score
        self.maxAttempts = maxAttempts
        self.solverLimits = solverLimits
    }
}

public struct GeneratedLevel: Sendable, Hashable {
    public var state: GameState
    public var seed: UInt64
    public var report: DifficultyReport
}

public enum GeneratorError: Error, Hashable, CustomStringConvertible {
    case noLevelFound(attempts: Int)
    public var description: String {
        switch self {
        case .noLevelFound(let n): return "no level matched the constraints after \(n) attempts"
        }
    }
}

/// Random-shuffle + rejection-sampling level generator.
public enum Generator {
    /// The raw (unfiltered) level for `seed`: all `colors × capacity` layers
    /// shuffled into `colors` full bottles, plus `emptyBottles` empty ones.
    public static func candidate(_ config: GeneratorConfig, seed: UInt64) -> GameState {
        var rng = SplitMix64(seed: seed)
        var layers: [Layer] = []
        for color in 0..<config.colors {
            layers += Array(repeating: .color(ColorID(color)), count: config.capacity)
        }
        rng.shuffle(&layers)
        var bottles: [Bottle] = []
        for i in 0..<config.colors {
            let slice = layers[(i * config.capacity)..<((i + 1) * config.capacity)]
            bottles.append(Bottle(layers: Array(slice), capacity: config.capacity))
        }
        bottles += Array(repeating: Bottle(capacity: config.capacity), count: config.emptyBottles)
        return GameState(bottles: bottles)
    }

    /// Checks a candidate; returns its report if it passes every filter.
    public static func evaluate(_ state: GameState, config: GeneratorConfig, seed: UInt64) -> DifficultyReport? {
        // Reject: any bottle already solved (full with one color).
        if state.bottles.contains(where: { !$0.isEmpty && $0.isSolved }) { return nil }
        // Reject: unsolvable or unknown.
        guard case .solved(let moves, let explored) = Solver().solve(state, limits: config.solverLimits) else { return nil }
        // Cheap filter before the (more expensive) full report.
        if let range = config.minMoves, !range.contains(moves.count) { return nil }
        let report = Difficulty.analyze(state, solution: moves, statesExplored: explored, sampleSeed: seed)
        if let range = config.score, !range.contains(report.score) { return nil }
        return report
    }

    /// First passing level, trying seeds `config.seed`, `config.seed + 1`, …
    public static func generate(_ config: GeneratorConfig) throws -> GeneratedLevel {
        guard let level = try generate(config, count: 1).first else { throw GeneratorError.noLevelFound(attempts: config.maxAttempts) }
        return level
    }

    /// `count` passing levels, using consecutive seeds. `maxAttempts` applies per level.
    public static func generate(_ config: GeneratorConfig, count: Int,
                                progress: ((GeneratedLevel) -> Void)? = nil) throws -> [GeneratedLevel] {
        var result: [GeneratedLevel] = []
        var seed = config.seed
        while result.count < count {
            var found: GeneratedLevel?
            for _ in 0..<config.maxAttempts {
                let candidate = candidate(config, seed: seed)
                defer { seed &+= 1 }
                if let report = evaluate(candidate, config: config, seed: seed) {
                    found = GeneratedLevel(state: candidate, seed: seed, report: report)
                    break
                }
            }
            guard let found else { throw GeneratorError.noLevelFound(attempts: config.maxAttempts) }
            result.append(found)
            progress?(found)
        }
        return result
    }
}
