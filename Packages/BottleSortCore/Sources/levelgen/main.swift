import BottleSortCore
import Foundation

// levelgen — generate, report and benchmark Bottle Sort levels.
//
//   levelgen --colors 4 --capacity 4 --empty 2 --count 20 \
//            --min-moves 8 --max-moves 15 --seed 1 --out my_pack.json
//   levelgen --colors 5 --empty 2 --locks 1 --locks-matter --count 5 --out locks.json
//   levelgen --colors 5 --empty 2 --essence 1 --essence-cost 2 --count 5 --out runes.json
//   levelgen --colors 5 --empty 2 --narrow 1 --tap 1 --glass-cost 2 --count 5 --out glass.json
//   levelgen --colors 5 --empty 2 --frozen 1:4 --frozen-cost 2 --count 5 --out ice.json
//   levelgen --colors 5 --empty 2 --bubbling 1:3 --bubbling-cost 2 --count 5 --out bog.json
//   levelgen --colors 4 --empty 2 --twins 1 --link-placement filled --link-cost 2 --count 5 --out twins.json
//   levelgen --preset chapter2 --out Levels/chapter_02.json
//   levelgen --preset all --out-dir Levels
//   levelgen --report Levels            (every *.json in the folder)
//   levelgen --bench [--colors 8] [--count 10]

let usage = """
usage:
  levelgen --colors N [--capacity 4] [--empty 2] [--locks 0] [--count 20] [--seed 1]
           [--min-moves A --max-moves B] [--min-score X --max-score Y]
           [--id-prefix p1] --out FILE
           [--hidden] [--locks-matter] [--pool K] [--easiest]
           [--essence N [--essence-empty K] [--essence-matter | --essence-cost C]]
           [--narrow N] [--funnel N] [--tap N] [--glass-matter | --glass-cost C]
           [--frozen N:MAXTURNS [--frozen-matter | --frozen-cost C]]
           [--bubbling N:PERIOD [--bubbling-matter | --bubbling-cost C]]
           [--twins N] [--overflow N] [--link-placement any|filled|empty|mixed] [--links-matter | --link-cost C]
           [--name NAME --subtitle TEXT] [--kind chapter|challenge --chapter N --location NAME]
  levelgen --preset chapter1|…|chapter8|challenger|expert|master [--seed S] --out FILE
  levelgen --preset all --out-dir DIR
           (writes chapter_01…08.json and challenge_challenger|expert|master.json)
  levelgen --report FILE|DIR       (exit status 2 if a level doesn't match its minMoves)
  levelgen --bench [--colors 8] [--capacity 4] [--empty 2] [--locks 0] [--essence 0 [--essence-empty K]]
           [--narrow 0] [--funnel 0] [--tap 0] [--frozen N:MAXTURNS] [--bubbling N:PERIOD]
           [--twins 0] [--overflow 0] [--link-placement any] [--count 10] [--seed 1]
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
    let flagNames: Set<String> = ["--bench", "--help", "--hidden", "--locks-matter", "--essence-matter", "--glass-matter", "--frozen-matter", "--bubbling-matter", "--links-matter", "--easiest"]
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

/// `--frozen N:MAXTURNS` (frozen layers and their largest thaw counter; `N` alone means
/// counters up to 3). (0, 3) when absent.
func frozenOption() -> (count: Int, maxTurns: Int) {
    guard let raw = options["--frozen"] else { return (0, 3) }
    let parts = raw.split(separator: ":").map { Int($0) }
    guard (1...2).contains(parts.count), let count = parts[0], let turns = parts.count == 2 ? parts[1] : 3,
          (0...Rules.maxFrozenLayers).contains(count), (1...Rules.maxThawTurns).contains(turns) else {
        fail("--frozen expects N:MAXTURNS with N in 0...\(Rules.maxFrozenLayers) and MAXTURNS in 1...\(Rules.maxThawTurns)")
    }
    return (count, turns)
}

/// `--bubbling N:PERIOD` (bubbling flasks and their period; `N` alone means period 3).
/// (0, 3) when absent.
func bubblingOption() -> (count: Int, period: Int) {
    guard let raw = options["--bubbling"] else { return (0, 3) }
    let parts = raw.split(separator: ":").map { Int($0) }
    guard (1...2).contains(parts.count), let count = parts[0], let period = parts.count == 2 ? parts[1] : 3,
          (0...Rules.maxBubblingFlasks).contains(count), Rules.bubblingPeriods.contains(period) else {
        fail("--bubbling expects N:PERIOD with N in 0...\(Rules.maxBubblingFlasks) and PERIOD in \(Rules.bubblingPeriods.lowerBound)...\(Rules.bubblingPeriods.upperBound)")
    }
    return (count, period)
}

/// `--link-placement any|filled|empty|mixed` (`LinkPlacement`; `any` when absent).
func linkPlacementOption() -> LinkPlacement {
    guard let raw = options["--link-placement"] else { return .any }
    guard let placement = LinkPlacement(rawValue: raw) else {
        fail("--link-placement expects " + LinkPlacement.allCases.map(\.rawValue).joined(separator: ", "))
    }
    return placement
}

/// `--twins N` and `--overflow N` (twin pairs and overflow pipes), both ≥ 0.
func linkOptions() -> (twins: Int, overflow: Int) {
    let twins = int("--twins", default: 0)!, overflow = int("--overflow", default: 0)!
    guard twins >= 0, overflow >= 0 else { fail("--twins and --overflow must not be negative") }
    return (twins, overflow)
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

/// Re-solves every level of one pack file and prints a difficulty table. Returns the number of
/// problems: minMoves mismatches, and in chapter packs mechanics (e.g. locks) that don't matter
/// (`MechanicImpact`).
func report(path: String) -> Int {
    let pack: LevelPack
    do { pack = try LevelLoader.load(contentsOf: URL(fileURLWithPath: path)) } catch { fail("\(path): \(error)") }
    struct Row { let index: Int; let id: String; let colors: Int; let empty: Int; let locks: Int; let runes: Int; let glass: String; let ice: Int; let bub: Int; let links: String; let r: DifficultyReport }
    var rows: [Row] = []
    var problems = 0
    for (i, level) in pack.levels.enumerated() {
        let state = level.gameState
        guard let r = Difficulty.analyze(state, sampleSeed: UInt64(i)) else { fail("\(level.id): not solvable within limits") }
        if let expected = level.meta?.minMoves, expected != r.minMoves {
            log("warning: \(level.id) meta.minMoves=\(expected) but solver says \(r.minMoves)")
            problems += 1
        }
        if pack.isChapter {
            for instance in MechanicImpact.instances(in: state)
            where !MechanicImpact.matters(instance, in: state, minMoves: r.minMoves) {
                log("warning: \(level.id): \(instance) doesn't matter")
                problems += 1
            }
        }
        let colors = Set(state.bottles.flatMap(\.layers).compactMap(\.colorID)).count
        rows.append(Row(index: i + 1, id: level.id, colors: colors, empty: state.bottles.filter(\.isEmpty).count,
                        locks: state.bottles.filter { $0.lockedBy != nil }.count,
                        runes: state.bottles.filter { $0.essenceColor != nil }.count, glass: glassSummary(state),
                        ice: state.bottles.reduce(0) { $0 + $1.frozenLayers.count },
                        bub: state.bottles.filter(\.isBubbling).count, links: linkSummary(state), r: r))
    }
    var title = pack.name ?? path
    if let kind = pack.kind { title += " (\(kind.rawValue)\(pack.chapter.map { " \($0)" } ?? ""))" }
    if let mechanics = pack.introduces { title += ", introduces " + mechanics.map(\.rawValue).joined(separator: ", ") }
    print("== \(title) — \(path)")
    let header = "  #  id         colors empty locks runes glass ice bub links minMoves  states  deadEnd  branch  score"
    print(header)
    print(String(repeating: "-", count: header.count))
    for row in rows.sorted(by: { ($0.r.score, $0.index) < ($1.r.score, $1.index) }) {
        let dead: String
        switch row.r.deadEndMethod {
        case .exact: dead = String(format: "%.3f", row.r.deadEndRatio)
        case .sampled: dead = String(format: "~%.2f", row.r.deadEndRatio)
        }
        print(String(format: "%3d  ", row.index) + pad(row.id, 10)
              + String(format: " %6d %5d %5d %5d ", row.colors, row.empty, row.locks, row.runes) + pad(row.glass, 5, right: true)
              + String(format: " %3d %3d ", row.ice, row.bub) + pad(row.links, 5, right: true)
              + String(format: " %8d %7d ", row.r.minMoves, row.r.statesExplored)
              + pad(dead, 8, right: true)
              + String(format: " %7.2f %6.1f", row.r.branchingFactor, row.r.score))
    }
    print("\n\(rows.count) levels, sorted by score (# = position in the pack).")
    let scores = rows.map(\.r.score)
    if let lo = scores.min(), let hi = scores.max() {
        print(String(format: "score min %.1f, mean %.1f, max %.1f", lo, scores.reduce(0, +) / Double(scores.count), hi))
        print("curve (pack order): " + scores.map { String(format: "%.0f", $0) }.joined(separator: " "))
    }
    print("\(problems) problem(s)\n")
    return problems
}

/// Narrow necks, funnels and taps of a level as "nN fF tT" letters (e.g. "n2t1"; "-" for none).
func glassSummary(_ state: GameState) -> String {
    let n = state.bottles.filter(\.hasNarrowNeck).count
    let f = state.bottles.filter(\.isFunnel).count
    let t = state.bottles.filter(\.hasTap).count
    let parts = [(n, "n"), (f, "f"), (t, "t")].filter { $0.0 > 0 }.map { "\($0.1)\($0.0)" }
    return parts.isEmpty ? "-" : parts.joined()
}

/// Twin pairs and overflow pipes of a level as "tT oO" letters (e.g. "t1o1"; "-" for none).
func linkSummary(_ state: GameState) -> String {
    let t = state.links.filter { if case .twins = $0 { return true } else { return false } }.count
    let o = state.links.filter { if case .overflow = $0 { return true } else { return false } }.count
    let parts = [(t, "t"), (o, "o")].filter { $0.0 > 0 }.map { "\($0.1)\($0.0)" }
    return parts.isEmpty ? "-" : parts.joined()
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
    /// Score window for this tier (overrides `--min-score/--max-score`).
    var score: ClosedRange<Double>? = nil
    /// Reject levels with a lock that doesn't matter (`LockImpact`).
    var locksMatter = false
    /// With `locksMatter`: each lock must add at least `LockImpact.strongCost` moves
    /// (the key pour plus a detour of two or more), instead of the minimum.
    var strongLocks = false
    /// Essence flasks (C1) per level, and how many of them are empty flasks (nil = any mix).
    var essence = 0
    var essenceEmpty: Int? = nil
    /// Moves each essence flask must add (`EssenceImpact`); nil = no must-matter check.
    var essenceCost: Int? = nil
    /// Narrow-neck, funnel and tap flasks per level (C2, C4).
    var narrow = 0
    var funnel = 0
    var tap = 0
    /// Moves each narrow neck, funnel and tap must change (`GlassImpact`); nil = no must-matter check.
    var glassCost: Int? = nil
    /// Frozen layers per level (D1) and their largest thaw counter.
    var frozen = 0
    var frozenTurns = 3
    /// Moves each frozen layer must add (`FrozenImpact`); nil = no must-matter check.
    var frozenCost: Int? = nil
    /// Bubbling flasks per level (D2) and their period.
    var bubbling = 0
    var bubblingPeriod = 3
    /// Moves each bubbling flask must change (`BubblingImpact`); nil = no must-matter check.
    var bubblingCost: Int? = nil
    /// Twin pairs (F1) and overflow pipes (F2) per level, and which flasks they go on.
    var twins = 0
    var overflow = 0
    var linkPlacement: LinkPlacement = .any
    /// Moves each link must change (`LinkImpact`; an overflow pipe may instead set a spill
    /// trap); nil = no must-matter check.
    var linkCost: Int? = nil
    /// Keep the easiest `count` of the pool instead of the hardest (tutorial recipes).
    var keepEasiest = false
    /// Frozen tutorial: every frozen layer has a layer above it (`FrozenImpact.everyIceHasALayerAbove`),
    /// and an optimal solution needs no relocation and pours from above the ice
    /// (`FrozenImpact.solvesWithoutRelocation(_:in:pouringAboveIce:)`).
    var teachesIce = false
    /// Bubbling tutorial: an optimal solution needs no relocation and pours a layer right
    /// after it rose (`BubblingImpact.solvesWithoutRelocation(_:in:pouringARisenLayer:)`), and
    /// no first move is a dead end (`MechanicImpact.everyFirstMoveSolvable`).
    var teachesBubbling = false
    /// Link tutorial: an optimal solution needs no relocation and uses every link (a split
    /// pour, a pour through each pipe; `LinkImpact.solvesUsingEveryLink`), and no first move
    /// is a dead end (`MechanicImpact.everyFirstMoveSolvable`).
    var teachesLinks = false
    /// The pack is sorted by score within a section; sections follow each other in increasing order.
    var section = 0
    /// Candidates tried per level before giving up (`GeneratorConfig.maxAttempts`).
    var maxAttempts = 2_000
}

struct PackPreset {
    let file: String        // e.g. "chapter_02"
    let idPrefix: String    // e.g. "c2"
    let name: String
    let subtitle: String
    var kind: PackKind
    var chapter: Int? = nil
    var location: String? = nil
    var introduces: [Mechanic]? = nil
    let seed: UInt64
    let tiers: [Tier]
}

/// Chapter 1 tiers (the original Starter pack, see DECISIONS.md). The final pack is sorted by score globally.
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

/// All shipped packs: chapters (main path) first, then challenges. Tiers are tuned from measured
/// distributions (see DECISIONS.md). Chapter 1 and the challenges keep the seeds and id prefixes of
/// the original pack_01/02/03/06, so they regenerate unchanged and saved stars keep their ids.
let packPresets: [String: PackPreset] = [
    "chapter1": PackPreset(file: "chapter_01", idPrefix: "p1", name: "Apprentice Cellar",
                           subtitle: "Sort every potion into its own flask", kind: .chapter, chapter: 1,
                           location: "Apprentice Cellar", introduces: [.basic], seed: 1, tiers: starterTiers),
    "chapter2": PackPreset(file: "chapter_02", idPrefix: "c2", name: "Rune Vault",
                           subtitle: "Sealed flasks open with a rune-stone key", kind: .chapter, chapter: 2,
                           location: "Rune Vault", introduces: [.sealed], seed: 7_000, tiers: [
        // Tutorial: 3 colors in size-3 flasks; the key sits under a short run.
        Tier(count: 1, colors: 3, capacity: 3, empty: 1, locks: 1, moves: any, pool: 8, locksMatter: true,
             keepEasiest: true, section: 0),
        // One seal (every lock must matter).
        Tier(count: 3, colors: 3, capacity: 4, empty: 2, locks: 1, moves: any, score: 20...27, locksMatter: true, strongLocks: true, section: 1),
        Tier(count: 5, colors: 4, capacity: 4, empty: 2, locks: 1, moves: any, score: 27...34, locksMatter: true, strongLocks: true, section: 1),
        Tier(count: 6, colors: 5, capacity: 4, empty: 2, locks: 1, moves: any, score: 33...41, locksMatter: true, strongLocks: true, section: 1),
        Tier(count: 4, colors: 6, capacity: 4, empty: 2, locks: 1, moves: 17...99, score: 39...45, locksMatter: true, strongLocks: true, section: 1),
        Tier(count: 3, colors: 5, capacity: 4, empty: 1, locks: 1, moves: any, score: 40...46, locksMatter: true, strongLocks: true, section: 1),
        // Two seals.
        Tier(count: 4, colors: 6, capacity: 4, empty: 2, locks: 2, moves: 19...99, score: 45...51, locksMatter: true, strongLocks: true, section: 2),
        Tier(count: 4, colors: 7, capacity: 4, empty: 2, locks: 2, moves: 21...99, score: 50...58, locksMatter: true, strongLocks: true, section: 2),
    ]),
    "chapter3": PackPreset(file: "chapter_03", idPrefix: "c3", name: "Misty Marsh",
                           subtitle: "Murky potions hide what lies beneath", kind: .chapter, chapter: 3,
                           location: "Misty Marsh", introduces: [.murky], seed: 8_000, tiers: [
        // Tutorial: tiny murky level.
        Tier(count: 1, colors: 3, capacity: 3, empty: 2, hidden: true, moves: 4...6, pool: 4, keepEasiest: true, section: 0),
        // Murky only.
        Tier(count: 5, colors: 4, capacity: 4, empty: 2, hidden: true, moves: any, score: 26...32, section: 1),
        Tier(count: 7, colors: 5, capacity: 4, empty: 2, hidden: true, moves: any, score: 31...38, section: 1),
        Tier(count: 6, colors: 6, capacity: 4, empty: 2, hidden: true, moves: any, score: 37...43, section: 1),
        Tier(count: 3, colors: 5, capacity: 4, empty: 1, hidden: true, moves: any, score: 38...44, section: 1),
        // Murky + one seal (every lock must matter).
        Tier(count: 4, colors: 6, capacity: 4, empty: 2, locks: 1, hidden: true, moves: 17...99, score: 43...49,
             locksMatter: true, strongLocks: true, section: 2),
        Tier(count: 4, colors: 7, capacity: 4, empty: 2, locks: 1, hidden: true, moves: 20...99, score: 49...57,
             locksMatter: true, strongLocks: true, section: 2),
    ]),
    "chapter4": PackPreset(file: "chapter_04", idPrefix: "c4", name: "Glyph Library",
                           subtitle: "A flask etched with a rune takes only its own color", kind: .chapter, chapter: 4,
                           location: "Glyph Library", introduces: [.essence], seed: 9_000, tiers: [
        // Tutorial: 3 colors in size-3 flasks; one of the two empty flasks carries a rune.
        Tier(count: 1, colors: 3, capacity: 3, empty: 2, moves: any, pool: 8, essence: 1, essenceEmpty: 1,
             essenceCost: EssenceImpact.minimumCost, keepEasiest: true, section: 0),
        // Essence only; every rune costs a detour of 2+ moves (EssenceImpact.strongCost).
        Tier(count: 3, colors: 4, capacity: 3, empty: 2, moves: any, score: 19...25, essence: 2,
             essenceCost: EssenceImpact.strongCost, section: 1),
        Tier(count: 3, colors: 4, capacity: 4, empty: 2, moves: any, score: 23...30, essence: 2,
             essenceCost: EssenceImpact.strongCost, section: 1),
        Tier(count: 5, colors: 5, capacity: 4, empty: 2, moves: any, score: 29...37, essence: 1,
             essenceCost: EssenceImpact.strongCost, section: 1),
        Tier(count: 4, colors: 6, capacity: 4, empty: 2, moves: any, score: 36...43, essence: 1,
             essenceCost: EssenceImpact.strongCost, section: 1),
        Tier(count: 3, colors: 6, capacity: 4, empty: 2, moves: any, score: 35...42, essence: 2,
             essenceCost: EssenceImpact.strongCost, section: 1),
        Tier(count: 3, colors: 7, capacity: 4, empty: 2, moves: any, score: 43...50, essence: 1,
             essenceCost: EssenceImpact.strongCost, section: 1),
        // Runes with earlier mechanics: murky layers, then one strong seal (one empty flask,
        // like the sealed daily: the lock layout adds a partly filled flask).
        Tier(count: 3, colors: 6, capacity: 4, empty: 2, hidden: true, moves: any, score: 40...46, essence: 1,
             essenceCost: EssenceImpact.strongCost, section: 2),
        Tier(count: 3, colors: 6, capacity: 4, empty: 1, locks: 1, moves: any, score: 42...50, locksMatter: true,
             strongLocks: true, essence: 1, essenceCost: EssenceImpact.strongCost, section: 2),
        Tier(count: 2, colors: 7, capacity: 4, empty: 1, locks: 1, hidden: true, moves: any, score: 48...57,
             locksMatter: true, strongLocks: true, essence: 1, essenceCost: EssenceImpact.strongCost, section: 2),
    ]),
    "chapter5": PackPreset(file: "chapter_05", idPrefix: "c5", name: "Glass Works",
                           subtitle: "Narrow necks, funnels and taps change how potions flow", kind: .chapter, chapter: 5,
                           location: "Glass Works", introduces: [.narrowNeck, .funnel, .tap], seed: 10_000, tiers: [
        // Tutorial: 3 colors in size-3 flasks; one narrow neck that costs at least 2 moves.
        Tier(count: 1, colors: 3, capacity: 3, empty: 2, moves: any, pool: 8, narrow: 1,
             glassCost: GlassImpact.strongCost, keepEasiest: true, section: 0),
        // Narrow necks only (every glass flask changes the optimum by 2+ moves).
        Tier(count: 3, colors: 4, capacity: 4, empty: 2, moves: any, score: 22...29, narrow: 1,
             glassCost: GlassImpact.strongCost, section: 1),
        Tier(count: 3, colors: 5, capacity: 4, empty: 2, moves: any, score: 28...35, narrow: 1,
             glassCost: GlassImpact.strongCost, section: 1),
        // Funnels (they matter by the trap they set), then with a narrow neck.
        Tier(count: 1, colors: 4, capacity: 4, empty: 2, moves: any, pool: 4, funnel: 1,
             glassCost: GlassImpact.strongCost, keepEasiest: true, section: 2),
        Tier(count: 3, colors: 5, capacity: 4, empty: 2, moves: any, score: 32...38, funnel: 1,
             glassCost: GlassImpact.strongCost, section: 2),
        Tier(count: 2, colors: 5, capacity: 4, empty: 2, moves: any, score: 36...42, narrow: 1, funnel: 1,
             glassCost: GlassImpact.strongCost, section: 2),
        // Taps, then with a narrow neck.
        Tier(count: 1, colors: 4, capacity: 3, empty: 2, moves: any, pool: 4, tap: 1,
             glassCost: GlassImpact.strongCost, keepEasiest: true, section: 3),
        Tier(count: 3, colors: 5, capacity: 4, empty: 2, moves: any, score: 36...44, tap: 1,
             glassCost: GlassImpact.strongCost, section: 3),
        Tier(count: 2, colors: 5, capacity: 4, empty: 2, moves: any, score: 40...46, narrow: 1, tap: 1,
             glassCost: GlassImpact.strongCost, section: 3),
        // All three, and with earlier mechanics: murky layers, a strong seal, an essence rune.
        Tier(count: 2, colors: 6, capacity: 4, empty: 2, moves: any, score: 42...48, narrow: 1, funnel: 1,
             glassCost: GlassImpact.strongCost, section: 4),
        Tier(count: 2, colors: 6, capacity: 4, empty: 2, moves: any, score: 45...51, funnel: 1, tap: 1,
             glassCost: GlassImpact.strongCost, section: 4),
        Tier(count: 2, colors: 6, capacity: 4, empty: 2, hidden: true, moves: any, score: 46...53, narrow: 1, tap: 1,
             glassCost: GlassImpact.strongCost, section: 4),
        Tier(count: 2, colors: 6, capacity: 4, empty: 2, locks: 1, moves: any, score: 46...54, locksMatter: true,
             strongLocks: true, narrow: 1, glassCost: GlassImpact.strongCost, section: 4),
        Tier(count: 2, colors: 6, capacity: 4, empty: 2, moves: any, score: 49...56, essence: 1, essenceEmpty: 0,
             essenceCost: EssenceImpact.minimumCost, tap: 1, glassCost: GlassImpact.strongCost, section: 4),
        Tier(count: 1, colors: 7, capacity: 4, empty: 2, moves: any, score: 51...58, narrow: 1, funnel: 1, tap: 1,
             glassCost: GlassImpact.strongCost, section: 4),
    ]),
    "chapter6": PackPreset(file: "chapter_06", idPrefix: "c6", name: "Frost Peak",
                           subtitle: "Frozen layers wait for the thaw", kind: .chapter, chapter: 6,
                           location: "Frost Peak", introduces: [.frozen], seed: 11_000, tiers: [
        // Tutorial: 3 colors in size-3 flasks, two empty flasks, one frozen layer that costs 2+ moves,
        // with a layer above it that pours on the way, and every star reachable without parking a flask.
        Tier(count: 1, colors: 3, capacity: 3, empty: 2, moves: any, pool: 16, frozen: 1, frozenTurns: 5,
             frozenCost: FrozenImpact.strongCost, keepEasiest: true, teachesIce: true, section: 0),
        // Ice only, sorted together by score: one frozen layer (with two empty flasks a single
        // layer almost never costs 2 moves, so one empty flask), then two (two empty flasks).
        Tier(count: 2, colors: 3, capacity: 4, empty: 1, moves: any, frozen: 1, frozenTurns: 4,
             frozenCost: FrozenImpact.strongCost, section: 1),
        Tier(count: 4, colors: 4, capacity: 4, empty: 1, moves: any, frozen: 1, frozenTurns: 5,
             frozenCost: FrozenImpact.strongCost, section: 1),
        Tier(count: 2, colors: 4, capacity: 3, empty: 2, moves: any, frozen: 2, frozenTurns: 5,
             frozenCost: FrozenImpact.strongCost, section: 1),
        Tier(count: 3, colors: 4, capacity: 4, empty: 2, moves: any, frozen: 2, frozenTurns: 5,
             frozenCost: FrozenImpact.strongCost, section: 1),
        Tier(count: 3, colors: 5, capacity: 4, empty: 2, moves: any, pool: 2, frozen: 2, frozenTurns: 5,
             frozenCost: FrozenImpact.strongCost, section: 1),
        // With earlier mechanics: murky layers, a rune, then strong seals (the seal layout's
        // partly filled flask leaves room for one empty flask).
        Tier(count: 2, colors: 5, capacity: 4, empty: 2, hidden: true, moves: any, score: 35...41, frozen: 2,
             frozenTurns: 5, frozenCost: FrozenImpact.strongCost, section: 2),
        Tier(count: 2, colors: 5, capacity: 4, empty: 2, moves: any, score: 35...42, essence: 1,
             essenceCost: EssenceImpact.minimumCost, frozen: 2, frozenTurns: 5, frozenCost: FrozenImpact.strongCost,
             section: 2),
        Tier(count: 2, colors: 4, capacity: 4, empty: 1, locks: 1, moves: any, score: 35...41, locksMatter: true,
             strongLocks: true, frozen: 1, frozenTurns: 5, frozenCost: FrozenImpact.strongCost, section: 2),
        Tier(count: 2, colors: 5, capacity: 4, empty: 1, locks: 1, moves: any, score: 36...44, locksMatter: true,
             strongLocks: true, frozen: 2, frozenTurns: 5, frozenCost: FrozenImpact.strongCost, section: 2),
        Tier(count: 2, colors: 6, capacity: 4, empty: 1, locks: 1, moves: any, score: 40...48, locksMatter: true,
             strongLocks: true, frozen: 2, frozenTurns: 5, frozenCost: FrozenImpact.strongCost, section: 2),
        Tier(count: 2, colors: 6, capacity: 4, empty: 1, locks: 1, hidden: true, moves: any, score: 42...50,
             locksMatter: true, strongLocks: true, frozen: 2, frozenTurns: 5, frozenCost: FrozenImpact.strongCost,
             section: 2),
        Tier(count: 3, colors: 7, capacity: 4, empty: 1, locks: 1, moves: any, score: 49...58, locksMatter: true,
             strongLocks: true, frozen: 2, frozenTurns: 5, frozenCost: FrozenImpact.strongCost, section: 2),
    ]),
    "chapter7": PackPreset(file: "chapter_07", idPrefix: "c7", name: "Bubbling Bog",
                           subtitle: "Bubbling flasks lift their bottom layer to the top", kind: .chapter, chapter: 7,
                           location: "Bubbling Bog", introduces: [.bubbling], seed: 12_000, tiers: [
        // Tutorial: 3 colors in size-3 flasks, two empty flasks, one flask that bubbles every
        // 2 moves; its rise changes the optimum by 2+ moves, an optimal solution pours a risen
        // layer without parking a flask, and no first move is a dead end.
        Tier(count: 1, colors: 3, capacity: 3, empty: 2, moves: any, pool: 16, bubbling: 1, bubblingPeriod: 2,
             bubblingCost: BubblingImpact.strongCost, keepEasiest: true, teachesBubbling: true, section: 0),
        // Bubbling only (every bubbling flask changes the optimum by 2+ moves, either way).
        Tier(count: 3, colors: 3, capacity: 4, empty: 2, moves: any, score: 19...27, bubbling: 1, bubblingPeriod: 3,
             bubblingCost: BubblingImpact.strongCost, section: 1),
        Tier(count: 3, colors: 4, capacity: 3, empty: 2, moves: any, score: 23...29, bubbling: 1, bubblingPeriod: 3,
             bubblingCost: BubblingImpact.strongCost, section: 1),
        Tier(count: 2, colors: 4, capacity: 4, empty: 2, moves: any, bubbling: 2, bubblingPeriod: 2,
             bubblingCost: BubblingImpact.strongCost, section: 1),
        Tier(count: 3, colors: 4, capacity: 4, empty: 2, moves: any, score: 30...37, bubbling: 1, bubblingPeriod: 3,
             bubblingCost: BubblingImpact.strongCost, section: 1),
        Tier(count: 2, colors: 4, capacity: 4, empty: 2, moves: any, score: 30...39, bubbling: 2, bubblingPeriod: 3,
             bubblingCost: BubblingImpact.strongCost, section: 1),
        Tier(count: 3, colors: 5, capacity: 4, empty: 2, moves: any, score: 36...43, bubbling: 1, bubblingPeriod: 4,
             bubblingCost: BubblingImpact.strongCost, section: 1),
        Tier(count: 2, colors: 6, capacity: 4, empty: 2, moves: any, score: 42...48, bubbling: 1, bubblingPeriod: 3,
             bubblingCost: BubblingImpact.strongCost, section: 1),
        // With earlier mechanics: murky layers, then strong seals (the seal layout's partly
        // filled flask leaves room for one empty flask), then both.
        Tier(count: 3, colors: 5, capacity: 4, empty: 2, hidden: true, moves: any, score: 36...44, bubbling: 1,
             bubblingPeriod: 3, bubblingCost: BubblingImpact.strongCost, section: 2),
        Tier(count: 3, colors: 5, capacity: 4, empty: 1, locks: 1, moves: any, score: 36...45, locksMatter: true,
             strongLocks: true, bubbling: 1, bubblingPeriod: 3, bubblingCost: BubblingImpact.strongCost, section: 2),
        Tier(count: 3, colors: 6, capacity: 4, empty: 1, locks: 1, hidden: true, moves: any, score: 43...50,
             locksMatter: true, strongLocks: true, bubbling: 1, bubblingPeriod: 3,
             bubblingCost: BubblingImpact.strongCost, section: 2),
        Tier(count: 2, colors: 7, capacity: 4, empty: 1, locks: 1, moves: any, score: 49...56, locksMatter: true,
             strongLocks: true, bubbling: 1, bubblingPeriod: 3, bubblingCost: BubblingImpact.strongCost, section: 2),
    ]),
    "chapter8": PackPreset(file: "chapter_08", idPrefix: "c8", name: "Twin Towers",
                           subtitle: "Chained twins share every pour; overflow pipes catch what doesn't fit",
                           kind: .chapter, chapter: 8, location: "Twin Towers", introduces: [.twins, .overflow],
                           seed: 13_000, tiers: [
        // Tutorial: 3 colors in size-3 flasks; two of the three empty flasks are chained twins; the chain
        // costs 2+ moves, an optimal solution splits a pour into the twins without parking a flask, and
        // no first move is a dead end.
        Tier(count: 1, colors: 3, capacity: 3, empty: 3, moves: any, pool: 16, twins: 1, linkPlacement: .empty,
             linkCost: LinkImpact.strongCost, keepEasiest: true, teachesLinks: true, section: 0),
        // Twins only (every chain changes the optimum by 2+ moves): on two filled flasks, or on two of
        // three empty flasks.
        Tier(count: 2, colors: 3, capacity: 4, empty: 2, moves: any, score: 18...24, twins: 1, linkPlacement: .filled,
             linkCost: LinkImpact.strongCost, section: 1),
        Tier(count: 2, colors: 4, capacity: 3, empty: 2, moves: any, score: 23...30, twins: 1, linkPlacement: .filled,
             linkCost: LinkImpact.strongCost, section: 1),
        Tier(count: 3, colors: 4, capacity: 4, empty: 3, moves: any, score: 28...35, twins: 1, linkPlacement: .empty,
             linkCost: LinkImpact.strongCost, section: 1),
        Tier(count: 3, colors: 5, capacity: 4, empty: 3, moves: any, score: 35...42, twins: 1, linkPlacement: .empty,
             linkCost: LinkImpact.strongCost, section: 1),
        Tier(count: 2, colors: 5, capacity: 4, empty: 2, moves: any, score: 37...45, twins: 1, linkPlacement: .filled,
             linkCost: LinkImpact.strongCost, section: 1),
        // Overflow pipes (from a filled flask into an empty one; a pipe matters by the spill trap it
        // sets, DECISIONS 181): 6 colors in size-3 flasks.
        Tier(count: 5, colors: 6, capacity: 3, empty: 2, moves: any, overflow: 1, linkPlacement: .mixed,
             linkCost: LinkImpact.strongCost, section: 2),
        // With earlier mechanics: murky twins and pipes, twins with a strong seal (one empty flask, or
        // two with 6 colors).
        Tier(count: 3, colors: 5, capacity: 4, empty: 2, hidden: true, moves: any, score: 38...46, twins: 1,
             linkPlacement: .filled, linkCost: LinkImpact.strongCost, section: 3),
        Tier(count: 2, colors: 6, capacity: 3, empty: 2, hidden: true, moves: any, overflow: 1, linkPlacement: .mixed,
             linkCost: LinkImpact.strongCost, section: 3),
        Tier(count: 3, colors: 5, capacity: 4, empty: 1, locks: 1, moves: any, score: 38...48, locksMatter: true,
             strongLocks: true, twins: 1, linkPlacement: .filled, linkCost: LinkImpact.strongCost, section: 3),
        Tier(count: 3, colors: 6, capacity: 4, empty: 2, locks: 1, moves: any, score: 44...56, locksMatter: true,
             strongLocks: true, twins: 1, linkPlacement: .filled, linkCost: LinkImpact.strongCost, section: 3),
        // The hardest: 7 colors, twins on two filled flasks.
        Tier(count: 2, colors: 7, capacity: 4, empty: 2, moves: any, score: 50...57, twins: 1, linkPlacement: .filled,
             linkCost: LinkImpact.strongCost, section: 3),
        // Both links in one recipe: a twin chain and a pipe, each mattering on its own (rare: ~1 in 1000).
        Tier(count: 1, colors: 6, capacity: 3, empty: 2, moves: any, twins: 1, overflow: 1, linkPlacement: .any,
             linkCost: LinkImpact.strongCost, section: 3, maxAttempts: 8_000),
    ]),
    "challenger": PackPreset(file: "challenge_challenger", idPrefix: "p2", name: "Challenger",
                             subtitle: "8–10 colors, tight spaces", kind: .challenge, seed: 2_000, tiers: [
        Tier(count: 6, colors: 5, capacity: 4, empty: 1, moves: any, pool: 4),     // one empty bottle
        Tier(count: 8, colors: 8, capacity: 4, empty: 2, moves: 24...99, pool: 3),
        Tier(count: 6, colors: 7, capacity: 5, empty: 2, moves: any, pool: 2),     // taller bottles
        Tier(count: 6, colors: 9, capacity: 4, empty: 2, moves: 27...99, pool: 2),
        Tier(count: 4, colors: 10, capacity: 4, empty: 2, moves: 30...99, pool: 2),
    ]),
    "expert": PackPreset(file: "challenge_expert", idPrefix: "p3", name: "Expert",
                         subtitle: "10–12 colors and tall flasks", kind: .challenge, seed: 3_000, tiers: [
        Tier(count: 6, colors: 6, capacity: 5, empty: 1, moves: any, pool: 2),     // one empty, tall
        Tier(count: 6, colors: 8, capacity: 5, empty: 2, moves: 30...99, pool: 2),
        Tier(count: 6, colors: 10, capacity: 4, empty: 2, moves: 30...99, pool: 3),
        Tier(count: 6, colors: 11, capacity: 4, empty: 2, moves: 33...99, pool: 2),
        Tier(count: 6, colors: 12, capacity: 4, empty: 2, moves: 36...99, pool: 2),
    ]),
    "master": PackPreset(file: "challenge_master", idPrefix: "p6", name: "Master",
                         subtitle: "Everything at once. Good luck.", kind: .challenge, seed: 6_000, tiers: [
        Tier(count: 4, colors: 6, capacity: 5, empty: 1, moves: any, pool: 3),
        Tier(count: 4, colors: 10, capacity: 5, empty: 2, moves: 40...99, pool: 2),
        Tier(count: 4, colors: 12, capacity: 4, empty: 2, moves: 38...99, pool: 3),
        Tier(count: 4, colors: 10, capacity: 4, empty: 2, locks: 2, moves: any, pool: 1),
        Tier(count: 4, colors: 10, capacity: 4, empty: 2, hidden: true, moves: 31...99, pool: 2),
    ]),
]
let presetOrder = ["chapter1", "chapter2", "chapter3", "chapter4", "chapter5", "chapter6", "chapter7", "chapter8", "challenger", "expert", "master"]

func generate(tiers: [Tier], seed: UInt64, idPrefix: String, scoreRange: ClosedRange<Double>?) -> [LevelDefinition] {
    var all: [(level: GeneratedLevel, hidden: Bool, section: Int)] = []
    for (t, tier) in tiers.enumerated() {
        // Separate seed space per tier, so editing one tier doesn't change the others.
        let config = GeneratorConfig(colors: tier.colors, capacity: tier.capacity, emptyBottles: tier.empty,
                                     locks: tier.locks, seed: seed &+ UInt64(t) * 1_000_000, minMoves: tier.moves,
                                     score: tier.score ?? scoreRange, requireLocksMatter: tier.locksMatter,
                                     lockCost: tier.strongLocks ? LockImpact.strongCost : LockImpact.minimumCost,
                                     essence: tier.essence, essenceEmpty: tier.essenceEmpty,
                                     requireEssenceMatter: tier.essenceCost != nil,
                                     essenceCost: tier.essenceCost ?? EssenceImpact.minimumCost,
                                     hidden: tier.hidden, narrowNecks: tier.narrow, funnels: tier.funnel, taps: tier.tap,
                                     requireGlassMatter: tier.glassCost != nil,
                                     glassCost: tier.glassCost ?? GlassImpact.minimumCost,
                                     frozen: tier.frozen, frozenMaxTurns: tier.frozenTurns,
                                     requireFrozenMatter: tier.frozenCost != nil,
                                     frozenCost: tier.frozenCost ?? FrozenImpact.minimumCost,
                                     bubbling: tier.bubbling, bubblingPeriod: tier.bubblingPeriod,
                                     requireBubblingMatter: tier.bubblingCost != nil,
                                     bubblingCost: tier.bubblingCost ?? BubblingImpact.minimumCost,
                                     twins: tier.twins, overflow: tier.overflow, linkPlacement: tier.linkPlacement,
                                     requireLinksMatter: tier.linkCost != nil,
                                     linkCost: tier.linkCost ?? LinkImpact.minimumCost, maxAttempts: tier.maxAttempts)
        let start = ContinuousClock.now
        var generated: [GeneratedLevel] = []
        do {
            generated = try Generator.generate(config, count: tier.count * tier.pool) { level in
                log("  seed \(level.seed): minMoves \(level.report.minMoves), score \(level.report.score)")
            }
        } catch { fail("tier \(t + 1) (\(tier.colors) colors): \(error)") }
        if tier.teachesIce {
            generated = generated.filter {
                FrozenImpact.everyIceHasALayerAbove($0.state)
                    && FrozenImpact.solvesWithoutRelocation($0.state, in: $0.report.minMoves, pouringAboveIce: true)
            }
            if generated.count < tier.count { fail("tier \(t + 1): too few levels teach the ice; raise the pool") }
        }
        if tier.teachesBubbling {
            generated = generated.filter {
                BubblingImpact.solvesWithoutRelocation($0.state, in: $0.report.minMoves, pouringARisenLayer: true)
                    && MechanicImpact.everyFirstMoveSolvable($0.state)
            }
            if generated.count < tier.count { fail("tier \(t + 1): too few levels teach the bubbling; raise the pool") }
        }
        if tier.teachesLinks {
            generated = generated.filter {
                LinkImpact.solvesUsingEveryLink($0.state, in: $0.report.minMoves)
                    && MechanicImpact.everyFirstMoveSolvable($0.state)
            }
            if generated.count < tier.count { fail("tier \(t + 1): too few levels teach the links; raise the pool") }
        }
        // Keep the hardest (or, for a tutorial, the easiest) `count` of the pool.
        let hardestFirst = generated.sorted { ($0.report.score, $1.seed) > ($1.report.score, $0.seed) }
        let kept = tier.keepEasiest ? hardestFirst.reversed().prefix(tier.count) : hardestFirst.prefix(tier.count)
        all += kept.map { ($0, tier.hidden, tier.section) }
        let pooled = tier.pool > 1 ? " (\(tier.keepEasiest ? "easiest" : "best") of \(tier.count * tier.pool))" : ""
        log("tier \(t + 1): \(tier.count)\(pooled) × \(tier.colors) colors, cap \(tier.capacity), \(tier.empty) empty, \(tier.locks) locks\(tier.essence > 0 ? ", \(tier.essence) essence" : "")\(tier.narrow > 0 ? ", \(tier.narrow) narrow" : "")\(tier.funnel > 0 ? ", \(tier.funnel) funnel" : "")\(tier.tap > 0 ? ", \(tier.tap) tap" : "")\(tier.frozen > 0 ? ", \(tier.frozen) frozen ≤\(tier.frozenTurns)" : "")\(tier.bubbling > 0 ? ", \(tier.bubbling) bubbling /\(tier.bubblingPeriod)" : "")\(tier.twins > 0 ? ", \(tier.twins) twins" : "")\(tier.overflow > 0 ? ", \(tier.overflow) overflow" : "")\(tier.hidden ? ", hidden" : "") — \(formatTime(ContinuousClock.now - start))")
    }
    // Sort by score within each section, so difficulty rises through the whole pack.
    return all.sorted { ($0.section, $0.level.report.score, $0.level.seed) < ($1.section, $1.level.report.score, $1.level.seed) }
        .enumerated().map { i, entry in
            LevelDefinition(id: String(format: "%@_%03d", idPrefix, i + 1), state: entry.level.state,
                            hidden: entry.hidden, meta: LevelMeta(seed: entry.level.seed, report: entry.level.report))
        }
}

func write(_ levels: [LevelDefinition], to path: String, pack template: LevelPack) {
    do {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pack = template
        pack.levels = levels
        try LevelLoader.encode(pack).write(to: url)
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
    let locks = int("--locks", default: 0)!
    let frozen = frozenOption()
    let bubbling = bubblingOption()
    let links = linkOptions()
    let config = GeneratorConfig(colors: colors, capacity: capacity, emptyBottles: empty, locks: locks,
                                 essence: int("--essence", default: 0)!, essenceEmpty: int("--essence-empty"),
                                 narrowNecks: int("--narrow", default: 0)!, funnels: int("--funnel", default: 0)!,
                                 taps: int("--tap", default: 0)!, frozen: frozen.count, frozenMaxTurns: frozen.maxTurns,
                                 bubbling: bubbling.count, bubblingPeriod: bubbling.period,
                                 twins: links.twins, overflow: links.overflow, linkPlacement: linkPlacementOption())
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
    var isDirectory: ObjCBool = false
    let files: [String]
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        files = names.filter { $0.hasSuffix(".json") }.sorted().map { path + "/" + $0 }
    } else {
        files = [path]
    }
    let problems = files.map(report(path:)).reduce(0, +)
    if files.count > 1 { print("\(files.count) files, \(problems) problem(s)") }
    if problems > 0 { exit(2) }
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
            let template = LevelPack(name: preset.name, subtitle: preset.subtitle, kind: preset.kind, chapter: preset.chapter,
                                     location: preset.location, introduces: preset.introduces, levels: [])
            write(generate(tiers: preset.tiers, seed: seed, idPrefix: options["--id-prefix"] ?? preset.idPrefix, scoreRange: scores),
                  to: out, pack: template)
        }
    } else {
        guard let out = options["--out"], let colors = int("--colors") else { fail(usage) }
        let seed = UInt64(int("--seed", default: 1)!)
        let moves = range(int("--min-moves"), int("--max-moves"), name: "moves") ?? 0...Int.max
        let locks = int("--locks", default: 0)!
        guard locks >= 0, locks < colors else { fail("--locks must be between 0 and colors - 1") }
        let essence = int("--essence", default: 0)!
        guard essence >= 0, essence <= colors else { fail("--essence must be between 0 and colors") }
        let essenceCost = int("--essence-cost") ?? (flags.contains("--essence-matter") ? EssenceImpact.minimumCost : nil)
        let glassCost = int("--glass-cost") ?? (flags.contains("--glass-matter") ? GlassImpact.minimumCost : nil)
        let narrow = int("--narrow", default: 0)!, funnel = int("--funnel", default: 0)!, tap = int("--tap", default: 0)!
        guard narrow >= 0, funnel >= 0, tap >= 0 else { fail("--narrow, --funnel and --tap must not be negative") }
        let frozen = frozenOption()
        let frozenCost = int("--frozen-cost") ?? (flags.contains("--frozen-matter") ? FrozenImpact.minimumCost : nil)
        let bubbling = bubblingOption()
        let bubblingCost = int("--bubbling-cost") ?? (flags.contains("--bubbling-matter") ? BubblingImpact.minimumCost : nil)
        let links = linkOptions()
        let linkCost = int("--link-cost") ?? (flags.contains("--links-matter") ? LinkImpact.minimumCost : nil)
        let tier = Tier(count: int("--count", default: 20)!, colors: colors, capacity: int("--capacity", default: 4)!,
                        empty: int("--empty", default: 2)!, locks: locks, hidden: flags.contains("--hidden"), moves: moves,
                        pool: int("--pool", default: 1)!, locksMatter: flags.contains("--locks-matter"),
                        essence: essence, essenceEmpty: int("--essence-empty"), essenceCost: essenceCost,
                        narrow: narrow, funnel: funnel, tap: tap, glassCost: glassCost,
                        frozen: frozen.count, frozenTurns: frozen.maxTurns, frozenCost: frozenCost,
                        bubbling: bubbling.count, bubblingPeriod: bubbling.period, bubblingCost: bubblingCost,
                        twins: links.twins, overflow: links.overflow, linkPlacement: linkPlacementOption(),
                        linkCost: linkCost, keepEasiest: flags.contains("--easiest"))
        let kind = options["--kind"].map { raw -> PackKind in
            guard let k = PackKind(rawValue: raw) else { fail("--kind expects chapter or challenge") }
            return k
        }
        let template = LevelPack(name: options["--name"], subtitle: options["--subtitle"], kind: kind,
                                 chapter: int("--chapter"), location: options["--location"], levels: [])
        write(generate(tiers: [tier], seed: seed, idPrefix: options["--id-prefix"] ?? "p1", scoreRange: scores),
              to: out, pack: template)
    }
}
