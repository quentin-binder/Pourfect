/// A compact, bottle-order-independent key for a game state.
///
/// **v1 words (classic and sealed states, unchanged).** Each bottle is packed into one
/// `UInt64`:
/// - bits 0..<54: up to 9 layers, 6 bits each, bottom first. Tokens:
///   0 = no layer, 1...47 = color `token - 1` (colors 0...46),
///   48...63 = key `token - 48` (keys 0...15),
/// - bits 56..<64: seal key + 1 (0 = not sealed), so seal identity is part of the key.
/// The bottle codes are then sorted, so two states that differ only in the order of
/// their bottles produce the same key. A state with no links, the standard goal, no move
/// counter and at most one seal per bottle (no other modifiers) is encoded exactly like
/// this, so `codes` is one word per bottle as before.
///
/// **v2 (variable length), for everything else.** `codes` is a sequence of bottle groups
/// sorted lexicographically, then an optional global section:
/// - Bottle group: the v1 word, with bit 55 set if the bottle has extension words; then
///   one word `n` and `n` modifier words (`words(for:)`: tag in bits 56..<64, payload
///   below; a cauldron adds one word per recipe). Bit 54 of a group's first word is
///   always 0.
/// - Global section (only if there are links, a non-standard goal or a move counter):
///   a marker word with bit 54 set and the number of global words in the low bits, then
///   the sorted link words, the goal words and the move counter word.
///
/// **Links (and goal targets) canonicalization.** They point at bottles by index, but the
/// key must not depend on bottle order. Each endpoint is written as the *rank* of its
/// bottle's group in the sorted order. Bottles with identical groups (a tie) are
/// interchangeable for everything except the links, so among all rank assignments that
/// permute tied bottles the one giving the smallest global section is used; that makes
/// the key a true canonical form: equal for states that differ by a bottle permutation
/// (with links renumbered), and different otherwise. If a pathological level has more
/// than `maxTiePermutations` such assignments, the bottles' own order breaks the ties:
/// the key stays correct (different states never share a key) but symmetric duplicates
/// may get different keys.
public struct StateKey: Hashable, Sendable {
    public let codes: [UInt64]

    public static let maxCapacity = 9
    public static let maxColorID = 46
    public static let maxKeyID = 15
    /// Largest counter or index that fits a modifier/link payload field (8 bits).
    public static let maxSmallValue = 255
    static let keyTokenBase: UInt64 = 48
    static let extensionFlag: UInt64 = 1 << 55
    static let globalMarker: UInt64 = 1 << 54
    static let maxTiePermutations = 720

    public init(_ state: GameState) {
        if state.isBottlesOnly {
            var codes: [UInt64] = []
            codes.reserveCapacity(state.bottles.count)
            for bottle in state.bottles {
                guard let code = StateKey.classicCode(for: bottle) else {
                    self.codes = StateKey.pairCodes(state) ?? StateKey.extendedCodes(state)
                    return
                }
                codes.append(code)
            }
            codes.sort()
            self.codes = codes
        } else {
            self.codes = StateKey.linkedCodes(state) ?? StateKey.extendedCodes(state)
        }
    }

    /// One bottle as a (v1 word, modifier word or 0) pair: the `pairCodes` form of its group.
    struct Pair: Hashable, Comparable {
        let first: UInt64
        let extra: UInt64
        static func < (a: Pair, b: Pair) -> Bool { (a.first, a.extra) < (b.first, b.extra) }
    }

    /// The pair of `bottle` (see `pairCodes`), or nil if its group needs more than one
    /// modifier word.
    @inline(__always)
    static func pair(for bottle: Bottle) -> Pair? {
        if let code = classicCode(for: bottle) { return Pair(first: code, extra: 0) }
        var extra: UInt64 = 0
        var sealed = false
        for modifier in bottle.modifiers {
            if modifier.isSeal && !sealed {
                sealed = true   // the first seal is in the v1 word
                continue
            }
            guard extra == 0, let word = singleWord(for: modifier) else { return nil }
            extra = word
        }
        return Pair(first: code(for: bottle) | extensionFlag, extra: extra)
    }

    /// One bottle of a linked state for `linkedCodes`: its pair and its *role* in the links
    /// (a bit per end kind: twin, overflow start, overflow end, switch, gate; 0 = unlinked).
    struct LinkedGroup: Hashable, Comparable {
        let pair: Pair
        let role: UInt64
        static func < (a: LinkedGroup, b: LinkedGroup) -> Bool { (a.pair, a.role) < (b.pair, b.role) }
    }

    /// The key of a state with links (F1, F2) but no goal and no move counter, whose bottles
    /// each fit a pair (`pair(for:)`); nil if the state doesn't fit (then `extendedCodes`).
    ///
    /// Like `extendedCodes` (bottle groups, then a global section with the link words, the
    /// endpoints as ranks), except that bottles are sorted by (pair, role): a linked bottle
    /// then never ties with an unlinked one, so the usual case (an empty linked flask next to
    /// empty plain ones) needs no search over tied bottles. Ties of the same role (two pairs of
    /// empty twins) still take the minimum over permutations (`globalWords`). The codes are
    /// self-delimiting (groups, then the counted global section), the role of each bottle
    /// follows from the link words, and the order depends only on the bottles' contents and
    /// roles, so the key is a true canonical form here too. Whether a state takes this path
    /// doesn't depend on bottle order, so both forms never meet for one position.
    static func linkedCodes(_ state: GameState) -> [UInt64]? {
        guard state.moveCount == nil, state.hasStandardGoal else { return nil }
        let links = state.links
        var groups: [LinkedGroup] = []
        groups.reserveCapacity(state.bottles.count)
        var roles = [UInt64](repeating: 0, count: state.bottles.count)
        for link in links {
            let (a, b) = link.endpoints
            guard roles.indices.contains(a), roles.indices.contains(b) else { return nil }
            switch link {
            case .twins:
                roles[a] |= 1
                roles[b] |= 1
            case .overflow:
                roles[a] |= 2
                roles[b] |= 4
            case .switchGate:
                roles[a] |= 8
                roles[b] |= 16
            }
        }
        for (i, bottle) in state.bottles.enumerated() {
            guard let pair = pair(for: bottle) else { return nil }
            groups.append(LinkedGroup(pair: pair, role: roles[i]))
        }
        let order = groups.indices.sorted { a, b in groups[a] == groups[b] ? a < b : groups[a] < groups[b] }
        var codes: [UInt64] = []
        codes.reserveCapacity(state.bottles.count + 8)
        for i in order {
            let pair = groups[i].pair
            codes.append(pair.first)
            if pair.extra != 0 {
                codes.append(1)
                codes.append(pair.extra)
            }
        }
        let global = untiedLinkWords(links, groups: groups, order: order)
            ?? globalWords(state, groups: groups, order: order)
        if !global.isEmpty {
            codes.append(globalMarker | UInt64(global.count))
            codes += global
        }
        return codes
    }

    /// `globalWords` for links only (standard goal, no counter) when no linked bottle is
    /// tied with another bottle (equal groups): the ranks are then unique and no permutation
    /// needs to be tried. nil if some linked bottle is tied (the general search decides).
    @inline(__always)
    static func untiedLinkWords(_ links: [Link], groups: [LinkedGroup], order: [Int]) -> [UInt64]? {
        var rankOf = [Int](repeating: 0, count: order.count)
        for (rank, bottle) in order.enumerated() { rankOf[bottle] = rank }
        func isTied(_ bottle: Int) -> Bool {
            let rank = rankOf[bottle]
            return (rank > 0 && groups[order[rank - 1]] == groups[bottle])
                || (rank + 1 < order.count && groups[order[rank + 1]] == groups[bottle])
        }
        var words: [UInt64] = [0xD0 << 56 | UInt64(links.count)]
        words.reserveCapacity(links.count + 1)
        for link in links {
            let (a, b) = link.endpoints
            // Twins tied only with each other: either order gives the same (sorted) word.
            if case .twins = link, groups[a] == groups[b] {
                let ranks = [rankOf[a], rankOf[b]].sorted()
                let others = order.indices.filter { groups[order[$0]] == groups[a] }
                guard others.count == 2 else { return nil }
                words.append(link.tag << 56 | UInt64(ranks[0]) << 40 | UInt64(ranks[1]) << 24)
                continue
            }
            guard !isTied(a), !isTied(b) else { return nil }
            var (ra, rb) = (rankOf[a], rankOf[b])
            if link.isSymmetric && rb < ra { swap(&ra, &rb) }
            words.append(link.tag << 56 | UInt64(ra) << 40 | UInt64(rb) << 24)
        }
        words[1...].sort()
        return words
    }

    /// Fast path of `extendedCodes` for a state of bottles only in which each bottle has
    /// at most one modifier besides its seal, encoded in one word (e.g. an essence rune):
    /// every group is `[v1]` or `[v1 | extensionFlag, 1, word]`, so sorting (v1 word,
    /// modifier word or 0) pairs gives the same order as sorting the groups (a group's
    /// first word decides unless both carry the flag; modifier words are never 0) and the
    /// same codes, without building an array per bottle. nil if the state doesn't fit.
    static func pairCodes(_ state: GameState) -> [UInt64]? {
        var pairs: [(UInt64, UInt64)] = []
        pairs.reserveCapacity(state.bottles.count)
        for bottle in state.bottles {
            guard let pair = pair(for: bottle) else { return nil }
            pairs.append((pair.first, pair.extra))
        }
        pairs.sort { $0 < $1 }
        var codes: [UInt64] = []
        codes.reserveCapacity(state.bottles.count + 4)
        for (first, extra) in pairs {
            codes.append(first)
            if extra != 0 {
                codes.append(1)
                codes.append(extra)
            }
        }
        return codes
    }

    /// `words(for:)` of a modifier that encodes in one word (all but a cauldron).
    @inline(__always)
    static func singleWord(for modifier: BottleModifier) -> UInt64? {
        switch modifier {
        case .essence(let c): return modifier.tag << 56 | UInt64(truncatingIfNeeded: c.rawValue) & 0xFF_FFFF
        case .narrowNeck, .funnel, .tap: return modifier.tag << 56
        case let .frozen(layer, turns):
            return modifier.tag << 56 | (UInt64(truncatingIfNeeded: layer) & 0xFF_FFFF) << 24
                | UInt64(truncatingIfNeeded: turns) & 0xFF_FFFF
        case let .bubbling(every, phase):
            return modifier.tag << 56 | (UInt64(truncatingIfNeeded: every) & 0xFF_FFFF) << 24
                | UInt64(truncatingIfNeeded: phase) & 0xFF_FFFF
        case .cauldron: return nil
        default: return words(for: modifier)[0]
        }
    }

    /// Whether `state` fits in the packed encoding.
    public static func canEncode(_ state: GameState) -> Bool {
        let small = 0...maxSmallValue
        guard state.bottles.count <= maxSmallValue + 1,
              state.moveCount.map({ $0 >= 0 }) ?? true else { return false }
        let bottlesFit = state.bottles.allSatisfy { bottle in
            bottle.capacity <= maxCapacity
                && bottle.layers.count <= maxCapacity
                && bottle.layers.allSatisfy(fits)
                && bottle.modifiers.allSatisfy { modifier in
                    switch modifier {
                    case .sealed(let k): return (0...maxKeyID).contains(k.rawValue)
                    case .essence(let c): return (0...maxColorID).contains(c.rawValue)
                    case .narrowNeck, .funnel, .tap: return true
                    case let .frozen(layer, turns): return small.contains(layer) && small.contains(turns)
                    case let .bubbling(every, phase): return small.contains(every) && small.contains(phase)
                    case .cauldron(let recipes):
                        return recipes.count <= maxSmallValue && recipes.allSatisfy {
                            [$0.a, $0.b, $0.result].allSatisfy { (0...maxColorID).contains($0.rawValue) }
                        }
                    }
                }
        }
        let indices = state.bottles.indices
        let linksFit = state.links.allSatisfy { indices.contains($0.endpoints.0) && indices.contains($0.endpoints.1) }
        let goalFits: Bool = {
            switch state.goal {
            case .standard: return true
            case .rescue(let n): return n >= 0
            case .order(let targets), .pattern(let targets):
                return targets.allSatisfy { indices.contains($0.bottle) && $0.layers.count <= maxCapacity && $0.layers.allSatisfy(fits) }
            }
        }()
        return bottlesFit && linksFit && goalFits
    }

    private static func fits(_ layer: Layer) -> Bool {
        switch layer {
        case .color(let c): return (0...maxColorID).contains(c.rawValue)
        case .key(let k): return (0...maxKeyID).contains(k.rawValue)
        }
    }

    static func token(for layer: Layer) -> UInt64 {
        switch layer {
        case .color(let c): return UInt64(c.rawValue + 1)
        case .key(let k): return keyTokenBase + UInt64(k.rawValue)
        }
    }

    static func layerBits(_ layers: [Layer]) -> UInt64 {
        var code: UInt64 = 0
        for (i, layer) in layers.enumerated() {
            code |= token(for: layer) << UInt64(6 * i)
        }
        return code
    }

    /// The v1 word for `bottle`: layers plus its seal.
    static func code(for bottle: Bottle) -> UInt64 {
        var code = layerBits(bottle.layers)
        if let lock = bottle.lockedBy {
            code |= UInt64(lock.rawValue + 1) << 56
        }
        return code
    }

    /// The v1 word, or nil if the bottle needs extension words (any modifier but one seal).
    @inline(__always)
    static func classicCode(for bottle: Bottle) -> UInt64? {
        switch bottle.storage {
        case .none: return layerBits(bottle.layers)
        case .sealed(let lock): return layerBits(bottle.layers) | UInt64(lock.rawValue + 1) << 56
        case .list: return nil
        }
    }

    /// The encoding of one modifier: a tag word, plus one word per recipe for a cauldron.
    static func words(for modifier: BottleModifier) -> [UInt64] {
        let head = modifier.tag << 56
        func u(_ n: Int) -> UInt64 { UInt64(truncatingIfNeeded: n) & 0xFF_FFFF }
        switch modifier {
        case .sealed(let k): return [head | u(k.rawValue)]
        case .essence(let c): return [head | u(c.rawValue)]
        case .narrowNeck, .funnel, .tap: return [head]
        case let .frozen(layer, turns): return [head | u(layer) << 24 | u(turns)]
        case let .bubbling(every, phase): return [head | u(every) << 24 | u(phase)]
        case .cauldron(let recipes):
            return [head | u(recipes.count)] + recipes.map { r in
                u(r.a.rawValue) << 32 | u(r.b.rawValue) << 16 | u(r.result.rawValue)
            }
        }
    }

    /// One bottle's group: the v1 word (with the first seal), then extension words.
    static func group(for bottle: Bottle) -> [UInt64] {
        if let code = classicCode(for: bottle) { return [code] }
        let (_, others) = Bottle.splitSeal(bottle.modifiers)
        let extra = others.flatMap(words(for:))
        return [code(for: bottle) | extensionFlag, UInt64(extra.count)] + extra
    }

    static func extendedCodes(_ state: GameState) -> [UInt64] {
        let groups = state.bottles.map(group(for:))
        let order = groups.indices.sorted { a, b in
            groups[a] == groups[b] ? a < b : groups[a].lexicographicallyPrecedes(groups[b])
        }
        var codes = order.flatMap { groups[$0] }
        let global = globalWords(state, groups: groups, order: order)
        if !global.isEmpty {
            codes.append(globalMarker | UInt64(global.count))
            codes += global
        }
        return codes
    }

    /// Links, goal and counters, with bottle references written as canonical ranks.
    static func globalWords<Group: Equatable>(_ state: GameState, groups: [Group], order: [Int]) -> [UInt64] {
        let links = state.links
        let goal = state.goal
        var fixed: [UInt64] = []
        if case .rescue(let n) = goal { fixed.append(0xF0 << 56 | UInt64(n)) }
        if let moveCount = state.moveCount { fixed.append(0xFF << 56 | UInt64(moveCount)) }
        let targets = goal.targets
        if links.isEmpty && targets.isEmpty {
            if goal != .standard { fixed.insert(goalTag(goal) << 56, at: 0) }
            return fixed
        }
        // Tie classes: runs of equal groups in the sorted order.
        var classes: [[Int]] = []   // ranks of each class with more than one member
        var start = 0
        for r in 1..<(order.count + 1) {
            if r == order.count || groups[order[r]] != groups[order[start]] {
                if r - start > 1 { classes.append(Array(start..<r)) }
                start = r
            }
        }
        var rankOf = [Int](repeating: 0, count: order.count)
        for (rank, bottle) in order.enumerated() { rankOf[bottle] = rank }
        let referenced = Set(links.flatMap { [$0.endpoints.0, $0.endpoints.1] } + targets.map(\.bottle))
        classes.removeAll { ranks in !ranks.contains { referenced.contains(order[$0]) } }

        func encode(_ rankOf: [Int]) -> [UInt64] {
            var words = links.map { link -> UInt64 in
                var (a, b) = (rankOf[link.endpoints.0], rankOf[link.endpoints.1])
                if link.isSymmetric && b < a { swap(&a, &b) }
                return link.tag << 56 | UInt64(a) << 40 | UInt64(b) << 24
            }
            words.sort()
            words.insert(0xD0 << 56 | UInt64(words.count), at: 0)
            var goalWords = [goalTag(goal) << 56 | UInt64(targets.count)]
            var targetWords = targets.map { t -> [UInt64] in
                // Rank, then the layers (bits 0..<54). No separate count: layer tokens are
                // never 0, so the layer bits already determine it (a count at bit 48 would
                // overlap a 9th layer's token).
                [UInt64(rankOf[t.bottle]) << 56 | layerBits(t.layers)]
            }
            targetWords.sort { $0.lexicographicallyPrecedes($1) }
            goalWords += targetWords.flatMap { $0 }
            return words + (goal == .standard ? [] : goalWords)
        }

        var best = encode(rankOf)
        let permutations = tiePermutationCount(classSizes: classes.map(\.count))
        if permutations > 1 && permutations <= maxTiePermutations {
            // Try every assignment of tied bottles to their class's ranks.
            var current = rankOf
            func search(_ classIndex: Int) {
                if classIndex == classes.count {
                    let words = encode(current)
                    if words.lexicographicallyPrecedes(best) { best = words }
                    return
                }
                let ranks = classes[classIndex]
                let members = ranks.map { order[$0] }
                for perm in permutationsOf(ranks) {
                    for (member, rank) in zip(members, perm) { current[member] = rank }
                    search(classIndex + 1)
                }
                for (member, rank) in zip(members, ranks) { current[member] = rank }
            }
            search(0)
        }
        return best + fixed
    }

    /// The number of rank assignments of tied bottles (the product of the classes'
    /// factorials), saturating at `maxTiePermutations + 1`, so large or many tie classes
    /// fall back to bottle order instead of overflowing.
    static func tiePermutationCount(classSizes: [Int]) -> Int {
        var total = 1
        for size in classSizes {
            for factor in stride(from: 2, through: size, by: 1) {
                total *= factor
                if total > maxTiePermutations { return maxTiePermutations + 1 }
            }
        }
        return total
    }

    static func goalTag(_ goal: Goal) -> UInt64 {
        switch goal {
        case .standard: return 0xE0
        case .order: return 0xE1
        case .pattern: return 0xE2
        case .rescue: return 0xE3
        }
    }

    static func permutationsOf(_ items: [Int]) -> [[Int]] {
        guard items.count > 1 else { return [items] }
        var result: [[Int]] = []
        for (i, first) in items.enumerated() {
            var rest = items
            rest.remove(at: i)
            for tail in permutationsOf(rest) { result.append([first] + tail) }
        }
        return result
    }
}

extension GameState {
    /// Canonical key: equal for states that differ only in bottle order.
    public var canonicalKey: StateKey { StateKey(self) }
}
