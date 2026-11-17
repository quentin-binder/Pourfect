/// Match-3 "ingredient gathering" model (R9). Pure value types; all rules live in M3Rules.swift.
///
/// Coordinates: `row` 0 is the TOP row, `col` 0 the left column; gravity pulls towards higher rows.

/// One of the six lab ingredients. Raw values are the JSON names; `index` is the stable order
/// used for ties (lowest index wins) and for `collected` counters.
public enum M3Kind: String, Codable, CaseIterable, Sendable, Hashable, Comparable {
    case mushroom, crystal, feather, moonflower, ember, drop

    public var index: Int {
        switch self {
        case .mushroom: 0
        case .crystal: 1
        case .feather: 2
        case .moonflower: 3
        case .ember: 4
        case .drop: 5
        }
    }

    public init?(index: Int) {
        guard (0..<6).contains(index) else { return nil }
        self = M3Kind.allCases[index]
    }

    /// English display name ("Moonflower"); the app localizes its own labels.
    public var name: String {
        switch self {
        case .mushroom: "Mushroom"
        case .crystal: "Crystal"
        case .feather: "Feather"
        case .moonflower: "Moonflower"
        case .ember: "Ember"
        case .drop: "Potion Drop"
        }
    }

    public static func < (a: M3Kind, b: M3Kind) -> Bool { a.index < b.index }
}

/// Special pieces. JSON names: "row", "column", "bloom", "prism".
/// - `row` / `column` ("Comet"): clears its whole row / column.
/// - `bloom`: clears the 3×3 square around it.
/// - `prism`: has no ingredient kind; clears every piece of one kind.
public enum M3Special: String, Codable, Sendable, Hashable, CaseIterable {
    case row, column, bloom, prism

    public var isLine: Bool { self == .row || self == .column }
}

/// An ingredient piece. `kind` is nil only for a prism. `frost` is the number of ice layers
/// (0…2) encasing it: frozen pieces can't be swapped and are never cleared while frozen.
public struct M3Piece: Codable, Sendable, Hashable {
    public var kind: M3Kind?
    public var special: M3Special?
    public var frost: Int

    public init(kind: M3Kind?, special: M3Special? = nil, frost: Int = 0) {
        self.kind = kind
        self.special = special
        self.frost = frost
    }

    public static func prism() -> M3Piece { M3Piece(kind: nil, special: .prism) }

    public var isFrozen: Bool { frost > 0 }
    public var isPrism: Bool { special == .prism }
}

/// What occupies an open cell.
public enum M3Item: Sendable, Hashable {
    case piece(M3Piece)
    /// A potion flask (drop-down goal item): falls, can't be swapped, matched or blasted.
    case flask

    public var piece: M3Piece? {
        if case .piece(let p) = self { return p }
        return nil
    }

    public var isFlask: Bool { self == .flask }
}

/// One board cell. `exists == false` is a hole in the board mask (never holds anything).
/// `crate > 0` is a sealed crate with that many hits left (then `item` is nil).
public struct M3Cell: Sendable, Hashable {
    public var exists: Bool
    public var crate: Int
    public var item: M3Item?

    public init(exists: Bool = true, crate: Int = 0, item: M3Item? = nil) {
        self.exists = exists
        self.crate = crate
        self.item = item
    }

    /// Part of a column's gravity stack: an existing cell without a crate.
    public var isOpen: Bool { exists && crate == 0 }
    public var piece: M3Piece? { item?.piece }
}

public struct M3Pos: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public var row: Int
    public var col: Int

    public init(_ row: Int, _ col: Int) {
        self.row = row
        self.col = col
    }

    public init(row: Int, col: Int) { self.init(row, col) }

    /// Row-major order (top row first, then left to right).
    public static func < (a: M3Pos, b: M3Pos) -> Bool { (a.row, a.col) < (b.row, b.col) }

    public var description: String { "(\(row),\(col))" }

    public func isAdjacent(to other: M3Pos) -> Bool { abs(row - other.row) + abs(col - other.col) == 1 }
}

/// A player swap: the piece at `from` is dragged onto `to` (orthogonal neighbours).
public struct M3Swap: Codable, Sendable, Hashable, CustomStringConvertible {
    public var from: M3Pos
    public var to: M3Pos

    public init(_ from: M3Pos, _ to: M3Pos) {
        self.from = from
        self.to = to
    }

    public var isHorizontal: Bool { from.row == to.row }
    public var description: String { "\(from)->\(to)" }
}

/// The board grid (≤ 8×8), row-major.
public struct M3Board: Sendable, Hashable {
    public static let maxSize = 8

    public let width: Int
    public let height: Int
    public var cells: [M3Cell]

    public init(width: Int, height: Int, cells: [M3Cell]) {
        precondition(cells.count == width * height)
        self.width = width
        self.height = height
        self.cells = cells
    }

    @inline(__always) public func index(_ p: M3Pos) -> Int { p.row * width + p.col }
    @inline(__always) public func pos(_ i: Int) -> M3Pos { M3Pos(i / width, i % width) }

    public func contains(_ p: M3Pos) -> Bool { p.row >= 0 && p.row < height && p.col >= 0 && p.col < width }

    public subscript(_ p: M3Pos) -> M3Cell {
        get { cells[index(p)] }
        set { cells[index(p)] = newValue }
    }

    public subscript(_ row: Int, _ col: Int) -> M3Cell {
        get { cells[row * width + col] }
        set { cells[row * width + col] = newValue }
    }

    public var positions: [M3Pos] { (0..<cells.count).map(pos) }

    /// Orthogonal neighbours inside the grid (they may be holes).
    public func neighbors(_ p: M3Pos) -> [M3Pos] {
        [M3Pos(p.row - 1, p.col), M3Pos(p.row + 1, p.col), M3Pos(p.row, p.col - 1), M3Pos(p.row, p.col + 1)]
            .filter(contains)
    }

    /// Open cells of column `col`, top to bottom (the column's gravity stack).
    public func openCells(column col: Int) -> [M3Pos] {
        (0..<height).compactMap { r in self[r, col].isOpen ? M3Pos(r, col) : nil }
    }

    /// The lowest open cell of a column (where a flask is collected), if any.
    public func bottomOpenCell(column col: Int) -> M3Pos? {
        for r in stride(from: height - 1, through: 0, by: -1) where self[r, col].isOpen { return M3Pos(r, col) }
        return nil
    }

    /// Whether the piece here can take part in a swap: a piece without frost.
    public func isSwappable(_ p: M3Pos) -> Bool {
        guard contains(p), let piece = self[p].piece else { return false }
        return !piece.isFrozen
    }

    public var frostLayers: Int { cells.reduce(0) { $0 + ($1.piece?.frost ?? 0) } }
    public var crateHits: Int { cells.reduce(0) { $0 + $1.crate } }
    public var flaskCount: Int { cells.reduce(0) { $0 + ($1.item == .flask ? 1 : 0) } }

    /// Compact text picture for tests and tools: `.` hole, `#n` crate, `F` flask, `_` empty open cell,
    /// a piece is its kind letter (m c f o e d; `*` prism) followed by `-` row, `|` column, `+` bloom,
    /// and `~`/`=` for 1/2 frost layers. Cells are separated by spaces.
    public var picture: String {
        var lines: [String] = []
        for r in 0..<height {
            var tokens: [String] = []
            for c in 0..<width {
                let cell = self[r, c]
                if !cell.exists { tokens.append("."); continue }
                if cell.crate > 0 { tokens.append("#\(cell.crate)"); continue }
                switch cell.item {
                case nil: tokens.append("_")
                case .flask: tokens.append("F")
                case .piece(let p): tokens.append(M3Board.token(p))
                }
            }
            lines.append(tokens.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    static let kindLetters: [Character] = ["m", "c", "f", "o", "e", "d"]

    static func token(_ p: M3Piece) -> String {
        var s = p.kind.map { String(kindLetters[$0.index]) } ?? "*"
        switch p.special {
        case .row: s += "-"
        case .column: s += "|"
        case .bloom: s += "+"
        case .prism, nil: break
        }
        if p.frost == 1 { s += "~" } else if p.frost >= 2 { s += "=" }
        return s
    }

    /// Parses `picture` (used by tests to build exact boards).
    public init(picture: String) {
        let rows = picture.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
        let h = rows.count, w = rows.first?.count ?? 0
        var cells: [M3Cell] = []
        for row in rows {
            precondition(row.count == w, "ragged picture")
            for t in row { cells.append(M3Board.parseToken(t)) }
        }
        self.init(width: w, height: h, cells: cells)
    }

    static func parseToken(_ t: String) -> M3Cell {
        if t == "." { return M3Cell(exists: false) }
        if t == "_" { return M3Cell() }
        if t == "F" { return M3Cell(item: .flask) }
        if t.hasPrefix("#") { return M3Cell(crate: Int(t.dropFirst()) ?? 1) }
        var chars = Array(t)
        var kind: M3Kind? = nil
        var special: M3Special? = nil
        if chars[0] == "*" { special = .prism } else if let k = kindLetters.firstIndex(of: chars[0]) { kind = M3Kind(index: k) } else {
            preconditionFailure("bad token \(t)")
        }
        chars.removeFirst()
        var frost = 0
        for ch in chars {
            switch ch {
            case "-": special = .row
            case "|": special = .column
            case "+": special = .bloom
            case "~": frost = 1
            case "=": frost = 2
            default: preconditionFailure("bad token \(t)")
            }
        }
        return M3Cell(item: .piece(M3Piece(kind: kind, special: special, frost: frost)))
    }
}
