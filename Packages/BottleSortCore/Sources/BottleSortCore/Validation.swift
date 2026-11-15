public enum ValidationError: Error, Hashable, Sendable, CustomStringConvertible {
    case noBottles
    case inconsistentCapacity(bottle: Int, capacity: Int, expected: Int)
    case invalidCapacity(Int)
    case overfilled(bottle: Int, count: Int, capacity: Int)
    case wrongColorCount(color: ColorID, count: Int, expected: Int)
    case negativeColor(ColorID)
    /// The same key id appears as a key layer more than once.
    case duplicateKey(KeyID)
    /// More than one bottle is locked by the same key id.
    case duplicateLock(KeyID)
    /// A bottle is locked but no key layer opens it.
    case lockWithoutKey(KeyID)
    /// A key layer has no bottle locked by it.
    case keyWithoutLock(KeyID)

    public var description: String {
        switch self {
        case .noBottles: return "level has no bottles"
        case let .inconsistentCapacity(b, c, e): return "bottle \(b) has capacity \(c), expected \(e)"
        case let .invalidCapacity(c): return "invalid capacity \(c)"
        case let .overfilled(b, n, c): return "bottle \(b) holds \(n) layers but capacity is \(c)"
        case let .wrongColorCount(color, n, e): return "color \(color.rawValue) has \(n) layers, expected \(e)"
        case let .negativeColor(c): return "negative color id \(c.rawValue)"
        case let .duplicateKey(k): return "key \(k.rawValue) appears more than once"
        case let .duplicateLock(k): return "more than one bottle is locked by key \(k.rawValue)"
        case let .lockWithoutKey(k): return "lock \(k.rawValue) has no matching key"
        case let .keyWithoutLock(k): return "key \(k.rawValue) has no matching lock"
        }
    }
}

extension GameState {
    /// Structural checks: consistent capacity, no overfilled bottle,
    /// every color appears exactly `capacity` times, and keys and locks pair
    /// up one-to-one (each key id at most once as a layer and once as a lock).
    public func validate() -> [ValidationError] {
        guard let capacity = bottles.first?.capacity else { return [.noBottles] }
        var errors: [ValidationError] = []
        if capacity < 1 { errors.append(.invalidCapacity(capacity)) }
        var counts: [ColorID: Int] = [:]
        var keyCounts: [KeyID: Int] = [:]
        var lockCounts: [KeyID: Int] = [:]
        for (i, bottle) in bottles.enumerated() {
            if bottle.capacity != capacity {
                errors.append(.inconsistentCapacity(bottle: i, capacity: bottle.capacity, expected: capacity))
            }
            if bottle.layers.count > bottle.capacity {
                errors.append(.overfilled(bottle: i, count: bottle.layers.count, capacity: bottle.capacity))
            }
            if let lock = bottle.lockedBy { lockCounts[lock, default: 0] += 1 }
            for layer in bottle.layers {
                if let c = layer.colorID { counts[c, default: 0] += 1 }
                if let k = layer.keyID { keyCounts[k, default: 0] += 1 }
            }
        }
        for (color, n) in counts.sorted(by: { $0.key < $1.key }) {
            if color.rawValue < 0 { errors.append(.negativeColor(color)) }
            if n != capacity { errors.append(.wrongColorCount(color: color, count: n, expected: capacity)) }
        }
        for (key, n) in keyCounts.sorted(by: { $0.key < $1.key }) {
            if n > 1 { errors.append(.duplicateKey(key)) }
            if lockCounts[key] == nil { errors.append(.keyWithoutLock(key)) }
        }
        for (key, n) in lockCounts.sorted(by: { $0.key < $1.key }) {
            if n > 1 { errors.append(.duplicateLock(key)) }
            if keyCounts[key] == nil { errors.append(.lockWithoutKey(key)) }
        }
        return errors
    }
}
