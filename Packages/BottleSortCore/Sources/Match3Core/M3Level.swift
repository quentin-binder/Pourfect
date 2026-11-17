import Foundation

/// A level goal. JSON: `{"type":"collect","kind":"moonflower","count":20}`, `{"type":"frost"}`,
/// `{"type":"crates"}`, `{"type":"drops","count":3}`, `{"type":"score","count":5000}`.
public struct M3Goal: Codable, Sendable, Hashable {
    public enum GoalType: String, Codable, Sendable, Hashable, CaseIterable {
        /// Clear `count` pieces of `kind` (specials of that kind count too).
        case collect
        /// Remove every frost layer on the board.
        case frost
        /// Break every sealed crate.
        case crates
        /// Bring `count` potion flasks down to the bottom (must equal `drops.total`).
        case drops
        /// Reach `count` points.
        case score
    }

    public var type: GoalType
    public var kind: M3Kind?
    public var count: Int?

    public init(type: GoalType, kind: M3Kind? = nil, count: Int? = nil) {
        self.type = type
        self.kind = kind
        self.count = count
    }

    public static func collect(_ kind: M3Kind, _ count: Int) -> M3Goal { M3Goal(type: .collect, kind: kind, count: count) }
    public static let frost = M3Goal(type: .frost)
    public static let crates = M3Goal(type: .crates)
    public static func drops(_ count: Int) -> M3Goal { M3Goal(type: .drops, count: count) }
    public static func score(_ count: Int) -> M3Goal { M3Goal(type: .score, count: count) }

    /// English text for tools ("Collect 20 Moonflower").
    public var summary: String {
        switch type {
        case .collect: "collect \(count ?? 0) \(kind?.rawValue ?? "?")"
        case .frost: "clear all frost"
        case .crates: "break all crates"
        case .drops: "drop \(count ?? 0) flasks"
        case .score: "score \(count ?? 0)"
        }
    }
}

/// Potion flasks that fall to the bottom (drop-down goal).
public struct M3Drops: Codable, Sendable, Hashable {
    /// Flasks in the level, including those placed in the layout (`F`).
    public var total: Int
    /// New flasks spawn only while fewer than this are on the board.
    public var maxOnBoard: Int
    /// Columns new flasks may spawn in (nil = every column).
    public var columns: [Int]?

    public init(total: Int, maxOnBoard: Int = 1, columns: [Int]? = nil) {
        self.total = total
        self.maxOnBoard = maxOnBoard
        self.columns = columns
    }
}

/// A piece placed by the level instead of the seed (on an `o`, `1` or `2` layout cell).
public struct M3PlacedPiece: Codable, Sendable, Hashable {
    public var row: Int
    public var col: Int
    /// nil only for a prism.
    public var kind: M3Kind?
    public var special: M3Special?

    public init(row: Int, col: Int, kind: M3Kind?, special: M3Special? = nil) {
        self.row = row
        self.col = col
        self.kind = kind
        self.special = special
    }
}

/// Score thresholds for the second and third star (one star = goals met).
public struct M3StarThresholds: Codable, Sendable, Hashable {
    public var two: Int
    public var three: Int

    public init(two: Int, three: Int) {
        self.two = two
        self.three = three
    }

    /// 0 when the level was lost, else 1…3.
    public func stars(score: Int, won: Bool) -> Int {
        guard won else { return 0 }
        return score >= three ? 3 : score >= two ? 2 : 1
    }
}

/// Optional tuning record written by `m3gen` (not read by the rules).
public struct M3Tuning: Codable, Sendable, Hashable {
    /// Target bot pass rate in percent.
    public var target: Int
    /// Measured pass rate (percent) of the reference bot with `moves`.
    public var passRate: Int
    /// Bot runs measured.
    public var runs: Int

    public init(target: Int, passRate: Int, runs: Int) {
        self.target = target
        self.passRate = passRate
        self.runs = runs
    }
}

/// One match-3 level.
///
/// `layout` rows (top first), one character per cell:
/// `.` hole, `o` open cell with a seeded piece, `1`/`2` seeded piece under 1/2 frost layers,
/// `A`/`B`/`C` sealed crate needing 1/2/3 hits, `F` potion flask.
public struct M3Level: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var seed: UInt64
    public var layout: [String]
    public var kinds: [M3Kind]
    public var moves: Int
    public var goals: [M3Goal]
    public var stars: M3StarThresholds
    public var drops: M3Drops?
    public var pieces: [M3PlacedPiece]?
    public var tuning: M3Tuning?

    public init(id: String, title: String, seed: UInt64, layout: [String], kinds: [M3Kind], moves: Int,
                goals: [M3Goal], stars: M3StarThresholds, drops: M3Drops? = nil, pieces: [M3PlacedPiece]? = nil,
                tuning: M3Tuning? = nil) {
        self.id = id
        self.title = title
        self.seed = seed
        self.layout = layout
        self.kinds = kinds
        self.moves = moves
        self.goals = goals
        self.stars = stars
        self.drops = drops
        self.pieces = pieces
        self.tuning = tuning
    }

    public var height: Int { layout.count }
    public var width: Int { layout.first?.count ?? 0 }

    /// Layout cells as characters (row-major); empty if the layout is ragged.
    var layoutChars: [[Character]] { layout.map(Array.init) }

    public var hasFrost: Bool { layout.contains { $0.contains("1") || $0.contains("2") } }
    public var hasCrates: Bool { layout.contains { $0.contains("A") || $0.contains("B") || $0.contains("C") } }
    public var hasDrops: Bool { (drops?.total ?? 0) > 0 }

    /// FNV-1a (64-bit, hex) of the level's sorted-key JSON: pins generator output in golden tests.
    public var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// The mechanics this level uses (for the app's tips and the tools).
    public var features: [String] {
        var f: [String] = []
        if hasFrost { f.append("frost") }
        if hasCrates { f.append("crates") }
        if hasDrops { f.append("drops") }
        return f
    }
}

/// An episode's metadata.
public struct M3Episode: Codable, Sendable, Hashable {
    /// 1…10: the episode after sorting chapter `number`.
    public var number: Int
    public var name: String
    public var subtitle: String
    /// The sorting chapter it follows (always `number` in v1).
    public var followsChapter: Int

    public init(number: Int, name: String, subtitle: String, followsChapter: Int) {
        self.number = number
        self.name = name
        self.subtitle = subtitle
        self.followsChapter = followsChapter
    }
}

/// One episode file `Levels/match3/gathering_NN.json`.
public struct M3EpisodeFile: Codable, Sendable, Hashable {
    public static let formatName = "pourfect-match3"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var episode: M3Episode
    public var levels: [M3Level]

    public init(episode: M3Episode, levels: [M3Level]) {
        self.format = M3EpisodeFile.formatName
        self.version = M3EpisodeFile.currentVersion
        self.episode = episode
        self.levels = levels
    }

    public static func decode(_ data: Data) throws -> M3EpisodeFile {
        try JSONDecoder().decode(M3EpisodeFile.self, from: data)
    }

    /// Stable, pretty JSON (sorted keys) with a trailing newline.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    /// Every problem in the file (format, version, episode metadata, each level).
    public func validate() -> [M3ValidationError] {
        var errors: [M3ValidationError] = []
        if format != M3EpisodeFile.formatName { errors.append(.badFormat(format)) }
        if version != M3EpisodeFile.currentVersion { errors.append(.unsupportedVersion(version)) }
        if !(1...10).contains(episode.number) { errors.append(.badEpisode(episode.number)) }
        var ids = Set<String>()
        for level in levels {
            if !ids.insert(level.id).inserted { errors.append(.duplicateID(level.id)) }
            errors += level.validate()
        }
        if levels.isEmpty { errors.append(.noLevels) }
        return errors
    }
}

public enum M3ValidationError: Error, Sendable, Hashable, CustomStringConvertible {
    case badFormat(String)
    case unsupportedVersion(Int)
    case badEpisode(Int)
    case noLevels
    case duplicateID(String)
    case badSize(width: Int, height: Int)
    case raggedLayout
    case unknownLayoutCharacter(Character)
    case tooFewCells(Int)
    case kindCount(Int)
    case duplicateKinds
    case moves(Int)
    case noGoals
    case duplicateGoal(M3Goal.GoalType)
    case goalCount(M3Goal.GoalType)
    case collectKindMissing
    case collectKindNotInLevel(M3Kind)
    case frostGoalWithoutFrost
    case crateGoalWithoutCrates
    case dropsGoalWithoutDrops
    case dropsGoalMismatch(goal: Int, total: Int)
    case dropsConfig
    case flaskAtBottom(M3Pos)
    case starThresholds
    case placedPieceOutside(M3Pos)
    case placedPieceNotOnPieceCell(M3Pos)
    case placedPieceKind(M3Pos)
    case duplicatePlacedPiece(M3Pos)
    case placedPiecesMatch
    case noPlayableStart

    public var description: String {
        switch self {
        case .badFormat(let f): "format is \"\(f)\", expected \"\(M3EpisodeFile.formatName)\""
        case .unsupportedVersion(let v): "unsupported version \(v)"
        case .badEpisode(let n): "episode number \(n) is not 1…10"
        case .noLevels: "no levels"
        case .duplicateID(let id): "duplicate level id \(id)"
        case .badSize(let w, let h): "board \(w)×\(h) is not within 3…8 × 3…8"
        case .raggedLayout: "layout rows differ in length"
        case .unknownLayoutCharacter(let c): "unknown layout character \"\(c)\""
        case .tooFewCells(let n): "only \(n) cells"
        case .kindCount(let n): "\(n) ingredient kinds (needs 3…6)"
        case .duplicateKinds: "an ingredient kind is listed twice"
        case .moves(let n): "move limit \(n) is not 1…99"
        case .noGoals: "no goals"
        case .duplicateGoal(let t): "two \(t.rawValue) goals of the same kind"
        case .goalCount(let t): "\(t.rawValue) goal needs a positive count"
        case .collectKindMissing: "collect goal without a kind"
        case .collectKindNotInLevel(let k): "collect goal for \(k.rawValue), which the level doesn't use"
        case .frostGoalWithoutFrost: "frost goal but no frost in the layout"
        case .crateGoalWithoutCrates: "crate goal but no crates in the layout"
        case .dropsGoalWithoutDrops: "drops goal but no drops config"
        case .dropsGoalMismatch(let g, let t): "drops goal \(g) differs from drops.total \(t)"
        case .dropsConfig: "drops config is invalid (total ≥ flasks in layout, maxOnBoard ≥ 1, columns on the board)"
        case .flaskAtBottom(let p): "flask at \(p) starts on its column's bottom cell"
        case .starThresholds: "star thresholds must satisfy 0 < two < three"
        case .placedPieceOutside(let p): "placed piece at \(p) is outside the board"
        case .placedPieceNotOnPieceCell(let p): "placed piece at \(p) is not on an o/1/2 cell"
        case .placedPieceKind(let p): "placed piece at \(p) has a bad kind (prism has none; others need one of the level's kinds)"
        case .duplicatePlacedPiece(let p): "two placed pieces at \(p)"
        case .placedPiecesMatch: "placed pieces form a match"
        case .noPlayableStart: "no start board without matches and with a valid swap could be built"
        }
    }
}

extension M3Level {
    static let layoutCharacters: Set<Character> = [".", "o", "1", "2", "A", "B", "C", "F"]

    /// Every problem with the level; empty means valid.
    public func validate() -> [M3ValidationError] {
        var errors: [M3ValidationError] = []
        let rows = layoutChars
        let w = width, h = height
        guard (3...M3Board.maxSize).contains(w), (3...M3Board.maxSize).contains(h) else {
            return [.badSize(width: w, height: h)]
        }
        if rows.contains(where: { $0.count != w }) { return [.raggedLayout] }
        for row in rows {
            for ch in row where !M3Level.layoutCharacters.contains(ch) { errors.append(.unknownLayoutCharacter(ch)) }
        }
        if !errors.isEmpty { return errors }
        let cellCount = rows.joined().filter { $0 != "." }.count
        if cellCount < 9 { errors.append(.tooFewCells(cellCount)) }
        if !(3...6).contains(kinds.count) { errors.append(.kindCount(kinds.count)) }
        if Set(kinds).count != kinds.count { errors.append(.duplicateKinds) }
        if !(1...99).contains(moves) { errors.append(.moves(moves)) }
        if goals.isEmpty { errors.append(.noGoals) }
        var seenTypes = Set<String>()
        for goal in goals {
            let key = goal.type.rawValue + (goal.kind?.rawValue ?? "")
            if !seenTypes.insert(key).inserted { errors.append(.duplicateGoal(goal.type)) }
            switch goal.type {
            case .collect:
                if (goal.count ?? 0) <= 0 { errors.append(.goalCount(.collect)) }
                if let k = goal.kind { if !kinds.contains(k) { errors.append(.collectKindNotInLevel(k)) } } else {
                    errors.append(.collectKindMissing)
                }
            case .frost: if !hasFrost { errors.append(.frostGoalWithoutFrost) }
            case .crates: if !hasCrates { errors.append(.crateGoalWithoutCrates) }
            case .drops:
                if (goal.count ?? 0) <= 0 { errors.append(.goalCount(.drops)) }
                if let d = drops { if d.total != goal.count { errors.append(.dropsGoalMismatch(goal: goal.count ?? 0, total: d.total)) } } else {
                    errors.append(.dropsGoalWithoutDrops)
                }
            case .score: if (goal.count ?? 0) <= 0 { errors.append(.goalCount(.score)) }
            }
        }
        if !(0 < stars.two && stars.two < stars.three) { errors.append(.starThresholds) }

        // Flasks.
        let layoutFlasks = rows.joined().filter { $0 == "F" }.count
        if let d = drops {
            let columnsOK = (d.columns ?? []).allSatisfy { (0..<w).contains($0) } && d.columns?.isEmpty != true
            if d.total < max(1, layoutFlasks) || d.maxOnBoard < 1 || !columnsOK { errors.append(.dropsConfig) }
        } else if layoutFlasks > 0 {
            errors.append(.dropsConfig)
        }
        let board = M3Rules.emptyBoard(self)
        for c in 0..<w {
            if let bottom = board.bottomOpenCell(column: c), rows[bottom.row][c] == "F" { errors.append(.flaskAtBottom(bottom)) }
        }

        // Placed pieces.
        var placedAt = Set<M3Pos>()
        for p in pieces ?? [] {
            let pos = M3Pos(p.row, p.col)
            guard board.contains(pos) else { errors.append(.placedPieceOutside(pos)); continue }
            if !"o12".contains(rows[p.row][p.col]) { errors.append(.placedPieceNotOnPieceCell(pos)) }
            let kindOK = p.special == .prism ? p.kind == nil : (p.kind.map(kinds.contains) ?? false)
            if !kindOK { errors.append(.placedPieceKind(pos)) }
            if !placedAt.insert(pos).inserted { errors.append(.duplicatePlacedPiece(pos)) }
        }
        if !errors.isEmpty { return errors }
        var placedBoard = board
        for p in pieces ?? [] { M3Rules.place(p, on: &placedBoard, layout: rows) }
        if !M3Rules.findGroups(placedBoard, swap: nil).isEmpty { errors.append(.placedPiecesMatch) }
        if errors.isEmpty, M3Game.makeStart(self) == nil { errors.append(.noPlayableStart) }
        return errors
    }
}
