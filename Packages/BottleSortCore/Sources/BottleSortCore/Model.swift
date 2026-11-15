// Pure game model. No UI frameworks may be imported in this module.

/// Identifies a liquid color. Plain integer, so levels stay compact in JSON.
public struct ColorID: RawRepresentable, Hashable, Codable, Comparable, Sendable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.rawValue = value }
    public static func < (a: ColorID, b: ColorID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { "c\(rawValue)" }
}

/// Identifies a key / lock pair (used by the locks & keys mechanic, Phase 5).
public struct KeyID: RawRepresentable, Hashable, Codable, Comparable, Sendable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.rawValue = value }
    public static func < (a: KeyID, b: KeyID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { "k\(rawValue)" }
}

/// One unit of content in a bottle.
///
/// JSON form (level files): a color layer is a plain integer, a key layer is
/// an object `{"key": n}`.
public enum Layer: Hashable, Codable, Sendable, CustomStringConvertible {
    case color(ColorID)
    /// A key: occupies one slot, moves alone, and opens the bottle locked by the same id.
    case key(KeyID)

    private enum CodingKeys: String, CodingKey { case key }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let n = try? container.decode(Int.self) {
            self = .color(ColorID(n))
            return
        }
        let object = try decoder.container(keyedBy: CodingKeys.self)
        self = .key(KeyID(try object.decode(Int.self, forKey: .key)))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .color(let c):
            var container = encoder.singleValueContainer()
            try container.encode(c.rawValue)
        case .key(let k):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(k.rawValue, forKey: .key)
        }
    }

    /// The color of this layer, or nil if it is not a color layer.
    public var colorID: ColorID? {
        if case .color(let c) = self { return c }
        return nil
    }

    /// The key id of this layer, or nil if it is not a key layer.
    public var keyID: KeyID? {
        if case .key(let k) = self { return k }
        return nil
    }

    public var isKey: Bool { keyID != nil }

    public var description: String {
        switch self {
        case .color(let c): return "\(c.rawValue)"
        case .key(let k): return k.description
        }
    }
}

/// A bottle: a stack of layers, bottom → top.
public struct Bottle: Hashable, Codable, Sendable, CustomStringConvertible {
    public var layers: [Layer]
    public let capacity: Int
    public var lockedBy: KeyID?

    public init(layers: [Layer] = [], capacity: Int, lockedBy: KeyID? = nil) {
        self.layers = layers
        self.capacity = capacity
        self.lockedBy = lockedBy
    }

    /// Convenience: build from color numbers, bottom → top.
    public init(_ colors: [Int], capacity: Int, lockedBy: KeyID? = nil) {
        self.init(layers: colors.map { .color(ColorID($0)) }, capacity: capacity, lockedBy: lockedBy)
    }

    public var isEmpty: Bool { layers.isEmpty }
    public var isFull: Bool { layers.count >= capacity }
    public var freeSpace: Int { max(0, capacity - layers.count) }
    public var topLayer: Layer? { layers.last }

    /// Number of contiguous identical layers at the top (0 if empty).
    /// Note: what actually moves in a pour is `Rules.movableRunCount` (a key always moves alone).
    public var topRunCount: Int {
        guard let top = layers.last else { return 0 }
        var n = 0
        for layer in layers.reversed() {
            guard layer == top else { break }
            n += 1
        }
        return n
    }

    /// Empty, or full with a single color. See `Rules.isSolved(_:)`.
    public var isSolved: Bool { Rules.isSolved(self) }

    public var description: String {
        let lock = lockedBy.map { "🔒\($0.rawValue)" } ?? ""
        return lock + "[" + layers.map(\.description).joined(separator: ",") + "]/\(capacity)"
    }
}

/// Pour from bottle index `from` into bottle index `to`.
public struct Move: Hashable, Codable, Sendable, CustomStringConvertible {
    public let from: Int
    public let to: Int
    public init(from: Int, to: Int) { self.from = from; self.to = to }
    public var description: String { "\(from)→\(to)" }
}

/// The full board.
public struct GameState: Hashable, Codable, Sendable, CustomStringConvertible {
    public var bottles: [Bottle]
    public init(bottles: [Bottle]) { self.bottles = bottles }

    public var description: String { bottles.map(\.description).joined(separator: " ") }
}

extension GameState {
    /// The same puzzle with its bottles in a random order. Bottle order never changes the puzzle
    /// (same canonical key, same optimal solution length), so this is purely presentation, e.g. so
    /// empty bottles aren't always at the end.
    public func shufflingBottles<G: RandomNumberGenerator>(using rng: inout G) -> GameState {
        GameState(bottles: bottles.shuffled(using: &rng))
    }
}
