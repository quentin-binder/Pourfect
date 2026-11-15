import Foundation

/// A level pack file (`Levels/*.json`).
public struct LevelPack: Codable, Sendable, Hashable {
    public static let currentVersion = 1
    public var version: Int
    public var levels: [LevelDefinition]

    public init(version: Int = LevelPack.currentVersion, levels: [LevelDefinition]) {
        self.version = version
        self.levels = levels
    }
}

public struct LevelDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var capacity: Int
    public var bottles: [BottleDefinition]
    public var meta: LevelMeta?

    public init(id: String, capacity: Int, bottles: [BottleDefinition], meta: LevelMeta? = nil) {
        self.id = id
        self.capacity = capacity
        self.bottles = bottles
        self.meta = meta
    }

    public init(id: String, state: GameState, meta: LevelMeta? = nil) {
        self.init(id: id,
                  capacity: state.bottles.first?.capacity ?? 0,
                  bottles: state.bottles.map { BottleDefinition(layers: $0.layers, lockedBy: $0.lockedBy) },
                  meta: meta)
    }

    public var gameState: GameState {
        GameState(bottles: bottles.map { Bottle(layers: $0.layers, capacity: capacity, lockedBy: $0.lockedBy) })
    }
}

public struct BottleDefinition: Codable, Sendable, Hashable {
    /// Bottom → top. Color layers are plain integers.
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

    public var description: String {
        switch self {
        case .unsupportedVersion(let v): return "unsupported level file version \(v)"
        case let .invalidLevel(id, errors): return "level \(id): " + errors.map(\.description).joined(separator: "; ")
        case .duplicateID(let id): return "duplicate level id \(id)"
        }
    }
}

public enum LevelLoader {
    /// Decodes a pack and validates every level.
    public static func load(_ data: Data) throws -> LevelPack {
        let pack = try JSONDecoder().decode(LevelPack.self, from: data)
        guard pack.version == LevelPack.currentVersion else { throw LevelLoadError.unsupportedVersion(pack.version) }
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
        // Collapse arrays of plain numbers (layer lists) onto a single line.
        let compact = text.replacing(/\[[\s\d,\-]*\]/) { match in
            let numbers = match.output.split(whereSeparator: { "[], \n".contains($0) })
            return "[" + numbers.joined(separator: ", ") + "]"
        }
        return Data((compact + "\n").utf8)
    }
}
