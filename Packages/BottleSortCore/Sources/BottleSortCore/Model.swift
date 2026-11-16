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

/// A bottle: a stack of layers, bottom → top, plus the modifiers it carries.
public struct Bottle: Hashable, Sendable, CustomStringConvertible {
    public var layers: [Layer]
    public let capacity: Int
    /// The modifiers, stored compactly: a plain or sealed flask (every shipped level) holds
    /// no array, so copying a bottle costs no more than before modifiers existed. Always
    /// normalized (see `modifiers`), so the synthesized equality is set equality.
    var storage: ModifierStorage

    enum ModifierStorage: Hashable, Sendable {
        case none
        case sealed(KeyID)
        /// Normalized, and never empty or a lone seal.
        case list([BottleModifier])

        init(_ normalized: [BottleModifier]) {
            if normalized.isEmpty {
                self = .none
            } else if normalized.count == 1, case .sealed(let key) = normalized[0] {
                self = .sealed(key)
            } else {
                self = .list(normalized)
            }
        }
    }

    public init(layers: [Layer] = [], capacity: Int, modifiers: [BottleModifier]) {
        self.layers = layers
        self.capacity = capacity
        self.storage = ModifierStorage(Bottle.normalize(modifiers))
    }

    public init(layers: [Layer] = [], capacity: Int, lockedBy: KeyID? = nil) {
        self.layers = layers
        self.capacity = capacity
        self.storage = lockedBy.map(ModifierStorage.sealed) ?? .none
    }

    /// Convenience: build from color numbers, bottom → top.
    public init(_ colors: [Int], capacity: Int, lockedBy: KeyID? = nil) {
        self.init(layers: colors.map { .color(ColorID($0)) }, capacity: capacity, lockedBy: lockedBy)
    }

    /// What this flask carries (seal, essence rune, …), as a set: always deduplicated and
    /// sorted in `BottleModifier.canonicalOrder` (setting normalizes), so equal sets
    /// compare equal. Empty for a plain flask. The rules for each case live in `Rules`.
    public var modifiers: [BottleModifier] {
        get {
            switch storage {
            case .none: return []
            case .sealed(let key): return [.sealed(key)]
            case .list(let list): return list
            }
        }
        set { storage = ModifierStorage(Bottle.normalize(newValue)) }
    }

    /// Whether the flask carries no modifier at all.
    public var isPlain: Bool {
        if case .none = storage { return true }
        return false
    }

    /// Whether every modifier is *static* (`BottleModifier.isStatic`): no state of its own,
    /// nothing that changes between moves. True for a plain flask.
    var hasOnlyStaticModifiers: Bool {
        if case .list(let list) = storage { return list.allSatisfy(\.isStatic) }
        return true
    }

    /// For the solver's pruning: `ok` is whether every modifier is static, a frozen layer
    /// (D1) or bubbling (D2); `frozen` whether the flask holds a frozen layer, `bubbling`
    /// whether it bubbles.
    var pruningKind: (ok: Bool, frozen: Bool, bubbling: Bool) {
        guard case .list(let list) = storage else { return (true, false, false) }
        var frozen = false, bubbling = false
        for modifier in list {
            switch modifier {
            case .frozen: frozen = true
            case .bubbling: bubbling = true
            default: if !modifier.isStatic { return (false, frozen, bubbling) }
            }
        }
        return (true, frozen, bubbling)
    }

    /// D2: the flask's bubbling period and phase, or nil if it doesn't bubble. For the
    /// app's bubbles and gauge.
    public var bubbling: Bubbling? {
        guard case .list(let list) = storage else { return nil }
        for modifier in list {
            if case let .bubbling(every, phase) = modifier { return Bubbling(every: every, phase: phase) }
        }
        return nil
    }

    /// D2: whether the flask bubbles (its bottom layer rises to the top every few moves).
    public var isBubbling: Bool { bubbling != nil }

    /// D1: the frozen layers of this flask, bottom first (empty when it holds no ice).
    /// For the app's ice overlay and counter.
    public var frozenLayers: [FrozenLayer] {
        guard case .list(let list) = storage else { return [] }
        return list.compactMap { modifier in
            if case let .frozen(layer, turns) = modifier { return FrozenLayer(layer: layer, turns: turns) }
            return nil
        }
    }

    /// D1: moves until layer `layer` (0 = bottom) thaws, or nil if it isn't frozen.
    public func thawTurns(atLayer layer: Int) -> Int? {
        frozenLayers.first { $0.layer == layer }?.turns
    }

    /// D1: whether the flask holds a frozen layer (the app's frost rim). Its frozen layers
    /// and everything below them can't move, and a tap flask can't pour.
    public var holdsIce: Bool {
        guard case .list(let list) = storage else { return false }
        return list.contains { if case .frozen = $0 { return true } else { return false } }
    }

    /// D1: whether the top layer is frozen: nothing can be poured into or out of the flask.
    public var isIcedOver: Bool {
        guard let top = layers.indices.last else { return false }
        return thawTurns(atLayer: top) != nil
    }

    /// Whether the flask carries `modifier` (e.g. `.narrowNeck`).
    @inline(__always)
    func has(_ modifier: BottleModifier) -> Bool {
        if case .list(let list) = storage { return list.contains(modifier) }
        return false
    }

    /// C2: the flask has a narrow neck (one layer per pour, in or out). For the app's collar.
    public var hasNarrowNeck: Bool { has(.narrowNeck) }
    /// C4: the flask carries a funnel (receives, never pours out). For the app's funnel.
    public var isFunnel: Bool { has(.funnel) }
    /// C4: the flask has a tap (pours from the bottom, never receives). For the app's spigot.
    public var hasTap: Bool { has(.tap) }

    /// Number of contiguous identical layers at the bottom (0 if empty). A tap pours this run.
    public var bottomRunCount: Int {
        guard let bottom = layers.first else { return 0 }
        var n = 0
        for layer in layers {
            guard layer == bottom else { break }
            n += 1
        }
        return n
    }

    /// The color of this flask's essence rune (C1): it receives only this color. nil for a
    /// flask without one. For the app's rune and tint.
    public var essenceColor: ColorID? {
        guard case .list(let list) = storage else { return nil }
        for modifier in list {
            if case .essence(let color) = modifier { return color }
        }
        return nil
    }

    /// The key of this flask's seal (its `.sealed` modifier), or nil if it isn't sealed.
    /// Compatibility accessor from before modifiers existed: setting it replaces the seal.
    public var lockedBy: KeyID? {
        get {
            switch storage {
            case .none: return nil
            case .sealed(let key): return key
            case .list(let list):
                for modifier in list {
                    if case .sealed(let key) = modifier { return key }
                }
                return nil
            }
        }
        set {
            if case .list = storage {
                var kept = modifiers.filter { !$0.isSeal }
                if let newValue { kept.append(.sealed(newValue)) }
                modifiers = kept
            } else {
                storage = newValue.map(ModifierStorage.sealed) ?? .none
            }
        }
    }

    /// Whether this flask carries a seal.
    public var isSealed: Bool { lockedBy != nil }

    static func normalize(_ modifiers: [BottleModifier]) -> [BottleModifier] {
        var result: [BottleModifier] = []
        for m in modifiers.map(\.normalized).sorted(by: BottleModifier.canonicalOrder) where result.last != m {
            result.append(m)
        }
        return result
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
        let others = Bottle.splitSeal(modifiers).others
        let extra = others.isEmpty ? "" : "{" + others.map(\.description).joined(separator: ",") + "}"
        return lock + extra + "[" + layers.map(\.description).joined(separator: ",") + "]/\(capacity)"
    }
}

extension BottleModifier {
    var isSeal: Bool {
        if case .sealed = self { return true }
        return false
    }

    /// A modifier that only decides what its flask accepts or gives (seal, essence): no
    /// state of its own, no change to how many layers move or from where.
    var isGate: Bool {
        switch self {
        case .sealed, .essence: return true
        case .narrowNeck, .funnel, .tap, .frozen, .bubbling, .cauldron: return false
        }
    }

    /// A modifier with no state of its own that never changes between moves: the gates plus
    /// the glass modifiers (narrow neck, funnel, tap), which change how many layers move and
    /// from which end, but only as a function of the two bottles of the pour. The solver's
    /// pruning rules hold for flasks that carry only these (`Solver.candidateMoves`,
    /// DECISIONS 133, 147), using the actual plan amount. A frozen layer is not static (its
    /// counter ticks every move); the solver keeps only rule 3 while one exists (DECISIONS 162).
    /// Bubbling isn't either (its phase ticks every move; DECISIONS 172).
    var isStatic: Bool {
        switch self {
        case .sealed, .essence, .narrowNeck, .funnel, .tap: return true
        case .frozen, .bubbling, .cauldron: return false
        }
    }
}

extension Bottle: Codable {
    // JSON: {"layers": […], "capacity": n, "lockedBy": k?, "modifiers": […]?}. The (first)
    // seal is written as `lockedBy`, the v1 form; `modifiers` holds every other modifier
    // and is omitted when there is none.
    private enum CodingKeys: String, CodingKey { case layers, capacity, lockedBy, modifiers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var modifiers = try c.decodeIfPresent([BottleModifier].self, forKey: .modifiers) ?? []
        if let lock = try c.decodeIfPresent(KeyID.self, forKey: .lockedBy) { modifiers.append(.sealed(lock)) }
        self.init(layers: try c.decode([Layer].self, forKey: .layers), capacity: try c.decode(Int.self, forKey: .capacity),
                  modifiers: modifiers)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layers, forKey: .layers)
        try c.encode(capacity, forKey: .capacity)
        let (lock, others) = Bottle.splitSeal(modifiers)
        try c.encodeIfPresent(lock, forKey: .lockedBy)
        if !others.isEmpty { try c.encode(others, forKey: .modifiers) }
    }

    /// The first seal's key (the v1 `lockedBy`) and every other modifier, in order.
    static func splitSeal(_ modifiers: [BottleModifier]) -> (lock: KeyID?, others: [BottleModifier]) {
        var lock: KeyID?
        var others: [BottleModifier] = []
        for m in modifiers {
            if case .sealed(let k) = m, lock == nil { lock = k } else { others.append(m) }
        }
        return (lock, others)
    }
}

/// D1: one frozen layer of a flask (`Bottle.frozenLayers`): its index (0 = bottom) and the
/// moves left until it thaws (1 = it thaws after the next move).
public struct FrozenLayer: Hashable, Sendable {
    public var layer: Int
    public var turns: Int
    public init(layer: Int, turns: Int) {
        self.layer = layer
        self.turns = turns
    }
}

/// D2: the bubbling state of a flask (`Bottle.bubbling`): its period and the moves made
/// since its last rise.
public struct Bubbling: Hashable, Sendable {
    /// The bottom layer rises every `every` moves (`Rules.bubblingPeriods`).
    public var every: Int
    /// Moves since the last rise (0..<every); the app's gauge shows `phase / every` filled.
    public var phase: Int
    public init(every: Int, phase: Int) {
        self.every = every
        self.phase = phase
    }

    /// Moves until the next rise, 1...every: 1 means the bottom layer rises after the next
    /// move (the gauge is one step from full).
    public var movesUntilRise: Int { max(1, every - phase) }
}

/// Pour from bottle index `from` into bottle index `to`.
public struct Move: Hashable, Codable, Sendable, CustomStringConvertible {
    public let from: Int
    public let to: Int
    public init(from: Int, to: Int) { self.from = from; self.to = to }
    public var description: String { "\(from)→\(to)" }
}

/// The full board: the bottles, plus level-wide links, the goal and counters.
///
/// Classic and sealed levels only use `bottles`: `links` is empty, `goal` is `.standard`
/// and `moveCount` is nil. Links and goal sit in one shared box that is nil for that
/// default, so a classic state is as cheap to copy as before.
public struct GameState: Hashable, Sendable, CustomStringConvertible {
    public var bottles: [Bottle]
    /// Moves made so far. Stored (non-nil) only while a rule depends on it (a timed
    /// mechanic or goal such as `.rescue`), because it makes otherwise equal states
    /// different for the solver. `Rules.resolve` increments it when present, up to
    /// `Rules.moveCountLimit` (so the state graph stays finite).
    public var moveCount: Int?
    private var structure: Structure?

    /// Static, level-wide data. A class so a state copy costs one reference.
    private final class Structure: Hashable, Sendable {
        let links: [Link]
        let goal: Goal
        init(links: [Link], goal: Goal) {
            self.links = links
            self.goal = goal
        }
        static func == (a: Structure, b: Structure) -> Bool { a === b || (a.links == b.links && a.goal == b.goal) }
        func hash(into hasher: inout Hasher) {
            hasher.combine(links)
            hasher.combine(goal)
        }
    }

    public init(bottles: [Bottle], links: [Link] = [], goal: Goal = .standard, moveCount: Int? = nil) {
        self.bottles = bottles
        self.moveCount = moveCount
        self.structure = GameState.box(links: links, goal: goal)
    }

    private static func box(links: [Link], goal: Goal) -> Structure? {
        links.isEmpty && goal == .standard ? nil : Structure(links: links, goal: goal)
    }

    /// Level-wide links between bottles (by index). Empty for classic levels.
    public var links: [Link] {
        get { structure?.links ?? [] }
        set { structure = GameState.box(links: newValue, goal: goal) }
    }

    /// When the level is won. `.standard` for classic levels.
    public var goal: Goal {
        get { structure?.goal ?? .standard }
        set { structure = GameState.box(links: links, goal: newValue) }
    }

    /// No links, the standard goal and no move counter: the state is described by its
    /// bottles alone (fast paths in `Rules`, `StateKey` and the solver).
    var isBottlesOnly: Bool { structure == nil && moveCount == nil }

    /// Whether the goal is `.standard` (without building the `Goal` value).
    var hasStandardGoal: Bool { structure.map { $0.goal == .standard } ?? true }

    public var description: String {
        var text = bottles.map(\.description).joined(separator: " ")
        if !links.isEmpty { text += " links[" + links.map(\.description).joined(separator: " ") + "]" }
        if goal != .standard { text += " goal:\(goal.name)" }
        if let moveCount { text += " moves:\(moveCount)" }
        return text
    }
}

extension GameState: Codable {
    // {"bottles": […]} as before; links, goal and moveCount only when they aren't the default.
    private enum CodingKeys: String, CodingKey { case bottles, links, goal, moveCount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bottles: try c.decode([Bottle].self, forKey: .bottles),
                  links: try c.decodeIfPresent([Link].self, forKey: .links) ?? [],
                  goal: try c.decodeIfPresent(Goal.self, forKey: .goal) ?? .standard,
                  moveCount: try c.decodeIfPresent(Int.self, forKey: .moveCount))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bottles, forKey: .bottles)
        if !links.isEmpty { try c.encode(links, forKey: .links) }
        if goal != .standard { try c.encode(goal, forKey: .goal) }
        try c.encodeIfPresent(moveCount, forKey: .moveCount)
    }
}

extension GameState {
    /// The same puzzle with its bottles in a random order. Bottle order never changes the puzzle
    /// (same canonical key, same optimal solution length), so this is purely presentation, e.g. so
    /// empty bottles aren't always at the end. Links and goal targets follow their bottles.
    public func shufflingBottles<G: RandomNumberGenerator>(using rng: inout G) -> GameState {
        var order = Array(bottles.indices)
        order.shuffle(using: &rng)   // same swaps as `bottles.shuffled(using:)`
        return permuted(by: order)
    }

    /// The same puzzle with `bottles[order[i]]` at position i; links and goal targets are
    /// renumbered so they follow their bottles. `order` must be a permutation of the indices.
    public func permuted(by order: [Int]) -> GameState {
        var newIndex = [Int](repeating: 0, count: order.count)
        for (i, old) in order.enumerated() { newIndex[old] = i }
        return GameState(bottles: order.map { bottles[$0] },
                         links: links.map { $0.remapped { newIndex[$0] } },
                         goal: goal.remapped { newIndex[$0] },
                         moveCount: moveCount)
    }
}
