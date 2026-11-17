import Foundation
import HiddenCore

// hiddengen — the hidden-object rooms' fixed rounds (R11, DECISIONS 304).
// Every player gets the curated layouts in HiddenScenes/<room>/rounds.json; the generator only proposes them.
//
//   hiddengen propose <HiddenScenes dir> <room|all> [--force]
//       write rounds.json from the generator (variant 0 of every round); refuses to overwrite without --force
//   hiddengen propose <HiddenScenes dir> <room> --round N [--variant V] [--force]
//       replace one round with the generator's candidate (variant V, default 1) — for a round the review rejects
//   hiddengen check <HiddenScenes dir> [room|all]
//       load + validate rounds.json, print targets+decoys per round (exit 1 on any problem)
//   hiddengen freeze <HiddenScenes dir> [room|all]
//       validate, then rewrite rounds.json in the canonical form (sorted keys, review notes kept)
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    print("usage: hiddengen propose|check|freeze <HiddenScenes dir> [room|all] [--round N] [--variant V] [--force]")
    exit(2)
}

func option(_ name: String) -> Int? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return Int(args[i + 1])
}

let dir = URL(fileURLWithPath: args[1])
let which = args.count > 2 && !args[2].hasPrefix("--") ? args[2] : "all"
let rooms = which == "all" ? HiddenSceneID.allCases : [HiddenSceneID(rawValue: which)].compactMap { $0 }
guard !rooms.isEmpty else {
    print("unknown room \(which)")
    exit(2)
}
let force = args.contains("--force")

func write(_ file: HiddenFixedFile, to url: URL) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try enc.encode(file)
    data.append(0x0A)
    try data.write(to: url)
}

var failed = false
for room in rooms {
    let folder = dir.appending(path: room.rawValue)
    let scene = try HiddenScene(data: Data(contentsOf: folder.appending(path: "scene.json")))
    let out = folder.appending(path: "rounds.json")
    switch args[0] {
    case "propose":
        if let round = option("--round") {
            guard HiddenCurve.rounds.contains(round) else { print("round \(round) is not 1…10"); exit(2) }
            var file = try JSONDecoder().decode(HiddenFixedFile.self, from: Data(contentsOf: out))
            let variant = option("--variant") ?? 1
            let layout = HiddenGenerator.round(scene, round: round, variant: variant)
            let proposal = HiddenFixedFile(proposing: [layout]).rounds[0]
            guard force else {
                print("\(room.rawValue) round \(round), variant \(variant) (use --force to write it):")
                for o in proposal.objects { print("  \(o.role == .target ? "T" : "d") \(o.id) @\(o.spot) L\(o.longSide)") }
                continue
            }
            var replaced = proposal
            replaced.notes = ["proposed by hiddengen (variant \(variant)), not reviewed yet"]
            file.rounds = file.rounds.map { $0.round == round ? replaced : $0 }
            try write(file, to: out)
            print("\(room.rawValue): round \(round) replaced by variant \(variant); review it before shipping")
        } else {
            if FileManager.default.fileExists(atPath: out.path), !force {
                print("\(room.rawValue): rounds.json exists (use --force)")
                continue
            }
            try write(HiddenFixedFile(proposing: HiddenCurve.rounds.map { HiddenGenerator.round(scene, round: $0) }), to: out)
            print("\(room.rawValue): wrote \(out.path)")
        }
    case "check", "freeze":
        do {
            let data = try Data(contentsOf: out)
            let layouts = try HiddenFixedLayouts.load(data, scene: scene)
            let counts = layouts.map { "\($0.targets.count)+\($0.decoys.count)" }.joined(separator: " ")
            print("\(room.rawValue): ok  targets+decoys per round: \(counts)")
            if args[0] == "freeze" {
                try write(try JSONDecoder().decode(HiddenFixedFile.self, from: data), to: out)
                print("\(room.rawValue): froze \(out.path)")
            }
        } catch {
            failed = true
            print("\(room.rawValue): \(error)")
        }
    default:
        print("unknown command \(args[0])")
        exit(2)
    }
}
exit(failed ? 1 : 0)
