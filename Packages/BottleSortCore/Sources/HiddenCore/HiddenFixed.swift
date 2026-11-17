import Foundation

/// Turning an object picture for a fixed layout: the canvas it needs and its alpha turned the same way.
/// Degrees are clockwise on screen (y down), about the picture's centre; the canvas is the rotated box rounded up.
public enum HiddenRotation {
    public static func canvasSize(width w: Int, height h: Int, degrees: Double) -> (width: Int, height: Int) {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return (w, h) }
        let a = degrees * .pi / 180
        let c = abs(cos(a)), s = abs(sin(a))
        let rw = Double(w) * c + Double(h) * s, rh = Double(w) * s + Double(h) * c
        return (max(1, Int((rw - 1e-6).rounded(.up))), max(1, Int((rh - 1e-6).rounded(.up))))
    }

    /// Source pixel position (in the unturned picture) of canvas pixel centre (cx, cy).
    public static func source(x cx: Double, y cy: Double, width w: Int, height h: Int, canvas: (width: Int, height: Int),
                              degrees: Double) -> (x: Double, y: Double) {
        let a = degrees * .pi / 180
        let px = cx - Double(canvas.width) / 2, py = cy - Double(canvas.height) / 2
        // inverse of a clockwise turn (y down): x = x' cos + y' sin, y = −x' sin + y' cos
        let sx = px * cos(a) + py * sin(a), sy = -px * sin(a) + py * cos(a)
        return (sx + Double(w) / 2, sy + Double(h) / 2)
    }

    /// The alpha channel turned onto its canvas (nearest pixel), for hit masks.
    public static func rotateAlpha(_ alpha: [UInt8], width w: Int, height h: Int, degrees: Double)
        -> (alpha: [UInt8], width: Int, height: Int) {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return (alpha, w, h) }
        let canvas = canvasSize(width: w, height: h, degrees: degrees)
        var out = [UInt8](repeating: 0, count: canvas.width * canvas.height)
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let s = source(x: Double(x) + 0.5, y: Double(y) + 0.5, width: w, height: h, canvas: canvas, degrees: degrees)
                let ix = Int(s.x.rounded(.down)), iy = Int(s.y.rounded(.down))
                if ix >= 0, iy >= 0, ix < w, iy < h { out[y * canvas.width + x] = alpha[iy * w + ix] }
            }
        }
        return (out, canvas.width, canvas.height)
    }
}

/// One object of a fixed round as stored in `rounds.json`.
public struct HiddenFixedObject: Codable, Sendable, Hashable {
    public var id: String
    public var spot: String
    public var role: HiddenRole
    /// Long side of the (unturned) drawn object, background px.
    public var longSide: Int
    public var flip: Bool
    /// Tint strength toward the surroundings (the pipeline draws 0.18…0.26; the review may raise it).
    public var tint: Double
    public var dx: Int?
    public var dy: Int?
    /// Clockwise degrees.
    public var rotation: Double?

    public init(_ p: HiddenPlacement) {
        id = p.objectID
        spot = p.spotID
        role = p.role
        longSide = p.longSide
        flip = p.flipped
        tint = (p.tint * 10000).rounded() / 10000
        dx = p.dx == 0 ? nil : p.dx
        dy = p.dy == 0 ? nil : p.dy
        rotation = p.rotation == 0 ? nil : p.rotation
    }
}

public struct HiddenFixedRound: Codable, Sendable, Hashable {
    public var round: Int
    /// The review's notes on this round (what was changed and why).
    public var notes: [String]?
    /// Targets in find-list order first, then decoys.
    public var objects: [HiddenFixedObject]
}

/// `HiddenScenes/<room>/rounds.json`: the ten curated rounds of a room (R11). Every player gets exactly these;
/// they never change when the generator does (it only proposed them). DECISIONS 304.
public struct HiddenFixedFile: Codable, Sendable, Hashable {
    public static let format = "pourfect-hidden-rounds-v1"
    public var format: String
    public var scene: String
    public var rounds: [HiddenFixedRound]

    public init(scene: HiddenSceneID, rounds: [HiddenFixedRound]) {
        format = Self.format
        self.scene = scene.rawValue
        self.rounds = rounds
    }

    /// A proposal: the generator's layouts written out for review.
    public init(proposing layouts: [HiddenRoundLayout]) {
        self.init(scene: layouts.first?.scene ?? .attic, rounds: layouts.map { l in
            HiddenFixedRound(round: l.round, notes: nil, objects: (l.targets + l.decoys).map(HiddenFixedObject.init))
        })
    }
}

public enum HiddenFixedError: Error, Equatable, CustomStringConvertible {
    case badFormat(String)
    case invalid([String])
    public var description: String {
        switch self {
        case .badFormat(let f): "rounds.json: unknown format \(f)"
        case .invalid(let problems): "rounds.json: " + problems.joined(separator: "; ")
        }
    }
}

/// Loads and checks the fixed rounds of a room.
public enum HiddenFixedLayouts {
    public static let targetRange = 5...HiddenCurve.maxTargets
    public static let longSideRange = 8...220
    public static let tintRange: ClosedRange<Double> = 0...0.5
    public static let maxOffset = 80

    /// All ten rounds, in order; throws with every problem found.
    public static func load(_ data: Data, scene: HiddenScene) throws -> [HiddenRoundLayout] {
        let file = try JSONDecoder().decode(HiddenFixedFile.self, from: data)
        guard file.format == HiddenFixedFile.format else { throw HiddenFixedError.badFormat(file.format) }
        var problems: [String] = []
        if file.scene != scene.id.rawValue { problems.append("scene \(file.scene) is not \(scene.id.rawValue)") }
        let numbers = file.rounds.map(\.round)
        if numbers.sorted() != Array(HiddenCurve.rounds) { problems.append("rounds must be 1…10 once each, got \(numbers)") }
        var layouts: [HiddenRoundLayout] = []
        for r in file.rounds.sorted(by: { $0.round < $1.round }) {
            switch layout(r, scene: scene) {
            case .success(let l):
                let issues = validate(l, scene: scene)
                problems += issues.map { "round \(r.round): \($0)" }
                layouts.append(l)
            case .failure(let e):
                if case .invalid(let p) = e { problems += p.map { "round \(r.round): \($0)" } }
            }
        }
        guard problems.isEmpty else { throw HiddenFixedError.invalid(problems) }
        return layouts
    }

    /// Builds the placements of one stored round (object, spot and number checks).
    public static func layout(_ r: HiddenFixedRound, scene: HiddenScene) -> Result<HiddenRoundLayout, HiddenFixedError> {
        var problems: [String] = []
        var targets: [HiddenPlacement] = [], decoys: [HiddenPlacement] = []
        for o in r.objects {
            guard let obj = scene.object(o.id) else { problems.append("unknown object \(o.id)"); continue }
            guard let spot = scene.spot(o.spot) else { problems.append("unknown spot \(o.spot) for \(o.id)"); continue }
            if spot.unusable { problems.append("\(o.id) on unusable spot \(o.spot)") }
            if !spot.accepts(obj.sizeClass) { problems.append("spot \(o.spot) does not take \(obj.sizeClass) \(o.id)") }
            if !longSideRange.contains(o.longSide) { problems.append("\(o.id) long side \(o.longSide)") }
            if !tintRange.contains(o.tint) { problems.append("\(o.id) tint \(o.tint)") }
            if abs(o.dx ?? 0) > maxOffset || abs(o.dy ?? 0) > maxOffset { problems.append("\(o.id) offset too large") }
            if let a = o.rotation, !(-180...180).contains(a) { problems.append("\(o.id) rotation \(a)") }
            let p = HiddenPlacement(object: obj, spot: spot, role: o.role, longSide: o.longSide, flipped: o.flip, tint: o.tint,
                                    dx: o.dx ?? 0, dy: o.dy ?? 0, rotation: o.rotation ?? 0)
            if o.role == .target { targets.append(p) } else { decoys.append(p) }
        }
        guard problems.isEmpty else { return .failure(.invalid(problems)) }
        let seed = HiddenGenerator.seed(scene.id, round: r.round, variant: 0)
        return .success(HiddenRoundLayout(scene: scene.id, round: r.round, variant: 0, seed: seed,
                                          targets: targets, decoys: decoys, placedOrder: targets + decoys))
    }

    /// The rules every fixed round keeps: a fair find list, nothing covered, nothing outside the picture, and the
    /// round's place on the curve.
    public static func validate(_ l: HiddenRoundLayout, scene: HiddenScene) -> [String] {
        var problems: [String] = []
        let all = l.targets + l.decoys
        if !targetRange.contains(l.targets.count) { problems.append("\(l.targets.count) targets") }
        if l.decoys.count > HiddenCurve.maxDecoys { problems.append("\(l.decoys.count) decoys") }
        if Set(all.map(\.objectID)).count != all.count { problems.append("an object is used twice") }
        if Set(all.map(\.spotID)).count != all.count { problems.append("a spot is used twice") }
        let targetNames = Set(l.targets.compactMap { scene.object($0.objectID)?.name.lowercased() })
        for d in l.decoys where targetNames.contains(scene.object(d.objectID)?.name.lowercased() ?? "") {
            problems.append("decoy \(d.objectID) has a target's name")
        }
        for p in all where p.x < 0 || p.y < 0 || p.rect.maxX > scene.width || p.rect.maxY > scene.height {
            problems.append("\(p.objectID) outside the picture")
        }
        let guarded = l.targets.map { (id: $0.objectID, box: HiddenGenerator.footprint($0.rect).insetBy(-HiddenGenerator.decoyMargin)) }
        for d in l.decoys {
            let box = HiddenGenerator.footprint(d.rect)
            for g in guarded where g.box.intersects(box) { problems.append("decoy \(d.objectID) touches target \(g.id)") }
        }
        for (i, a) in l.targets.enumerated() {
            for b in l.targets[(i + 1)...] where a.rect.intersects(b.rect) {
                problems.append("targets \(a.objectID) and \(b.objectID) overlap")
            }
        }
        return problems + curveProblems(l, scene: scene)
    }

    /// The round's place on the difficulty curve (`HiddenCurve.spec`): no target on a spot harder than the round
    /// allows, at least `hardSpotTargets` on hard spots (difficulty ≥ 2), at most `maxMediumTargets` medium
    /// targets, and exactly `goldTargets` gold-ish targets (none outside the hoard's rounds 6–10).
    public static func curveProblems(_ l: HiddenRoundLayout, scene: HiddenScene) -> [String] {
        let spec = HiddenCurve.spec(scene.id, round: l.round)
        var problems: [String] = []
        var hard = 0, medium = 0, gold = 0
        let goldish = HiddenCurve.goldish(scene.id)
        for t in l.targets {
            guard let spot = scene.spot(t.spotID), let o = scene.object(t.objectID) else { continue }
            if spot.difficulty > spec.maxSpotDifficulty {
                problems.append("target \(t.objectID) on \(t.spotID) (difficulty \(spot.difficulty), round allows \(spec.maxSpotDifficulty))")
            }
            if spot.difficulty >= 2 { hard += 1 }
            if o.sizeClass == .medium { medium += 1 }
            if goldish.contains(t.objectID) { gold += 1 }
        }
        if hard < spec.hardSpotTargets { problems.append("\(hard) targets on hard spots, round asks for \(spec.hardSpotTargets)") }
        if medium > spec.maxMediumTargets { problems.append("\(medium) medium targets, round allows \(spec.maxMediumTargets)") }
        if gold != spec.goldTargets { problems.append("\(gold) gold targets, round asks for \(spec.goldTargets)") }
        return problems
    }
}
