import BottleSortCore
import Foundation

/// The weekday flavour of the Daily Distillery.
public enum DistillDailyTier: String, Sendable, Hashable, Codable, CaseIterable {
    case gentle, splitter, twoColors, heat, valves, crossings, grand

    /// English name; the app localizes its own labels.
    public var name: String {
        switch self {
        case .gentle: "Gentle"
        case .splitter: "Splitter"
        case .twoColors: "Two Colors"
        case .heat: "Heat Coil"
        case .valves: "Valves"
        case .crossings: "Crossings"
        case .grand: "Grand Still"
        }
    }
}

public struct DistillDailySpec: Sendable, Hashable {
    public var weekday: Weekday
    public var tier: DistillDailyTier
    public var config: DistillGenConfig
    /// Difficulty score the day's pick aims at (`DistillGenerator.score`).
    public var targetScore: Int
    /// "Monday · Gentle"
    public var label: String { "\(weekday.name) · \(tier.name)" }
}

/// Daily Distillery, generator id "distill-daily-v1" (separate from the Daily Brew and the Daily Gathering, which are
/// untouched). One level per UTC date, from a date-seeded stream; integer maths and node limits only (no clocks), so
/// every device builds the same level. Difficulty rises Monday → Sunday (DECISIONS 278).
public enum DistillDaily {
    public static let algorithmVersion = "distill-daily-v1"

    public static func levelID(for date: DailyDate) -> String { "distill-daily-\(date.isoString)" }

    public static func spec(for date: DailyDate) -> DistillDailySpec { spec(for: date.weekday) }

    public static func spec(for weekday: Weekday) -> DistillDailySpec {
        let decoys: [DistillShape] = [.straight, .straight, .elbow, .elbow, .elbow, .tee, .cap]
        let limits = DistillSolverLimits(maxNodes: 150_000)
        let config: DistillGenConfig
        let tier: DistillDailyTier
        switch weekday {
        case .monday:
            tier = .gentle
            config = DistillGenConfig(width: 5, height: 5, decoyFill: 75, decoyShapes: [.straight, .elbow, .elbow, .cap],
                                      waypoints: 0...1, taps: 6...9, minNetwork: 8, limits: limits)
        case .tuesday:
            tier = .splitter
            config = DistillGenConfig(width: 5, height: 5, targetsPerGroup: 2...2, fixedDecoys: 1, decoyFill: 80,
                                      decoyShapes: decoys, waypoints: 0...1, taps: 8...12, minNetwork: 10, limits: limits)
        case .wednesday:
            tier = .twoColors
            config = DistillGenConfig(width: 6, height: 6, groups: 2, fixedDecoys: 1, decoyFill: 85, decoyShapes: decoys,
                                      waypoints: 0...1, taps: 10...15, minNetwork: 14, limits: limits)
        case .thursday:
            tier = .heat
            config = DistillGenConfig(width: 6, height: 6, targetsPerGroup: 2...2, coils: 1, decoyFill: 85,
                                      decoyShapes: decoys, waypoints: 0...1, taps: 11...16, minNetwork: 14, limits: limits)
        case .friday:
            tier = .valves
            config = DistillGenConfig(width: 6, height: 6, groups: 2, targetsPerGroup: 1...2, fixedNetwork: 1,
                                      repairWithRivets: true, valves: 1, decoyFill: 85, decoyShapes: decoys,
                                      waypoints: 0...1, taps: 12...18, minNetwork: 15, limits: limits)
        case .saturday:
            tier = .crossings
            config = DistillGenConfig(width: 7, height: 7, groups: 2, targetsPerGroup: 1...2, crosses: 1...2, fixedDecoys: 1,
                                      decoyFill: 90, decoyShapes: decoys, waypoints: 0...1, noise: 4, taps: 15...22, minNetwork: 20,
                                      limits: limits)
        case .sunday:
            tier = .grand
            config = DistillGenConfig(width: 7, height: 7, groups: 2, targetsPerGroup: 1...2, crosses: 0...2, fixedNetwork: 1,
                                      fixedDecoys: 1, repairWithRivets: true, valves: 1, coils: 1, decoyFill: 90,
                                      decoyShapes: decoys, waypoints: 0...1, noise: 4, taps: 18...28, minNetwork: 22, limits: limits)
        }
        let target = [Weekday.monday: 14, .tuesday: 22, .wednesday: 28, .thursday: 34, .friday: 38, .saturday: 52,
                      .sunday: 62][weekday]!
        return DistillDailySpec(weekday: weekday, tier: tier, config: config, targetScore: target)
    }

    /// FNV-1a of "distill-daily-v1|YYYY-MM-DD", mixed once.
    public static func baseSeed(for date: DailyDate) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(algorithmVersion)|\(date.isoString)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        var mixer = SplitMix64(seed: hash)
        return mixer.next()
    }

    /// Levels built per day; the one whose score is closest to the weekday's target is the daily.
    public static let candidates = 4

    /// The day's level: `candidates` levels from consecutive seeds after the date's seed, closest score to the
    /// weekday's target (first wins a tie). If the weekday's generator gives up on all of them (not seen in testing),
    /// the Monday settings are used with more attempts, so a level always exists.
    public static func level(for date: DailyDate) -> DistillLevel {
        let spec = spec(for: date)
        let seed = baseSeed(for: date)
        let id = levelID(for: date)
        var best: DistillLevel?
        for k in 0..<candidates {
            guard let l = DistillGenerator.generate(spec.config, seed: seed &+ UInt64(k), id: id, title: spec.label) else { continue }
            if best == nil || abs(l.stats!.score - spec.targetScore) < abs(best!.stats!.score - spec.targetScore) { best = l }
        }
        if let best { return best }
        return fallbackLevel(seed: seed, id: id, title: spec.label)
    }

    /// The level used when every weekday candidate fails: Monday's settings with more attempts (tested over
    /// many seeds in `GeneratorTests`).
    static func fallbackLevel(seed: UInt64, id: String, title: String) -> DistillLevel {
        var fallback = Self.spec(for: .monday).config
        fallback.maxAttempts = 500
        return DistillGenerator.generate(fallback, seed: seed, id: id, title: title)!
    }

    /// A Daily Distillery win as a `DailyResult`, so `DailyStreaks` gives its own streak and stats (kept in a
    /// separate store by the app). "Perfect" = the minimum taps without a hint.
    public static func result(date: DailyDate, taps: Int, minTaps: Int, usedHint: Bool, solvedAt: Date) -> DailyResult {
        DailyResult(date: date, moves: taps, minMoves: minTaps, usedHint: usedHint, solvedAt: solvedAt)
    }

    /// Stable fingerprint of a level's board (FNV-1a over the level-file rows, sources, targets, valves, coils
    /// and minTaps), for golden tests.
    public static func fingerprint(_ level: DistillLevel) -> UInt64 {
        var text = level.gridRows.joined(separator: "/")
        for s in level.board.sources { text += "|s\(s.pos.r),\(s.pos.c),\(s.color.rawValue),\(s.outlet.letter)" }
        for t in level.board.targets { text += "|t\(t.pos.r),\(t.pos.c),\(t.color.rawValue),\(t.inlet.letter)" }
        for i in 0..<level.board.cellCount {
            let p = level.board.pieces[i]
            if let v = p.valve { text += "|v\(i),\(v)" }
            if let c = p.coil { text += "|c\(i),\(c.from.rawValue),\(c.to.rawValue)" }
        }
        text += "|m\(level.minTaps)"
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}
