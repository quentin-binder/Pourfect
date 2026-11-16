import Foundation
import Testing
@testable import BottleSortCore

@Suite struct LevelFileV2Tests {
    /// A level using every v2 feature (none of them playable yet, so only `decode` takes it).
    static func everything() -> LevelDefinition {
        var s = state([[0, 1, 0, 1], [1, 0, 1, 0], [], [], []])
        s.bottles[1].lockedBy = 3
        s.bottles[2].layers = [.key(3)]
        s.bottles[0].modifiers = [.narrowNeck, .frozen(layer: 1, turns: 3)]
        s.bottles[2].modifiers += [.essence(1)]
        s.bottles[3].modifiers = [.bubbling(every: 3, phase: 1), .funnel]
        s.bottles[4].modifiers = [.funnel, .cauldron([Recipe(2, 1, result: 0)])]
        s.links = [.twins(0, 3), .overflow(from: 1, to: 4), .switchGate(switch: 2, gate: 0)]
        s.goal = .order([GoalTarget(bottle: 4, layers: [.color(0), .color(0), .color(0), .color(0)])])
        return LevelDefinition(id: "v2", state: s, meta: LevelMeta(seed: 9))
    }

    @Test func v2RoundTripKeepsEverything() throws {
        let level = Self.everything()
        let pack = LevelPack(name: "Mechanics", levels: [level])
        #expect(pack.requiredVersion == 2)
        let data = try LevelLoader.encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""version" : 2"#))
        #expect(text.contains(#""lockedBy" : 3"#))
        #expect(text.contains(#""type" : "narrowNeck""#))
        #expect(text.contains(#""between" : [0, 3]"#))
        #expect(text.contains(#""type" : "order""#))
        let decoded = try LevelLoader.decode(data)
        #expect(decoded.version == 2)
        #expect(decoded.levels == [level])
        #expect(decoded.levels[0].gameState == level.gameState)
        #expect(decoded.levels[0].gameState.canonicalKey == level.gameState.canonicalKey)
        // Encoding again gives the same bytes.
        #expect(try LevelLoader.encode(decoded) == data)
    }

    @Test func gameStateSurvivesTheLevelDefinition() {
        let level = Self.everything()
        let s = level.gameState
        #expect(s.bottles[0].modifiers == [.narrowNeck, .frozen(layer: 1, turns: 3)])
        #expect(s.bottles[1].lockedBy == 3)
        #expect(s.bottles[2].modifiers == [.essence(1)])
        #expect(s.links.count == 3)
        #expect(LevelDefinition(id: "v2", state: s, meta: LevelMeta(seed: 9)) == level)
    }

    @Test func unimplementedMechanicsDontLoadForPlay() throws {
        let data = try LevelLoader.encode(LevelPack(levels: [Self.everything()]))
        #expect(throws: LevelLoadError.self) { try LevelLoader.load(data) }
        let errors = Self.everything().gameState.validate()
        for name in ["essence", "narrowNeck", "tap", "funnel", "frozen", "bubbling", "twins", "overflow", "cauldron", "switchGate"] {
            #expect(!errors.contains(.unsupportedMechanic(name)), "\(name)")
        }
        for name in ["order"] {
            #expect(errors.contains(.unsupportedMechanic(name)), "\(name)")
        }
        #expect(Solver().solve(Self.everything().gameState) == .unknown(reason: .unsupportedState))
    }

    @Test func classicAndSealedPacksStayVersion1() throws {
        var s = state([[0, 1, 0, 1], [1, 0, 1, 0], [], []])
        s.bottles[2].layers = [.key(2)]
        s.bottles[3].lockedBy = 2
        let pack = LevelPack(version: 2, levels: [LevelDefinition(id: "x", state: s)])
        #expect(pack.requiredVersion == 1)
        let text = String(decoding: try LevelLoader.encode(pack), as: UTF8.self)
        #expect(text.contains(#""version" : 1"#))
        #expect(!text.contains("modifiers") && !text.contains("links") && !text.contains("goal"))
        #expect(try LevelLoader.load(Data(text.utf8)).levels[0].gameState == s)
    }

    @Test func version2FileWithV1ContentLoads() throws {
        let json = #"{"version": 2, "levels": [{"id": "a", "capacity": 2, "bottles": [{"layers": [0, 1]}, {"layers": [1, 0]}, {"layers": []}]}]}"#
        let pack = try LevelLoader.load(Data(json.utf8))
        #expect(pack.levels[0].gameState == state([[0, 1], [1, 0], []], capacity: 2))
    }

    @Test func version1FileMayNotUseV2Fields() {
        let json = #"{"version": 1, "levels": [{"id": "a", "capacity": 2, "bottles": [{"layers": [0, 0], "modifiers": [{"type": "funnel"}]}, {"layers": []}]}]}"#
        #expect(throws: LevelLoadError.needsVersion2(id: "a")) { try LevelLoader.decode(Data(json.utf8)) }
    }

    @Test func modifierJSONForms() throws {
        let modifiers: [BottleModifier] = [.sealed(2), .essence(4), .narrowNeck, .funnel, .tap,
                                           .frozen(layer: 0, turns: 5), .bubbling(every: 4, phase: 2),
                                           .cauldron([Recipe(3, 1, result: 7), Recipe(0, 2, result: 5)])]
        let data = try JSONEncoder().encode(modifiers)
        let back = try JSONDecoder().decode([BottleModifier].self, from: data)
        #expect(back == modifiers.map(\.normalized))
        let unknown = Data(#"[{"type": "teleport"}]"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([BottleModifier].self, from: unknown) }
    }

    @Test func linkAndGoalJSONForms() throws {
        let links: [Link] = [.twins(1, 2), .overflow(from: 0, to: 3), .switchGate(switch: 4, gate: 5)]
        #expect(try JSONDecoder().decode([Link].self, from: JSONEncoder().encode(links)) == links)
        let goals: [Goal] = [.standard, .rescue(withinMoves: 12),
                             .pattern([GoalTarget(bottle: 1, layers: [.color(0), .color(1)])])]
        #expect(try JSONDecoder().decode([Goal].self, from: JSONEncoder().encode(goals)) == goals)
    }

    @Test func gameStateCodableKeepsTheOldShape() throws {
        let s = state([[0, 1], [1, 0], []], capacity: 2)
        let text = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(!text.contains("links") && !text.contains("goal") && !text.contains("moveCount") && !text.contains("modifiers"))
        #expect(try JSONDecoder().decode(GameState.self, from: Data(text.utf8)) == s)
        var rich = s
        rich.links = [.twins(0, 1)]
        rich.moveCount = 4
        rich.bottles[2].modifiers = [.tap]
        #expect(try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(rich)) == rich)
    }
}
