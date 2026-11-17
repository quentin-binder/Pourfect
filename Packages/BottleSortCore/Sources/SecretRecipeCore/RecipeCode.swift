/// Secret Recipe (R10b): the alchemist hides an ordered recipe of five different ingredients out
/// of eight; the player deduces it from count-only feedback. Pure rules, no UI.

/// The eight ingredients on the tray, in tray order (raw value = tray position). The first six are
/// the gathering (match-3) ingredients; honeycomb and starleaf are new to Secret Recipe.
public enum RecipeIngredient: Int, CaseIterable, Sendable, Hashable, Codable, Comparable {
    case mushroom = 0, crystal, feather, moonflower, ember, drop, honeycomb, starleaf

    public static func < (a: RecipeIngredient, b: RecipeIngredient) -> Bool { a.rawValue < b.rawValue }

    /// English name; the app localizes its own labels.
    public var name: String {
        switch self {
        case .mushroom: "Mushroom"
        case .crystal: "Crystal"
        case .feather: "Feather"
        case .moonflower: "Moonflower"
        case .ember: "Ember"
        case .drop: "Potion Drop"
        case .honeycomb: "Honeycomb"
        case .starleaf: "Starleaf"
        }
    }
}

/// An ordered recipe (a secret or a guess): exactly `length` different ingredients.
/// Codable as a string of tray digits ("03571").
public struct RecipeCode: Sendable, Hashable, Codable, CustomStringConvertible {
    public static let length = 5
    public static let ingredientCount = RecipeIngredient.allCases.count
    /// 8 · 7 · 6 · 5 · 4
    public static let permutationCount = 6720

    public let slots: [RecipeIngredient]

    /// nil unless there are exactly five ingredients and no repeats.
    public init?(_ slots: [RecipeIngredient]) {
        guard slots.count == RecipeCode.length, Set(slots).count == RecipeCode.length else { return nil }
        self.slots = slots
    }

    /// From tray positions 0...7.
    public init?(trayPositions: [Int]) {
        let slots = trayPositions.compactMap(RecipeIngredient.init(rawValue:))
        guard slots.count == trayPositions.count else { return nil }
        self.init(slots)
    }

    /// From a digit string ("03571").
    public init?(digits: String) {
        let values = digits.map { $0.wholeNumberValue ?? -1 }
        self.init(trayPositions: values)
    }

    public var digits: String { slots.map { String($0.rawValue) }.joined() }
    public var description: String { digits }

    /// Bit i set when ingredient i is in the recipe.
    var mask: UInt8 { slots.reduce(0) { $0 | (1 << UInt8($1.rawValue)) } }

    /// Whether the ingredients follow the tray order strictly up or strictly down (a guess a
    /// player might try first just by reading the tray).
    public var isTrayOrdered: Bool {
        let raw = slots.map(\.rawValue)
        return zip(raw, raw.dropFirst()).allSatisfy(<) || zip(raw, raw.dropFirst()).allSatisfy(>)
    }

    /// The feedback a guess earns against this recipe as the secret.
    public func feedback(for guess: RecipeCode) -> RecipeFeedback {
        var exact = 0
        for i in 0..<RecipeCode.length where slots[i] == guess.slots[i] { exact += 1 }
        let common = (mask & guess.mask).nonzeroBitCount
        return RecipeFeedback(exact: exact, misplaced: common - exact)
    }

    /// Every recipe, in lexicographic tray order (index = position in this list).
    public static let all: [RecipeCode] = {
        var result: [RecipeCode] = []
        result.reserveCapacity(permutationCount)
        func extend(_ prefix: [RecipeIngredient], _ used: UInt8) {
            if prefix.count == length {
                result.append(RecipeCode(unchecked: prefix))
                return
            }
            for ingredient in RecipeIngredient.allCases where used & (1 << UInt8(ingredient.rawValue)) == 0 {
                extend(prefix + [ingredient], used | (1 << UInt8(ingredient.rawValue)))
            }
        }
        extend([], 0)
        return result
    }()

    private init(unchecked slots: [RecipeIngredient]) { self.slots = slots }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let recipe = RecipeCode(digits: s) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a recipe: \(s)")
        }
        self = recipe
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(digits)
    }
}

/// Count-only feedback for one guess: how many ingredients sit in the right slot (gold drops) and
/// how many are in the recipe but in another slot (silver drops). It never says which slots.
public struct RecipeFeedback: Sendable, Hashable, Codable, CustomStringConvertible {
    public let exact: Int
    public let misplaced: Int

    public init(exact: Int, misplaced: Int) {
        self.exact = exact
        self.misplaced = misplaced
    }

    /// Both recipes use 5 of the same 8 ingredients, so at least 2 are always shared.
    public var common: Int { exact + misplaced }
    public var isSolved: Bool { exact == RecipeCode.length }
    public var description: String { "\(exact)+\(misplaced)" }
}
