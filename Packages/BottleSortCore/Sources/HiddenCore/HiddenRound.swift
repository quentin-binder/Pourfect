import Foundation

/// What a round asks for. See `HiddenCurve.spec`.
public struct HiddenRoundSpec: Sendable, Hashable, Codable {
    public let round: Int
    /// Objects on the find list.
    public let targets: Int
    /// Non-findable library objects drawn the same way (tapping one is a wrong tap).
    public let decoys: Int
    /// Random size factor range (layout.py: 0.88…1.0); later rounds draw objects smaller.
    public let scaleLow: Double
    public let scaleHigh: Double
    /// Targets only on spots with `difficulty` up to this (decoys use any spot).
    public let maxSpotDifficulty: Int
    /// At most this many medium (larger) targets.
    public let maxMediumTargets: Int
    /// This many targets go to hard spots (difficulty ≥ 2: containers) when one is free.
    public let hardSpotTargets: Int
    /// Gold-coloured targets (dragon's hoard only; 0 = none of them on the find list).
    public let goldTargets: Int

    public var scale: ClosedRange<Double> { scaleLow...scaleHigh }
}

/// The ten rounds of every room: more objects to find, more decoys, smaller objects, harder spots; in the dragon's
/// hoard gold objects (gold on gold coins) join the find list from round 6.
public enum HiddenCurve {
    public static let rounds = 1...10
    /// Upper bounds the scenes must support (validated on load).
    public static let maxTargets = 15
    public static let maxDecoys = 20

    //                         round:  1     2     3     4     5     6     7     8     9     10
    static let targetCounts =        [8,    9,    10,   10,   11,   12,   12,   13,   14,   15]
    static let decoyCounts =         [8,    10,   11,   12,   14,   15,   16,   18,   19,   20]
    static let scaleLows =           [0.88, 0.88, 0.86, 0.85, 0.84, 0.82, 0.80, 0.79, 0.78, 0.76]
    static let scaleHighs =          [1.0,  1.0,  0.98, 0.97, 0.96, 0.94, 0.92, 0.91, 0.90, 0.88]
    static let maxDifficulty =       [1,    1,    2,    2,    3,    3,    4,    4,    4,    4]
    static let maxMedium =           [5,    5,    5,    4,    4,    4,    3,    3,    2,    2]
    static let hardTargets =         [0,    0,    0,    1,    1,    1,    2,    2,    3,    3]
    static let hoardGold =           [0,    0,    0,    0,    0,    1,    1,    2,    2,    3]

    public static func spec(_ scene: HiddenSceneID, round: Int) -> HiddenRoundSpec {
        let r = min(max(round, rounds.lowerBound), rounds.upperBound)
        let i = r - 1
        return HiddenRoundSpec(round: r, targets: targetCounts[i], decoys: decoyCounts[i],
                               scaleLow: scaleLows[i], scaleHigh: scaleHighs[i],
                               maxSpotDifficulty: maxDifficulty[i], maxMediumTargets: maxMedium[i],
                               hardSpotTargets: hardTargets[i], goldTargets: scene == .hoard ? hoardGold[i] : 0)
    }

    /// "Gold-ish" objects: at least 35 % of their opaque pixels gold-hued (hue 25–60°, saturation > 0.35,
    /// value > 0.45; measured on the exported PNGs, see DECISIONS). Only the hoard has them.
    public static func goldish(_ scene: HiddenSceneID) -> Set<String> {
        guard scene == .hoard else { return [] }
        return ["goblet", "crown", "amulet", "round_shield", "gold_plate", "scepter", "royal_orb", "gold_bar", "harp",
                "bracelet", "golden_mask", "golden_apple", "phoenix_feather", "golden_key", "medallion", "golden_bird"]
    }
}

/// A round: what to draw (back to front) and what to find. Players get the fixed ones from `rounds.json`
/// (`HiddenFixedLayouts`); the generator only proposes them.
public struct HiddenRoundLayout: Sendable, Hashable, Codable {
    public let scene: HiddenSceneID
    public let round: Int
    public let variant: Int
    public let seed: UInt64
    /// The find list, in list order.
    public let targets: [HiddenPlacement]
    public let decoys: [HiddenPlacement]

    /// Targets and decoys back to front (by spot y, ties in placing order), like layout.py.
    public var drawOrder: [HiddenPlacement] {
        stableSorted(placedOrder) { $0.anchorY < $1.anchorY }
    }

    /// Targets then decoys, in the order they were placed.
    let placedOrder: [HiddenPlacement]

    public func placement(_ objectID: String) -> HiddenPlacement? { placedOrder.first { $0.objectID == objectID } }

    /// Stable text fingerprint for golden tests.
    public var fingerprint: String {
        drawOrder.map { p in
            "\(p.role == .target ? "T" : "d"):\(p.objectID)@\(p.spotID):\(p.width)x\(p.height)\(p.flipped ? "f" : ""):\(Int((p.tint * 1000).rounded()))"
        }.joined(separator: " ")
    }
}

public enum HiddenGenerator {
    public static let seedVersion = "hidden-v1"
    /// Decoys keep this far (background px) from every target's box, shadow side included.
    public static let decoyMargin = 4

    /// Seed for (room, round, variant): FNV-1a 64 of `hidden-v1|attic|3|0`, then the SplitMix64 finalizer.
    /// Variant 0 is the seed of a round's proposal and of its fixed layout (the lantern's offsets); other variants
    /// only make further proposals (`hiddengen`, DEBUG `-LPHiddenSeed`). Players never get generated rounds.
    public static func seed(_ scene: HiddenSceneID, round: Int, variant: Int) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in "\(seedVersion)|\(scene.rawValue)|\(round)|\(variant)".utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        var z = h &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public static func round(_ scene: HiddenScene, round: Int, variant: Int = 0) -> HiddenRoundLayout {
        let spec = HiddenCurve.spec(scene.id, round: round)
        return layout(scene, spec: spec, seed: seed(scene.id, round: spec.round, variant: variant), variant: variant)
    }

    /// An object's box together with its contact shadow's core (the box moved by the shadow offset).
    static func footprint(_ r: HiddenRect) -> HiddenRect {
        HiddenRect(x: r.x, y: r.y, width: r.width + HiddenBlend.shadowOffset.x, height: r.height + HiddenBlend.shadowOffset.y)
    }

    /// The round generator (deterministic for a seed; Python-compatible random stream):
    /// 1. a random order of the whole library; targets are taken from it: first `goldTargets` gold-ish objects, then
    ///    non-gold ones, at most `maxMediumTargets` medium;
    /// 2. targets are placed medium first on the shuffled spots, each on the first free spot that takes its size
    ///    class, keeps layout.py's spacing to everything placed, and is not harder than `maxSpotDifficulty`; the first
    ///    `hardSpotTargets` that fit a hard spot (difficulty ≥ 2) go there; a target with no spot is dropped and the
    ///    next object in the order takes its place;
    /// 3. size factor, flip and tint are drawn when an object is placed (layout.py's formulas);
    /// 4. decoys: the rest of the library in the same order (never a target's id or name), medium first, on the
    ///    remaining spots with the same spacing, any difficulty, each on the first spot where its drawn box (shadow
    ///    included) stays `decoyMargin` px clear of every target's, so a decoy never covers a target or hides under one
    ///    (sizes drawn for a turned-down spot are discarded). Up to `spec.decoys`: a room with few spots for what is
    ///    left of its library gets fewer (the market's small-only shelves in rounds 8–10).
    public static func layout(_ scene: HiddenScene, spec: HiddenRoundSpec, seed: UInt64, variant: Int = 0) -> HiddenRoundLayout {
        var rng = PythonRandom(seed: seed)
        let gold = HiddenCurve.goldish(scene.id)
        let order = rng.sample(scene.objects, scene.objects.count)
        var free = scene.spots.filter { !$0.unusable }
        rng.shuffle(&free)

        // 1. candidates for the find list: the library order, gold-ish ones first so the round gets its gold targets
        var queue = order.filter { gold.contains($0.id) } + order.filter { !gold.contains($0.id) }

        var targets: [HiddenPlacement] = []
        var usedSpots: [HiddenSpot] = []
        var mediumCount = 0, goldCount = 0, hardCount = 0

        // 2. pick and place targets: medium ones first among the next picks, like layout.py
        while targets.count < spec.targets, !queue.isEmpty {
            let need = spec.targets - targets.count
            var batch: [HiddenObject] = []
            var mediumInBatch = 0, goldInBatch = 0
            while batch.count < need, !queue.isEmpty {
                let o = queue.removeFirst()
                let isGold = gold.contains(o.id)
                if isGold, goldCount + goldInBatch >= spec.goldTargets { continue }
                if !isGold, (targets.count - goldCount) + (batch.count - goldInBatch) >= spec.targets - spec.goldTargets { continue }
                if o.sizeClass == .medium, mediumCount + mediumInBatch >= spec.maxMediumTargets { continue }
                if o.sizeClass == .medium { mediumInBatch += 1 }
                if isGold { goldInBatch += 1 }
                batch.append(o)
            }
            for o in stableSorted(batch, by: { $0.sizeClass == .medium && $1.sizeClass != .medium }) {
                let fits: (HiddenSpot) -> Bool = { s in
                    s.accepts(o.sizeClass) && HiddenRules.isSpaced(s, from: usedSpots)
                }
                var index: Int?
                if hardCount < spec.hardSpotTargets {
                    index = free.firstIndex { $0.difficulty >= 2 && fits($0) }
                    if index != nil { hardCount += 1 }
                }
                if index == nil { index = free.firstIndex { $0.difficulty <= spec.maxSpotDifficulty && fits($0) } }
                guard let i = index else { continue }
                let s = free.remove(at: i)
                usedSpots.append(s)
                if o.sizeClass == .medium { mediumCount += 1 }
                if gold.contains(o.id) { goldCount += 1 }
                targets.append(HiddenRules.place(o, at: s, role: .target, scale: spec.scale, rng: &rng))
            }
        }

        // 4. decoys
        let targetIDs = Set(targets.map(\.objectID))
        let targetNames = Set(targets.compactMap { scene.object($0.objectID)?.name.lowercased() })
        let decoyPool = stableSorted(order.filter { !targetIDs.contains($0.id) && !targetNames.contains($0.name.lowercased()) },
                                     by: { $0.sizeClass == .medium && $1.sizeClass != .medium })
        let guarded = targets.map { footprint($0.rect).insetBy(-decoyMargin) }
        var decoys: [HiddenPlacement] = []
        for o in decoyPool where decoys.count < spec.decoys {
            for (i, s) in free.enumerated() where s.accepts(o.sizeClass) && HiddenRules.isSpaced(s, from: usedSpots) {
                var trial = rng   // the sizes drawn for a spot that is turned down are not used
                let p = HiddenRules.place(o, at: s, role: .decoy, scale: spec.scale, rng: &trial)
                let box = footprint(p.rect)
                if guarded.contains(where: { $0.intersects(box) }) { continue }
                rng = trial
                usedSpots.append(free.remove(at: i))
                decoys.append(p)
                break
            }
        }
        return HiddenRoundLayout(scene: scene.id, round: spec.round, variant: variant, seed: seed,
                                 targets: targets, decoys: decoys, placedOrder: targets + decoys)
    }
}
