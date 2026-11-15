import Foundation

/// A level pack file (`Levels/*.json`).
///
/// Every field but `version` and `levels` is optional, so older files still load.
/// The app shows packs as *chapters* (main path, star-gated, see `ChapterGate`)
/// or *challenges* (optional, never gated).
public struct LevelPack: Codable, Sendable, Hashable {
    public static let currentVersion = 1
    public var version: Int
    /// Display name, e.g. "Apprentice Cellar" or "Challenger". Optional; the app falls back to the file name.
    public var name: String?
    /// One-line description shown under the name.
    public var subtitle: String?
    /// Chapter (main path) or challenge (optional area). nil in files written before chapters existed.
    public var kind: PackKind?
    /// 1-based position on the chapter map. Only for `kind == .chapter`.
    public var chapter: Int?
    /// Theme location of a chapter, e.g. "Rune Vault".
    public var location: String?
    /// Mechanics this pack introduces (shown as a first-time tutorial), e.g. `[.sealed]`.
    public var introduces: [Mechanic]?
    public var levels: [LevelDefinition]

    public init(version: Int = LevelPack.currentVersion, name: String? = nil, subtitle: String? = nil,
                kind: PackKind? = nil, chapter: Int? = nil, location: String? = nil, introduces: [Mechanic]? = nil,
                levels: [LevelDefinition]) {
        self.version = version
        self.name = name
        self.subtitle = subtitle
        self.kind = kind
        self.chapter = chapter
        self.location = location
        self.introduces = introduces
        self.levels = levels
    }

    /// Whether this pack is part of the star-gated main path.
    public var isChapter: Bool { kind == .chapter }

    /// Most stars a player can earn in this pack (3 per level).
    public var maxStars: Int { ChapterGate.maxStars(recipeCount: levels.count) }

    /// Stars earned in this pack; `stars(levelID)` returns the best stars for a level (nil = not cleared).
    public func progress(stars: (String) -> Int?) -> ChapterProgress {
        ChapterProgress(stars: levels.reduce(0) { $0 + ChapterGate.clampedStars(stars($1.id)) },
                        recipeCount: levels.count)
    }
}

/// Where a pack is shown in the app.
public enum PackKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Main path: a numbered, star-gated chapter.
    case chapter
    /// Optional Challenges area: never gated.
    case challenge
}

/// A game mechanic a pack can introduce. Stored as a string so files naming
/// mechanics this build doesn't know (later chapters) still load.
public struct Mechanic: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Plain sorting (chapter 1).
    public static let basic: Mechanic = "basic"
    /// Sealed flasks opened by rune-stone keys (`lockedBy` / key layers; chapter 2).
    public static let sealed: Mechanic = "sealed"
    /// Murky potions: layers below the top run show as "?" (`hidden`; chapter 3).
    public static let murky: Mechanic = "murky"

    public var description: String { rawValue }
}

public struct LevelDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var capacity: Int
    public var bottles: [BottleDefinition]
    /// Hidden-layers mode (display only). JSON key `"hidden"`, omitted when false.
    public var hidden: Bool?
    public var meta: LevelMeta?

    public init(id: String, capacity: Int, bottles: [BottleDefinition], hidden: Bool = false, meta: LevelMeta? = nil) {
        self.id = id
        self.capacity = capacity
        self.bottles = bottles
        self.hidden = hidden ? true : nil
        self.meta = meta
    }

    public init(id: String, state: GameState, hidden: Bool = false, meta: LevelMeta? = nil) {
        self.init(id: id,
                  capacity: state.bottles.first?.capacity ?? 0,
                  bottles: state.bottles.map { BottleDefinition(layers: $0.layers, lockedBy: $0.lockedBy) },
                  hidden: hidden,
                  meta: meta)
    }

    /// Whether the level is played with hidden layers.
    public var isHidden: Bool { hidden ?? false }

    public var gameState: GameState {
        GameState(bottles: bottles.map { Bottle(layers: $0.layers, capacity: capacity, lockedBy: $0.lockedBy) })
    }
}

public struct BottleDefinition: Codable, Sendable, Hashable {
    /// Bottom → top. Color layers are plain integers, keys are `{"key": n}`.
    public var layers: [Layer]
    public var lockedBy: KeyID?

    public init(layers: [Layer], lockedBy: KeyID? = nil) {
        self.layers = layers
        self.lockedBy = lockedBy
    }
}

/// Informational metadata written by `levelgen`. Not used by the rules.
public struct LevelMeta: Codable, Sendable, Hashable {
    public var seed: UInt64?
    public var minMoves: Int?
    public var score: Double?
    public var statesExplored: Int?
    public var deadEndRatio: Double?
    public var branchingFactor: Double?

    public init(seed: UInt64? = nil, minMoves: Int? = nil, score: Double? = nil,
                statesExplored: Int? = nil, deadEndRatio: Double? = nil, branchingFactor: Double? = nil) {
        self.seed = seed
        self.minMoves = minMoves
        self.score = score
        self.statesExplored = statesExplored
        self.deadEndRatio = deadEndRatio
        self.branchingFactor = branchingFactor
    }

    public init(seed: UInt64?, report: DifficultyReport) {
        self.init(seed: seed, minMoves: report.minMoves, score: report.score,
                  statesExplored: report.statesExplored, deadEndRatio: report.deadEndRatio,
                  branchingFactor: report.branchingFactor)
    }
}

public enum LevelLoadError: Error, Hashable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case invalidLevel(id: String, errors: [ValidationError])
    case duplicateID(String)
    /// `kind` is "chapter" but `chapter` is missing or below 1.
    case missingChapterNumber

    public var description: String {
        switch self {
        case .unsupportedVersion(let v): return "unsupported level file version \(v)"
        case let .invalidLevel(id, errors): return "level \(id): " + errors.map(\.description).joined(separator: "; ")
        case .duplicateID(let id): return "duplicate level id \(id)"
        case .missingChapterNumber: return "a chapter pack needs \"chapter\": n (n ≥ 1)"
        }
    }
}

public enum LevelLoader {
    /// Decodes a pack and validates every level.
    public static func load(_ data: Data) throws -> LevelPack {
        let pack = try JSONDecoder().decode(LevelPack.self, from: data)
        guard pack.version == LevelPack.currentVersion else { throw LevelLoadError.unsupportedVersion(pack.version) }
        if pack.kind == .chapter, (pack.chapter ?? 0) < 1 { throw LevelLoadError.missingChapterNumber }
        var seen = Set<String>()
        for level in pack.levels {
            guard seen.insert(level.id).inserted else { throw LevelLoadError.duplicateID(level.id) }
            let errors = level.gameState.validate()
            if !errors.isEmpty { throw LevelLoadError.invalidLevel(id: level.id, errors: errors) }
        }
        return pack
    }

    public static func load(contentsOf url: URL) throws -> LevelPack {
        try load(Data(contentsOf: url))
    }

    /// Pretty JSON with each bottle's layer list on one line.
    public static func encode(_ pack: LevelPack) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(pack), as: UTF8.self)
        // Collapse layer lists (numbers and `{"key": n}` objects) onto a single line.
        let compact = text.replacing(/\[(?:[\s\d,\-]|\{\s*"key"\s*:\s*-?\d+\s*\})*\]/) { match in
            String(match.output).filter { !$0.isWhitespace }
                .replacingOccurrences(of: ",", with: ", ")
                .replacingOccurrences(of: ":", with: ": ")
        }
        return Data((compact + "\n").utf8)
    }
}
