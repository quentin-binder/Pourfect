// Mechanic types (R4 architecture). The *rules* for every case live in Rules.swift;
// this file only defines the data and its JSON form.
//
// How a new mechanic plugs in (see also DECISIONS 120–129):
// 1. Its case already exists here (or is added here): a `BottleModifier` for
//    something a flask carries, a `Link` for something between two flasks, a
//    `Goal` for a different win condition.
// 2. Rule code goes into the hook switches in Rules.swift (`Rules.apply(_:as:to:)`
//    for pours, `Rules.blocksSolved` for "is this flask done", the turn steps of
//    `Rules.resolve`), and the case is added to `isImplemented`.
// 3. StateKey (`StateKey.words(for:)`), JSON (`Codable` below) and validation already
//    know every case, so states stay canonical and levels round-trip from day one.

/// Something a flask carries that changes how pours into or out of it work.
///
/// A bottle's modifiers are a *set*: `Bottle` keeps them sorted in `canonicalOrder`,
/// so equal sets compare equal and encode identically.
///
/// Per-layer state (frozen layers) is a modifier too, `.frozen(layer:turns:)`, holding
/// the layer's index from the bottom. A frozen layer and everything below it can't
/// move, so that index stays valid while the layer is frozen. This keeps `Layer` a
/// plain value (runs, equality and the 6-bit layer tokens of `StateKey` unchanged).
public enum BottleModifier: Hashable, Sendable, CustomStringConvertible {
    /// A1 sealed flask: can't be poured from or into, except by key `KeyID`,
    /// which opens it (immediate effect "unseal"). Implemented; `Bottle.lockedBy` is
    /// its compatibility accessor.
    case sealed(KeyID)
    /// C1 essence flask: only receives this color. (R5)
    case essence(ColorID)
    /// C2 narrow neck: one layer per pour, in or out. (R5)
    case narrowNeck
    /// C4 funnel: receives, never pours out. (R5)
    case funnel
    /// C4 tap: pours from the bottom layer, never receives. (R5)
    case tap
    /// D1 frozen layer: layer `layer` (0 = bottom) and everything below it can't move;
    /// `turns` counts down after every move and the layer thaws at 0. (R5)
    case frozen(layer: Int, turns: Int)
    /// D2 bubbling flask: every `every` moves the bottom layer rises to the top;
    /// `phase` counts moves since the last rise (0..<every). (R5)
    case bubbling(every: Int, phase: Int)
    /// E1 mixing cauldron: pouring `a` onto `b` (or `b` onto `a`) inside it turns
    /// both layers into `result`. Recipes are kept sorted. (R5)
    case cauldron([Recipe])

    /// Whether `Rules` implements this modifier. Levels using an unimplemented one fail
    /// validation and the solver refuses them (`.unsupportedState`).
    public var isImplemented: Bool {
        switch self {
        case .sealed: return true
        case .essence, .narrowNeck, .funnel, .tap, .frozen, .bubbling, .cauldron: return false
        }
    }

    /// JSON `type` tag and short name.
    public var name: String {
        switch self {
        case .sealed: return "sealed"
        case .essence: return "essence"
        case .narrowNeck: return "narrowNeck"
        case .funnel: return "funnel"
        case .tap: return "tap"
        case .frozen: return "frozen"
        case .bubbling: return "bubbling"
        case .cauldron: return "cauldron"
        }
    }

    /// Stable tag, used for ordering and by `StateKey`. Never renumber.
    var tag: UInt64 {
        switch self {
        case .sealed: return 1
        case .essence: return 2
        case .narrowNeck: return 3
        case .funnel: return 4
        case .tap: return 5
        case .frozen: return 6
        case .bubbling: return 7
        case .cauldron: return 8
        }
    }

    /// Whether this modifier holds state that changes on its own as moves are made
    /// (handled in step 4 of `Rules.resolve`).
    public var isTimed: Bool {
        switch self {
        case .frozen, .bubbling: return true
        default: return false
        }
    }

    /// The same modifier in its canonical form (cauldron recipes sorted).
    public var normalized: BottleModifier {
        if case .cauldron(let recipes) = self { return .cauldron(recipes.sorted(by: Recipe.order)) }
        return self
    }

    /// Total order used to keep a bottle's modifiers sorted: by tag, then payload.
    static func canonicalOrder(_ a: BottleModifier, _ b: BottleModifier) -> Bool {
        let wa = StateKey.words(for: a), wb = StateKey.words(for: b)
        return wa.lexicographicallyPrecedes(wb)
    }

    public var description: String {
        switch self {
        case .sealed(let k): return "sealed(\(k.rawValue))"
        case .essence(let c): return "essence(\(c.rawValue))"
        case .narrowNeck, .funnel, .tap: return name
        case let .frozen(layer, turns): return "frozen(\(layer):\(turns))"
        case let .bubbling(every, phase): return "bubbling(\(every):\(phase))"
        case .cauldron(let recipes): return "cauldron(\(recipes.map(\.description).joined(separator: ",")))"
        }
    }
}

/// A mixing recipe: `a` + `b` → `result` (order of `a` and `b` doesn't matter).
public struct Recipe: Hashable, Codable, Sendable, CustomStringConvertible {
    public var a: ColorID
    public var b: ColorID
    public var result: ColorID
    public init(_ a: ColorID, _ b: ColorID, result: ColorID) {
        self.a = min(a, b)
        self.b = max(a, b)
        self.result = result
    }
    public var description: String { "\(a.rawValue)+\(b.rawValue)=\(result.rawValue)" }

    private enum CodingKeys: String, CodingKey { case a, b, result }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(ColorID.self, forKey: .a), try c.decode(ColorID.self, forKey: .b),
                  result: try c.decode(ColorID.self, forKey: .result))
    }

    static func order(_ x: Recipe, _ y: Recipe) -> Bool {
        (x.a, x.b, x.result) < (y.a, y.b, y.result)
    }
}

/// A level-wide connection between two flasks, by bottle index in `GameState.bottles`.
///
/// Links never move with canonical sorting: `StateKey` maps each endpoint to the
/// rank of its bottle in the canonical order (see `StateKey`), so the key stays
/// independent of bottle order.
public enum Link: Hashable, Sendable, CustomStringConvertible {
    /// F1 twin flasks: a pour into one also pours the same layers into the other. (R5)
    case twins(Int, Int)
    /// F2 overflow pipe: what doesn't fit into `from` flows on into `to`. (R5)
    case overflow(from: Int, to: Int)
    /// A3 switch → gate: while `switch` is complete, `gate` is open. The gate's state is
    /// derived from the switch's content, so it needs no stored state. (R5)
    case switchGate(switch: Int, gate: Int)

    public var isImplemented: Bool { false }

    /// The two bottles it connects, in declaration order.
    public var endpoints: (Int, Int) {
        switch self {
        case let .twins(a, b): return (a, b)
        case let .overflow(a, b): return (a, b)
        case let .switchGate(a, b): return (a, b)
        }
    }

    /// Whether swapping the endpoints gives the same link.
    public var isSymmetric: Bool {
        if case .twins = self { return true }
        return false
    }

    public var name: String {
        switch self {
        case .twins: return "twins"
        case .overflow: return "overflow"
        case .switchGate: return "switchGate"
        }
    }

    /// Stable tag, used by `StateKey`. Never renumber.
    var tag: UInt64 {
        switch self {
        case .twins: return 1
        case .overflow: return 2
        case .switchGate: return 3
        }
    }

    /// The same link with its endpoints renumbered by `map`.
    public func remapped(_ map: (Int) -> Int) -> Link {
        switch self {
        case let .twins(a, b): return .twins(map(a), map(b))
        case let .overflow(a, b): return .overflow(from: map(a), to: map(b))
        case let .switchGate(a, b): return .switchGate(switch: map(a), gate: map(b))
        }
    }

    public var description: String {
        let (a, b) = endpoints
        switch self {
        case .twins: return "\(a)⇄\(b)"
        case .overflow: return "\(a)⤳\(b)"
        case .switchGate: return "\(a)⊸\(b)"
        }
    }
}

/// A target for one flask in an order or pattern goal.
public struct GoalTarget: Hashable, Codable, Sendable {
    /// Bottle index in `GameState.bottles`.
    public var bottle: Int
    /// Required content, bottom → top (an order is `capacity` layers of one color).
    public var layers: [Layer]
    public init(bottle: Int, layers: [Layer]) {
        self.bottle = bottle
        self.layers = layers
    }
}

/// When a level is won. `GameState.isSolved` asks `Rules.isMet(_:by:)`.
public enum Goal: Hashable, Sendable {
    /// Every flask is empty or full with one color (and nothing is sealed). Implemented.
    case standard
    /// R7 order: each target flask ends with its target content; every other flask is
    /// standard-solved. Targets reference bottles by index, like links.
    case order([GoalTarget])
    /// R7 layered recipe: like `order`, but a target may be any exact layer pattern.
    case pattern([GoalTarget])
    /// R7 rescue: every seal open within `withinMoves` moves (needs `GameState.moveCount`).
    case rescue(withinMoves: Int)

    public var isImplemented: Bool { self == .standard }

    public var name: String {
        switch self {
        case .standard: return "standard"
        case .order: return "order"
        case .pattern: return "pattern"
        case .rescue: return "rescue"
        }
    }

    /// Whether the rules need `GameState.moveCount` for this goal.
    public var needsMoveCount: Bool {
        if case .rescue = self { return true }
        return false
    }

    var targets: [GoalTarget] {
        switch self {
        case .order(let t), .pattern(let t): return t
        case .standard, .rescue: return []
        }
    }

    /// The same goal with its bottle references renumbered by `map`.
    public func remapped(_ map: (Int) -> Int) -> Goal {
        func remap(_ targets: [GoalTarget]) -> [GoalTarget] {
            targets.map { GoalTarget(bottle: map($0.bottle), layers: $0.layers) }
        }
        switch self {
        case .standard, .rescue: return self
        case .order(let t): return .order(remap(t))
        case .pattern(let t): return .pattern(remap(t))
        }
    }
}

// MARK: - JSON

// Level files (v2) write each of these as an object with a "type" tag, e.g.
// {"type": "essence", "color": 3}, {"type": "twins", "between": [0, 4]},
// {"type": "order", "targets": [{"bottle": 2, "layers": [5, 5, 5, 5]}]}.

extension BottleModifier: Codable {
    private enum CodingKeys: String, CodingKey { case type, key, color, layer, turns, every, phase, recipes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "sealed": self = .sealed(KeyID(try c.decode(Int.self, forKey: .key)))
        case "essence": self = .essence(ColorID(try c.decode(Int.self, forKey: .color)))
        case "narrowNeck": self = .narrowNeck
        case "funnel": self = .funnel
        case "tap": self = .tap
        case "frozen": self = .frozen(layer: try c.decode(Int.self, forKey: .layer), turns: try c.decode(Int.self, forKey: .turns))
        case "bubbling": self = .bubbling(every: try c.decode(Int.self, forKey: .every), phase: try c.decodeIfPresent(Int.self, forKey: .phase) ?? 0)
        case "cauldron": self = BottleModifier.cauldron(try c.decode([Recipe].self, forKey: .recipes)).normalized
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown flask modifier \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .type)
        switch self {
        case .sealed(let k): try c.encode(k.rawValue, forKey: .key)
        case .essence(let color): try c.encode(color.rawValue, forKey: .color)
        case .narrowNeck, .funnel, .tap: break
        case let .frozen(layer, turns):
            try c.encode(layer, forKey: .layer)
            try c.encode(turns, forKey: .turns)
        case let .bubbling(every, phase):
            try c.encode(every, forKey: .every)
            try c.encode(phase, forKey: .phase)
        case .cauldron(let recipes): try c.encode(recipes, forKey: .recipes)
        }
    }
}

extension Link: Codable {
    private enum CodingKeys: String, CodingKey { case type, between, from, to, `switch`, gate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "twins":
            let pair = try c.decode([Int].self, forKey: .between)
            guard pair.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .between, in: c, debugDescription: "twins need two flasks")
            }
            self = .twins(pair[0], pair[1])
        case "overflow": self = .overflow(from: try c.decode(Int.self, forKey: .from), to: try c.decode(Int.self, forKey: .to))
        case "switchGate": self = .switchGate(switch: try c.decode(Int.self, forKey: .switch), gate: try c.decode(Int.self, forKey: .gate))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown link \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .type)
        switch self {
        case let .twins(a, b): try c.encode([a, b], forKey: .between)
        case let .overflow(a, b):
            try c.encode(a, forKey: .from)
            try c.encode(b, forKey: .to)
        case let .switchGate(a, b):
            try c.encode(a, forKey: .switch)
            try c.encode(b, forKey: .gate)
        }
    }
}

extension Goal: Codable {
    private enum CodingKeys: String, CodingKey { case type, targets, withinMoves }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "standard": self = .standard
        case "order": self = .order(try c.decode([GoalTarget].self, forKey: .targets))
        case "pattern": self = .pattern(try c.decode([GoalTarget].self, forKey: .targets))
        case "rescue": self = .rescue(withinMoves: try c.decode(Int.self, forKey: .withinMoves))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown goal \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .type)
        switch self {
        case .standard: break
        case .order(let t), .pattern(let t): try c.encode(t, forKey: .targets)
        case .rescue(let n): try c.encode(n, forKey: .withinMoves)
        }
    }
}
