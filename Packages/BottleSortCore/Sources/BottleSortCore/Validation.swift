public enum ValidationError: Error, Hashable, Sendable, CustomStringConvertible {
    case noBottles
    case inconsistentCapacity(bottle: Int, capacity: Int, expected: Int)
    case invalidCapacity(Int)
    case overfilled(bottle: Int, count: Int, capacity: Int)
    case wrongColorCount(color: ColorID, count: Int, expected: Int)
    case negativeColor(ColorID)
    /// A color id above `StateKey.maxColorID` (the solver can't encode it).
    case colorOutOfRange(ColorID)
    /// A key or lock id outside `0...StateKey.maxKeyID` (the solver can't encode it).
    case keyOutOfRange(KeyID)
    /// The key for this lock can never be reached: it sits inside the bottle it opens,
    /// or inside another bottle whose lock can't be opened (e.g. key A behind lock B,
    /// key B behind lock A).
    case unopenableLock(KeyID)
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
        case let .colorOutOfRange(c): return "color id \(c.rawValue) is above \(StateKey.maxColorID)"
        case let .keyOutOfRange(k): return "key/lock id \(k.rawValue) is outside 0...\(StateKey.maxKeyID)"
        case let .unopenableLock(k): return "lock \(k.rawValue) can never be opened (its key is locked away behind it)"
        case let .duplicateKey(k): return "key \(k.rawValue) appears more than once"
        case let .duplicateLock(k): return "more than one bottle is locked by key \(k.rawValue)"
        case let .lockWithoutKey(k): return "lock \(k.rawValue) has no matching key"
        case let .keyWithoutLock(k): return "key \(k.rawValue) has no matching lock"
        }
    }
}

extension GameState {
    /// Structural checks: consistent capacity (1...`StateKey.maxCapacity`), no
    /// overfilled bottle, every color appears exactly `capacity` times, color and
    /// key ids fit the solver's encoding, keys and locks pair up one-to-one (each
    /// key id at most once as a layer and once as a lock), and every lock's key can
    /// be reached (not behind its own lock, directly or through a cycle of locks).
    public func validate() -> [ValidationError] {
        guard let capacity = bottles.first?.capacity else { return [.noBottles] }
        var errors: [ValidationError] = []
        if !(1...StateKey.maxCapacity).contains(capacity) { errors.append(.invalidCapacity(capacity)) }
        var counts: [ColorID: Int] = [:]
        var keyCounts: [KeyID: Int] = [:]
        var lockCounts: [KeyID: Int] = [:]
        /// Every key layer with the lock of the bottle it sits in (nil = unlocked bottle).
        var keyHomes: [(key: KeyID, home: KeyID?)] = []
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
                if let k = layer.keyID {
                    keyCounts[k, default: 0] += 1
                    keyHomes.append((k, bottle.lockedBy))
                }
            }
        }
        for (color, n) in counts.sorted(by: { $0.key < $1.key }) {
            if color.rawValue < 0 { errors.append(.negativeColor(color)) }
            if color.rawValue > StateKey.maxColorID { errors.append(.colorOutOfRange(color)) }
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
        for key in Set(keyCounts.keys).union(lockCounts.keys).sorted()
        where !(0...StateKey.maxKeyID).contains(key.rawValue) {
            errors.append(.keyOutOfRange(key))
        }
        // Locks that can be opened: start from keys in unlocked bottles, then keep
        // adding keys whose bottle's lock is already openable.
        var openable: Set<KeyID> = []
        var changed = true
        while changed {
            changed = false
            for (key, home) in keyHomes where !openable.contains(key) {
                if home.map(openable.contains) ?? true {
                    openable.insert(key)
                    changed = true
                }
            }
        }
        for key in lockCounts.keys.sorted() where keyCounts[key] != nil && !openable.contains(key) {
            errors.append(.unopenableLock(key))
        }
        return errors
    }
}
