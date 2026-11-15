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
  levelgen --preset starter [--seed 1] [--id-prefix p1] --out FILE
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
    let flagNames: Set<String> = ["--bench", "--help"]
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
    let moves: ClosedRange<Int>
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

func generate(tiers: [Tier], seed: UInt64, idPrefix: String, scoreRange: ClosedRange<Double>?) -> [LevelDefinition] {
    var all: [GeneratedLevel] = []
    for (t, tier) in tiers.enumerated() {
        // Separate seed space per tier, so editing one tier doesn't change the others.
        let config = GeneratorConfig(colors: tier.colors, capacity: tier.capacity, emptyBottles: tier.empty,
                                     locks: tier.locks, seed: seed &+ UInt64(t) * 1_000_000, minMoves: tier.moves, score: scoreRange)
        let start = ContinuousClock.now
        do {
            all += try Generator.generate(config, count: tier.count) { level in
                log("  seed \(level.seed): minMoves \(level.report.minMoves), score \(level.report.score)")
            }
        } catch { fail("tier \(t + 1) (\(tier.colors) colors): \(error)") }
        log("tier \(t + 1): \(tier.count) × \(tier.colors) colors, cap \(tier.capacity), \(tier.empty) empty, \(tier.locks) locks — \(formatTime(ContinuousClock.now - start))")
    }
    // One global sort by score, so difficulty rises through the whole pack.
    return all.sorted { ($0.report.score, $0.seed) < ($1.report.score, $1.seed) }
        .enumerated().map { i, level in
            LevelDefinition(id: String(format: "%@_%03d", idPrefix, i + 1), state: level.state,
                            meta: LevelMeta(seed: level.seed, report: level.report))
        }
}

func write(_ levels: [LevelDefinition], to path: String) {
    do {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LevelLoader.encode(LevelPack(levels: levels)).write(to: url)
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
    guard let out = options["--out"] else { fail(usage) }
    let seed = UInt64(int("--seed", default: 1)!)
    let prefix = options["--id-prefix"] ?? "p1"
    let scores = range(double("--min-score"), double("--max-score"), name: "score")
    let tiers: [Tier]
    if let preset = options["--preset"] {
        guard preset == "starter" else { fail("unknown preset \(preset)") }
        tiers = starterTiers
    } else {
        guard let colors = int("--colors") else { fail(usage) }
        let moves = range(int("--min-moves"), int("--max-moves"), name: "moves") ?? 0...Int.max
        let locks = int("--locks", default: 0)!
        guard locks >= 0, locks < colors else { fail("--locks must be between 0 and colors - 1") }
        tiers = [Tier(count: int("--count", default: 20)!, colors: colors, capacity: int("--capacity", default: 4)!,
                      empty: int("--empty", default: 2)!, locks: locks, moves: moves)]
    }
    write(generate(tiers: tiers, seed: seed, idPrefix: prefix, scoreRange: scores), to: out)
}
