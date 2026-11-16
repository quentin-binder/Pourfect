/// Rush (R6): solve as many generated recipes as possible before the clock runs out.
/// Pure logic: the clock, the per-run level plan and the best-score record. The app drives
/// the timer, plays the levels and stores the record (DECISIONS 225).

/// The Rush clock. The app calls `tick` with the time that passed while a level was on the
/// board (never while it waits for the next level, so generation never costs the player time).
public struct RushClock: Sendable, Hashable, Codable {
    /// Starting time: 3:00.
    public static let duration: Double = 180
    /// Added for every solved recipe.
    public static let solveBonus: Double = 5
    /// Taken for every skipped recipe.
    public static let skipPenalty: Double = 10

    public private(set) var remaining: Double
    public private(set) var solved = 0
    public private(set) var skipped = 0

    public init(duration: Double = RushClock.duration) {
        remaining = max(0, duration)
    }

    public var isOver: Bool { remaining <= 0 }

    /// Whole seconds left, rounded up (what the timer shows: 0:00 only once time is up).
    public var displaySeconds: Int { Int(remaining.rounded(.up)) }

    /// Time passes. Ignored once the run is over or for a non-positive interval.
    public mutating func tick(_ seconds: Double) {
        guard !isOver, seconds > 0 else { return }
        remaining = max(0, remaining - seconds)
    }

    /// A recipe was solved (before time ran out): counts and adds the bonus.
    public mutating func solve() {
        guard !isOver else { return }
        solved += 1
        remaining += Self.solveBonus
    }

    /// A recipe was skipped: costs the penalty (the run can end on it).
    public mutating func skip() {
        guard !isOver else { return }
        skipped += 1
        remaining = max(0, remaining - Self.skipPenalty)
    }
}

/// Best Rush score and how many runs were played. Stored by the app on its own key, never
/// with recipe stars (DECISIONS 226).
public struct RushRecord: Sendable, Hashable, Codable {
    public var best: Int
    public var runs: Int

    public init(best: Int = 0, runs: Int = 0) {
        self.best = max(0, best)
        self.runs = max(0, runs)
    }

    /// Records a finished run; true when it set a new best (a run with no solves never does).
    @discardableResult
    public mutating func record(solved: Int) -> Bool {
        runs += 1
        guard solved > best else { return false }
        best = solved
        return true
    }
}

/// Mechanics a Rush recipe can use once the player has learned them on the main path. Only
/// quick ones: each needs few extra solves to check and reads at a glance.
public enum RushMechanic: String, Sendable, Hashable, Codable, CaseIterable {
    case sealed, murky, essence, narrowNeck, frozen

    public var mechanic: Mechanic {
        switch self {
        case .sealed: return .sealed
        case .murky: return .murky
        case .essence: return .essence
        case .narrowNeck: return .narrowNeck
        case .frozen: return .frozen
        }
    }

    /// The Rush mechanics among `learned` (main-path mechanics the player has met), in a fixed order.
    public static func unlocked(by learned: Set<Mechanic>) -> [RushMechanic] {
        allCases.filter { learned.contains($0.mechanic) }
    }
}

/// One Rush recipe's settings.
public struct RushSpec: Sendable, Hashable {
    /// 0-based position in the run.
    public var index: Int
    public var colors: Int
    public var capacity: Int
    public var emptyBottles: Int
    public var mechanic: RushMechanic?
    /// Accepted optimal lengths (phase `.spec`).
    public var minMoves: ClosedRange<Int>

    public var hidden: Bool { mechanic == .murky }

    /// Generator settings: one instance of the mechanic, which must matter at the minimum cost.
    func generatorConfig(window: ClosedRange<Int>?) -> GeneratorConfig {
        let m = mechanic
        return GeneratorConfig(colors: colors, capacity: capacity, emptyBottles: emptyBottles,
                               locks: m == .sealed ? 1 : 0, minMoves: window,
                               requireLocksMatter: m == .sealed,
                               essence: m == .essence ? 1 : 0, requireEssenceMatter: m == .essence,
                               hidden: hidden,
                               narrowNecks: m == .narrowNeck ? 1 : 0, requireGlassMatter: m == .narrowNeck,
                               frozen: m == .frozen ? 1 : 0, frozenMaxTurns: 5, requireFrozenMatter: m == .frozen,
                               solverLimits: RushPlan.solverLimits)
    }
}

/// How a Rush recipe was found.
public enum RushGenerationPhase: Int, Sendable, Hashable {
    /// The spec with its window.
    case spec = 1
    /// The spec without the window (optimal length up to `RushPlan.relaxedMaxMoves`).
    case relaxed
    /// A plain 4-color recipe.
    case easyFallback
    /// The built-in fixed recipe (never expected in practice).
    case fixedFallback
}

public struct RushLevel: Sendable, Hashable {
    public var spec: RushSpec
    public var level: LevelDefinition
    public var phase: RushGenerationPhase
    /// Candidates tried in total.
    public var attempts: Int
}

/// The recipes of one Rush run: deterministic for (run seed, index, unlocked mechanics), with
/// a difficulty that only goes up:
///
/// | index  | with a mechanic unlocked          | without                |
/// |--------|-----------------------------------|------------------------|
/// | 0      | 3 colors, 4–9 moves               | same                   |
/// | 1–2    | 4 colors, 7–12                    | same                   |
/// | 3–4    | 5 colors, 10–15                   | same                   |
/// | 5–9    | 4 colors + mechanic, 10–15        | 5 colors, 11–16        |
/// | 10–14  | 5 colors + mechanic, 12–18        | 6 colors, 13–18        |
/// | 15…    | 5 colors + mechanic, 14–18        | 6 colors, 15–18        |
///
/// Flask size 4, two empty flasks (one with a seal, like the sealed daily: the seal layout
/// adds a partly filled flask, and the seal check stays small). From index 5 the unlocked
/// mechanics take turns in an order shuffled per run, so two recipes in a row never share one.
///
/// Only state caps are used (no timeout), so a seed gives the same run on every device.
public enum RushPlan {
    public static let algorithmVersion = "rush-v1"
    /// Per-solve state cap. Rush recipes solve in far fewer states.
    public static let solverLimits = SolverLimits(maxStates: 200_000)
    public static let firstMechanicIndex = 5
    public static let specAttempts = 40
    public static let relaxedAttempts = 40
    public static let fallbackAttempts = 100
    /// Longest optimal solution phase `.relaxed` accepts.
    public static let relaxedMaxMoves = 20

    public static func levelID(seed: UInt64, index: Int) -> String { "rush-\(seed)-\(index + 1)" }

    /// The spec of recipe `index` (0-based) in the run with `seed`.
    public static func spec(index: Int, seed: UInt64, mechanics: [RushMechanic]) -> RushSpec {
        let index = max(0, index)
        let available = RushMechanic.allCases.filter(mechanics.contains)
        func make(_ colors: Int, _ window: ClosedRange<Int>, _ mechanic: RushMechanic? = nil) -> RushSpec {
            RushSpec(index: index, colors: colors, capacity: 4, emptyBottles: 2, mechanic: mechanic, minMoves: window)
        }
        switch index {
        case 0: return make(3, 4...9)
        case 1...2: return make(4, 7...12)
        case 3...4: return make(5, 10...15)
        default: break
        }
        guard !available.isEmpty else {
            switch index {
            case ..<10: return make(5, 11...16)
            case ..<15: return make(6, 13...18)
            default: return make(6, 15...18)
            }
        }
        var order = available
        var rng = SplitMix64(seed: seed ^ 0x5255_5348_4D45_4348)   // "RUSHMECH"
        rng.shuffle(&order)
        let mechanic = order[(index - firstMechanicIndex) % order.count]
        var spec: RushSpec
        switch index {
        case ..<10: spec = make(4, 10...15, mechanic)
        case ..<15: spec = make(5, 12...18, mechanic)
        default: spec = make(5, 14...18, mechanic)
        }
        if mechanic == .sealed { spec.emptyBottles = 1 }
        return spec
    }

    /// First generator seed for recipe `index` of the run.
    public static func baseSeed(seed: UInt64, index: Int) -> UInt64 {
        var mixer = SplitMix64(seed: seed &+ UInt64(max(0, index)) &* 0x9E37_79B9_7F4A_7C15)
        return mixer.next()
    }

    /// Recipe `index` of the run. Throws `CancellationError` if the calling task is cancelled.
    public static func level(index: Int, seed: UInt64, mechanics: [RushMechanic]) throws -> RushLevel {
        let spec = spec(index: index, seed: seed, mechanics: mechanics)
        let base = baseSeed(seed: seed, index: index)
        var attempts = 0
        let relaxed = spec.generatorConfig(window: 1...relaxedMaxMoves)
        let phases: [(RushGenerationPhase, GeneratorConfig, UInt64, Int)] = [
            (.spec, spec.generatorConfig(window: spec.minMoves), 0, specAttempts),
            (.relaxed, relaxed, 1_000, relaxedAttempts),
            (.easyFallback, GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, solverLimits: solverLimits),
             2_000, fallbackAttempts),
        ]
        for (phase, config, offset, count) in phases {
            for i in 0..<count {
                let seed = base &+ offset &+ UInt64(i)
                let candidate = Generator.candidate(config, seed: seed)
                attempts += 1
                let found = accept(candidate, config: config)
                if Task.isCancelled { throw CancellationError() }
                guard let minMoves = found else { continue }
                // The easy fallback is plain: never murky.
                let hidden = phase == .easyFallback ? false : spec.hidden
                let level = LevelDefinition(id: levelID(seed: seed, index: index), state: candidate, hidden: hidden,
                                            meta: LevelMeta(seed: seed, minMoves: minMoves))
                return RushLevel(spec: spec, level: level, phase: phase, attempts: attempts)
            }
        }
        let level = LevelDefinition(id: levelID(seed: seed, index: index), state: fixedState,
                                    meta: LevelMeta(seed: nil, minMoves: fixedMinMoves))
        return RushLevel(spec: spec, level: level, phase: .fixedFallback, attempts: attempts)
    }

    /// Built-in last resort (the daily's): 4 colors, size 4, 2 empty flasks, 13 moves.
    static let fixedState = GameState(bottles: [
        Bottle([0, 1, 2, 3], capacity: 4),
        Bottle([1, 2, 3, 0], capacity: 4),
        Bottle([2, 3, 0, 1], capacity: 4),
        Bottle([3, 0, 1, 2], capacity: 4),
        Bottle(capacity: 4),
        Bottle(capacity: 4),
    ])
    static let fixedMinMoves = 13

    /// The optimal length if the candidate passes: no presolved flask, solved within the cap,
    /// in the window, and every mechanic matters at the minimum cost.
    static func accept(_ state: GameState, config: GeneratorConfig) -> Int? {
        if state.bottles.contains(where: Generator.isPresolved) { return nil }
        guard case .solved(let moves, _) = Solver().solve(state, limits: config.solverLimits) else { return nil }
        let n = moves.count
        if let range = config.minMoves, !range.contains(n) { return nil }
        let limits = config.solverLimits
        if config.requireLocksMatter, !LockImpact.everyLockMatters(state, minMoves: n, cost: config.lockCost, limits: limits) {
            return nil
        }
        if config.requireEssenceMatter,
           !EssenceImpact.everyEssenceMatters(state, minMoves: n, cost: config.essenceCost, limits: limits) { return nil }
        if config.requireGlassMatter,
           !GlassImpact.everyGlassMatters(state, minMoves: n, cost: config.glassCost, limits: limits) { return nil }
        if config.requireFrozenMatter,
           !FrozenImpact.everyFrozenMatters(state, minMoves: n, cost: config.frozenCost, limits: limits) { return nil }
        return n
    }
}
