import BottleSortCore
import Foundation
import Match3Core

// m3gen — match-3 (R9) bot simulator, tuner, episode preset, report and daily generator.
// Build in release:  swift build -c release --product m3gen   (binary: .build/release/m3gen)

let usage = """
usage:
  m3gen sim FILE [--level ID] [--policy greedy|reference|novice|random|all] [--runs N] [--bot-seed S] [--moves N]
      plays each level N times (default 200) and prints the pass rate, moves left and scores at its move
      limit (or --moves), plus the suggested move limit for the level's tuning target (or --target P)
  m3gen tune FILE --level ID --target P [--runs N]
      suggests move limit and star thresholds for a target pass rate
  m3gen episodes [--out DIR] [--only E] [--runs N]
      regenerates the shipped episodes from the preset (deterministic; default DIR ../../Levels/match3)
  m3gen report [DIR] [--runs N] [--window W]
      validates every episode file and re-measures each level with a different bot stream:
      pass rate must be within ±W (default 12) points of its target
  m3gen daily [YYYY-MM-DD] [--days N]
      generates m3daily-v1 levels and prints them with timings
  m3gen bench FILE [--runs N]
      times bot games
"""

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(1) }
args.removeFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func intOption(_ name: String, _ fallback: Int) -> Int { option(name).flatMap(Int.init) ?? fallback }

func positional() -> String? {
    var i = 0
    while i < args.count {
        if args[i].hasPrefix("--") { i += 2; continue }
        return args[i]
    }
    return nil
}

func load(_ path: String) -> M3EpisodeFile {
    do {
        return try M3EpisodeFile.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        FileHandle.standardError.write("cannot read \(path): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

func now() -> Double { Date().timeIntervalSinceReferenceDate }

func defaultLevelsDir() -> String {
    // Works from the package directory or the repo root.
    let fm = FileManager.default
    for candidate in ["../../Levels/match3", "Levels/match3"] where fm.fileExists(atPath: candidate) { return candidate }
    return "../../Levels/match3"
}

func describe(_ level: M3Level) -> String {
    "\(level.id) \(level.width)x\(level.height) kinds \(level.kinds.count) moves \(level.moves) goals ["
        + level.goals.map(\.summary).joined(separator: ", ") + "]"
        + (level.features.isEmpty ? "" : " features " + level.features.joined(separator: "+"))
}

switch command {
case "sim":
    guard let path = positional() else { print(usage); exit(1) }
    let file = load(path)
    let runs = intOption("--runs", 200)
    let botSeed = UInt64(intOption("--bot-seed", 1))
    let policyName = option("--policy") ?? "reference"
    let policies = policyName == "all" ? M3BotPolicy.all : [M3BotPolicy.named(policyName) ?? .reference]
    for level in file.levels where option("--level").map({ $0 == level.id }) ?? true {
        print(describe(level))
        for policy in policies {
            let start = now()
            let results = M3Bot.simulate(level, policy: policy, runs: runs, botSeed: botSeed)
            let limit = intOption("--moves", level.moves)
            let summary = M3Bot.summarize(results, limit: limit, stars: level.stars)
            let target = intOption("--target", level.tuning?.target ?? 70)
            let suggested = M3Bot.suggestMoves(results, targetPercent: target).map(String.init) ?? "> cap"
            print(String(format: "  %-9@ %@; for %d%%: %@ moves (%.2f s)", policy.name as NSString,
                         summary.description as NSString, target, suggested as NSString, now() - start))
        }
    }

case "tune":
    guard let path = positional(), let id = option("--level"), let target = option("--target").flatMap(Int.init) else {
        print(usage); exit(1)
    }
    let file = load(path)
    guard let level = file.levels.first(where: { $0.id == id }) else { print("no level \(id)"); exit(1) }
    let results = M3Bot.simulate(level, policy: .reference, runs: intOption("--runs", 300))
    guard let moves = M3Bot.suggestMoves(results, targetPercent: target) else { print("even 99 moves pass < \(target)%"); exit(1) }
    let stars = M3Bot.suggestStars(results, limit: moves)
    print("\(id): moves \(moves), stars two \(stars.two) three \(stars.three)")
    print("  " + M3Bot.summarize(results, limit: moves, stars: stars).description)

case "episodes":
    let dir = option("--out") ?? defaultLevelsDir()
    let runs = intOption("--runs", M3Content.tuningRuns)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for episode in M3Content.episodes where option("--only").flatMap(Int.init).map({ $0 == episode.episode.number }) ?? true {
        let start = now()
        var levels: [M3Level] = []
        for spec in episode.specs {
            guard let result = M3Tuner.tune(spec, runs: runs) else { print("  \(spec.id): could not tune"); exit(1) }
            levels.append(result.level)
            print("  \(describe(result.level)) target \(spec.targetPercent)% → \(result.summary.passRate)% scale \(result.scale)% stars \(result.level.stars.two)/\(result.level.stars.three)")
        }
        let file = M3EpisodeFile(episode: episode.episode, levels: levels)
        let errors = file.validate()
        if !errors.isEmpty { print("episode \(episode.episode.number) invalid: \(errors)"); exit(1) }
        let path = "\(dir)/" + M3Content.fileName(episode.episode.number)
        try! file.encoded().write(to: URL(fileURLWithPath: path))
        print(String(format: "wrote %@ (%.1f s)", path, now() - start))
    }

case "report":
    let dir = positional() ?? defaultLevelsDir()
    let runs = intOption("--runs", 200)
    let window = intOption("--window", 12)
    var failures = 0, count = 0
    let start = now()
    for number in 1...10 {
        let path = "\(dir)/" + M3Content.fileName(number)
        guard FileManager.default.fileExists(atPath: path) else { print("missing \(path)"); failures += 1; continue }
        let file = load(path)
        let errors = file.validate()
        if !errors.isEmpty { print("\(path): \(errors)"); failures += 1 }
        print("Episode \(number) — \(file.episode.name)")
        for level in file.levels {
            count += 1
            let results = M3Bot.simulate(level, policy: .reference, runs: runs, botSeed: 7_777)
            let s = M3Bot.summarize(results, limit: level.moves, stars: level.stars)
            let target = level.tuning?.target ?? 0
            let ok = abs(s.passRate - target) <= window
            if !ok { failures += 1 }
            print("  \(ok ? "ok " : "BAD") \(describe(level)) target \(target)% measured \(s.passRate)% stars \(s.stars)")
        }
    }
    print(String(format: "%d levels, %d problems (%.1f s)", count, failures, now() - start))
    exit(failures == 0 ? 0 : 1)

case "daily":
    let first = positional().flatMap(DailyDate.init(isoString:)) ?? DailyDate.today()
    let days = intOption("--days", 7)
    var worst = 0.0
    for d in 0..<days {
        let date = first.adding(days: d)
        let start = now()
        let gen = M3Daily.generate(for: date)
        let t = now() - start
        worst = max(worst, t)
        print(String(format: "%@ %@ cand %d %.3f s  %@ pass %d%% stars %d/%d fp %@", date.isoString as NSString,
                     gen.spec.label as NSString, gen.candidates, t, describe(gen.level) as NSString, gen.passRate,
                     gen.level.stars.two, gen.level.stars.three, gen.level.fingerprint as NSString))
    }
    print(String(format: "worst %.3f s", worst))

case "trace":
    // m3gen trace FILE --level ID [--policy P] [--bot-seed S] [--max N]: prints the board after every move.
    guard let path = positional(), let id = option("--level") else { print(usage); exit(1) }
    let file = load(path)
    guard let level = file.levels.first(where: { $0.id == id }), var game = M3Game(level: level) else { print("no level \(id)"); exit(1) }
    let policy = M3BotPolicy.named(option("--policy") ?? "reference") ?? .reference
    var rng = SplitMix64(seed: UInt64(intOption("--bot-seed", 1)))
    print(game.board.picture + "\n")
    var n = 0
    while game.status == .playing, n < intOption("--max", 99), let s = M3Bot.choose(game, policy: policy, rng: &rng) {
        let r = game.play(s)
        n += 1
        let progress = level.goals.map { g -> String in let p = game.progress(g); return "\(g.summary) \(p.current)/\(p.target)" }
        print("move \(n): \(s) waves \(r.waves.count) +\(r.scoreGained) left \(r.movesLeft) \(r.status) | " + progress.joined(separator: ", "))
        print(game.board.picture + "\n")
    }
    if game.status == .won {
        let f = game.playFinale()
        print("finale: \(f.bursts.count) bursts +\(f.scoreGained) → \(f.finalScore), \(f.stars) stars")
    }

case "bench":
    guard let path = positional() else { print(usage); exit(1) }
    let file = load(path)
    let runs = intOption("--runs", 100)
    let start = now()
    var moves = 0
    for level in file.levels {
        for r in M3Bot.simulate(level, policy: .reference, runs: runs) { moves += r.movesUsed }
    }
    let t = now() - start
    print(String(format: "%d games, %d moves, %.2f s (%.1f µs/move)", runs * file.levels.count, moves, t, t * 1e6 / Double(max(1, moves))))

default:
    print(usage)
    exit(1)
}
