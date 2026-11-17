import BottleSortCore
import Foundation

/// How a level was made (written by the generator; informational).
public struct DistillStats: Hashable, Sendable, Codable {
    public var seed: UInt64
    /// Pieces the solved network uses (sources and targets not counted).
    public var networkCells: Int
    /// Pieces outside the network.
    public var decoys: Int
    /// Solver branch points (counting pass).
    public var decisions: Int
    /// Solver nodes (counting pass).
    public var nodes: Int
    /// Mechanics present: "tee", "cross", "fixed", "valve", "coil", "cap", "colors2", "colors3".
    public var mechanics: [String]
    /// Difficulty score (DECISIONS 274).
    public var score: Int

    public init(seed: UInt64, networkCells: Int, decoys: Int, decisions: Int, nodes: Int, mechanics: [String], score: Int) {
        self.seed = seed
        self.networkCells = networkCells
        self.decoys = decoys
        self.decisions = decisions
        self.nodes = nodes
        self.mechanics = mechanics
        self.score = score
    }
}

/// One distillery puzzle.
///
/// JSON (DECISIONS 275):
/// ```
/// { "id": "d1-01", "title": "…", "width": 4, "height": 4,
///   "grid": ["S . . .", "I1 L2 C0* .", …],      // a token per cell, space separated
///   "sources": [{"r":0,"c":0,"color":0,"dir":"s"}], "targets": [{"r":3,"c":3,"color":0,"dir":"w"}],
///   "valves": [{"r":1,"c":2,"target":0}], "coils": [{"r":2,"c":1,"from":0,"to":5}],
///   "minTaps": 5, "stats": {…} }
/// ```
/// Tokens: "." empty, "S" source cell, "F" target flask cell, "X" cross, or a shape letter (C cap, I straight,
/// L elbow, T tee) with its rotation digit 0…3; a trailing "*" rivets the piece.
public struct DistillLevel: Hashable, Sendable, Codable {
    public var id: String
    public var title: String?
    public var board: DistillBoard
    /// Fewest taps to a win from the start (the solver's; stars compare against it).
    public var minTaps: Int
    public var stats: DistillStats?

    public init(id: String, title: String? = nil, board: DistillBoard, minTaps: Int, stats: DistillStats? = nil) {
        self.id = id
        self.title = title
        self.board = board
        self.minTaps = minTaps
        self.stats = stats
    }

    struct SourceJSON: Codable { var r: Int, c: Int, color: Int, dir: DistillDir }
    struct ValveJSON: Codable { var r: Int, c: Int, target: Int }
    struct CoilJSON: Codable { var r: Int, c: Int, from: Int, to: Int }

    enum CodingKeys: String, CodingKey {
        case id, title, width, height, grid, sources, targets, valves, coils, minTaps, stats
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        minTaps = try c.decode(Int.self, forKey: .minTaps)
        stats = try c.decodeIfPresent(DistillStats.self, forKey: .stats)
        let width = try c.decode(Int.self, forKey: .width), height = try c.decode(Int.self, forKey: .height)
        guard (1...DistillBoard.maxSide).contains(width), (1...DistillBoard.maxSide).contains(height) else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: c, debugDescription: "board size \(width)x\(height)")
        }
        let grid = try c.decode([String].self, forKey: .grid)
        guard grid.count == height else {
            throw DecodingError.dataCorruptedError(forKey: .grid, in: c, debugDescription: "grid has \(grid.count) rows")
        }
        var pieces: [DistillPiece] = []
        var marks: [Character] = []
        for row in grid {
            let tokens = row.split(separator: " ")
            guard tokens.count == width else {
                throw DecodingError.dataCorruptedError(forKey: .grid, in: c, debugDescription: "row \"\(row)\" needs \(width) tokens")
            }
            for t in tokens {
                guard let piece = DistillLevel.piece(token: String(t)) else {
                    throw DecodingError.dataCorruptedError(forKey: .grid, in: c, debugDescription: "bad token \(t)")
                }
                pieces.append(piece)
                marks.append(t.first == "S" || t.first == "F" ? t.first! : " ")
            }
        }
        let sources = try c.decode([SourceJSON].self, forKey: .sources)
            .map { DistillSource(pos: DistillPos($0.r, $0.c), color: ColorID($0.color), outlet: $0.dir) }
        let targets = try c.decode([SourceJSON].self, forKey: .targets)
            .map { DistillTarget(pos: DistillPos($0.r, $0.c), color: ColorID($0.color), inlet: $0.dir) }
        var board = DistillBoard(width: width, height: height, pieces: pieces, sources: sources, targets: targets)
        for v in try c.decodeIfPresent([ValveJSON].self, forKey: .valves) ?? [] {
            let p = DistillPos(v.r, v.c)
            guard board.contains(p) else { throw DecodingError.dataCorruptedError(forKey: .valves, in: c, debugDescription: "valve off the board") }
            board[p].valve = v.target
        }
        for k in try c.decodeIfPresent([CoilJSON].self, forKey: .coils) ?? [] {
            let p = DistillPos(k.r, k.c)
            guard board.contains(p) else { throw DecodingError.dataCorruptedError(forKey: .coils, in: c, debugDescription: "coil off the board") }
            board[p].coil = DistillCoil(from: ColorID(k.from), to: ColorID(k.to))
        }
        // "S"/"F" tokens must match the source/target lists (checked by validate()); keep them for it.
        self.board = board
        tokenMarks = marks
    }

    /// "S"/"F" marks read from the grid (validation only; not part of equality).
    var tokenMarks: [Character]? = nil

    public static func == (a: DistillLevel, b: DistillLevel) -> Bool {
        a.id == b.id && a.title == b.title && a.board == b.board && a.minTaps == b.minTaps && a.stats == b.stats
    }
    public func hash(into h: inout Hasher) { h.combine(id); h.combine(board); h.combine(minTaps) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(board.width, forKey: .width)
        try c.encode(board.height, forKey: .height)
        try c.encode(gridRows, forKey: .grid)
        try c.encode(board.sources.map { SourceJSON(r: $0.pos.r, c: $0.pos.c, color: $0.color.rawValue, dir: $0.outlet) }, forKey: .sources)
        try c.encode(board.targets.map { SourceJSON(r: $0.pos.r, c: $0.pos.c, color: $0.color.rawValue, dir: $0.inlet) }, forKey: .targets)
        let cells = (0..<board.cellCount).map(board.pos)
        let valves = cells.compactMap { p in board[p].valve.map { ValveJSON(r: p.r, c: p.c, target: $0) } }
        let coils = cells.compactMap { p in board[p].coil.map { CoilJSON(r: p.r, c: p.c, from: $0.from.rawValue, to: $0.to.rawValue) } }
        if !valves.isEmpty { try c.encode(valves, forKey: .valves) }
        if !coils.isEmpty { try c.encode(coils, forKey: .coils) }
        try c.encode(minTaps, forKey: .minTaps)
        try c.encodeIfPresent(stats, forKey: .stats)
    }

    /// The grid as level-file rows.
    public var gridRows: [String] {
        (0..<board.height).map { r in
            (0..<board.width).map { c -> String in
                let p = DistillPos(r, c)
                switch board.kind(at: p) {
                case .source: return "S"
                case .target: return "F"
                case .piece(let piece): return DistillLevel.token(piece)
                }
            }.joined(separator: " ")
        }
    }

    public static func token(_ piece: DistillPiece) -> String {
        switch piece.shape {
        case .empty: return "."
        case .cross: return "X" + (piece.fixed ? "*" : "")
        default: return piece.shape.letter + String(piece.rotation) + (piece.fixed ? "*" : "")
        }
    }

    static func piece(token: String) -> DistillPiece? {
        var t = Substring(token)
        var fixed = false
        if t.hasSuffix("*") { fixed = true; t = t.dropLast() }
        guard let first = t.first else { return nil }
        if first == "S" || first == "F" { return t.count == 1 && !fixed ? .empty : nil }
        guard let shape = DistillShape(letter: first) else { return nil }
        if shape == .empty || shape == .cross {
            guard t.count == 1, !(shape == .empty && fixed) else { return nil }
            return DistillPiece(shape, fixed: fixed)
        }
        guard t.count == 2, let r = Int(String(t.last!)), (0...3).contains(r) else { return nil }
        return DistillPiece(shape, rotation: r, fixed: fixed)
    }
}

/// A problem found by `validate()`.
public struct DistillIssue: Hashable, Sendable, CustomStringConvertible {
    public var level: String
    public var message: String
    public var description: String { "\(level): \(message)" }
}

/// Highest palette color index the app can draw (12 colors).
public let distillPaletteSize = 12

extension DistillLevel {
    /// Structural checks (no solving): sizes, tokens, sources/targets, valves, coils, colors.
    public func validate() -> [DistillIssue] {
        var out: [String] = []
        let b = board
        if !(DistillBoard.minSide...DistillBoard.maxSide).contains(b.width) || !(DistillBoard.minSide...DistillBoard.maxSide).contains(b.height) {
            out.append("board \(b.width)x\(b.height) outside \(DistillBoard.minSide)…\(DistillBoard.maxSide)")
        }
        if b.pieces.count != b.width * b.height { out.append("piece count") }
        if b.sources.isEmpty { out.append("no source") }
        if b.targets.isEmpty { out.append("no target") }
        var used = Set<DistillPos>()
        for (kind, pos, dir, color) in b.sources.map({ ("source", $0.pos, $0.outlet, $0.color) }) + b.targets.map({ ("target", $0.pos, $0.inlet, $0.color) }) {
            if !b.contains(pos) { out.append("\(kind) \(pos) off the board"); continue }
            if !used.insert(pos).inserted { out.append("two things on \(pos)") }
            if b[pos] != .empty { out.append("\(kind) \(pos) on a piece") }
            if !b.contains(pos.moved(dir)) { out.append("\(kind) \(pos) faces the edge") }
            if !(0..<distillPaletteSize).contains(color.rawValue) { out.append("\(kind) \(pos) color \(color.rawValue)") }
        }
        if let marks = tokenMarks {
            for i in marks.indices where marks[i] != " " {
                let p = b.pos(i)
                let ok = marks[i] == "S" ? b.sources.contains { $0.pos == p } : b.targets.contains { $0.pos == p }
                if !ok { out.append("grid \(marks[i]) at \(p) without a matching entry") }
            }
            for s in b.sources where b.contains(s.pos) && marks[b.index(s.pos)] != "S" { out.append("source \(s.pos) not marked S") }
            for t in b.targets where b.contains(t.pos) && marks[b.index(t.pos)] != "F" { out.append("target \(t.pos) not marked F") }
        }
        for i in 0..<b.pieces.count {
            let piece = b.pieces[i], p = b.pos(i)
            if let v = piece.valve {
                if !b.targets.indices.contains(v) { out.append("valve \(p) links missing target \(v)") }
                if ![.straight, .elbow, .tee].contains(piece.shape) { out.append("valve \(p) on a \(piece.shape)") }
            }
            if let coil = piece.coil {
                if ![.straight, .elbow, .tee].contains(piece.shape) { out.append("coil \(p) on a \(piece.shape)") }
                if coil.from == coil.to { out.append("coil \(p) keeps its color") }
                if !(0..<distillPaletteSize).contains(coil.from.rawValue) || !(0..<distillPaletteSize).contains(coil.to.rawValue) {
                    out.append("coil \(p) color")
                }
                if piece.valve != nil { out.append("coil and valve on \(p)") }
            }
        }
        if minTaps < 1 { out.append("minTaps \(minTaps) (the level starts solved?)") }
        return out.map { DistillIssue(level: id, message: $0) }
    }

    /// `validate()` plus the solver: solvable, minimum equals `minTaps`, and (when `requireUnique`) one network.
    public func validateSolving(requireUnique: Bool = true, limits: DistillSolverLimits = .init()) -> [DistillIssue] {
        var issues = validate()
        guard issues.isEmpty else { return issues }
        if board.isWon { issues.append(DistillIssue(level: id, message: "starts won")) }
        let result = DistillSolver.solve(board, limits: limits)
        if !result.complete { issues.append(DistillIssue(level: id, message: "solver limit hit")) }
        if let m = result.minTaps {
            if m != minTaps { issues.append(DistillIssue(level: id, message: "minTaps \(minTaps), solver \(m)")) }
        } else {
            issues.append(DistillIssue(level: id, message: "unsolvable"))
        }
        if requireUnique && result.solutionCount != 1 {
            issues.append(DistillIssue(level: id, message: "\(result.solutionCount) solved networks"))
        }
        return issues
    }
}

/// A file of distillery levels (a workshop stage or a challenge pack).
public struct DistillPackFile: Hashable, Sendable, Codable {
    public static let formatName = "pourfect-distillery"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var id: String
    public var title: String
    public var levels: [DistillLevel]

    public init(id: String, title: String, levels: [DistillLevel]) {
        format = Self.formatName
        version = Self.currentVersion
        self.id = id
        self.title = title
        self.levels = levels
    }

    public static func decode(_ data: Data) throws -> DistillPackFile {
        let file = try JSONDecoder().decode(DistillPackFile.self, from: data)
        guard file.format == formatName else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "format \(file.format)"))
        }
        guard file.version <= currentVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "version \(file.version) is newer"))
        }
        return file
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    public func validate() -> [DistillIssue] {
        var issues: [DistillIssue] = []
        if format != Self.formatName { issues.append(DistillIssue(level: id, message: "format \(format)")) }
        if version != Self.currentVersion { issues.append(DistillIssue(level: id, message: "version \(version)")) }
        var ids = Set<String>()
        for level in levels {
            if !ids.insert(level.id).inserted { issues.append(DistillIssue(level: level.id, message: "duplicate id")) }
            issues += level.validate()
        }
        return issues
    }
}
