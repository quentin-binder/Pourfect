public enum ValidationError: Error, Hashable, Sendable, CustomStringConvertible {
    case noBottles
    case inconsistentCapacity(bottle: Int, capacity: Int, expected: Int)
    case invalidCapacity(Int)
    case overfilled(bottle: Int, count: Int, capacity: Int)
    case wrongColorCount(color: ColorID, count: Int, expected: Int)
    case negativeColor(ColorID)

    public var description: String {
        switch self {
        case .noBottles: return "level has no bottles"
        case let .inconsistentCapacity(b, c, e): return "bottle \(b) has capacity \(c), expected \(e)"
        case let .invalidCapacity(c): return "invalid capacity \(c)"
        case let .overfilled(b, n, c): return "bottle \(b) holds \(n) layers but capacity is \(c)"
        case let .wrongColorCount(color, n, e): return "color \(color.rawValue) has \(n) layers, expected \(e)"
        case let .negativeColor(c): return "negative color id \(c.rawValue)"
        }
    }
}

extension GameState {
    /// Structural checks: consistent capacity, no overfilled bottle,
    /// and every color appears exactly `capacity` times.
    public func validate() -> [ValidationError] {
        guard let capacity = bottles.first?.capacity else { return [.noBottles] }
        var errors: [ValidationError] = []
        if capacity < 1 { errors.append(.invalidCapacity(capacity)) }
        var counts: [ColorID: Int] = [:]
        for (i, bottle) in bottles.enumerated() {
            if bottle.capacity != capacity {
                errors.append(.inconsistentCapacity(bottle: i, capacity: bottle.capacity, expected: capacity))
            }
            if bottle.layers.count > bottle.capacity {
                errors.append(.overfilled(bottle: i, count: bottle.layers.count, capacity: bottle.capacity))
            }
            for layer in bottle.layers {
                if let c = layer.colorID { counts[c, default: 0] += 1 }
            }
        }
        for (color, n) in counts.sorted(by: { $0.key < $1.key }) {
            if color.rawValue < 0 { errors.append(.negativeColor(color)) }
            if n != capacity { errors.append(.wrongColorCount(color: color, count: n, expected: capacity)) }
        }
        return errors
    }
}
