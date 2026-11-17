import Foundation

// MARK: - Hit testing

/// A downsampled alpha mask of one object PNG: a cell is opaque if any pixel in its `step × step` block has
/// alpha above `threshold` (60, as on the review pages). Built once per object when the scene loads.
public struct HiddenAlphaMask: Sendable, Hashable {
    public static let defaultStep = 2
    public static let defaultThreshold: UInt8 = 60

    public let pixelWidth: Int
    public let pixelHeight: Int
    public let step: Int
    public let columns: Int
    public let rows: Int
    private let cells: [Bool]

    /// `alpha`: one byte per pixel, row-major, `width × height` (the PNG's alpha channel).
    public init(alpha: [UInt8], width: Int, height: Int, step: Int = defaultStep, threshold: UInt8 = defaultThreshold) {
        precondition(width > 0 && height > 0 && step > 0 && alpha.count >= width * height)
        pixelWidth = width
        pixelHeight = height
        self.step = step
        columns = (width + step - 1) / step
        rows = (height + step - 1) / step
        var c = [Bool](repeating: false, count: columns * rows)
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > threshold {
                c[(y / step) * columns + x / step] = true
            }
        }
        cells = c
    }

    public func isOpaque(column: Int, row: Int) -> Bool {
        column >= 0 && row >= 0 && column < columns && row < rows && cells[row * columns + column]
    }

    /// Share of opaque cells (for tests and tuning).
    public var coverage: Double { Double(cells.filter { $0 }.count) / Double(cells.count) }
}

public enum HiddenHit: Sendable, Hashable {
    case target(String)
    case decoy(String)
    case nothing
}

/// Finds what a tap at a background point touches. Exact hits on an object's alpha win, topmost first (a decoy hit
/// exactly is a decoy); otherwise the nearest unfound target whose opaque pixels lie within `slop` background pixels.
public struct HiddenHitTester: Sendable {
    let placements: [HiddenPlacement]   // back to front
    let masks: [String: HiddenAlphaMask]

    /// `masks` by object id (the natural-size PNGs the placements were sized from).
    public init(layout: HiddenRoundLayout, masks: [String: HiddenAlphaMask]) {
        placements = layout.drawOrder
        self.masks = masks
    }

    public func hit(at p: HiddenPoint, slop: Double, found: Set<String> = []) -> HiddenHit {
        let live = placements.filter { !($0.role == .target && found.contains($0.objectID)) }
        for pl in live.reversed() where distance(p, pl, limit: 0) != nil {
            return pl.role == .target ? .target(pl.objectID) : .decoy(pl.objectID)
        }
        var best: (id: String, d: Double)?
        for pl in live where pl.role == .target {
            if let d = distance(p, pl, limit: slop), d < (best?.d ?? .infinity) { best = (pl.objectID, d) }
        }
        return best.map { .target($0.id) } ?? .nothing
    }

    /// Distance (background px) from `p` to the nearest opaque cell centre of the placed object, if within `limit`;
    /// `limit` 0 = the cell under `p` itself.
    func distance(_ p: HiddenPoint, _ pl: HiddenPlacement, limit: Double) -> Double? {
        guard let m = masks[pl.objectID], pl.width > 0, pl.height > 0 else { return nil }
        let sx = Double(m.pixelWidth) / Double(pl.width), sy = Double(m.pixelHeight) / Double(pl.height)
        func local(_ q: HiddenPoint) -> (Double, Double) {
            var u = (q.x - Double(pl.x)) * sx
            if pl.flipped { u = Double(m.pixelWidth) - u }
            return (u, (q.y - Double(pl.y)) * sy)
        }
        if limit <= 0 {
            let (u, v) = local(p)
            guard u >= 0, v >= 0, u < Double(m.pixelWidth), v < Double(m.pixelHeight) else { return nil }
            return m.isOpaque(column: Int(u) / m.step, row: Int(v) / m.step) ? 0 : nil
        }
        let box = pl.rect
        guard p.x >= Double(box.x) - limit, p.x <= Double(box.maxX) + limit,
              p.y >= Double(box.y) - limit, p.y <= Double(box.maxY) + limit else { return nil }
        let (u0, v0) = local(HiddenPoint(x: p.x - limit, y: p.y - limit))
        let (u1, v1) = local(HiddenPoint(x: p.x + limit, y: p.y + limit))
        let c0 = max(0, Int((min(u0, u1) / Double(m.step)).rounded(.down)))
        let c1 = min(m.columns - 1, Int((max(u0, u1) / Double(m.step)).rounded(.down)))
        let r0 = max(0, Int((min(v0, v1) / Double(m.step)).rounded(.down)))
        let r1 = min(m.rows - 1, Int((max(v0, v1) / Double(m.step)).rounded(.down)))
        guard c0 <= c1, r0 <= r1 else { return nil }
        var best: Double?
        for r in r0...r1 {
            for c in c0...c1 where m.isOpaque(column: c, row: r) {
                // cell centre back in background pixels
                var u = (Double(c) + 0.5) * Double(m.step)
                if pl.flipped { u = Double(m.pixelWidth) - u }
                let bx = Double(pl.x) + u / sx, by = Double(pl.y) + (Double(r) + 0.5) * Double(m.step) / sy
                let d = ((bx - p.x) * (bx - p.x) + (by - p.y) * (by - p.y)).squareRoot()
                if d <= limit, d < (best ?? .infinity) { best = d }
            }
        }
        return best
    }
}

public enum HiddenTouch {
    /// Touch radius in screen points that counts as touching an object.
    public static let touchRadiusPoints = 22.0
    /// Slop in background pixels for the current zoom: the touch radius converted, at least 6 px (the review
    /// page's), at most 48 px so a zoomed-out tap doesn't reach across the shelf.
    public static func slop(pointsPerBackgroundPixel: Double, touchRadiusPoints: Double = touchRadiusPoints) -> Double {
        guard pointsPerBackgroundPixel > 0 else { return 6 }
        return min(48, max(6, touchRadiusPoints / pointsPerBackgroundPixel))
    }
}

// MARK: - Round state

public enum HiddenTapOutcome: Sendable, Hashable {
    /// A new find; `remaining` after it.
    case found(String, remaining: Int)
    /// A decoy, an empty spot or a tap after the round is over: shake / puff, counted while playing.
    case wrong(decoy: String?)
}

/// Stars for a finished round: calm, no timer.
public enum HiddenStars {
    /// 3 stars: no hint and at most this many wrong taps.
    public static let perfectWrongTaps = 3
    /// 2 stars: at most this many hints and wrong taps; else 1 star.
    public static let goodHints = 2
    public static let goodWrongTaps = 10

    public static func stars(hints: Int, wrongTaps: Int) -> Int {
        if hints == 0, wrongTaps <= perfectWrongTaps { return 3 }
        if hints <= goodHints, wrongTaps <= goodWrongTaps { return 2 }
        return 1
    }
}

/// The lantern hint: a glow circling the area of one remaining object, recharging after a cooldown.
public struct HiddenHintGlow: Sendable, Hashable {
    public static let cooldown = 30.0
    public let objectID: String
    /// Centre and radius in background pixels; the object lies inside but not at the centre.
    public let center: HiddenPoint
    public let radius: Double

    /// Deterministic for (round seed, hint number): the centre is moved off the object by up to 35 % of the radius.
    public static func glow(for p: HiddenPlacement, seed: UInt64, hintNumber: Int) -> HiddenHintGlow {
        let radius = Double(max(p.width, p.height)) * 1.5 + 40
        var rng = PythonRandom(seed: seed ^ (0x4C41_4E54_0000_0000 | UInt64(truncatingIfNeeded: hintNumber)))
        let angle = rng.random() * 2 * Double.pi
        let off = radius * 0.35 * (0.5 + 0.5 * rng.random())
        return HiddenHintGlow(objectID: p.objectID,
                              center: HiddenPoint(x: p.center.x + cos(angle) * off, y: p.center.y + sin(angle) * off),
                              radius: radius)
    }
}

/// One round in play. Times are seconds on the app's clock (only the hint cooldown reads them).
public struct HiddenRoundState: Sendable, Hashable, Codable {
    public let scene: HiddenSceneID
    public let round: Int
    public let seed: UInt64
    /// Find list (object ids) in list order.
    public let targets: [String]
    public private(set) var found: [String] = []
    public private(set) var wrongTaps = 0
    public private(set) var hintsUsed = 0
    public private(set) var lastHintAt: Double?

    public init(layout: HiddenRoundLayout) {
        scene = layout.scene
        round = layout.round
        seed = layout.seed
        targets = layout.targets.map(\.objectID)
    }

    public var foundSet: Set<String> { Set(found) }
    public var remaining: [String] { targets.filter { !found.contains($0) } }
    public var isComplete: Bool { found.count == targets.count }
    public var stars: Int { HiddenStars.stars(hints: hintsUsed, wrongTaps: wrongTaps) }

    @discardableResult
    public mutating func tap(_ hit: HiddenHit) -> HiddenTapOutcome {
        switch hit {
        case .target(let id) where targets.contains(id) && !found.contains(id) && !isComplete:
            found.append(id)
            return .found(id, remaining: targets.count - found.count)
        case .decoy(let id):
            if !isComplete { wrongTaps += 1 }
            return .wrong(decoy: id)
        default:
            if !isComplete { wrongTaps += 1 }
            return .wrong(decoy: nil)
        }
    }

    /// Seconds until the lantern is ready (0 = ready).
    public func hintCooldownRemaining(now: Double) -> Double {
        guard let last = lastHintAt else { return 0 }
        return max(0, HiddenHintGlow.cooldown - (now - last))
    }

    /// Lights the lantern over the first remaining object in list order (counts as a hint); nil while it recharges
    /// or when everything is found.
    public mutating func useHint(now: Double, layout: HiddenRoundLayout) -> HiddenHintGlow? {
        guard !isComplete, hintCooldownRemaining(now: now) == 0, let id = remaining.first,
              let p = layout.placement(id) else { return nil }
        hintsUsed += 1
        lastHintAt = now
        return HiddenHintGlow.glow(for: p, seed: seed, hintNumber: hintsUsed)
    }

    /// Accessibility "reveal next": finds the first remaining object at once; counts as a hint, no cooldown.
    public mutating func revealNext() -> String? {
        guard let id = remaining.first else { return nil }
        hintsUsed += 1
        found.append(id)
        return id
    }
}

// MARK: - Progression

public enum HiddenProgression {
    public static let rounds = HiddenCurve.rounds

    /// The sorting chapter whose unlock opens a room: attic 2, market 5, hoard 8.
    public static func openingChapter(_ scene: HiddenSceneID) -> Int {
        switch scene {
        case .attic: 2
        case .market: 5
        case .hoard: 8
        }
    }

    /// - `chapterUnlocked`: open flags for chapters 1…10 (index 0 = chapter 1, `ChapterGate.unlockedChapters`).
    ///   Rooms only read sorting progress; their stars never feed sorting gates.
    public static func isSceneUnlocked(_ scene: HiddenSceneID, chapterUnlocked: [Bool]) -> Bool {
        let i = openingChapter(scene) - 1
        return chapterUnlocked.indices.contains(i) && chapterUnlocked[i]
    }

    /// Rounds open in order: round 1, then round n once round n − 1 has been finished.
    public static func isRoundUnlocked(_ round: Int, in scene: HiddenSceneID, progress: HiddenProgress) -> Bool {
        guard rounds.contains(round) else { return false }
        return round == 1 || progress.bestStars(scene, round: round - 1) > 0
    }

    /// "hidden.attic": the story scene on a room's first opening (lines live in the app's catalog).
    public static func sceneID(_ scene: HiddenSceneID) -> String { "hidden.\(scene.rawValue)" }

    public static func sceneOnOpening(_ scene: HiddenSceneID, seen: Set<String>) -> String? {
        let id = sceneID(scene)
        return seen.contains(id) ? nil : id
    }
}

/// Saved per player: best stars and finished plays per round (key `attic.3`).
public struct HiddenProgress: Sendable, Hashable, Codable {
    public private(set) var best: [String: Int] = [:]
    public private(set) var plays: [String: Int] = [:]

    public init() {}

    static func key(_ s: HiddenSceneID, _ r: Int) -> String { "\(s.rawValue).\(r)" }

    public func bestStars(_ s: HiddenSceneID, round r: Int) -> Int { best[Self.key(s, r)] ?? 0 }
    /// Finished plays of a round = the layout variant its next play uses (0 the first time).
    public func finishedPlays(_ s: HiddenSceneID, round r: Int) -> Int { plays[Self.key(s, r)] ?? 0 }
    public func stars(_ s: HiddenSceneID) -> Int { HiddenProgression.rounds.reduce(0) { $0 + bestStars(s, round: $1) } }
    public func roundsFinished(_ s: HiddenSceneID) -> Int { HiddenProgression.rounds.filter { bestStars(s, round: $0) > 0 }.count }
    /// The first round not finished yet (nil when all ten are).
    public func nextRound(_ s: HiddenSceneID) -> Int? { HiddenProgression.rounds.first { bestStars(s, round: $0) == 0 } }

    /// Records a finished round (stars 1…3); returns true for a new best.
    @discardableResult
    public mutating func record(_ s: HiddenSceneID, round r: Int, stars: Int) -> Bool {
        guard HiddenProgression.rounds.contains(r) else { return false }
        let k = Self.key(s, r), st = min(3, max(1, stars))
        plays[k, default: 0] += 1
        guard st > (best[k] ?? 0) else { return false }
        best[k] = st
        return true
    }
}
