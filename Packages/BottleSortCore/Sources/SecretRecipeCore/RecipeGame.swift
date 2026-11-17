/// One brewed guess and what the alchemist said about it.
public struct RecipeTurn: Sendable, Hashable, Codable {
    public let guess: RecipeCode
    public let feedback: RecipeFeedback

    public init(guess: RecipeCode, feedback: RecipeFeedback) {
        self.guess = guess
        self.feedback = feedback
    }
}

/// A game of Secret Recipe: up to `maxGuesses` guesses; won when a guess has all five in place,
/// lost after the last wrong guess (the recipe is then revealed).
public struct RecipeGame: Sendable, Hashable, Codable {
    public static let maxGuesses = 8

    public enum Status: String, Sendable, Hashable, Codable {
        case playing, won, lost
    }

    public let secret: RecipeCode
    public private(set) var turns: [RecipeTurn] = []

    public init(secret: RecipeCode) { self.secret = secret }

    /// Replays saved guesses (extra guesses after the game ended are ignored).
    public init(secret: RecipeCode, guesses: [RecipeCode]) {
        self.secret = secret
        for guess in guesses { brew(guess) }
    }

    public var guesses: [RecipeCode] { turns.map(\.guess) }

    public var status: Status {
        if turns.last?.feedback.isSolved == true { return .won }
        return turns.count >= RecipeGame.maxGuesses ? .lost : .playing
    }

    public var isOver: Bool { status != .playing }
    public var guessesLeft: Int { isOver ? 0 : RecipeGame.maxGuesses - turns.count }

    /// The secret once the game is over (won or lost); nil while playing.
    public var revealed: RecipeCode? { isOver ? secret : nil }

    /// Brews a guess: returns its turn, or nil when the game is already over (nothing changes).
    @discardableResult
    public mutating func brew(_ guess: RecipeCode) -> RecipeTurn? {
        guard !isOver else { return nil }
        let turn = RecipeTurn(guess: guess, feedback: secret.feedback(for: guess))
        turns.append(turn)
        return turn
    }

    /// Recipes still consistent with every turn so far (the secret is always among them).
    public var candidatesLeft: Int { RecipeCandidates.count(consistentWith: turns) }
}

/// The deduction helper: which of the 6720 recipes agree with the feedback so far.
public enum RecipeCandidates {
    /// Slots of every recipe, flattened (5 per recipe), and each recipe's ingredient mask.
    private static let slots: [UInt8] = RecipeCode.all.flatMap { $0.slots.map { UInt8($0.rawValue) } }
    private static let masks: [UInt8] = RecipeCode.all.map(\.mask)

    public static func count(consistentWith turns: [RecipeTurn]) -> Int {
        var n = 0
        forEachConsistent(turns) { _ in n += 1 }
        return n
    }

    public static func consistent(with turns: [RecipeTurn]) -> [RecipeCode] {
        var result: [RecipeCode] = []
        forEachConsistent(turns) { result.append(RecipeCode.all[$0]) }
        return result
    }

    private static func forEachConsistent(_ turns: [RecipeTurn], _ body: (Int) -> Void) {
        let guesses = turns.map { turn -> (slots: [UInt8], mask: UInt8, exact: Int, common: Int) in
            (turn.guess.slots.map { UInt8($0.rawValue) }, turn.guess.mask, turn.feedback.exact, turn.feedback.common)
        }
        slots.withUnsafeBufferPointer { all in
            candidates: for index in 0..<RecipeCode.permutationCount {
                let base = index * RecipeCode.length
                for guess in guesses {
                    guard (masks[index] & guess.mask).nonzeroBitCount == guess.common else { continue candidates }
                    var exact = 0
                    for i in 0..<RecipeCode.length where all[base + i] == guess.slots[i] { exact += 1 }
                    guard exact == guess.exact else { continue candidates }
                }
                body(index)
            }
        }
    }
}
