import Foundation

/// The art pipeline's placement rules (`poc/hidden-object/tools/layout.py`, also written into each scene.json's
/// "placement" block), ported exactly; `HiddenPoC` replays layout.py itself and is checked against its output.
public enum HiddenRules {
    /// Largest rendered long side per size class, in background pixels.
    public static func classCap(_ c: HiddenSizeClass) -> Int {
        switch c {
        case .small: 68
        case .medium: 112
        }
    }
    /// Chosen spots keep their anchors at least `minGap · (maxSizeA + maxSizeB)` apart.
    public static let minGap = 0.6
    /// layout.py's random size factor `uniform(0.88, 1.0)` (rounds may shrink it, `HiddenRoundSpec.scale`).
    public static let pocScale: ClosedRange<Double> = 0.88...1.0
    /// Horizontal flip with this probability (`random() < 0.3`).
    public static let flipChance = 0.3
    /// Tint strength toward the local colours, `uniform(0.18, 0.26)`.
    public static let tintRange: ClosedRange<Double> = 0.18...0.26
    /// Thin objects (long / short side above this) are drawn up to 25 % longer.
    public static let thinAspect = 1.6

    /// `render_size`: `min(spot.maxSize, classCap) · u`; thin objects × (1 + 0.25 · min(1, (aspect − 1.6) / 1.4)),
    /// never above 1.25 · maxSize; rounded half-to-even (Python `round`), at least 8.
    public static func renderLongSide(_ o: HiddenObject, at s: HiddenSpot, factor u: Double) -> Int {
        var long = Double(min(s.maxSize, classCap(o.sizeClass))) * u
        let aspect = o.aspect
        if aspect > thinAspect {
            long = min(long * (1 + 0.25 * min(1.0, (aspect - thinAspect) / 1.4)), Double(s.maxSize) * 1.25)
        }
        return max(8, Int(long.rounded(.toNearestOrEven)))
    }

    /// The drawn size for a long side: each side × (L / natural long side), rounded half-to-even, at least 1.
    public static func drawnSize(_ o: HiddenObject, longSide: Int) -> (width: Int, height: Int) {
        let k = Double(longSide) / Double(o.longSide)
        return (max(1, Int((Double(o.pixelWidth) * k).rounded(.toNearestOrEven))),
                max(1, Int((Double(o.pixelHeight) * k).rounded(.toNearestOrEven))))
    }

    /// layout.py's spacing test against every already chosen spot.
    public static func isSpaced(_ s: HiddenSpot, from chosen: [HiddenSpot]) -> Bool {
        chosen.allSatisfy { c in
            let dx = Double(s.x - c.x), dy = Double(s.y - c.y)
            return (dx * dx + dy * dy).squareRoot() >= minGap * Double(s.maxSize + c.maxSize)
        }
    }

    /// Draws the per-placement randoms in layout.py's order (size factor, flip, tint) and builds the placement.
    public static func place(_ o: HiddenObject, at s: HiddenSpot, role: HiddenRole, scale: ClosedRange<Double>,
                             rng: inout PythonRandom) -> HiddenPlacement {
        let long = renderLongSide(o, at: s, factor: rng.uniform(scale.lowerBound, scale.upperBound))
        let flipped = rng.random() < flipChance
        let tint = rng.uniform(tintRange.lowerBound, tintRange.upperBound)
        return HiddenPlacement(object: o, spot: s, role: role, longSide: long, flipped: flipped, tint: tint)
    }
}

public enum HiddenRole: String, Codable, Sendable, Hashable {
    /// On the find list.
    case target
    /// Drawn exactly like a target but not findable: tapping it is a wrong tap.
    case decoy
}

/// One object drawn into the scene. All coordinates in background pixels; the object image's bottom centre sits on
/// the spot anchor: `x = spot.x − width / 2` (floor), `y = spot.y − height`.
public struct HiddenPlacement: Sendable, Hashable, Codable {
    public let objectID: String
    public let spotID: String
    public let role: HiddenRole
    public let longSide: Int
    public let width: Int
    public let height: Int
    public let flipped: Bool
    /// Tint strength t (0.18…0.26), see `HiddenBlend.tint`.
    public let tint: Double
    public let x: Int
    public let y: Int
    /// Spot anchor (bottom centre); `anchorY` orders drawing back to front.
    public let anchorX: Int
    public let anchorY: Int
    public let occlusion: HiddenOcclusionGeometry?

    public init(object o: HiddenObject, spot s: HiddenSpot, role: HiddenRole, longSide: Int, flipped: Bool, tint: Double) {
        objectID = o.id
        spotID = s.id
        self.role = role
        self.longSide = longSide
        let size = HiddenRules.drawnSize(o, longSide: longSide)
        width = size.width
        height = size.height
        self.flipped = flipped
        self.tint = tint
        x = s.x - size.width / 2
        y = s.y - size.height
        anchorX = s.x
        anchorY = s.y
        occlusion = s.occlusion.map { HiddenOcclusionGeometry($0) }
    }

    /// Where the object image is drawn.
    public var rect: HiddenRect { HiddenRect(x: x, y: y, width: width, height: height) }
    public var center: HiddenPoint { HiddenPoint(x: Double(x) + Double(width) / 2, y: Double(y) + Double(height) / 2) }

    /// The contact shadow's canvas (`shadow_for`): the object's alpha × 0.38 in `HiddenBlend.shadowColor` on a
    /// canvas padded by 16 px, Gaussian blur σ 5, drawn under the object offset by (+5, +4).
    public var shadowRect: HiddenRect {
        let pad = HiddenBlend.shadowPad
        return HiddenRect(x: x - pad + HiddenBlend.shadowOffset.x, y: y - pad + HiddenBlend.shadowOffset.y,
                          width: width + 2 * pad, height: height + 2 * pad)
    }

    /// The background box whose mean colour the object is tinted toward (`match_to_scene`): the object's box grown
    /// by max(width, height) on every side, clipped to the background.
    public func tintSampleRect(sceneWidth: Int, sceneHeight: Int) -> HiddenRect {
        let pad = max(width, height)
        let x0 = max(0, x - pad), y0 = max(0, y - pad)
        let x1 = min(sceneWidth, x + width + pad), y1 = min(sceneHeight, y + height + pad)
        return HiddenRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}

/// layout.py, replayed: `pick` (sample `count` objects, medium first, shuffle the spots, first spaced compatible spot
/// each), then per object back to front by spot y: size factor, flip, tint. Used by the golden tests; the game's rounds
/// come from `HiddenGenerator`.
public enum HiddenPoC {
    /// nil where layout.py stops with "no free spot".
    public static func layout(_ scene: HiddenScene, seed: UInt64, count: Int = 12) -> [HiddenPlacement]? {
        var rng = PythonRandom(seed: seed)
        var objects = rng.sample(scene.objects, count)
        objects = stableSorted(objects) { $0.sizeClass == .medium && $1.sizeClass != .medium }
        var free = scene.spots
        rng.shuffle(&free)
        var chosen: [(HiddenObject, HiddenSpot)] = []
        for o in objects {
            guard let i = free.firstIndex(where: { $0.accepts(o.sizeClass) && HiddenRules.isSpaced($0, from: chosen.map(\.1)) })
            else { return nil }
            chosen.append((o, free.remove(at: i)))
        }
        let ordered = stableSorted(chosen) { $0.1.y < $1.1.y }
        return ordered.map { HiddenRules.place($0.0, at: $0.1, role: .target, scale: HiddenRules.pocScale, rng: &rng) }
    }
}

/// Python's `sorted` is stable; Swift's `sorted` is too since 5, but it is not documented as such, so be explicit.
func stableSorted<T>(_ a: [T], by less: (T, T) -> Bool) -> [T] {
    a.enumerated().sorted { l, r in
        less(l.element, r.element) || (!less(r.element, l.element) && l.offset < r.offset)
    }.map(\.element)
}
