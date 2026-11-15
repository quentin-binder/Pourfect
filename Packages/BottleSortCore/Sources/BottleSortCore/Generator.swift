public struct GeneratorConfig: Sendable, Hashable {
    public var colors: Int
    public var capacity: Int
    public var emptyBottles: Int
    /// Number of locked bottles (each with one key). 0 = classic level.
    /// Must be less than `colors`. See `Generator.candidate` for the layout.
    public var locks: Int
    /// First seed to try; attempt i uses `seed + i`.
    public var seed: UInt64
    /// Accept only levels whose optimal length is in this range.
    public var minMoves: ClosedRange<Int>?
    /// Accept only levels whose score is in this range.
    public var score: ClosedRange<Double>?
    public var maxAttempts: Int
    public var solverLimits: SolverLimits

    public init(colors: Int, capacity: Int = 4, emptyBottles: Int = 2, locks: Int = 0, seed: UInt64 = 1,
                minMoves: ClosedRange<Int>? = nil, score: ClosedRange<Double>? = nil,
                maxAttempts: Int = 2_000, solverLimits: SolverLimits = .default) {
        self.colors = colors
        self.capacity = capacity
        self.emptyBottles = emptyBottles
        self.locks = locks
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
    /// The raw (unfiltered) level for `seed`.
    ///
    /// Classic (`locks == 0`): all `colors × capacity` color layers are
    /// shuffled into `colors` full bottles, plus `emptyBottles` empty ones.
    ///
    /// With `locks = L` (1 ≤ L < colors), using the same shuffled color layers:
    /// 1. Locked bottles: the first `L × capacity` shuffled layers fill `L`
    ///    bottles, locked by keys 1...L (so those colors are trapped inside).
    /// 2. The remaining `(colors − L) × capacity` color layers plus the `L` keys
    ///    are laid out in sequence and dealt into unlocked bottles of
    ///    `capacity` layers each, the last one partly filled (for L < capacity
    ///    it holds L layers). This adds exactly one bottle compared to classic,
    ///    and its free space is what makes room for the keys.
    /// 3. Key positions: a slot is "top" if it is the last slot of its bottle.
    ///    The non-top slots are shuffled and the first L of them (in sequence
    ///    order) become keys 1...L; the color layers fill the other slots in
    ///    their shuffled order. So every key sits below at least one layer.
    /// 4. `emptyBottles` empty bottles are appended.
    public static func candidate(_ config: GeneratorConfig, seed: UInt64) -> GameState {
        var rng = SplitMix64(seed: seed)
        let capacity = config.capacity
        var layers: [Layer] = []
        for color in 0..<config.colors {
            layers += Array(repeating: .color(ColorID(color)), count: capacity)
        }
        rng.shuffle(&layers)
        var bottles: [Bottle] = []
        if config.locks <= 0 {
            for i in 0..<config.colors {
                let slice = layers[(i * capacity)..<((i + 1) * capacity)]
                bottles.append(Bottle(layers: Array(slice), capacity: capacity))
            }
        } else {
            let locks = config.locks
            precondition(locks < config.colors, "locks must be less than colors")
            // 1. Locked bottles.
            for j in 0..<locks {
                let slice = layers[(j * capacity)..<((j + 1) * capacity)]
                bottles.append(Bottle(layers: Array(slice), capacity: capacity, lockedBy: KeyID(j + 1)))
            }
            // 2. + 3. Unlocked sequence with keys in non-top slots.
            var colors = Array(layers[(locks * capacity)...])
            let total = colors.count + locks
            let isTop = { (i: Int) in i % capacity == capacity - 1 || i == total - 1 }
            var nonTop = (0..<total).filter { !isTop($0) }
            precondition(nonTop.count >= locks, "not enough non-top slots for the keys")
            rng.shuffle(&nonTop)
            let keySlots = nonTop.prefix(locks).sorted()
            var sequence: [Layer] = []
            colors.reverse()  // pop from the end in original order
            var nextKey = 1
            for i in 0..<total {
                if keySlots.contains(i) {
                    sequence.append(.key(KeyID(nextKey)))
                    nextKey += 1
                } else {
                    sequence.append(colors.removeLast())
                }
            }
            for start in stride(from: 0, to: total, by: capacity) {
                bottles.append(Bottle(layers: Array(sequence[start..<min(total, start + capacity)]), capacity: capacity))
            }
        }
        // 4. Empty bottles.
        bottles += Array(repeating: Bottle(capacity: capacity), count: config.emptyBottles)
        return GameState(bottles: bottles)
    }

    /// Whether `bottle` holds content that is already sorted: solved and
    /// non-empty, or would be once its lock is removed.
    static func isPresolved(_ bottle: Bottle) -> Bool {
        var unlocked = bottle
        unlocked.lockedBy = nil
        return !unlocked.isEmpty && unlocked.isSolved
    }

    /// Checks a candidate; returns its report if it passes every filter.
    public static func evaluate(_ state: GameState, config: GeneratorConfig, seed: UInt64) -> DifficultyReport? {
        // Reject: any bottle already solved (full with one color), locked or not.
        if state.bottles.contains(where: isPresolved) { return nil }
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
