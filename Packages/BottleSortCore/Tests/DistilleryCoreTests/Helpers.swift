import BottleSortCore
import Foundation
@testable import DistilleryCore

/// A board from level-file rows ("S", "F", ".", "I1", "L2*", "X"…), sources and targets as (r, c, color, dir).
func board(_ rows: [String], sources: [(Int, Int, Int, DistillDir)], targets: [(Int, Int, Int, DistillDir)],
           valves: [(Int, Int, Int)] = [], coils: [(Int, Int, Int, Int)] = []) -> DistillBoard {
    let tokens = rows.map { $0.split(separator: " ").map(String.init) }
    var pieces: [DistillPiece] = []
    for row in tokens { for t in row { pieces.append(DistillLevel.piece(token: t)!) } }
    var b = DistillBoard(width: tokens[0].count, height: tokens.count, pieces: pieces,
                         sources: sources.map { DistillSource(pos: DistillPos($0.0, $0.1), color: ColorID($0.2), outlet: $0.3) },
                         targets: targets.map { DistillTarget(pos: DistillPos($0.0, $0.1), color: ColorID($0.2), inlet: $0.3) })
    for v in valves { b[DistillPos(v.0, v.1)].valve = v.2 }
    for k in coils { b[DistillPos(k.0, k.1)].coil = DistillCoil(from: ColorID(k.2), to: ColorID(k.3)) }
    return b
}

func P(_ r: Int, _ c: Int) -> DistillPos { DistillPos(r, c) }

func level(_ b: DistillBoard, minTaps: Int = 1) -> DistillLevel { DistillLevel(id: "t", board: b, minTaps: minTaps) }

/// Plays a tap (keeps `#expect` free of mutating calls).
@discardableResult
func tap(_ g: inout DistillGame, _ p: DistillPos, clockwise: Bool = true) -> DistillTapResult? { g.tap(p, clockwise: clockwise) }

/// The repo's Levels/distillery folder.
let distilleryLevelsURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Levels/distillery")

/// Generator-heavy tests (pack regeneration, many dailies) run optimized (`scripts/test-fast.sh`) and in a
/// debug build only with LP_SLOW_TESTS=1.
let heavyTestsEnabled: Bool = {
    #if DEBUG
    return ProcessInfo.processInfo.environment["LP_SLOW_TESTS"] == "1"
    #else
    return true
    #endif
}()
