import Foundation

/// The three hidden-object rooms (R11). Raw value = folder name under `HiddenScenes/` and the scene id in its
/// `scene.json`.
public enum HiddenSceneID: String, CaseIterable, Codable, Sendable, Hashable {
    case attic, market, hoard

    /// 1, 2, 3: the room's number in the wing.
    public var number: Int {
        switch self {
        case .attic: 1
        case .market: 2
        case .hoard: 3
        }
    }

    public init?(number: Int) {
        guard let s = Self.allCases.first(where: { $0.number == number }) else { return nil }
        self = s
    }
}

public enum HiddenSizeClass: String, Codable, Sendable, Hashable, CaseIterable {
    case small, medium
}

/// A whole-pixel point in background coordinates (`background.jpg`, 2752 × 1536).
public struct HiddenPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// An integer rectangle in background pixels: origin top-left.
public struct HiddenRect: Sendable, Hashable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public func intersects(_ o: HiddenRect) -> Bool {
        x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY
    }
    public func insetBy(_ d: Int) -> HiddenRect { HiddenRect(x: x + d, y: y + d, width: width - 2 * d, height: height - 2 * d) }
    public func contains(_ p: HiddenPoint) -> Bool {
        p.x >= Double(x) && p.y >= Double(y) && p.x < Double(maxX) && p.y < Double(maxY)
    }
}

/// One findable library object (`objects[]` in scene.json). `pixelWidth/Height` = the exported PNG's size.
public struct HiddenObject: Sendable, Hashable {
    public let id: String
    /// English display name; the app looks it up in the string catalog.
    public let name: String
    public let sizeClass: HiddenSizeClass
    /// Path of the PNG relative to the scene folder (`objects/<id>.png`).
    public let png: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public var longSide: Int { max(pixelWidth, pixelHeight) }
    public var aspect: Double { Double(longSide) / Double(min(pixelWidth, pixelHeight)) }
}

/// For container spots: the background inside `polygon` is drawn again over the object, its top edge feathered.
public struct HiddenOcclusion: Sendable, Hashable {
    public let cutY: Int
    public let polygon: [[Int]]
    public let feather: Int
}

/// A candidate place (`spots[]`): `x, y` is the bottom-centre anchor of an object standing there.
public struct HiddenSpot: Sendable, Hashable {
    public let id: String
    public let x: Int
    public let y: Int
    public let maxSize: Int
    public let sizeClasses: [HiddenSizeClass]
    public let surface: String
    public let occlusion: HiddenOcclusion?

    public func accepts(_ c: HiddenSizeClass) -> Bool { sizeClasses.contains(c) }

    /// 0…3, higher = harder to search: +2 container (partly hidden), +1 small objects only, +1 maxSize under 60.
    public var difficulty: Int {
        (occlusion == nil ? 0 : 2) + (sizeClasses == [.small] ? 1 : 0) + (maxSize < 60 ? 1 : 0)
    }
}

public struct HiddenBackgroundImage: Sendable, Hashable {
    public let file: String
    public let width: Int
    public let height: Int
    /// Image pixels per background pixel (1 or 0.5).
    public let scale: Double
}

public enum HiddenSceneError: Error, Equatable, CustomStringConvertible {
    case badFormat(String)
    case unknownScene(String)
    case invalid(String)

    public var description: String {
        switch self {
        case .badFormat(let f): "unsupported format \(f)"
        case .unknownScene(let s): "unknown scene \(s)"
        case .invalid(let why): why
        }
    }
}

/// A decoded and validated `scene.json` (format `pourfect-hidden-v1`, from the art pipeline's `export.py`).
public struct HiddenScene: Sendable, Hashable {
    public static let format = "pourfect-hidden-v1"

    public let id: HiddenSceneID
    /// English title from the export ("Alchemist's Attic").
    public let title: String
    public let width: Int
    public let height: Int
    public let images: [HiddenBackgroundImage]
    public let objects: [HiddenObject]
    public let spots: [HiddenSpot]

    public func object(_ id: String) -> HiddenObject? { objectIndex[id].map { objects[$0] } }
    public func spot(_ id: String) -> HiddenSpot? { spotIndex[id].map { spots[$0] } }

    private let objectIndex: [String: Int]
    private let spotIndex: [String: Int]

    public init(data: Data) throws {
        let raw: RawScene
        do { raw = try JSONDecoder().decode(RawScene.self, from: data) } catch {
            throw HiddenSceneError.invalid("not a scene file: \(error)")
        }
        guard raw.format == Self.format else { throw HiddenSceneError.badFormat(raw.format) }
        guard let id = HiddenSceneID(rawValue: raw.scene) else { throw HiddenSceneError.unknownScene(raw.scene) }
        func fail(_ s: String) -> HiddenSceneError { .invalid("\(raw.scene): \(s)") }
        guard raw.background.size.count == 2, raw.background.size[0] > 0, raw.background.size[1] > 0 else {
            throw fail("bad background size")
        }
        let w = raw.background.size[0], h = raw.background.size[1]
        guard !raw.title.isEmpty else { throw fail("no title") }
        var images: [HiddenBackgroundImage] = []
        for im in raw.background.images {
            guard im.size.count == 2, im.size[0] > 0, im.size[1] > 0, im.scale > 0, !im.file.isEmpty,
                  abs(Double(w) * im.scale - Double(im.size[0])) < 1 else { throw fail("bad background image \(im.file)") }
            images.append(HiddenBackgroundImage(file: im.file, width: im.size[0], height: im.size[1], scale: im.scale))
        }
        guard images.contains(where: { $0.scale == 1 }) else { throw fail("no full-size background") }

        var objects: [HiddenObject] = []
        var seenObjects = Set<String>(), seenNames = Set<String>()
        for o in raw.objects {
            guard !o.id.isEmpty, seenObjects.insert(o.id).inserted else { throw fail("duplicate or empty object id \(o.id)") }
            guard !o.name.isEmpty, seenNames.insert(o.name.lowercased()).inserted else { throw fail("duplicate name \(o.name)") }
            guard let c = HiddenSizeClass(rawValue: o.sizeClass) else { throw fail("bad size class for \(o.id)") }
            guard o.size.count == 2, o.size[0] > 0, o.size[1] > 0, !o.png.isEmpty else { throw fail("bad image for \(o.id)") }
            objects.append(HiddenObject(id: o.id, name: o.name, sizeClass: c, png: o.png,
                                        pixelWidth: o.size[0], pixelHeight: o.size[1]))
        }
        var spots: [HiddenSpot] = []
        var seenSpots = Set<String>()
        for s in raw.spots {
            guard !s.id.isEmpty, seenSpots.insert(s.id).inserted else { throw fail("duplicate or empty spot id \(s.id)") }
            guard (0...w).contains(s.x), (0...h).contains(s.y), s.maxSize > 0 else { throw fail("spot \(s.id) out of range") }
            let classes = try s.sizeClass.map { name -> HiddenSizeClass in
                guard let c = HiddenSizeClass(rawValue: name) else { throw fail("bad size class at \(s.id)") }
                return c
            }
            guard !classes.isEmpty else { throw fail("spot \(s.id) takes nothing") }
            var occ: HiddenOcclusion?
            if let o = s.occlusion {
                guard o.polygon.count >= 3, o.polygon.allSatisfy({ $0.count == 2 }), o.feather >= 0 else {
                    throw fail("bad occlusion at \(s.id)")
                }
                occ = HiddenOcclusion(cutY: o.cutY, polygon: o.polygon, feather: o.feather)
            }
            spots.append(HiddenSpot(id: s.id, x: s.x, y: s.y, maxSize: s.maxSize, sizeClasses: classes,
                                    surface: s.surface, occlusion: occ))
        }
        for c in HiddenSizeClass.allCases where objects.contains(where: { $0.sizeClass == c }) {
            guard spots.contains(where: { $0.accepts(c) }) else { throw fail("no spot takes \(c) objects") }
        }
        guard objects.count >= HiddenCurve.maxTargets else { throw fail("too few objects (\(objects.count))") }

        self.id = id
        title = raw.title
        width = w
        height = h
        self.images = images
        self.objects = objects
        self.spots = spots
        objectIndex = Dictionary(uniqueKeysWithValues: objects.enumerated().map { ($1.id, $0) })
        spotIndex = Dictionary(uniqueKeysWithValues: spots.enumerated().map { ($1.id, $0) })
    }
}

private struct RawScene: Decodable {
    struct Image: Decodable { let file: String; let size: [Int]; let scale: Double }
    struct Background: Decodable { let size: [Int]; let images: [Image] }
    struct Object: Decodable { let id: String; let name: String; let sizeClass: String; let png: String; let size: [Int] }
    struct Occlusion: Decodable { let cutY: Int; let polygon: [[Int]]; let feather: Int }
    struct Spot: Decodable {
        let id: String; let x: Int; let y: Int; let maxSize: Int; let sizeClass: [String]; let surface: String
        let occlusion: Occlusion?
    }
    let format: String
    let scene: String
    let title: String
    let background: Background
    let objects: [Object]
    let spots: [Spot]
}
