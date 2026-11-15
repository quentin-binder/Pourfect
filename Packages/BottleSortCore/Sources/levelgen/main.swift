import BottleSortCore
import Foundation

// levelgen — generate, report and benchmark Bottle Sort levels.
//
//   levelgen --colors 4 --capacity 4 --empty 2 --count 20 \
//            --min-moves 8 --max-moves 15 --seed 1 --out Levels/pack_01.json
//   levelgen --colors 5 --empty 2 --locks 1 --count 5 --out locks.json
//   levelgen --preset starter --out Levels/pack_01.json
//   levelgen --report Levels/pack_01.json
//   levelgen --bench [--colors 8] [--count 10]

let usage = """
usage:
  levelgen --colors N [--capacity 4] [--empty 2] [--locks 0] [--count 20] [--seed 1]
           [--min-moves A --max-moves B] [--min-score X --max-score Y]
           [--id-prefix p1] --out FILE
           [--hidden] [--pool K] [--name NAME --subtitle TEXT]
  levelgen --preset starter|challenger|expert|locks|hidden|master [--seed S] --out FILE
  levelgen --preset all --out-dir DIR      (writes pack_01.json … pack_06.json)
  levelgen --report FILE
  levelgen --bench [--colors 8] [--capacity 4] [--empty 2] [--count 10] [--seed 1]
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: Argument parsing

var options: [String: String] = [:]
var flags: Set<String> = []
do {
    var args = CommandLine.arguments.dropFirst()
    let flagNames: Set<String> = ["--bench", "--help", "--hidden"]
    while let arg = args.popFirst() {
        guard arg.hasPrefix("--") else { fail("unexpected argument \(arg)\n\(usage)") }
        if flagNames.contains(arg) { flags.insert(arg); continue }
        guard let value = args.popFirst() else { fail("missing value for \(arg)") }
        options[arg] = value
    }
}

func int(_ name: String, default value: Int? = nil) -> Int? {
    guard let raw = options[name] else { return value }
    guard let n = Int(raw) else { fail("\(name) expects an integer") }
    return n
}

func double(_ name: String) -> Double? {
    guard let raw = options[name] else { return nil }
    guard let n = Double(raw) else { fail("\(name) expects a number") }
    return n
}

func range<T: Comparable>(_ lo: T?, _ hi: T?, name: String) -> ClosedRange<T>? {
    switch (lo, hi) {
    case let (lo?, hi?):
        guard lo <= hi else { fail("\(name): min > max") }
        return lo...hi
    case (nil, nil): return nil
    default: fail("give both --min-\(name) and --max-\(name)")
    }
}

func pad(_ s: String, _ width: Int, right: Bool = false) -> String {
    let fill = String(repeating: " ", count: max(0, width - s.count))
    return right ? fill + s : s + fill
}

func formatTime(_ d: Duration) -> String {
    let c = d.components
    return String(format: "%.3f s", Double(c.seconds) + Double(c.attoseconds) / 1e18)
}

// MARK: Report

func report(path: String) {
    let pack: LevelPack
    do { pack = try LevelLoader.load(contentsOf: URL(fileURLWithPath: path)) } catch { fail("\(path): \(error)") }
    struct Row { let index: Int; let id: String; let colors: Int; let empty: Int; let locks: Int; let r: DifficultyReport }
    var rows: [Row] = []
    for (i, level) in pack.levels.enumerated() {
        let state = level.gameState
        guard let r = Difficulty.analyze(state, sampleSeed: UInt64(i)) else { fail("\(level.id): not solvable within limits") }
        if let expected = level.meta?.minMoves, expected != r.minMoves {
            log("warning: \(level.id) meta.minMoves=\(expected) but solver says \(r.minMoves)")
        }
        let colors = Set(state.bottles.flatMap(\.layers).compactMap(\.colorID)).count
        rows.append(Row(index: i + 1, id: level.id, colors: colors, empty: state.bottles.filter(\.isEmpty).count,
                        locks: state.bottles.filter { $0.lockedBy != nil }.count, r: r))
    }
    let header = "  #  id         colors empty locks minMoves  states  deadEnd  branch  score"
    print(header)
    print(String(repeating: "-", count: header.count))
    for row in rows.sorted(by: { ($0.r.score, $0.index) < ($1.r.score, $1.index) }) {
        let dead: String
        switch row.r.deadEndMethod {
        case .exact: dead = String(format: "%.3f", row.r.deadEndRatio)
        case .sampled: dead = String(format: "~%.2f", row.r.deadEndRatio)
        }
        print(String(format: "%3d  ", row.index) + pad(row.id, 10)
              + String(format: " %6d %5d %5d %8d %7d ", row.colors, row.empty, row.locks, row.r.minMoves, row.r.statesExplored)
              + pad(dead, 8, right: true)
              + String(format: " %7.2f %6.1f", row.r.branchingFactor, row.r.score))
    }
    print("\n\(rows.count) levels, sorted by score (# = position in the pack).")
}

// MARK: Generation

struct Tier {
    let count: Int
    let colors: Int
    let capacity: Int
    let empty: Int
    var locks: Int = 0
    var hidden = false
    let moves: ClosedRange<Int>
    /// Generate `count × pool` passing levels and keep the `count` with the highest score.
    var pool = 1
}

struct PackPreset {
    let file: String        // e.g. "pack_02"
    let idPrefix: String    // e.g. "p2"
    let name: String
    let subtitle: String
    let seed: UInt64
    let tiers: [Tier]
}

/// Starter pack tiers (see DECISIONS.md). The final pack is sorted by score globally.
let starterTiers: [Tier] = [
    Tier(count: 2, colors: 3, capacity: 3, empty: 2, moves: 4...6),     //  1–2   tutorial
    Tier(count: 3, colors: 3, capacity: 4, empty: 2, moves: 6...8),     //  3–5   tutorial
    Tier(count: 7, colors: 4, capacity: 4, empty: 2, moves: 8...12),    //  6–12
    Tier(count: 8, colors: 5, capacity: 4, empty: 2, moves: 12...15),   // 13–20
    Tier(count: 6, colors: 6, capacity: 4, empty: 2, moves: 16...19),   // 21–26
    Tier(count: 2, colors: 5, capacity: 4, empty: 1, moves: 12...30),   // 27–28  one empty bottle
    Tier(count: 5, colors: 7, capacity: 4, empty: 2, moves: 19...23),   // 29–33
    Tier(count: 2, colors: 6, capacity: 4, empty: 1, moves: 14...30),   // 34–35  one empty bottle
    Tier(count: 5, colors: 8, capacity: 4, empty: 2, moves: 23...27),   // 36–40
]

let any = 0...999

/// All shipped packs, easiest first. Tiers are tuned from measured distributions (see DECISIONS.md).
let packPresets: [String: PackPreset] = [
    "starter": PackPreset(file: "pack_01", idPrefix: "p1", name: "Starter",
                          subtitle: "Learn to pour — 3 to 8 colors", seed: 1, tiers: starterTiers),
    "challenger": PackPreset(file: "pack_02", idPrefix: "p2", name: "Challenger",
                             subtitle: "8–10 colors, tight spaces", seed: 2_000, tiers: [
        Tier(count: 6, colors: 5, capacity: 4, empty: 1, moves: any, pool: 4),     // one empty bottle
        Tier(count: 8, colors: 8, capacity: 4, empty: 2, moves: 24...99, pool: 3),
        Tier(count: 6, colors: 7, capacity: 5, empty: 2, moves: any, pool: 2),     // taller bottles
        Tier(count: 6, colors: 9, capacity: 4, empty: 2, moves: 27...99, pool: 2),
        Tier(count: 4, colors: 10, capacity: 4, empty: 2, moves: 30...99, pool: 2),
    ]),
    "expert": PackPreset(file: "pack_03", idPrefix: "p3", name: "Expert",
                         subtitle: "10–12 colors and tall bottles", seed: 3_000, tiers: [
        Tier(count: 6, colors: 6, capacity: 5, empty: 1, moves: any, pool: 2),     // one empty, tall
        Tier(count: 6, colors: 8, capacity: 5, empty: 2, moves: 30...99, pool: 2),
        Tier(count: 6, colors: 10, capacity: 4, empty: 2, moves: 30...99, pool: 3),
        Tier(count: 6, colors: 11, capacity: 4, empty: 2, moves: 33...99, pool: 2),
        Tier(count: 6, colors: 12, capacity: 4, empty: 2, moves: 36...99, pool: 2),
    ]),
    "locks": PackPreset(file: "pack_04", idPrefix: "p4", name: "Locks & Keys",
                        subtitle: "Find the key, open the bottle", seed: 4_000, tiers: [
        Tier(count: 6, colors: 6, capacity: 4, empty: 2, locks: 1, moves: any, pool: 2),
        Tier(count: 6, colors: 7, capacity: 4, empty: 2, locks: 1, moves: any, pool: 2),
        Tier(count: 6, colors: 6, capacity: 4, empty: 1, locks: 1, moves: any, pool: 3),
        Tier(count: 6, colors: 8, capacity: 4, empty: 2, locks: 2, moves: any, pool: 2),
        Tier(count: 6, colors: 9, capacity: 4, empty: 2, locks: 2, moves: any, pool: 1),
    ]),
    "hidden": PackPreset(file: "pack_05", idPrefix: "p5", name: "Hidden Depths",
                         subtitle: "Every layer below the top is a mystery", seed: 5_000, tiers: [
        Tier(count: 6, colors: 6, capacity: 4, empty: 2, hidden: true, moves: any, pool: 2),
        Tier(count: 6, colors: 7, capacity: 4, empty: 2, hidden: true, moves: any, pool: 2),
        Tier(count: 6, colors: 5, capacity: 4, empty: 1, hidden: true, moves: any, pool: 3),
        Tier(count: 6, colors: 8, capacity: 4, empty: 2, hidden: true, moves: 24...99, pool: 2),
        Tier(count: 6, colors: 7, capacity: 4, empty: 2, locks: 1, hidden: true, moves: any, pool: 2),
    ]),
    "master": PackPreset(file: "pack_06", idPrefix: "p6", name: "Master",
                         subtitle: "Everything at once. Good luck.", seed: 6_000, tiers: [
        Tier(count: 4, colors: 6, capacity: 5, empty: 1, moves: any, pool: 3),
        Tier(count: 4, colors: 10, capacity: 5, empty: 2, moves: 40...99, pool: 2),
        Tier(count: 4, colors: 12, capacity: 4, empty: 2, moves: 38...99, pool: 3),
        Tier(count: 4, colors: 10, capacity: 4, empty: 2, locks: 2, moves: any, pool: 1),
        Tier(count: 4, colors: 10, capacity: 4, empty: 2, hidden: true, moves: 31...99, pool: 2),
    ]),
]
let presetOrder = ["starter", "challenger", "expert", "locks", "hidden", "master"]

func generate(tiers: [Tier], seed: UInt64, idPrefix: String, scoreRange: ClosedRange<Double>?) -> [LevelDefinition] {
    var all: [(level: GeneratedLevel, hidden: Bool)] = []
    for (t, tier) in tiers.enumerated() {
        // Separate seed space per tier, so editing one tier doesn't change the others.
        let config = GeneratorConfig(colors: tier.colors, capacity: tier.capacity, emptyBottles: tier.empty,
                                     locks: tier.locks, seed: seed &+ UInt64(t) * 1_000_000, minMoves: tier.moves, score: scoreRange)
        let start = ContinuousClock.now
        var generated: [GeneratedLevel] = []
        do {
            generated = try Generator.generate(config, count: tier.count * tier.pool) { level in
                log("  seed \(level.seed): minMoves \(level.report.minMoves), score \(level.report.score)")
            }
        } catch { fail("tier \(t + 1) (\(tier.colors) colors): \(error)") }
        // Keep the hardest `count` of the pool.
        let kept = generated.sorted { ($0.report.score, $1.seed) > ($1.report.score, $0.seed) }.prefix(tier.count)
        all += kept.map { ($0, tier.hidden) }
        log("tier \(t + 1): \(tier.count)\(tier.pool > 1 ? " (best of \(tier.count * tier.pool))" : "") × \(tier.colors) colors, cap \(tier.capacity), \(tier.empty) empty, \(tier.locks) locks\(tier.hidden ? ", hidden" : "") — \(formatTime(ContinuousClock.now - start))")
    }
    // One global sort by score, so difficulty rises through the whole pack.
    return all.sorted { ($0.level.report.score, $0.level.seed) < ($1.level.report.score, $1.level.seed) }
        .enumerated().map { i, entry in
            LevelDefinition(id: String(format: "%@_%03d", idPrefix, i + 1), state: entry.level.state,
                            hidden: entry.hidden, meta: LevelMeta(seed: entry.level.seed, report: entry.level.report))
        }
}

func write(_ levels: [LevelDefinition], to path: String, name: String? = nil, subtitle: String? = nil) {
    do {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LevelLoader.encode(LevelPack(name: name, subtitle: subtitle, levels: levels)).write(to: url)
        _ = try LevelLoader.load(contentsOf: url)  // round-trip + validate
        log("wrote \(levels.count) levels to \(path)")
    } catch { fail("writing \(path): \(error)") }
}

// MARK: Benchmark

func bench() {
    let colors = int("--colors", default: 8)!
    let capacity = int("--capacity", default: 4)!
    let empty = int("--empty", default: 2)!
    let count = int("--count", default: 10)!
    let seed = UInt64(int("--seed", default: 1)!)
    let config = GeneratorConfig(colors: colors, capacity: capacity, emptyBottles: empty)
    var worst = Duration.zero
    var total = Duration.zero
    print("seed      result     moves   states    time")
    for s in seed..<(seed + UInt64(count)) {
        let state = Generator.candidate(config, seed: s)
        let start = ContinuousClock.now
        let result = Solver().solve(state)
        let elapsed = ContinuousClock.now - start
        worst = max(worst, elapsed)
        total += elapsed
        let (kind, moves, states): (String, String, Int) = switch result {
        case .solved(let m, let n): ("solved", "\(m.count)", n)
        case .unsolvable(let n): ("unsolvable", "-", n)
        case .unknown(let reason): ("unknown", "-", { if case .stateLimit(let n) = reason { n } else { 0 } }())
        }
        print(pad("\(s)", 9) + pad(kind, 11) + pad(moves, 5, right: true) + String(format: " %8d  ", states) + formatTime(elapsed))
    }
    print("worst \(formatTime(worst)), mean \(formatTime(total / count))")
}

// MARK: Main

if flags.contains("--help") { print(usage); exit(0) }
if let path = options["--report"] {
    report(path: path)
} else if flags.contains("--bench") {
    bench()
} else {
    let scores = range(double("--min-score"), double("--max-score"), name: "score")
    if let name = options["--preset"] {
        let names = name == "all" ? presetOrder : [name]
        for n in names {
            guard let preset = packPresets[n] else { fail("unknown preset \(n); choose from \(presetOrder.joined(separator: ", ")) or all") }
            let out: String
            if let dir = options["--out-dir"] { out = dir + "/" + preset.file + ".json" }
            else if names.count == 1, let file = options["--out"] { out = file }
            else { fail("--preset all needs --out-dir DIR") }
            log("== \(preset.name)")
            let seed = options["--seed"].map { _ in UInt64(int("--seed")!) } ?? preset.seed
            write(generate(tiers: preset.tiers, seed: seed, idPrefix: options["--id-prefix"] ?? preset.idPrefix, scoreRange: scores),
                  to: out, name: preset.name, subtitle: preset.subtitle)
        }
    } else {
        guard let out = options["--out"], let colors = int("--colors") else { fail(usage) }
        let seed = UInt64(int("--seed", default: 1)!)
        let moves = range(int("--min-moves"), int("--max-moves"), name: "moves") ?? 0...Int.max
        let locks = int("--locks", default: 0)!
        guard locks >= 0, locks < colors else { fail("--locks must be between 0 and colors - 1") }
        let tier = Tier(count: int("--count", default: 20)!, colors: colors, capacity: int("--capacity", default: 4)!,
                        empty: int("--empty", default: 2)!, locks: locks, hidden: flags.contains("--hidden"), moves: moves,
                        pool: int("--pool", default: 1)!)
        write(generate(tiers: [tier], seed: seed, idPrefix: options["--id-prefix"] ?? "p1", scoreRange: scores), to: out,
              name: options["--name"], subtitle: options["--subtitle"])
    }
}
