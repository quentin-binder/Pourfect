import BottleSortCore

// The Distillery (R10): a pipe-rotation puzzle. Pure rules; the app draws and animates.
// DECISIONS 270–279.

/// A side of a cell. Clockwise order: north, east, south, west (raw 0…3).
public enum DistillDir: Int, CaseIterable, Sendable, Hashable, Codable, CustomStringConvertible {
    case north = 0, east, south, west

    /// Bit of this side in an opening mask (north 1, east 2, south 4, west 8).
    public var bit: UInt8 { 1 << UInt8(rawValue) }
    public var opposite: DistillDir { DistillDir(rawValue: (rawValue + 2) & 3)! }
    /// The next side clockwise.
    public var clockwise: DistillDir { DistillDir(rawValue: (rawValue + 1) & 3)! }
    public var dr: Int { [-1, 0, 1, 0][rawValue] }
    public var dc: Int { [0, 1, 0, -1][rawValue] }

    /// "n", "e", "s", "w" (the level files' spelling).
    public var letter: String { ["n", "e", "s", "w"][rawValue] }
    public init?(letter: String) {
        guard let i = ["n", "e", "s", "w"].firstIndex(of: letter) else { return nil }
        self.init(rawValue: i)
    }
    public var description: String { letter }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = DistillDir(letter: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad direction \(s)"))
        }
        self = d
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(letter)
    }
}

/// Opening masks (bit per `DistillDir`).
public enum DistillMask {
    /// The mask turned clockwise `quarterTurns` times (north → east).
    public static func rotate(_ mask: UInt8, by quarterTurns: Int) -> UInt8 {
        let r = UInt8(((quarterTurns % 4) + 4) % 4)
        guard r != 0 else { return mask & 15 }
        return ((mask << r) | (mask >> (4 - r))) & 15
    }
    public static func has(_ mask: UInt8, _ dir: DistillDir) -> Bool { mask & dir.bit != 0 }
    public static func dirs(_ mask: UInt8) -> [DistillDir] { DistillDir.allCases.filter { mask & $0.bit != 0 } }
    public static func count(_ mask: UInt8) -> Int { mask.nonzeroBitCount }
}

/// The shape of a brass pipe piece. Rotation 0 is the base orientation; each quarter turn is clockwise.
public enum DistillShape: String, CaseIterable, Sendable, Hashable, Codable {
    /// An empty cell (nothing to rotate, nothing flows).
    case empty
    /// End cap: one opening, closed at the other end. Liquid that reaches it stops there (no leak).
    case cap
    /// North–south pipe.
    case straight
    /// North–east bend.
    case elbow
    /// Splitter: north, east and south (closed to the west). One junction: every opening joins.
    case tee
    /// Two independent pipes crossing (north–south and east–west); they never mix. Rotation changes nothing.
    case cross

    public var baseMask: UInt8 {
        switch self {
        case .empty: 0
        case .cap: 0b0001
        case .straight: 0b0101
        case .elbow: 0b0011
        case .tee: 0b0111
        case .cross: 0b1111
        }
    }

    /// Orientations that look (and flow) differently: 1 for empty and cross, 2 for a straight, else 4.
    public var distinctRotations: Int {
        switch self {
        case .empty, .cross: 1
        case .straight: 2
        default: 4
        }
    }

    /// Level-file letter: "C", "I", "L", "T", "X" ("." is an empty cell).
    public var letter: String {
        switch self {
        case .empty: "."
        case .cap: "C"
        case .straight: "I"
        case .elbow: "L"
        case .tee: "T"
        case .cross: "X"
        }
    }

    public init?(letter: Character) {
        switch letter {
        case ".": self = .empty
        case "C": self = .cap
        case "I": self = .straight
        case "L": self = .elbow
        case "T": self = .tee
        case "X": self = .cross
        default: return nil
        }
    }

    /// The independent liquid channels (each an opening mask) at a rotation.
    public func channels(rotation: Int) -> [UInt8] {
        switch self {
        case .empty: []
        case .cross: [0b0101, 0b1010]
        default: [DistillMask.rotate(baseMask, by: rotation)]
        }
    }

    /// The shape whose single channel has exactly this mask (nil for 0 or 4 openings).
    public static func shape(forMask mask: UInt8) -> (shape: DistillShape, rotation: Int)? {
        for shape in [DistillShape.cap, .straight, .elbow, .tee] {
            for r in 0..<4 where DistillMask.rotate(shape.baseMask, by: r) == mask { return (shape, r) }
        }
        return nil
    }
}

/// A heat coil's recipe: liquid of color `from` passing through leaves as `to`; other colors pass unchanged.
public struct DistillCoil: Hashable, Sendable, Codable {
    public var from: ColorID
    public var to: ColorID
    public init(from: ColorID, to: ColorID) {
        self.from = from
        self.to = to
    }
    public func apply(_ color: ColorID) -> ColorID { color == from ? to : color }
}

/// One cell's piece.
public struct DistillPiece: Hashable, Sendable {
    public var shape: DistillShape
    /// Quarter turns clockwise from the base orientation, 0…3.
    public var rotation: Int
    /// Riveted: can't be turned.
    public var fixed: Bool
    /// A valve: index of the target flask that must be full (its own color, clean) before it opens.
    public var valve: Int?
    /// A heat coil.
    public var coil: DistillCoil?

    public init(_ shape: DistillShape, rotation: Int = 0, fixed: Bool = false, valve: Int? = nil, coil: DistillCoil? = nil) {
        self.shape = shape
        self.rotation = ((rotation % 4) + 4) % 4
        self.fixed = fixed
        self.valve = valve
        self.coil = coil
    }

    public static let empty = DistillPiece(.empty)

    /// Openings of the whole piece at its rotation.
    public var mask: UInt8 { shape == .cross ? 15 : DistillMask.rotate(shape.baseMask, by: rotation) }
    public var channels: [UInt8] { shape.channels(rotation: rotation) }
    /// Whether a tap changes anything (not riveted, and turning changes the openings).
    public var isRotatable: Bool { !fixed && shape.distinctRotations > 1 }
}

/// A cell position, row 0 at the top.
public struct DistillPos: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public var r: Int
    public var c: Int
    public init(_ r: Int, _ c: Int) {
        self.r = r
        self.c = c
    }
    public func moved(_ d: DistillDir) -> DistillPos { DistillPos(r + d.dr, c + d.dc) }
    public static func < (a: DistillPos, b: DistillPos) -> Bool { (a.r, a.c) < (b.r, b.c) }
    public var description: String { "(\(r),\(c))" }
}

/// A cauldron outlet: pours its color out of its cell through `outlet`.
public struct DistillSource: Hashable, Sendable, Codable {
    public var pos: DistillPos
    public var color: ColorID
    public var outlet: DistillDir
    public init(pos: DistillPos, color: ColorID, outlet: DistillDir) {
        self.pos = pos
        self.color = color
        self.outlet = outlet
    }
}

/// An empty target flask: takes liquid in through `inlet` and wants `color`.
public struct DistillTarget: Hashable, Sendable, Codable {
    public var pos: DistillPos
    public var color: ColorID
    public var inlet: DistillDir
    public init(pos: DistillPos, color: ColorID, inlet: DistillDir) {
        self.pos = pos
        self.color = color
        self.inlet = inlet
    }
}

/// What occupies a cell.
public enum DistillCellKind: Hashable, Sendable {
    case piece(DistillPiece)
    case source(Int)
    case target(Int)
}

/// The distillery board: a grid of pieces (row-major) plus sources and targets on their own cells
/// (whose piece is `.empty`).
public struct DistillBoard: Hashable, Sendable {
    public static let maxSide = 7
    public static let minSide = 3

    public var width: Int
    public var height: Int
    public var pieces: [DistillPiece]
    public var sources: [DistillSource]
    public var targets: [DistillTarget]

    public init(width: Int, height: Int, pieces: [DistillPiece], sources: [DistillSource], targets: [DistillTarget]) {
        self.width = width
        self.height = height
        self.pieces = pieces
        self.sources = sources
        self.targets = targets
    }

    public func contains(_ p: DistillPos) -> Bool { p.r >= 0 && p.r < height && p.c >= 0 && p.c < width }
    public func index(_ p: DistillPos) -> Int { p.r * width + p.c }
    public func pos(_ index: Int) -> DistillPos { DistillPos(index / width, index % width) }
    public var cellCount: Int { width * height }

    public subscript(_ p: DistillPos) -> DistillPiece {
        get { pieces[index(p)] }
        set { pieces[index(p)] = newValue }
    }

    public func kind(at p: DistillPos) -> DistillCellKind {
        if let i = sources.firstIndex(where: { $0.pos == p }) { return .source(i) }
        if let i = targets.firstIndex(where: { $0.pos == p }) { return .target(i) }
        return .piece(self[p])
    }

    /// The independent channels (opening masks) of a cell: a source's outlet, a target's inlet, a piece's channels.
    public func channels(at p: DistillPos) -> [UInt8] {
        switch kind(at: p) {
        case .source(let i): [sources[i].outlet.bit]
        case .target(let i): [targets[i].inlet.bit]
        case .piece(let piece): piece.channels
        }
    }

    /// Positions of every rotatable piece, row-major.
    public var rotatablePositions: [DistillPos] {
        (0..<cellCount).map(pos).filter { p in
            if case .piece(let piece) = kind(at: p) { return piece.isRotatable }
            return false
        }
    }

    /// Positions of the valves, row-major.
    public var valvePositions: [DistillPos] { (0..<cellCount).map(pos).filter { self[$0].valve != nil } }

    /// Every color on the board (sources, targets, coils), sorted.
    public var colors: [ColorID] {
        var set = Set<ColorID>()
        for s in sources { set.insert(s.color) }
        for t in targets { set.insert(t.color) }
        for p in pieces { if let coil = p.coil { set.insert(coil.from); set.insert(coil.to) } }
        return set.sorted()
    }
}

/// Taps needed to turn a piece from `from` to `to` quarter turns (clockwise taps and counter-clockwise
/// long-presses both count one): min(k, 4 − k) for k = (to − from) mod 4.
public func distillTapCost(from: Int, to: Int) -> Int {
    let k = ((to - from) % 4 + 4) % 4
    return min(k, 4 - k)
}

extension DistillPiece {
    /// The fewest taps that give this piece the opening mask `mask`, with the rotation that does it
    /// (nil when no rotation of the shape has that mask). A riveted piece costs 0 only at its own mask.
    public func cheapestTurn(to mask: UInt8) -> (taps: Int, rotation: Int)? {
        if shape == .cross || shape == .empty { return self.mask == mask ? (0, rotation) : nil }
        var best: (Int, Int)?
        for r in 0..<4 where DistillMask.rotate(shape.baseMask, by: r) == mask {
            if fixed && r != rotation { continue }
            let cost = distillTapCost(from: rotation, to: r)
            if best == nil || cost < best!.0 { best = (cost, r) }
        }
        return best.map { (taps: $0.0, rotation: $0.1) }
    }
}
