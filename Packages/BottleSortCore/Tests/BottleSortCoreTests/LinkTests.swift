import Foundation
import Testing
@testable import BottleSortCore

/// Layers from color numbers, with `.key(k)` for negative numbers −k.
private func layers(_ values: [Int]) -> [Layer] {
    values.map { $0 < 0 ? .key(KeyID(-$0)) : .color(ColorID($0)) }
}

private func flask(_ values: [Int], _ capacity: Int, _ modifiers: [BottleModifier] = []) -> Bottle {
    Bottle(layers: layers(values), capacity: capacity, modifiers: modifiers)
}

/// F1 twin flasks: the rule cases.
@Suite struct TwinRuleTests {
    /// Source 0, twins 1 ⇄ 2, a spare flask 3.
    static func board(_ source: [Int], _ a: [Int], _ b: [Int], capacity: Int = 4,
                      extra: [Int] = []) -> GameState {
        GameState(bottles: [flask(source, capacity), flask(a, capacity), flask(b, capacity), flask(extra, capacity)],
                  links: [.twins(1, 2)])
    }

    @Test func aPourIsSplitEvenly() throws {
        let s = Self.board([1, 0, 0, 0], [], [])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        // A run of 3 splits as 1 + 1; the odd layer stays in the source.
        #expect(turn.state.bottles.map(\.layers) == [layers([1, 0]), layers([0]), layers([0]), []])
        let pour = try #require(turn.pour)
        #expect(pour.amount == 2 && pour.targetAmount == 1)
        #expect(pour.shares == [PourShare(bottle: 2, amount: 1, route: .twin)])
        #expect(pour.landings.map(\.bottle) == [1, 2] && pour.landings.map(\.amount) == [1, 1])
        // A run of 4 splits as 2 + 2.
        let even = try #require(Self.board([0, 0, 0, 0], [], [], extra: [1]).pouring(Move(from: 0, to: 2)))
        #expect(even.bottles.map(\.layers) == [[], layers([0, 0]), layers([0, 0]), layers([1])])
    }

    @Test func pouringIntoEitherTwinIsTheSame() throws {
        let s = Self.board([2, 0, 0], [1, 0], [0])
        let a = try #require(s.pouring(Move(from: 0, to: 1)))
        let b = try #require(s.pouring(Move(from: 0, to: 2)))
        #expect(a == b)
        #expect(a.bottles.map(\.layers) == [layers([2]), layers([1, 0, 0]), layers([0, 0]), []])
    }

    @Test func theSmallerFreeSpaceLimitsTheSplit() throws {
        // Twin 1 has one free slot: k = 1 although the run of 4 could give 2 each.
        let s = Self.board([0, 0, 0, 0], [1, 2, 0], [], extra: [1, 2])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 2))))
        #expect(turn.state.bottles.map(\.layers) == [layers([0, 0]), layers([1, 2, 0, 0]), layers([0]), layers([1, 2])])
        #expect(turn.pour?.amount == 2)
        // A full twin: nothing can be split.
        #expect(!Self.board([0, 0], [1, 2, 0, 0], []).canPour(Move(from: 0, to: 1)))
        #expect(!Self.board([0, 0], [], [1, 2, 0, 0]).canPour(Move(from: 0, to: 1)))
    }

    @Test func illegalPours() {
        // A single layer can't be split.
        #expect(!Self.board([1, 0], [], []).canPour(Move(from: 0, to: 1)))
        // Both twins must take the color.
        #expect(!Self.board([0, 0], [0], [1]).canPour(Move(from: 0, to: 1)))
        #expect(!Self.board([0, 0], [1], [0]).canPour(Move(from: 0, to: 2)))
        #expect(Self.board([0, 0], [0], []).canPour(Move(from: 0, to: 1)))
        // Never from one twin into the other, either way.
        let s = Self.board([], [0, 0], [])
        #expect(!s.canPour(Move(from: 1, to: 2)) && !Self.board([], [], [0, 0]).canPour(Move(from: 2, to: 1)))
        // A key never splits.
        let key = GameState(bottles: [flask([0, -1], 4), flask([], 4), flask([], 4), flask([0, 0, 0], 4, [.sealed(1)])],
                            links: [.twins(1, 2)])
        #expect(!key.canPour(Move(from: 0, to: 1)) && key.canPour(Move(from: 0, to: 3)))
    }

    @Test func poursOutOfATwinAreNormal() throws {
        let s = Self.board([], [1, 0, 0, 0], [2], extra: [0])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 1, to: 3))))
        #expect(turn.state.bottles[1].layers == layers([1]) && turn.state.bottles[3].layers == layers([0, 0, 0, 0]))
        #expect(turn.pour?.shares == [] && turn.pour?.amount == 3)
        #expect(s.canPour(Move(from: 1, to: 0)) && s.canPour(Move(from: 2, to: 0)))
    }

    @Test func modifiersOnATwinStillApply() throws {
        // A rune on one twin: only its color can be split into the pair.
        var s = Self.board([1, 1], [], [], extra: [0, 0])
        s.bottles[2].modifiers = [.essence(0)]
        #expect(!s.canPour(Move(from: 0, to: 1)) && s.canPour(Move(from: 3, to: 1)))
        #expect(Rules.linkRefusal(of: Move(from: 0, to: 1), in: s) == .twins(1, 2))
        // A narrow neck on one twin: one layer each, whatever the run.
        var neck = Self.board([0, 0, 0, 0], [], [], extra: [1])
        neck.bottles[1].modifiers = [.narrowNeck]
        let turn = try #require(Rules.resolve(neck, afterAction: .pour(Move(from: 0, to: 2))))
        #expect(turn.state.bottles.map(\.layers) == [layers([0, 0]), layers([0]), layers([0]), layers([1])])
        // A narrow-neck source pours one layer: nothing to split.
        var narrow = Self.board([0, 0, 0], [], [])
        narrow.bottles[0].modifiers = [.narrowNeck]
        #expect(!narrow.canPour(Move(from: 0, to: 1)))
        // Ice on top of a twin closes the pair.
        var icy = Self.board([0, 0], [], [1, 2], extra: [1, 2])
        icy.bottles[2].modifiers = [.frozen(layer: 1, turns: 2)]
        #expect(!icy.canPour(Move(from: 0, to: 1)))
        // A tap pours its bottom run into the twins.
        var tap = Self.board([0, 0, 1], [], [])
        tap.bottles[0].modifiers = [.tap]
        let tapped = try #require(Rules.resolve(tap, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(tapped.state.bottles.map(\.layers) == [layers([1]), layers([0]), layers([0]), []])
        #expect(tapped.pour?.fromBottom == true && tapped.pour?.amount == 2)
    }

    @Test func linkRefusals() {
        let s = Self.board([1, 0], [], [], extra: [2, 2])
        #expect(Rules.linkRefusal(of: Move(from: 0, to: 1), in: s) == .twins(1, 2))   // one layer
        let twinToTwin = Self.board([], [0, 0], [])
        #expect(Rules.linkRefusal(of: Move(from: 1, to: 2), in: twinToTwin) == .twins(1, 2))
        #expect(s.canPour(Move(from: 3, to: 1)) && Rules.linkRefusal(of: Move(from: 3, to: 1), in: s) == nil)
        #expect(Rules.linkRefusal(of: Move(from: 0, to: 3), in: s) == nil)               // base reason
        let pipe = GameState(bottles: [flask([0, 0], 3), flask([1, 0, 0], 3), flask([1, 1], 3)],
                             links: [.overflow(from: 1, to: 2)])
        #expect(Rules.linkRefusal(of: Move(from: 0, to: 1), in: pipe) == nil)
    }

    @Test func displayHelpers() {
        let s = GameState(bottles: (0..<6).map { _ in flask([], 3) }, links: [.twins(4, 1), .overflow(from: 2, to: 5)])
        #expect(s.twin(of: 4) == 1 && s.twin(of: 1) == 4 && s.twin(of: 2) == nil && s.twin(of: 0) == nil)
        #expect(s.overflowTarget(of: 2) == 5 && s.overflowTarget(of: 5) == nil && s.overflowTarget(of: 1) == nil)
        #expect(s.overflowSource(of: 5) == 2 && s.overflowSource(of: 2) == nil)
        #expect(s.link(at: 0) == nil && s.link(at: 1) == .twins(4, 1) && s.link(at: 5) == .overflow(from: 2, to: 5))
        #expect(s.hasLinks && !GameState(bottles: s.bottles).hasLinks)
        let level = LevelDefinition(id: "l", state: s, hidden: true)
        #expect(level.mechanics == [.murky, .twins, .overflow])
        #expect(Mechanic.twins.rawValue == "twins" && Mechanic.overflow.rawValue == "overflow")
        #expect(ChapterOutline.plan[7].introduces == [.twins, .overflow] && ChapterOutline.plan[7].location == "Twin Towers")
        #expect(Link.twins(0, 1).isImplemented && Link.overflow(from: 0, to: 1).isImplemented)
        #expect(!Link.switchGate(switch: 0, gate: 1).isImplemented)
        #expect(MechanicImpact.isTwoSided(.link(.twins(0, 1))) && MechanicImpact.isTwoSided(.link(.overflow(from: 0, to: 1))))
        #expect(LinkImpact.minimumCost == 1 && LinkImpact.strongCost == 2)
    }

    @Test func legalMovesAgreeWithResolve() {
        for s in LinkKeyTests.randomStates() {
            for from in s.bottles.indices {
                for to in s.bottles.indices {
                    let move = Move(from: from, to: to)
                    #expect(s.canPour(move) == (Rules.resolve(s, afterAction: .pour(move)) != nil))
                }
            }
        }
    }

    /// Color layers are conserved by every pour, linked or not.
    @Test func layersAreConserved() {
        func colors(_ s: GameState) -> Int { s.bottles.reduce(0) { $0 + $1.layers.filter { $0.colorID != nil }.count } }
        for s in LinkKeyTests.randomStates() {
            let count = colors(s)
            for move in s.legalMoves() {
                let next = s.pouring(move)!
                #expect(colors(next) == count)
                #expect(next.bottles.allSatisfy { $0.layers.count <= $0.capacity })
            }
        }
    }
}

/// F2 overflow pipes: the rule cases.
@Suite struct OverflowRuleTests {
    /// Source 0, pipe 1 → 2, a spare flask 3 (capacity 3).
    static func board(_ source: [Int], _ a: [Int], _ b: [Int], extra: [Int] = []) -> GameState {
        GameState(bottles: [flask(source, 3), flask(a, 3), flask(b, 3), flask(extra, 3)],
                  links: [.overflow(from: 1, to: 2)])
    }

    @Test func whatDoesntFitRunsOn() throws {
        let s = Self.board([1, 0, 0], [1, 0], [])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles.map(\.layers) == [layers([1]), layers([1, 0, 0]), layers([0]), []])
        let pour = try #require(turn.pour)
        #expect(pour.amount == 2 && pour.targetAmount == 1)
        #expect(pour.shares == [PourShare(bottle: 2, amount: 1, route: .overflow)])
        // Without the pipe the second 0 stays in the source.
        var plain = s
        plain.links = []
        #expect(plain.pouring(Move(from: 0, to: 1))?.bottles[0].layers == layers([1, 0]))
    }

    @Test func aFullFlaskPassesEverythingOn() throws {
        let s = Self.board([2, 0, 0], [1, 2, 0], [0])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles.map(\.layers) == [layers([2]), layers([1, 2, 0]), layers([0, 0, 0]), []])
        #expect(turn.pour?.targetAmount == 0 && turn.pour?.landings.map(\.bottle) == [2])
        // The full flask's top must still match: liquid of another color can't go in.
        #expect(!Self.board([2, 1, 1], [1, 2, 0], []).canPour(Move(from: 0, to: 1)))
    }

    @Test func theFarEndMustAccept() throws {
        // The far end has another color on top: the rest stays in the source.
        let s = Self.board([1, 0, 0], [1, 0], [2])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles.map(\.layers) == [layers([1, 0]), layers([1, 0, 0]), layers([2]), []])
        #expect(turn.pour?.shares == [])
        // Full far end, nothing fits into the full flask: illegal.
        #expect(!Self.board([2, 0, 0], [1, 2, 0], [2, 1, 1]).canPour(Move(from: 0, to: 1)))
        // The far end takes only what fits.
        let tight = try #require(Self.board([0, 0, 0], [1, 2, 0], [1, 0]).pouring(Move(from: 0, to: 1)))
        #expect(tight.bottles.map(\.layers) == [layers([0, 0]), layers([1, 2, 0]), layers([1, 0, 0]), []])
        // A rune on the far end vetoes other colors.
        var rune = Self.board([1, 0, 0], [1, 0], [])
        rune.bottles[2].modifiers = [.essence(1)]
        #expect(rune.pouring(Move(from: 0, to: 1))?.bottles[0].layers == layers([1, 0]))
        // A narrow neck on the far end takes one layer.
        var neck = Self.board([2, 0, 0], [1, 0], [])
        neck.bottles[2].modifiers = [.narrowNeck]
        #expect(neck.pouring(Move(from: 0, to: 1))?.bottles.map(\.layers) == [layers([2]), layers([1, 0, 0]), layers([0]), []])
    }

    @Test func pipesRunOneWayAndOneHop() throws {
        // Pouring into the far end is an ordinary pour.
        let s = Self.board([1, 0, 0], [0, 0], [0])
        #expect(s.pouring(Move(from: 0, to: 2))?.bottles.map(\.layers) == [layers([1]), layers([0, 0]), layers([0, 0, 0]), []])
        // From the far end into the pipe's flask: nothing flows back into the source.
        let back = Self.board([], [1, 0], [0, 0])
        #expect(back.pouring(Move(from: 2, to: 1))?.bottles.map(\.layers) == [[], layers([1, 0, 0]), layers([0]), []])
        // One hop: the far end's own pipe isn't followed (invalid level, but the rule is safe).
        let chain = GameState(bottles: [flask([0, 0, 0], 3), flask([1, 0], 3), flask([2, 2, 0], 3), flask([], 3)],
                              links: [.overflow(from: 1, to: 2), .overflow(from: 2, to: 3)])
        #expect(chain.pouring(Move(from: 0, to: 1))?.bottles.map(\.layers)
                == [layers([0, 0]), layers([1, 0, 0]), layers([2, 2, 0]), []])
    }

    @Test func aKeyOpensTheSealAsUsual() throws {
        let s = GameState(bottles: [flask([0, -1], 3), flask([1, 1, 1], 3, [.sealed(1)]), flask([], 3), flask([0, 0], 3)],
                          links: [.overflow(from: 1, to: 2)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(!turn.state.bottles[1].isSealed && turn.pour?.openedSeal == 1 && turn.pour?.shares == [])
        #expect(turn.state.bottles[2].isEmpty && turn.pour?.landings.isEmpty == true)
        // A key can't run through a pipe: it only goes into its own seal.
        let other = GameState(bottles: [flask([0, -1], 3), flask([1, 1, 1], 3), flask([], 3, [.sealed(1)]), flask([0, 0], 3)],
                              links: [.overflow(from: 1, to: 2)])
        #expect(!other.canPour(Move(from: 0, to: 1)))
    }

    @Test func aPipeNeverRefuses() {
        // Everything legal without the pipe stays legal with it.
        for s in LinkKeyTests.randomStates() where s.links.contains(where: { if case .overflow = $0 { true } else { false } }) {
            var plain = s
            plain.links = s.links.filter { if case .overflow = $0 { false } else { true } }
            for move in plain.legalMoves() {
                if case .twins? = s.link(at: move.to) { continue }
                #expect(s.canPour(move), "\(s) \(move)")
            }
        }
    }
}

/// Hand-made puzzles with links.
@Suite struct LinkPuzzleTests {
    /// The twins are the only empty flasks, and neither filled flask can pour into the other:
    /// every solution starts by splitting a run into the twins (4 moves; 3 with plain flasks).
    static let twinsNeeded = GameState(bottles: [flask([0, 1, 1], 3), flask([1, 0, 0], 3), flask([], 3), flask([], 3)],
                                       links: [.twins(2, 3)])

    @Test func theSplitIsRequired() throws {
        let s = Self.twinsNeeded
        let moves = try #require(Solver().solve(s).moves)
        #expect(moves.count == 4 && referenceMinMoves(s) == 4)
        let first = try #require(Rules.resolve(s, afterAction: .pour(moves[0])))
        #expect(first.pour?.shares.count == 1)
        // Every first move is a split.
        #expect(s.legalMoves().allSatisfy { Rules.resolve(s, afterAction: .pour($0))?.pour?.shares.isEmpty == false })
        let without = MechanicImpact.removing(.link(.twins(2, 3)), from: s)
        #expect(Solver().solve(without).moves?.count == 3 && referenceMinMoves(without) == 3)
        #expect(LinkImpact.everyLinkMatters(s, minMoves: 4))
        #expect(!LinkImpact.everyLinkMatters(s, minMoves: 4, cost: LinkImpact.strongCost))
        #expect(LinkImpact.solvesUsingEveryLink(s, in: 4) && !LinkImpact.solvesUsingEveryLink(s, in: 3))
        #expect(MechanicImpact.everyFirstMoveSolvable(s))
    }

    /// Twins only end empty (or start sorted): every pour into one also lands in the other, so
    /// a color split into the pair can never all come back together in one of them.
    @Test func twinsMustEndEmpty() {
        let s = GameState(bottles: [flask([0, 0], 2), flask([], 2), flask([], 2), flask([1, 1], 2)], links: [.twins(1, 2)])
        let next = s.pouring(Move(from: 0, to: 1))!
        #expect(next.bottles.map(\.layers) == [[], layers([0]), layers([0]), layers([1, 1])])
        #expect(referenceMinMoves(next) == 2 && !next.canPour(Move(from: 1, to: 2)))
    }

    /// A pipe's flask full with the right color on top passes the pour straight through.
    @Test func throughAFullFlask() throws {
        let s = GameState(bottles: [flask([1, 0, 0], 3), flask([2, 1, 0], 3), flask([0], 3), flask([2, 2, 1], 3), flask([], 3)],
                          links: [.overflow(from: 1, to: 2)])
        let turn = try #require(Rules.resolve(s, afterAction: .pour(Move(from: 0, to: 1))))
        #expect(turn.state.bottles[2].layers == layers([0, 0, 0]) && turn.pour?.targetAmount == 0)
        #expect(Solver().solve(s).moves?.count == referenceMinMoves(s))
    }

    /// An overflow pipe that sets a spill trap: from a still-solvable position, a pour into the
    /// pipe's flask spills the rest of its run into the far end and loses the level, while the
    /// same pour without the pipe would not (`MechanicImpact.spillDepth`). It never changes
    /// the optimal length (DECISIONS 181), so this is how it matters.
    @Test func aSpillTrap() throws {
        let config = GeneratorConfig(colors: 6, capacity: 3, emptyBottles: 2, overflow: 1, linkPlacement: .mixed)
        let s = Generator.candidate(config, seed: LinkPuzzleTests.spillSeed)
        let pipe = try #require(s.links.first)
        let moves = try #require(Solver().solve(s).moves)
        let without = MechanicImpact.removing(.link(pipe), from: s)
        #expect(Solver().solve(without).moves?.count == moves.count)
        let depth = try #require(MechanicImpact.spillDepth(of: .link(pipe), in: s))
        #expect(depth >= 1)
        #expect(MechanicImpact.matters(.link(pipe), in: s, minMoves: moves.count, cost: LinkImpact.strongCost))
        // A pipe that can't spill anything harmful doesn't matter.
        let calm = Generator.candidate(GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, overflow: 1), seed: 1)
        let calmMoves = try #require(Solver().solve(calm).moves)
        #expect(MechanicImpact.spillDepth(of: .link(calm.links[0]), in: calm) == nil)
        #expect(!LinkImpact.everyLinkMatters(calm, minMoves: calmMoves.count))
    }

    /// A seed of `aSpillTrap`'s configuration whose pipe sets a spill trap (found by search).
    static let spillSeed: UInt64 = 26
}

/// The solver with links: exact, and its pruning stays safe.
@Suite struct LinkSolverTests {
    static let configs = [
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, twins: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, twins: 1, linkPlacement: .empty),
        GeneratorConfig(colors: 3, capacity: 4, emptyBottles: 2, twins: 1, linkPlacement: .filled),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, overflow: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, overflow: 1, linkPlacement: .mixed),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, overflow: 2),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, twins: 1, overflow: 1),
        GeneratorConfig(colors: 4, capacity: 2, emptyBottles: 2, twins: 1, overflow: 1, linkPlacement: .filled),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, twins: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, essence: 1, overflow: 1),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 2, narrowNecks: 1, funnels: 1, twins: 1, linkPlacement: .filled),
        GeneratorConfig(colors: 3, capacity: 3, emptyBottles: 1, locks: 1, overflow: 1, linkPlacement: .mixed),
    ]

    /// The configurations' levels, plus copies with a modifier on a linked flask (the
    /// generator never puts one there, but the rules allow it).
    static func levels(_ config: GeneratorConfig, seeds: ClosedRange<UInt64>) -> [GameState] {
        seeds.flatMap { seed -> [GameState] in
            let s = Generator.candidate(config, seed: seed)
            guard let link = s.links.first else { return [s] }
            var marked = s
            let (a, b) = link.endpoints
            switch seed % 3 {
            case 0: marked.bottles[b].modifiers = [.narrowNeck]
            case 1:
                if let color = s.bottles.flatMap(\.layers).compactMap(\.colorID).first { marked.bottles[a].modifiers = [.essence(color)] }
            default: marked.bottles[a].modifiers = [.funnel]
            }
            return marked.validate().isEmpty ? [s, marked] : [s]
        }
    }

    /// Solver vs. the naive BFS (no pruning, no canonical keys) on many small random levels.
    @Test(arguments: configs.indices)
    func solverMatchesReference(_ index: Int) throws {
        let config = Self.configs[index]
        var checked = 0
        for s in Self.levels(config, seeds: 1...20) {
            #expect(s.validate().isEmpty, "\(s)")
            #expect(!s.links.isEmpty, "\(s)")
            let expected = referenceMinMoves(s)
            let result = Solver().solve(s)
            #expect(result.moves?.count == expected, "\(s)")
            if case .unsolvable = result { #expect(expected == nil) }
            if let moves = result.moves {
                var replay = s
                for m in moves { replay = try #require(replay.pouring(m)) }
                #expect(replay.isSolved)
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    /// The pruned candidate list reaches the same canonical children as every legal move,
    /// minus pours that only relocate an unlinked flask (rule 2, a canonical no-op).
    @Test func pruningKeepsEveryDistinctChild() {
        for config in Self.configs {
            for var s in Self.levels(config, seeds: 1...8) {
                for step in 0..<8 {
                    let key = s.canonicalKey
                    let all = Set(s.legalMoves().compactMap { s.pouring($0)?.canonicalKey }).subtracting([key])
                    let pruned = Set(Solver.candidateMoves(s).compactMap { s.pouring($0)?.canonicalKey }).subtracting([key])
                    #expect(all == pruned, "\(s)")
                    let moves = s.legalMoves()
                    guard !moves.isEmpty else { break }
                    s = s.pouring(moves[(step * 5 + 3) % moves.count])!
                }
            }
        }
    }

    /// Linked empty flasks are targets of their own; pouring into the second twin is skipped.
    @Test func linkedFlasksAreNeverAlike() {
        let s = GameState(bottles: [flask([0, 1, 1], 3), flask([1, 0, 0], 3), flask([], 3), flask([], 3), flask([], 3), flask([], 3)],
                          links: [.overflow(from: 0, to: 2), .twins(4, 5)])
        let moves = Solver.candidateMoves(s)
        #expect(moves.contains(Move(from: 1, to: 2)) && moves.contains(Move(from: 1, to: 3)))   // pipe end vs plain
        #expect(moves.contains(Move(from: 1, to: 4)) && !moves.contains(Move(from: 1, to: 5)))  // one twin only
        #expect(s.canPour(Move(from: 1, to: 5)))
        // A linked flask poured out whole is a real move (the link stays behind).
        let whole = GameState(bottles: [flask([0, 0, 0], 3), flask([1, 1, 1], 3), flask([], 3), flask([], 3)],
                              links: [.overflow(from: 0, to: 1)])
        #expect(Solver.candidateMoves(whole) == [Move(from: 0, to: 2), Move(from: 1, to: 2)])
        var plain = whole
        plain.links = []
        #expect(Solver.candidateMoves(plain).isEmpty)
    }
}

/// StateKey with links.
@Suite struct LinkKeyTests {
    static func randomStates() -> [GameState] {
        var result: [GameState] = []
        let extra = GeneratorConfig(colors: 6, emptyBottles: 2, locks: 1, essence: 1, twins: 1, overflow: 1)
        for config in LinkSolverTests.configs + [extra] {
            for var s in LinkSolverTests.levels(config, seeds: 1...4) {
                result.append(s)
                for step in 0..<6 {
                    let moves = s.legalMoves()
                    guard !moves.isEmpty else { break }
                    s = s.pouring(moves[(step * 7 + 1) % moves.count])!
                    result.append(s)
                }
            }
        }
        return result
    }

    @Test func keyIsBottleOrderIndependent() {
        var rng = SplitMix64(seed: 8)
        for s in Self.randomStates() {
            for _ in 0..<3 {
                var order = Array(s.bottles.indices)
                rng.shuffle(&order)
                #expect(s.permuted(by: order).canonicalKey == s.canonicalKey)
            }
        }
    }

    /// The linked fast path and the general encoding are both canonical forms: they agree on
    /// which states are the same position.
    @Test func fastPathAgreesWithTheGeneralEncoding() {
        let states = Self.randomStates()
        var rng = SplitMix64(seed: 3)
        var fast = 0
        for (i, a) in states.enumerated() {
            guard let codes = StateKey.linkedCodes(a) else { continue }
            fast += 1
            #expect(StateKey(a).codes == codes)
            var order = Array(a.bottles.indices)
            rng.shuffle(&order)
            let b = a.permuted(by: order)
            #expect(StateKey.linkedCodes(b) == codes && StateKey.extendedCodes(b) == StateKey.extendedCodes(a))
            for other in states[(i + 1)...].prefix(20) {
                guard let otherCodes = StateKey.linkedCodes(other) else { continue }
                #expect((otherCodes == codes) == (StateKey.extendedCodes(other) == StateKey.extendedCodes(a)))
            }
        }
        #expect(fast > 100)
    }

    @Test func linksArePartOfTheKey() {
        let base = GameState(bottles: [flask([0, 1, 1], 3), flask([1, 0, 0], 3), flask([], 3), flask([], 3)])
        var keys: Set<StateKey> = [base.canonicalKey]
        for links: [Link] in [[.twins(2, 3)], [.twins(0, 1)], [.twins(0, 2)], [.twins(1, 2)],
                              [.overflow(from: 0, to: 2)], [.overflow(from: 2, to: 0)], [.overflow(from: 0, to: 1)],
                              [.overflow(from: 1, to: 0)], [.overflow(from: 2, to: 3)], [.twins(0, 1), .overflow(from: 2, to: 3)]] {
            var s = base
            s.links = links
            keys.insert(s.canonicalKey)
        }
        #expect(keys.count == 11)
        // Equivalent descriptions give one key: twin order, and a pipe between the two empty flasks.
        var a = base, b = base, c = base, d = base
        a.links = [.twins(2, 3)]
        b.links = [.twins(3, 2)]
        c.links = [.overflow(from: 2, to: 3)]
        d.links = [.overflow(from: 3, to: 2)]
        #expect(a.canonicalKey == b.canonicalKey && c.canonicalKey == d.canonicalKey)
        // Two empty twin pairs, or two pipes between four empty flasks.
        let empties = GameState(bottles: (0..<4).map { _ in flask([], 2) } + [flask([0, 0], 2)], links: [.twins(0, 1), .twins(2, 3)])
        #expect(empties.permuted(by: [3, 1, 4, 2, 0]).canonicalKey == empties.canonicalKey)
        var pipes = empties
        pipes.links = [.overflow(from: 0, to: 1), .overflow(from: 2, to: 3)]
        #expect(pipes.permuted(by: [2, 4, 3, 0, 1]).canonicalKey == pipes.canonicalKey)
        var crossed = pipes
        crossed.links = [.overflow(from: 0, to: 1), .overflow(from: 1, to: 2)]
        #expect(crossed.canonicalKey != pipes.canonicalKey)
    }
}

/// Level files, validation and sessions with links.
@Suite struct LinkLevelTests {
    static let sample = GameState(bottles: [flask([0, 1, 1], 3), flask([1, 0, 0], 3), flask([], 3), flask([], 3),
                                            flask([2, 2, 2], 3)],
                                  links: [.twins(2, 3), .overflow(from: 0, to: 4)])

    @Test func jsonRoundTrip() throws {
        let level = LevelDefinition(id: "t1", state: Self.sample, meta: LevelMeta(seed: 1, minMoves: 4))
        let pack = LevelPack(name: "Twin Towers", kind: .chapter, chapter: 8, location: "Twin Towers",
                             introduces: [.twins, .overflow], levels: [level])
        #expect(pack.requiredVersion == 2)
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""type" : "twins""#) && text.contains(#""between" : [2, 3]"#))
        #expect(text.contains(#""type" : "overflow""#) && text.contains(#""from" : 0"#) && text.contains(#""to" : 4"#))
        let loaded = try LevelLoader.load(data)
        #expect(loaded.levels == pack.levels && loaded.introduces == [.twins, .overflow])
        #expect(loaded.levels[0].gameState == Self.sample)
        #expect(try LevelLoader.encode(loaded) == data)
    }

    @Test func handWrittenJSON() throws {
        let json = #"""
        {"version": 2, "levels": [{"id": "a", "capacity": 2, "bottles": [
          {"layers": [0, 1]}, {"layers": [1, 0]}, {"layers": []}, {"layers": []}],
          "links": [{"type": "twins", "between": [2, 3]}, {"type": "overflow", "from": 0, "to": 1}]}]}
        """#
        let s = try LevelLoader.load(Data(json.utf8)).levels[0].gameState
        #expect(s.links == [.twins(2, 3), .overflow(from: 0, to: 1)])
        #expect(s.validate().isEmpty)
        let v1 = json.replacingOccurrences(of: #""version": 2"#, with: #""version": 1"#)
        #expect(throws: LevelLoadError.needsVersion2(id: "a")) { try LevelLoader.load(Data(v1.utf8)) }
    }

    @Test func validation() {
        #expect(Self.sample.validate().isEmpty)
        var s = Self.sample
        s.links = [.twins(2, 3), .overflow(from: 3, to: 4)]
        #expect(s.validate() == [.flaskInSeveralLinks(bottle: 3)])
        s.links = [.twins(2, 3), .twins(3, 2)]
        #expect(s.validate() == [.flaskInSeveralLinks(bottle: 2), .flaskInSeveralLinks(bottle: 3)])
        s.links = [.twins(2, 2)]
        #expect(s.validate() == [.invalidLink(.twins(2, 2))])
        s.links = [.overflow(from: 0, to: 9)]
        #expect(s.validate() == [.invalidLink(.overflow(from: 0, to: 9))])
        var sealed = Self.sample
        sealed.bottles[2].layers = layers([-1])
        sealed.bottles[4].modifiers = [.sealed(1)]
        sealed.links = [.twins(4, 3)]
        #expect(sealed.validate() == [.sealedTwin(bottle: 4)])
        // A sealed flask at either end of a pipe is fine (its key opens it as usual).
        sealed.links = [.overflow(from: 4, to: 3)]
        #expect(sealed.validate().isEmpty)
        sealed.links = [.overflow(from: 3, to: 4)]
        #expect(sealed.validate().isEmpty)
        for e in [ValidationError.flaskInSeveralLinks(bottle: 1), .sealedTwin(bottle: 2)] {
            #expect(!e.description.isEmpty)
        }
        // Unimplemented links still don't load.
        var gate = Self.sample
        gate.links = [.switchGate(switch: 0, gate: 1)]
        #expect(gate.validate() == [.unsupportedMechanic("switchGate")])
    }

    @Test func undoAndRestartRestoreEverything() throws {
        var session = GameSession(Self.sample)
        let played = session.play(Move(from: 0, to: 2))                 // the 1s split into the twins
        let turn = try #require(played)
        #expect(turn.pour?.shares == [PourShare(bottle: 3, amount: 1, route: .twin)] && session.lastPour == turn.pour)
        #expect(session.state.bottles.map(\.layers) == [layers([0]), layers([1, 0, 0]), layers([1]), layers([1]), layers([2, 2, 2])])
        session.apply(Move(from: 1, to: 0))
        #expect(session.state.bottles[0].layers == layers([0, 0, 0]))
        session.undo()
        #expect(session.state.bottles.map(\.layers) == [layers([0]), layers([1, 0, 0]), layers([1]), layers([1]), layers([2, 2, 2])])
        #expect(session.lastPour == nil && session.state.links == Self.sample.links)
        session.undo()
        #expect(session.state == Self.sample && !session.canUndo)
        session.apply(Move(from: 0, to: 2))
        session.restart()
        #expect(session.state == Self.sample && session.moveCount == 0 && session.lastPour == nil)
    }

    /// Murky flags: shared layers land visible in the twin and at the pipe's far end.
    @Test func murkyMasksFollowEveryLanding() throws {
        let s = GameState(bottles: [flask([2, 1, 0, 0], 4), flask([], 4), flask([], 4), flask([0, 2, 1, 1], 4),
                                    flask([1, 2, 0, 2], 4)],
                          links: [.twins(1, 2)])
        var session = GameSession(s, hidden: true)
        #expect(session.hiddenMasks[0] == [true, true, false, false])
        session.apply(Move(from: 0, to: 1))
        #expect(session.hiddenMasks[0] == [true, false] && session.hiddenMasks[1] == [false] && session.hiddenMasks[2] == [false])
        session.undo()
        #expect(session.hiddenMasks[0] == [true, true, false, false] && session.hiddenMasks[1] == [] && session.hiddenMasks[2] == [])
        let pipe = GameState(bottles: [flask([2, 1, 0, 0], 4), flask([2, 1, 2, 0], 4), flask([], 4), flask([0, 2, 1, 1], 4),
                                       flask([], 4)],
                             links: [.overflow(from: 1, to: 2)])
        var murky = GameSession(pipe, hidden: true)
        murky.apply(Move(from: 0, to: 1))
        #expect(murky.state.bottles[2].layers == layers([0, 0]) && murky.hiddenMasks[2] == [false, false])
        #expect(murky.hiddenMasks[0] == [true, false])
    }
}

/// Generator options for links.
@Suite struct LinkGeneratorTests {
    @Test func noLinksLeaveEveryLevelUnchanged() {
        for seed in UInt64(1)...10 {
            let config = GeneratorConfig(colors: 5, locks: 1, essence: 1, narrowNecks: 1, taps: 1)
            var linked = config
            linked.twins = 1
            linked.overflow = 1
            let plain = Generator.candidate(config, seed: seed)
            let marked = Generator.candidate(linked, seed: seed)
            #expect(marked.bottles == plain.bottles)
            #expect(plain.links.isEmpty && marked.links.count == 2)
        }
    }

    @Test(arguments: LinkPlacement.allCases)
    func placementRules(_ placement: LinkPlacement) {
        for seed in UInt64(1)...30 {
            let config = GeneratorConfig(colors: 5, emptyBottles: 3, locks: 1, essence: 1, twins: 1, overflow: 1,
                                         linkPlacement: placement)
            let s = Generator.candidate(config, seed: seed)
            #expect(s.validate().isEmpty, "\(s)")
            let ends = s.links.flatMap { [$0.endpoints.0, $0.endpoints.1] }
            #expect(Set(ends).count == ends.count && ends.allSatisfy { s.bottles[$0].isPlain })
            for link in s.links {
                let (a, b) = link.endpoints
                switch (placement, link) {
                case (.filled, _): #expect(!s.bottles[a].isEmpty && !s.bottles[b].isEmpty)
                case (.empty, _), (.mixed, .twins): #expect(s.bottles[a].isEmpty && s.bottles[b].isEmpty)
                case (.mixed, .overflow): #expect(!s.bottles[a].isEmpty && s.bottles[b].isEmpty)
                default: break
                }
            }
            if placement != .empty && placement != .mixed { #expect(s.links.count == 2) }
        }
        // Too few flasks: fewer links.
        let tight = Generator.candidate(GeneratorConfig(colors: 3, emptyBottles: 2, twins: 2, overflow: 1, linkPlacement: .empty), seed: 1)
        #expect(tight.links.count == 1)
    }

    @Test func generationIsDeterministicAndLinksMatter() throws {
        let config = GeneratorConfig(colors: 4, capacity: 4, emptyBottles: 2, seed: 1, twins: 1, linkPlacement: .filled,
                                     requireLinksMatter: true, linkCost: LinkImpact.strongCost)
        let a = try Generator.generate(config, count: 2)
        let b = try Generator.generate(config, count: 2)
        #expect(a == b)
        for level in a {
            #expect(LinkImpact.instances(in: level.state).count == 1)
            #expect(LinkImpact.everyLinkMatters(level.state, minMoves: level.report.minMoves, cost: LinkImpact.strongCost))
        }
    }

    @Test func tutorialChecks() {
        #expect(LinkImpact.solvesUsingEveryLink(LinkPuzzleTests.twinsNeeded, in: 4))
        // A level whose solution never needs to pour into its twins.
        let idle = GameState(bottles: [flask([0, 1], 2), flask([1, 0], 2), flask([], 2), flask([], 2), flask([], 2)],
                             links: [.twins(3, 4)])
        let moves = Solver().solve(idle).moves?.count ?? 0
        #expect(moves > 0 && !LinkImpact.solvesUsingEveryLink(idle, in: moves))
        #expect(LinkImpact.solvesUsingEveryLink(state([[0, 0], []], capacity: 2), in: 1))
        #expect(LinkImpact.instances(in: Self.sampleWithSeal()).count == 2)
    }

    static func sampleWithSeal() -> GameState {
        var s = LinkLevelTests.sample
        s.bottles[0].layers = layers([0, 1, -1])
        s.bottles[1].modifiers = [.sealed(1)]
        return s
    }
}
