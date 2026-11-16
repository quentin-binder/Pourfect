import Foundation

/// A level pack file (`Levels/*.json`).
///
/// Every field but `version` and `levels` is optional, so older files still load.
///
/// Format versions: **1** = colors, keys and seals (`lockedBy`), murky flag. **2** adds
/// flask `modifiers`, level `links` and a `goal`. `LevelLoader.encode` writes version 2
/// only when a level uses something version 1 can't express (`requiredVersion`), so
/// classic and sealed packs stay byte-identical version-1 files.
/// The app shows packs as *chapters* (main path, star-gated, see `ChapterGate`)
/// or *challenges* (optional, never gated).
public struct LevelPack: Codable, Sendable, Hashable {
    /// The version written by default (and by `LevelLoader.encode` when nothing needs more).
    public static let currentVersion = 1
    /// Every version this build reads.
    public static let supportedVersions = 1...2
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

    /// The lowest format version that can express every level in the pack.
    public var requiredVersion: Int {
        levels.contains(where: \.needsVersion2) ? 2 : 1
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
    /// Essence flasks: a flask with a color rune receives only that color
    /// (`BottleModifier.essence`; chapter 4).
    public static let essence: Mechanic = "essence"
    /// Narrow-neck flasks: one layer per pour, in or out (`BottleModifier.narrowNeck`; chapter 5).
    public static let narrowNeck: Mechanic = "narrowNeck"
    /// Funnel flasks: receive, never pour out (`BottleModifier.funnel`; chapter 5).
    public static let funnel: Mechanic = "funnel"
    /// Tap flasks: pour from the bottom, never receive (`BottleModifier.tap`; chapter 5).
    public static let tap: Mechanic = "tap"
    /// Frozen layers: a layer and everything below it can't move until it thaws after a
    /// few moves (`BottleModifier.frozen`; chapter 6).
    public static let frozen: Mechanic = "frozen"
    /// Bubbling flasks: every few moves the bottom layer rises to the top
    /// (`BottleModifier.bubbling`; chapter 7).
    public static let bubbling: Mechanic = "bubbling"
    /// Twin flasks: two flasks on a silver chain share every pour into either one, split
    /// evenly (`Link.twins`; chapter 8).
    public static let twins: Mechanic = "twins"
    /// Overflow pipes: what doesn't fit into a full flask runs on through its pipe into
    /// another flask (`Link.overflow`; chapter 8).
    public static let overflow: Mechanic = "overflow"
    /// Mixing cauldrons: pouring one ingredient of a recipe onto the other inside a cauldron
    /// brews the result (`BottleModifier.cauldron`; chapter 9).
    public static let cauldron: Mechanic = "cauldron"
    /// Switch flasks and gates: a gate flask opens only while its switch flask is complete
    /// (full with one color) (`Link.switchGate`; chapter 10).
    public static let switches: Mechanic = "switch"

    public var description: String { rawValue }
}

public struct LevelDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var capacity: Int
    public var bottles: [BottleDefinition]
    /// Hidden-layers mode (display only). JSON key `"hidden"`, omitted when false.
    public var hidden: Bool?
    /// v2: links between flasks (by index in `bottles`). Omitted when empty.
    public var links: [Link]?
    /// v2: the win condition. Omitted for `.standard`.
    public var goal: Goal?
    public var meta: LevelMeta?

    public init(id: String, capacity: Int, bottles: [BottleDefinition], hidden: Bool = false,
                links: [Link] = [], goal: Goal = .standard, meta: LevelMeta? = nil) {
        self.id = id
        self.capacity = capacity
        self.bottles = bottles
        self.hidden = hidden ? true : nil
        self.links = links.isEmpty ? nil : links
        self.goal = goal == .standard ? nil : goal
        self.meta = meta
    }

    public init(id: String, state: GameState, hidden: Bool = false, meta: LevelMeta? = nil) {
        self.init(id: id,
                  capacity: state.bottles.first?.capacity ?? 0,
                  bottles: state.bottles.map { BottleDefinition(layers: $0.layers, modifiers: $0.modifiers) },
                  hidden: hidden,
                  links: state.links,
                  goal: state.goal,
                  meta: meta)
    }

    /// Whether the level is played with hidden layers.
    public var isHidden: Bool { hidden ?? false }

    /// The mechanics this level actually uses, in chapter order (sealed, murky, essence,
    /// narrow neck, funnel, tap, frozen, bubbling, twins, overflow, cauldron, switch),
    /// e.g. to pick the tips a recipe shows. Empty for a plain sorting level.
    public var mechanics: [Mechanic] {
        let all = bottles.flatMap(\.allModifiers)
        var result: [Mechanic] = []
        if all.contains(where: \.isSeal) { result.append(.sealed) }
        if isHidden { result.append(.murky) }
        if all.contains(where: { if case .essence = $0 { return true } else { return false } }) { result.append(.essence) }
        if all.contains(.narrowNeck) { result.append(.narrowNeck) }
        if all.contains(.funnel) { result.append(.funnel) }
        if all.contains(.tap) { result.append(.tap) }
        if all.contains(where: { if case .frozen = $0 { return true } else { return false } }) { result.append(.frozen) }
        if all.contains(where: { if case .bubbling = $0 { return true } else { return false } }) { result.append(.bubbling) }
        let links = links ?? []
        if links.contains(where: { if case .twins = $0 { return true } else { return false } }) { result.append(.twins) }
        if links.contains(where: { if case .overflow = $0 { return true } else { return false } }) { result.append(.overflow) }
        if all.contains(where: { if case .cauldron = $0 { return true } else { return false } }) { result.append(.cauldron) }
        if links.contains(where: { if case .switchGate = $0 { return true } else { return false } }) { result.append(.switches) }
        return result
    }

    /// Whether the level uses something format version 1 can't express.
    public var needsVersion2: Bool {
        !(links ?? []).isEmpty || (goal ?? .standard) != .standard
            || bottles.contains { !($0.modifiers ?? []).isEmpty }
    }

    public var gameState: GameState {
        GameState(bottles: bottles.map { Bottle(layers: $0.layers, capacity: capacity, modifiers: $0.allModifiers) },
                  links: links ?? [], goal: goal ?? .standard)
    }
}

public struct BottleDefinition: Codable, Sendable, Hashable {
    /// Bottom → top. Color layers are plain integers, keys are `{"key": n}`.
    public var layers: [Layer]
    /// The flask's seal (the v1 form of `BottleModifier.sealed`).
    public var lockedBy: KeyID?
    /// v2: every other modifier (`{"type": "essence", "color": 3}`, …). Omitted when empty.
    public var modifiers: [BottleModifier]?

    public init(layers: [Layer], lockedBy: KeyID? = nil) {
        self.layers = layers
        self.lockedBy = lockedBy
    }

    /// Splits `modifiers` into the v1 `lockedBy` (first seal) and the v2 rest.
    public init(layers: [Layer], modifiers: [BottleModifier]) {
        let (lock, others) = Bottle.splitSeal(modifiers)
        self.layers = layers
        self.lockedBy = lock
        self.modifiers = others.isEmpty ? nil : others
    }

    /// The seal plus every other modifier.
    public var allModifiers: [BottleModifier] {
        (modifiers ?? []) + (lockedBy.map { [.sealed($0)] } ?? [])
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
    /// A version-1 file uses something only version 2 can express (modifiers, links, goal).
    case needsVersion2(id: String)

    public var description: String {
        switch self {
        case .unsupportedVersion(let v): return "unsupported level file version \(v)"
        case let .invalidLevel(id, errors): return "level \(id): " + errors.map(\.description).joined(separator: "; ")
        case .duplicateID(let id): return "duplicate level id \(id)"
        case .missingChapterNumber: return "a chapter pack needs \"chapter\": n (n ≥ 1)"
        case .needsVersion2(let id): return "level \(id) uses modifiers, links or a goal, which need \"version\": 2"
        }
    }
}

public enum LevelLoader {
    /// Decodes a pack and checks its structure (version, chapter number, unique ids)
    /// without validating the levels against the rules.
    public static func decode(_ data: Data) throws -> LevelPack {
        let pack = try JSONDecoder().decode(LevelPack.self, from: data)
        guard LevelPack.supportedVersions.contains(pack.version) else { throw LevelLoadError.unsupportedVersion(pack.version) }
        if pack.kind == .chapter, (pack.chapter ?? 0) < 1 { throw LevelLoadError.missingChapterNumber }
        var seen = Set<String>()
        for level in pack.levels {
            guard seen.insert(level.id).inserted else { throw LevelLoadError.duplicateID(level.id) }
            if pack.version < 2 && level.needsVersion2 { throw LevelLoadError.needsVersion2(id: level.id) }
        }
        return pack
    }

    /// Decodes a pack and validates every level.
    public static func load(_ data: Data) throws -> LevelPack {
        let pack = try decode(data)
        for level in pack.levels {
            let errors = level.gameState.validate()
            if !errors.isEmpty { throw LevelLoadError.invalidLevel(id: level.id, errors: errors) }
        }
        return pack
    }

    public static func load(contentsOf url: URL) throws -> LevelPack {
        try load(Data(contentsOf: url))
    }

    /// Pretty JSON with each bottle's layer list on one line. The `version` written is
    /// `pack.requiredVersion`: 1 unless a level needs version 2.
    public static func encode(_ pack: LevelPack) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var pack = pack
        pack.version = pack.requiredVersion
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
