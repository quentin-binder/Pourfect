import BottleSortCore

/// A shipped distillery pack: three workshop stages on the map wing, two challenge packs (DECISIONS 276).
public enum DistillPack: String, CaseIterable, Sendable, Hashable, Codable {
    case stage1, stage2, stage3, expert, master

    /// "distillery_stage_01.json" … "distillery_master.json" (in Levels/distillery; names unique in the bundle).
    public var fileName: String {
        switch self {
        case .stage1: "distillery_stage_01.json"
        case .stage2: "distillery_stage_02.json"
        case .stage3: "distillery_stage_03.json"
        case .expert: "distillery_expert.json"
        case .master: "distillery_master.json"
        }
    }

    /// Pack id inside the file ("distillery-1" … "distillery-master").
    public var id: String {
        switch self {
        case .stage1: "distillery-1"
        case .stage2: "distillery-2"
        case .stage3: "distillery-3"
        case .expert: "distillery-expert"
        case .master: "distillery-master"
        }
    }

    /// English title; the app localizes its own.
    public var title: String {
        switch self {
        case .stage1: "The Cold Still"
        case .stage2: "Copper and Steam"
        case .stage3: "The Great Alembic"
        case .expert: "Distillery Expert"
        case .master: "Distillery Master"
        }
    }

    /// Workshop stage number (1…3), nil for the challenge packs.
    public var stage: Int? {
        switch self {
        case .stage1: 1
        case .stage2: 2
        case .stage3: 3
        default: nil
        }
    }

    public static func stage(_ n: Int) -> DistillPack? { allCases.first { $0.stage == n } }

    /// Level id: "d1-07", "dx-03" (expert), "dm-12" (master).
    public func levelID(_ index: Int) -> String {
        let n = index + 1
        let prefix: String
        switch self {
        case .stage1: prefix = "d1"
        case .stage2: prefix = "d2"
        case .stage3: prefix = "d3"
        case .expert: prefix = "dx"
        case .master: prefix = "dm"
        }
        return prefix + "-" + (n < 10 ? "0" : "") + String(n)
    }
}

/// One slot of a pack preset: the generator settings and the difficulty score the pick aims at.
public struct DistillSlot: Sendable, Hashable {
    public var config: DistillGenConfig
    public var targetScore: Int
    /// What this slot introduces (for the report and the app's tips): "rotate", "tee", "fixed", "colors",
    /// "cross", "coil", "valve", or nil.
    public var teaches: String?
}

/// The shipped presets (DECISIONS 276). Each slot generates `candidates` levels from consecutive seeds and keeps
/// the one whose score is closest to its target, so the packs rise steadily; output is deterministic.
public enum DistillContent {
    public static let levelsPerPack = 20
    public static let candidates = 12

    public static func baseSeed(_ pack: DistillPack) -> UInt64 {
        switch pack {
        case .stage1: 10_000
        case .stage2: 20_000
        case .stage3: 30_000
        case .expert: 40_000
        case .master: 50_000
        }
    }

    static func lerp(_ a: Int, _ b: Int, _ i: Int, _ n: Int) -> Int { n <= 1 ? a : a + (b - a) * i / (n - 1) }

    public static func slots(_ pack: DistillPack) -> [DistillSlot] {
        (0..<levelsPerPack).map { slot(pack, $0) }
    }

    public static func slot(_ pack: DistillPack, _ i: Int) -> DistillSlot {
        let basicDecoys: [DistillShape] = [.straight, .elbow, .elbow, .cap]
        let richDecoys: [DistillShape] = [.straight, .straight, .elbow, .elbow, .elbow, .tee, .cap]
        switch pack {
        case .stage1:
            // Rotation only: one cauldron, one flask, straights and elbows; 4×4, then 5×5.
            let small = i < 6
            var c = DistillGenConfig(width: small ? 4 : 5, height: small ? 4 : 5,
                                     decoyFill: lerp(35, 85, i, 20), decoyShapes: basicDecoys,
                                     waypoints: i < 3 ? 0...0 : (i < 12 ? 0...1 : 1...2), noise: 2 + i / 5,
                                     taps: i == 0 ? 2...3 : lerp(3, 10, i, 20)...lerp(5, 14, i, 20))
            c.minNetwork = small ? lerp(3, 7, i, 6) : lerp(8, 13, i - 6, 14)
            if i >= 16 { c.fixedDecoys = 1 }
            return DistillSlot(config: c, targetScore: lerp(5, 22, i, 20), teaches: i == 0 ? "rotate" : nil)
        case .stage2:
            // Tees, riveted pieces, two colors, crossings; 5×5 → 6×6.
            var c = DistillGenConfig(width: i < 8 ? 5 : 6, height: i < 8 ? 5 : 6, decoyFill: lerp(60, 90, i, 20),
                                     decoyShapes: richDecoys, waypoints: 0...1, noise: 3,
                                     taps: lerp(5, 14, i, 20)...lerp(9, 22, i, 20))
            switch i {
            case 0..<4:
                c.targetsPerGroup = 2...2
            case 4..<8:
                c.targetsPerGroup = 2...2
                c.fixedNetwork = 2
                c.fixedDecoys = 2
            case 8..<12:
                c.groups = 2
                c.fixedNetwork = i % 2
            case 12..<16:
                c.groups = 2
                c.crosses = 1...2
                c.fixedDecoys = 1
            default:
                c.groups = 2
                c.targetsPerGroup = 1...2
                c.crosses = 0...2
                c.fixedNetwork = 1 + i % 2
                c.fixedDecoys = 1
                c.capStubs = i % 2
            }
            c.minNetwork = i < 8 ? lerp(9, 13, i, 8) : lerp(14, 20, i - 8, 12)
            c.repairWithRivets = c.fixedNetwork > 0
            let teaches: String? = [0: "tee", 4: "fixed", 8: "colors", 12: "cross"][i]
            return DistillSlot(config: c, targetScore: lerp(14, 40, i, 20), teaches: teaches)
        case .stage3:
            // Heat coils, valves, then everything on 7×7.
            var c = DistillGenConfig(width: i < 8 ? 6 : 7, height: i < 8 ? 6 : 7, decoyFill: lerp(70, 92, i, 20),
                                     decoyShapes: richDecoys, waypoints: 0...1, noise: 3,
                                     taps: lerp(8, 20, i, 20)...lerp(14, 32, i, 20))
            switch i {
            case 0..<4:
                c.targetsPerGroup = 1...2
                c.coils = 1
            case 4..<8:
                c.targetsPerGroup = 2...2
                c.valves = 1
            case 8..<12:
                c.groups = 2
                c.coils = 1
                c.valves = i % 2
                c.fixedDecoys = 1
            case 12..<16:
                c.groups = 2
                c.targetsPerGroup = 1...2
                c.coils = 1
                c.valves = 1
                c.crosses = 0...1
                c.fixedNetwork = 1
            default:
                c.groups = i < 18 ? 2 : 3
                c.targetsPerGroup = i < 18 ? 1...2 : 1...1
                c.coils = 1 + i % 2
                c.valves = 1
                c.crosses = 0...2
                c.fixedNetwork = 1
                c.fixedDecoys = 1
            }
            c.minNetwork = i < 8 ? lerp(13, 17, i, 8) : lerp(20, 26, i - 8, 12)
            c.repairWithRivets = c.fixedNetwork > 0
            let teaches: String? = [0: "coil", 4: "valve"][i]
            return DistillSlot(config: c, targetScore: lerp(24, 60, i, 20), teaches: teaches)
        case .expert:
            var c = DistillGenConfig(width: i < 10 ? 6 : 7, height: i < 10 ? 6 : 7, groups: 2, targetsPerGroup: 1...2,
                                     crosses: 0...2, fixedNetwork: 1, fixedDecoys: 1, repairWithRivets: true,
                                     valves: i % 3 == 1 ? 1 : 0, coils: i % 3 == 2 ? 1 : 0, capStubs: i % 4 == 0 ? 1 : 0,
                                     decoyFill: 90, decoyShapes: richDecoys, waypoints: 0...1, noise: 4,
                                     taps: lerp(16, 22, i, 20)...lerp(26, 34, i, 20))
            c.minNetwork = i < 10 ? 17 : 22
            if i >= 15 { c.groups = 3; c.targetsPerGroup = 1...1 }
            return DistillSlot(config: c, targetScore: lerp(40, 70, i, 20), teaches: nil)
        case .master:
            var c = DistillGenConfig(width: 7, height: 7, groups: i < 10 ? 2 : 3, targetsPerGroup: i < 10 ? 2...2 : 1...2,
                                     crosses: 0...2, fixedNetwork: 1, fixedDecoys: 2, repairWithRivets: true,
                                     valves: 1, coils: 1 + i % 2, capStubs: i % 3 == 0 ? 1 : 0,
                                     decoyFill: 95, decoyShapes: richDecoys + [.tee], waypoints: 0...1, noise: 4,
                                     taps: lerp(24, 28, i, 20)...lerp(34, 40, i, 20))
            c.maxAttempts = 120
            c.minNetwork = lerp(24, 28, i, 20)
            return DistillSlot(config: c, targetScore: lerp(60, 90, i, 20), teaches: nil)
        }
    }

    /// Generates one slot: `candidates` levels from consecutive seeds, keeping the closest to the target score.
    public static func level(_ pack: DistillPack, index i: Int) -> DistillLevel? {
        let slot = slot(pack, i)
        var best: DistillLevel?
        for k in 0..<candidates {
            let seed = baseSeed(pack) &+ UInt64(i * 100 + k)
            guard let l = DistillGenerator.generate(slot.config, seed: seed, id: pack.levelID(i)) else { continue }
            if best == nil || abs(l.stats!.score - slot.targetScore) < abs(best!.stats!.score - slot.targetScore) { best = l }
        }
        return best
    }

    /// The whole pack file (nil if a slot fails).
    public static func pack(_ pack: DistillPack) -> DistillPackFile? {
        var levels: [DistillLevel] = []
        for i in 0..<levelsPerPack {
            guard let l = level(pack, index: i) else { return nil }
            levels.append(l)
        }
        return DistillPackFile(id: pack.id, title: pack.title, levels: levels)
    }
}

/// Where the distillery sits in the game (DECISIONS 277). Optional: it never blocks a sorting chapter, and its
/// stars never count towards a chapter gate (the app keeps them in their own store, keyed by the `d…` level ids).
public enum DistillProgression {
    public static let stages = 1...3

    /// The sorting chapter whose unlock opens stage `n`: 3, 6, 9.
    public static func openingChapter(stage n: Int) -> Int { 3 * n }

    /// - `chapterUnlocked`: open flags for chapters 1…10 (index 0 = chapter 1, `ChapterGate.unlockedChapters`).
    public static func isStageUnlocked(_ n: Int, chapterUnlocked: [Bool]) -> Bool {
        guard stages.contains(n) else { return false }
        let i = openingChapter(stage: n) - 1
        return chapterUnlocked.indices.contains(i) && chapterUnlocked[i]
    }

    /// Levels inside a stage open in order: level 0 is open, level i once level i − 1 is won.
    public static func isLevelUnlocked(_ index: Int, won: [Bool]) -> Bool {
        index == 0 || (index > 0 && index - 1 < won.count && won[index - 1])
    }

    /// "distillery.2": the story scene on a stage's first opening (the lines live in the app's catalog).
    public static func sceneID(stage n: Int) -> String { "distillery.\(n)" }

    public static func sceneOnOpening(stage n: Int, seen: Set<String>) -> String? {
        guard stages.contains(n) else { return nil }
        let id = sceneID(stage: n)
        return seen.contains(id) ? nil : id
    }
}

/// Random Distillery tiers (Challenges hub), seeded like Random Brew.
public enum DistillRandomTier: String, CaseIterable, Sendable, Hashable, Codable {
    case gentle, tricky, fiendish

    public var name: String {
        switch self {
        case .gentle: "Gentle"
        case .tricky: "Tricky"
        case .fiendish: "Fiendish"
        }
    }

    public var config: DistillGenConfig {
        let decoys: [DistillShape] = [.straight, .straight, .elbow, .elbow, .elbow, .tee, .cap]
        switch self {
        case .gentle:
            return DistillGenConfig(width: 5, height: 5, decoyFill: 75, decoyShapes: [.straight, .elbow, .elbow, .cap],
                                    waypoints: 0...1, taps: 5...10, minNetwork: 8)
        case .tricky:
            return DistillGenConfig(width: 6, height: 6, groups: 2, targetsPerGroup: 1...2, crosses: 0...1, fixedDecoys: 1,
                                    capStubs: 0, decoyFill: 85, decoyShapes: decoys, waypoints: 0...1, taps: 10...18, minNetwork: 14)
        case .fiendish:
            return DistillGenConfig(width: 7, height: 7, groups: 2, targetsPerGroup: 1...2, crosses: 0...2, fixedNetwork: 1,
                                    fixedDecoys: 1, repairWithRivets: true, valves: 1, coils: 1, decoyFill: 92,
                                    decoyShapes: decoys, waypoints: 0...1, noise: 4, taps: 18...30, minNetwork: 20,
                                    maxAttempts: 120)
        }
    }
}

public enum DistillRandom {
    /// A random level for a tier and seed (same seed, same level). Falls back to the gentle tier if the tier's
    /// generator gives up (practically never).
    public static func level(tier: DistillRandomTier, seed: UInt64) -> DistillLevel {
        let id = "distill-random-\(tier.rawValue)-\(seed)"
        if let l = DistillGenerator.generate(tier.config, seed: seed, id: id) { return l }
        var config = DistillRandomTier.gentle.config
        config.maxAttempts = 400
        return DistillGenerator.generate(config, seed: seed, id: id)!
    }
}
