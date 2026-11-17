import BottleSortCore
import Foundation
import Testing
@testable import DistilleryCore

@Suite struct ContentTests {
    static func load(_ pack: DistillPack) throws -> DistillPackFile {
        try DistillPackFile.decode(Data(contentsOf: distilleryLevelsURL.appendingPathComponent(pack.fileName)))
    }

    @Test(arguments: DistillPack.allCases) func shippedPackIsValidAndSolvable(_ pack: DistillPack) throws {
        let file = try Self.load(pack)
        #expect(file.validate().isEmpty)
        #expect(file.id == pack.id)
        #expect(file.levels.count == DistillContent.levelsPerPack)
        #expect(file.levels.map(\.id) == (0..<20).map(pack.levelID))
        for l in file.levels {
            let issues = l.validateSolving()
            #expect(issues.isEmpty, "\(issues)")
            #expect(l.board.width <= 7 && l.board.height <= 7)
            #expect(!l.board.isWon)
        }
    }

    @Test func stagesTeachInOrder() throws {
        func has(_ l: DistillLevel, _ m: String) -> Bool { l.stats!.mechanics.contains(m) }
        let s1 = try Self.load(.stage1).levels, s2 = try Self.load(.stage2).levels, s3 = try Self.load(.stage3).levels
        for l in s1 {
            #expect(l.board.width <= 5)
            #expect(l.board.sources.count == 1 && l.board.targets.count == 1)
            #expect(!l.board.pieces.contains { $0.valve != nil || $0.coil != nil })
        }
        #expect(s1.prefix(6).allSatisfy { $0.board.width == 4 })
        for l in s2 { #expect(!l.board.pieces.contains { $0.valve != nil || $0.coil != nil }) }
        #expect(has(s2[0], "tee"))
        #expect(s2[4].board.pieces.contains { $0.fixed })
        #expect(s2[8].board.sources.count == 2)
        #expect(has(s2[12], "cross"))
        #expect(has(s3[0], "coil"))
        #expect(has(s3[4], "valve"))
        #expect(s3.suffix(12).allSatisfy { $0.board.width == 7 })
        for (k, slot) in DistillContent.slots(.stage2).enumerated() where slot.teaches != nil { #expect(k % 4 == 0) }
    }

    @Test(arguments: DistillPack.allCases) func difficultyRises(_ pack: DistillPack) throws {
        let scores = try Self.load(pack).levels.map { $0.stats!.score }
        // Rising curve: each quarter's mean above the previous one.
        let quarters = stride(from: 0, to: 20, by: 5).map { scores[$0..<($0 + 5)].reduce(0, +) }
        #expect(quarters == quarters.sorted(), "\(scores)")
    }

    @Test func challengePacksAreHarderThanTheStages() throws {
        func mean(_ p: DistillPack) throws -> Int { try Self.load(p).levels.map(\.minTaps).reduce(0, +) / 20 }
        #expect(try mean(.stage1) < mean(.stage2))
        #expect(try mean(.stage2) < mean(.stage3))
        #expect(try mean(.stage3) < mean(.expert))
        #expect(try mean(.expert) < mean(.master))
    }

    /// The files are exactly what the presets generate (deterministic output).
    @Test(.enabled(if: heavyTestsEnabled), arguments: DistillPack.allCases) func packsRegenerateIdentically(_ pack: DistillPack) throws {
        let fresh = try #require(DistillContent.pack(pack)).encoded()
        let shipped = try Data(contentsOf: distilleryLevelsURL.appendingPathComponent(pack.fileName))
        #expect(fresh == shipped)
    }

    @Test func progression() {
        var open = Array(repeating: false, count: 10)
        open[0] = true; open[1] = true
        #expect(!DistillProgression.isStageUnlocked(1, chapterUnlocked: open))
        open[2] = true
        #expect(DistillProgression.isStageUnlocked(1, chapterUnlocked: open))
        #expect(!DistillProgression.isStageUnlocked(2, chapterUnlocked: open))
        open[5] = true
        #expect(DistillProgression.isStageUnlocked(2, chapterUnlocked: open))
        open[8] = true
        #expect(DistillProgression.isStageUnlocked(3, chapterUnlocked: open))
        #expect(!DistillProgression.isStageUnlocked(4, chapterUnlocked: open))
        #expect(DistillProgression.isLevelUnlocked(0, won: []))
        #expect(!DistillProgression.isLevelUnlocked(2, won: [true, false]))
        #expect(DistillProgression.isLevelUnlocked(2, won: [true, true]))
        #expect(DistillProgression.sceneOnOpening(stage: 2, seen: []) == "distillery.2")
        #expect(DistillProgression.sceneOnOpening(stage: 2, seen: ["distillery.2"]) == nil)
        // The app plays these as `StoryScene.distillery(n)`: the same ids.
        for n in DistillProgression.stages {
            #expect(StoryScene.distillery(n).id == DistillProgression.sceneID(stage: n))
        }
        #expect(Array(Story.distilleries) == Array(DistillProgression.stages))
        #expect(DistillPack.stage(3) == .stage3)
        #expect(DistillPack.expert.stage == nil)
    }
}

@Suite struct LevelFormatTests {
    let json = """
    {"id":"t1","width":3,"height":3,"grid":["S I0 F","C2* . X",". L1 ."],
     "sources":[{"r":0,"c":0,"color":0,"dir":"e"}],"targets":[{"r":0,"c":2,"color":5,"dir":"w"}],
     "coils":[{"r":0,"c":1,"from":0,"to":5}],"minTaps":1}
    """

    @Test func decodesAndRoundTrips() throws {
        let l = try JSONDecoder().decode(DistillLevel.self, from: Data(json.utf8))
        #expect(l.board[P(1, 0)] == DistillPiece(.cap, rotation: 2, fixed: true))
        #expect(l.board[P(1, 2)].shape == .cross)
        #expect(l.board[P(0, 1)].coil == DistillCoil(from: 0, to: 5))
        #expect(l.validate().isEmpty)
        #expect(l.validateSolving().isEmpty)
        let file = DistillPackFile(id: "p", title: "P", levels: [l])
        let back = try DistillPackFile.decode(file.encoded())
        #expect(back == file)
        #expect(back.levels[0].gridRows == ["S I0 F", "C2* . X", ". L1 ."])
    }

    @Test func rejectsBadInput() throws {
        let decoder = JSONDecoder()
        for bad in [json.replacingOccurrences(of: "I0", with: "I7"), json.replacingOccurrences(of: "\"C2* . X\"", with: "\"C2* .\""),
                    json.replacingOccurrences(of: "\"height\":3", with: "\"height\":2"),
                    json.replacingOccurrences(of: "\"width\":3", with: "\"width\":9")] {
            #expect(throws: (any Error).self) { try decoder.decode(DistillLevel.self, from: Data(bad.utf8)) }
        }
        let newer = #"{"format":"pourfect-distillery","version":2,"id":"p","title":"P","levels":[]}"#
        #expect(throws: (any Error).self) { try DistillPackFile.decode(Data(newer.utf8)) }
        let other = #"{"format":"pourfect-match3","version":1,"id":"p","title":"P","levels":[]}"#
        #expect(throws: (any Error).self) { try DistillPackFile.decode(Data(other.utf8)) }
    }

    @Test func validationFindsProblems() throws {
        var l = try JSONDecoder().decode(DistillLevel.self, from: Data(json.utf8))
        l.board[P(1, 1)] = DistillPiece(.straight, valve: 3)
        l.board.targets.append(DistillTarget(pos: P(0, 0), color: 1, inlet: .north))
        l.board.sources[0].color = 14
        let messages = l.validate().map(\.message)
        #expect(messages.contains { $0.contains("valve") })
        #expect(messages.contains { $0.contains("two things") })
        #expect(messages.contains { $0.contains("faces the edge") })
        #expect(messages.contains { $0.contains("color 14") })
        let wrongTaps = DistillLevel(id: "w", board: try JSONDecoder().decode(DistillLevel.self, from: Data(json.utf8)).board, minTaps: 3)
        #expect(wrongTaps.validateSolving().map(\.message) == ["minTaps 3, solver 1"])
    }
}
