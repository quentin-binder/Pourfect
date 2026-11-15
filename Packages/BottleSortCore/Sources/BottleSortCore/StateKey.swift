/// A compact, bottle-order-independent key for a game state.
///
/// Each bottle is packed into one `UInt64`:
/// - bits 0..<54: up to 9 layers, 6 bits each, bottom first. Tokens:
///   0 = no layer, 1...47 = color `token - 1` (colors 0...46),
///   48...63 = key `token - 48` (keys 0...15),
/// - bits 56..<64: `lockedBy + 1` (0 = unlocked), so lock identity is part of the key.
/// The bottle codes are then sorted, so two states that differ only in the
/// order of their bottles produce the same key.
public struct StateKey: Hashable, Sendable {
    public let codes: [UInt64]

    public static let maxCapacity = 9
    public static let maxColorID = 46
    public static let maxKeyID = 15
    static let keyTokenBase: UInt64 = 48

    public init(_ state: GameState) {
        var codes = state.bottles.map(StateKey.code(for:))
        codes.sort()
        self.codes = codes
    }

    /// Whether `state` fits in the packed encoding.
    public static func canEncode(_ state: GameState) -> Bool {
        state.bottles.allSatisfy { bottle in
            bottle.capacity <= maxCapacity
                && bottle.layers.count <= maxCapacity
                && (bottle.lockedBy.map { (0...maxKeyID).contains($0.rawValue) } ?? true)
                && bottle.layers.allSatisfy { layer in
                    switch layer {
                    case .color(let c): return (0...maxColorID).contains(c.rawValue)
                    case .key(let k): return (0...maxKeyID).contains(k.rawValue)
                    }
                }
        }
    }

    static func token(for layer: Layer) -> UInt64 {
        switch layer {
        case .color(let c): return UInt64(c.rawValue + 1)
        case .key(let k): return keyTokenBase + UInt64(k.rawValue)
        }
    }

    static func code(for bottle: Bottle) -> UInt64 {
        var code: UInt64 = 0
        for (i, layer) in bottle.layers.enumerated() {
            code |= token(for: layer) << UInt64(6 * i)
        }
        if let lock = bottle.lockedBy {
            code |= UInt64(lock.rawValue + 1) << 56
        }
        return code
    }
}

extension GameState {
    /// Canonical key: equal for states that differ only in bottle order.
    public var canonicalKey: StateKey { StateKey(self) }
}
