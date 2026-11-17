import BottleSortCore
import DistilleryCore
import Foundation

// distillgen — Distillery (R10) pack generator, report, daily and random levels.
// Build in release:  swift build -c release --product distillgen   (binary: .build/release/distillgen)

let usage = """
usage:
  distillgen packs [--out DIR] [--only stage1|stage2|stage3|expert|master]
      regenerates the shipped packs from the presets (deterministic; default DIR ../../Levels/distillery)
  distillgen report [DIR]
      validates every pack file and re-solves every level (unique network, minTaps matches), with timings
  distillgen show FILE [--level ID]
      prints levels as text (solved network marked)
  distillgen daily [YYYY-MM-DD] [--days N]
      generates distill-daily-v1 levels with timings and fingerprints
  distillgen random [--tier gentle|tricky|fiendish] [--seed S] [--count N]
      seeded Random Distillery levels
  distillgen gen [--size WxH] [--groups N] [--targets A-B] [--crosses A-B] [--fixed N] [--fixed-decoys N]
                 [--valves N] [--coils N] [--caps N] [--fill P] [--taps A-B] [--seed S] [--count N]
      one configuration
  distillgen bench [DIR]
      solver time per level (best of 5), slowest first
"""

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(1) }
args.removeFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func intOption(_ name: String, _ fallback: Int) -> Int { option(name).flatMap(Int.init) ?? fallback }

func rangeOption(_ name: String, _ fallback: ClosedRange<Int>) -> ClosedRange<Int> {
    guard let s = option(name) else { return fallback }
    let parts = s.split(separator: "-").compactMap { Int($0) }
    if parts.count == 2, parts[0] <= parts[1] { return parts[0]...parts[1] }
    if parts.count == 1 { return parts[0]...parts[0] }
    return fallback
}

func positional() -> String? {
    var i = 0
    while i < args.count {
        if args[i].hasPrefix("--") { i += 2; continue }
        return args[i]
    }
    return nil
}

func now() -> Double { Date().timeIntervalSinceReferenceDate }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func defaultDir() -> String {
    for candidate in ["../../Levels/distillery", "Levels/distillery"] where FileManager.default.fileExists(atPath: candidate) {
        return candidate
    }
    return "../../Levels/distillery"
}

func load(_ path: String) -> DistillPackFile {
    do {
        return try DistillPackFile.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        fail("cannot read \(path): \(error)")
    }
}

func summary(_ l: DistillLevel) -> String {
    let s = l.stats
    let mech = s.map { $0.mechanics.isEmpty ? "-" : $0.mechanics.joined(separator: "+") } ?? "?"
    return "\(l.id)  \(l.board.width)x\(l.board.height)  taps \(l.minTaps)  score \(s?.score ?? 0)  decisions \(s?.decisions ?? 0)"
        + "  net \(s?.networkCells ?? 0)  decoys \(s?.decoys ?? 0)  \(mech)"
}

/// Text picture: the grid tokens, with the solved network's pieces in brackets.
func picture(_ l: DistillLevel) -> String {
    let solved = DistillSolver.solve(l.board).best
    var lines: [String] = []
    for r in 0..<l.board.height {
        var row: [String] = []
        for c in 0..<l.board.width {
            let p = DistillPos(r, c)
            var t = l.gridRows[r].split(separator: " ")[c].description
            if l.board[p].valve != nil { t += "v" }
            if l.board[p].coil != nil { t += "h" }
            let inNet = solved?.masks[l.board.index(p)] != nil
            row.append((inNet ? "[" + t + "]" : " " + t + " ").padding(toLength: 7, withPad: " ", startingAt: 0))
        }
        lines.append(row.joined())
    }
    for s in l.board.sources { lines.append("  source \(s.pos) color \(s.color.rawValue) → \(s.outlet)") }
    for (k, t) in l.board.targets.enumerated() { lines.append("  target \(k) \(t.pos) wants \(t.color.rawValue) ← \(t.inlet)") }
    for i in 0..<l.board.cellCount {
        let piece = l.board.pieces[i]
        if let v = piece.valve { lines.append("  valve \(l.board.pos(i)) opens when target \(v) is full") }
        if let c = piece.coil { lines.append("  coil \(l.board.pos(i)) \(c.from.rawValue) → \(c.to.rawValue)") }
    }
    return lines.joined(separator: "\n")
}

switch command {
case "packs":
    let dir = option("--out") ?? defaultDir()
    let packs = option("--only").map { name in
        guard let p = DistillPack(rawValue: name) else { fail("unknown pack \(name)") }
        return [p]
    } ?? DistillPack.allCases
    for pack in packs {
        let t0 = now()
        var levels: [DistillLevel] = []
        for i in 0..<DistillContent.levelsPerPack {
            guard let l = DistillContent.level(pack, index: i) else { fail("\(pack.levelID(i)): no level") }
            levels.append(l)
            print(summary(l) + "  target \(DistillContent.slot(pack, i).targetScore)")
        }
        let file = DistillPackFile(id: pack.id, title: pack.title, levels: levels)
        let issues = file.validate()
        if !issues.isEmpty { fail(issues.map(\.description).joined(separator: "\n")) }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(pack.fileName)
        try! file.encoded().write(to: url)
        print(String(format: "%@: %d levels in %.1f s → %@", pack.rawValue, levels.count, now() - t0, url.path))
    }

case "report":
    let dir = positional() ?? defaultDir()
    var bad = 0
    var worst = 0.0
    for pack in DistillPack.allCases {
        let file = load(URL(fileURLWithPath: dir).appendingPathComponent(pack.fileName).path)
        var issues = file.validate()
        print("\(pack.fileName): \(file.title), \(file.levels.count) levels")
        for l in file.levels {
            let t0 = now()
            let lv = l.validateSolving()
            let dt = now() - t0
            worst = max(worst, dt)
            issues += lv
            print("  " + summary(l) + String(format: "  solve %.1f ms", dt * 1000) + (lv.isEmpty ? "" : "  FAIL"))
        }
        for issue in issues { print("  ! \(issue)") }
        bad += issues.count
    }
    print(String(format: "slowest validation %.1f ms; %d issue(s)", worst * 1000, bad))
    exit(bad == 0 ? 0 : 1)

case "show":
    guard let path = positional() else { print(usage); exit(1) }
    let file = load(path)
    for l in file.levels where option("--level").map({ $0 == l.id }) ?? true {
        print(summary(l))
        print(picture(l))
        print("")
    }

case "daily":
    let start = positional().flatMap(DailyDate.init(isoString:)) ?? DailyDate.today()
    let days = intOption("--days", 7)
    var worst = 0.0
    for k in 0..<days {
        let date = start.adding(days: k)
        let t0 = now()
        let l = DistillDaily.level(for: date)
        let dt = now() - t0
        worst = max(worst, dt)
        print(String(format: "%@  %@  %.0f ms  fingerprint %016llx", date.isoString, DistillDaily.spec(for: date).label,
                     dt * 1000, DistillDaily.fingerprint(l)))
        print("  " + summary(l))
        if args.contains("--show") { print(picture(l)) }
    }
    print(String(format: "slowest %.0f ms", worst * 1000))

case "random":
    let tier = option("--tier").flatMap(DistillRandomTier.init(rawValue:)) ?? .tricky
    let seed = UInt64(intOption("--seed", 1))
    for k in 0..<intOption("--count", 5) {
        let t0 = now()
        let l = DistillRandom.level(tier: tier, seed: seed &+ UInt64(k))
        print(String(format: "%.0f ms  ", (now() - t0) * 1000) + summary(l))
        if args.contains("--show") { print(picture(l)) }
    }

case "gen":
    let size = (option("--size") ?? "5x5").split(separator: "x").compactMap { Int($0) }
    guard size.count == 2 else { fail("--size WxH") }
    let config = DistillGenConfig(width: size[0], height: size[1], groups: intOption("--groups", 1),
                                  targetsPerGroup: rangeOption("--targets", 1...1), crosses: rangeOption("--crosses", 0...0),
                                  fixedNetwork: intOption("--fixed", 0), fixedDecoys: intOption("--fixed-decoys", 0),
                                  repairWithRivets: intOption("--fixed", 0) > 0, valves: intOption("--valves", 0),
                                  coils: intOption("--coils", 0), capStubs: intOption("--caps", 0),
                                  decoyFill: intOption("--fill", 80), waypoints: rangeOption("--waypoints", 0...1),
                                  noise: intOption("--noise", 3), taps: rangeOption("--taps", 4...12))
    let seed = UInt64(intOption("--seed", 1))
    var ok = 0
    let count = intOption("--count", 5)
    let t0 = now()
    for k in 0..<count {
        let t1 = now()
        guard let l = DistillGenerator.generate(config, seed: seed &+ UInt64(k), id: "gen-\(k + 1)") else {
            print("gen-\(k + 1): gave up")
            continue
        }
        ok += 1
        print(String(format: "%.0f ms  ", (now() - t1) * 1000) + summary(l))
        if args.contains("--show") { print(picture(l)) }
    }
    print(String(format: "%d/%d in %.2f s", ok, count, now() - t0))

case "bench":
    let dir = positional() ?? defaultDir()
    var rows: [(Double, String)] = []
    for pack in DistillPack.allCases {
        let file = load(URL(fileURLWithPath: dir).appendingPathComponent(pack.fileName).path)
        for l in file.levels {
            var best = Double.infinity
            var nodes = 0
            for _ in 0..<5 {
                let t0 = now()
                let r = DistillSolver.solve(l.board)
                best = min(best, now() - t0)
                nodes = r.nodes
            }
            rows.append((best, "\(l.id) \(l.board.width)x\(l.board.height) nodes \(nodes)"))
        }
    }
    rows.sort { $0.0 > $1.0 }
    for (t, s) in rows.prefix(12) { print(String(format: "%7.2f ms  %@", t * 1000, s)) }
    let total = rows.map(\.0).reduce(0, +)
    print(String(format: "%d levels, mean %.2f ms, max %.2f ms", rows.count, total / Double(max(1, rows.count)) * 1000,
                 (rows.first?.0 ?? 0) * 1000))

default:
    print(usage)
    exit(1)
}
