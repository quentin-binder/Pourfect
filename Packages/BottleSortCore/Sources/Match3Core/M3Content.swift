import BottleSortCore

/// The shipped episodes as a reproducible preset (`m3gen episodes` tunes it into Levels/match3).
/// Ten episodes of eight levels, one after each sorting chapter (DECISIONS 261).
public struct M3EpisodePreset: Sendable {
    public var episode: M3Episode
    public var specs: [M3LevelSpec]
}

public enum M3Content {
    /// Reference-bot games per tuning measurement.
    public static let tuningRuns = 200
    public static let levelsPerEpisode = 8

    public static func fileName(_ episode: Int) -> String {
        "gathering_" + (episode < 10 ? "0" : "") + "\(episode).json"
    }

    /// Target pass rate: 90 % for the first level, falling linearly to 55 % for the 80th.
    public static func targetPercent(episode: Int, level: Int) -> Int {
        let index = (episode - 1) * levelsPerEpisode + (level - 1)
        return 90 - (35 * index + 39) / 79
    }

    /// The level seed: fixed per level id.
    public static func seed(episode: Int, level: Int) -> UInt64 {
        var mixer = SplitMix64(seed: 0x5EED_0000 &+ UInt64(episode * 100 + level))
        return mixer.next() & 0x1F_FFFF_FFFF_FFFF  // < 2^53: exact in any JSON reader
    }

    // MARK: Shapes ("." hole, "o" cell, "1"/"2" frost, "A"/"B"/"C" crate, "F" flask)

    static let s6 = Array(repeating: "oooooo", count: 6)
    static let s7 = Array(repeating: "ooooooo", count: 7)
    static let s8 = Array(repeating: "oooooooo", count: 8)
    static let cut8 = [".oooooo.", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", ".oooooo."]
    static let diamond7 = ["..ooo..", ".ooooo.", "ooooooo", "ooooooo", "ooooooo", ".ooooo.", "..ooo.."]
    static let ring8 = ["oooooooo", "oooooooo", "oooooooo", "ooo..ooo", "ooo..ooo", "oooooooo", "oooooooo", "oooooooo"]
    static let plus8 = ["..oooo..", "..oooo..", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "..oooo..", "..oooo.."]
    static let wide8x7 = Array(repeating: "oooooooo", count: 7)

    static func kinds(_ n: Int, featuring f: M3Kind) -> [M3Kind] {
        var k = Array(M3Kind.allCases.prefix(n))
        if !k.contains(f) { k[n - 1] = f }
        return k
    }

    struct Raw {
        var layout: [String]
        var kinds: Int
        var goals: [M3Goal]
        var drops: M3Drops? = nil
        var range: ClosedRange<Int> = 20...32
    }

    static func preset(_ number: Int, _ name: String, _ subtitle: String, featuring f: M3Kind, _ raws: [Raw]) -> M3EpisodePreset {
        precondition(raws.count == levelsPerEpisode)
        let specs = raws.enumerated().map { i, raw in
            M3LevelSpec(id: "m3-\(number < 10 ? "0" : "")\(number)-\(i + 1)", title: "\(name) \(i + 1)",
                        layout: raw.layout, kinds: kinds(raw.kinds, featuring: f), goals: raw.goals, drops: raw.drops,
                        targetPercent: targetPercent(episode: number, level: i + 1), moveRange: raw.range,
                        seed: seed(episode: number, level: i + 1))
        }
        return M3EpisodePreset(episode: M3Episode(number: number, name: name, subtitle: subtitle, followsChapter: number),
                               specs: specs)
    }

    // MARK: Episodes

    public static let episodes: [M3EpisodePreset] = [
        preset(1, "Mushroom Hollow", "Swap neighbours to line up three and gather mushrooms", featuring: .mushroom, [
            Raw(layout: s6, kinds: 4, goals: [.collect(.mushroom, 12)], range: 16...24),
            Raw(layout: s6, kinds: 4, goals: [.collect(.mushroom, 18)], range: 18...26),
            Raw(layout: s7, kinds: 4, goals: [.collect(.mushroom, 20), .collect(.crystal, 12)], range: 18...26),
            Raw(layout: s7, kinds: 4, goals: [.collect(.mushroom, 25)], range: 20...28),
            Raw(layout: s7, kinds: 5, goals: [.collect(.mushroom, 18), .collect(.feather, 15)], range: 20...28),
            Raw(layout: cut8, kinds: 5, goals: [.collect(.mushroom, 25)], range: 20...28),
            Raw(layout: diamond7, kinds: 5, goals: [.collect(.mushroom, 20), .collect(.moonflower, 15)], range: 20...28),
            Raw(layout: cut8, kinds: 5, goals: [.collect(.mushroom, 30), .score(6000)], range: 22...30),
        ]),
        preset(2, "Crystal Grotto", "Lines of four and five leave glowing specials behind", featuring: .crystal, [
            Raw(layout: s7, kinds: 5, goals: [.collect(.crystal, 20)], range: 18...26),
            Raw(layout: diamond7, kinds: 5, goals: [.collect(.crystal, 20), .collect(.mushroom, 12)], range: 20...28),
            Raw(layout: cut8, kinds: 5, goals: [.collect(.crystal, 30)], range: 20...28),
            Raw(layout: plus8, kinds: 5, goals: [.collect(.crystal, 22), .collect(.feather, 18)], range: 20...28),
            Raw(layout: s8, kinds: 5, goals: [.score(9000)], range: 20...28),
            Raw(layout: ring8, kinds: 5, goals: [.collect(.crystal, 28), .collect(.moonflower, 18)], range: 22...30),
            Raw(layout: diamond7, kinds: 5, goals: [.collect(.crystal, 30)], range: 22...30),
            Raw(layout: s8, kinds: 5, goals: [.collect(.crystal, 30), .collect(.ember, 20), .collect(.mushroom, 20)], range: 22...32),
        ]),
        preset(3, "Moonlit Meadow", "Frost holds an ingredient fast: match beside it to thaw it", featuring: .moonflower, [
            Raw(layout: ["ooooooo", "ooooooo", "ooooooo", "o11111o", "ooooooo", "ooooooo", "ooooooo"],
                kinds: 5, goals: [.frost, .collect(.moonflower, 10)], range: 16...24),
            Raw(layout: ["ooooooo", "ooooooo", "o1ooo1o", "o11o11o", "ooooooo", "ooooooo", "ooooooo"],
                kinds: 5, goals: [.frost, .collect(.moonflower, 12)], range: 18...26),
            Raw(layout: [".oooooo.", "oooooooo", "oooooooo", "oo1111oo", "oo1111oo", "oooooooo", "oooooooo", ".oooooo."],
                kinds: 5, goals: [.frost, .collect(.moonflower, 15)], range: 18...28),
            Raw(layout: s7, kinds: 5, goals: [.collect(.moonflower, 25), .collect(.crystal, 15)], range: 20...28),
            Raw(layout: ["..ooo..", ".o111o.", "ooooooo", "o11o11o", "ooooooo", ".o111o.", "..ooo.."],
                kinds: 5, goals: [.frost, .collect(.moonflower, 10)], range: 20...30),
            Raw(layout: ["oooooooo", "oooooooo", "11oooo11", "11oooo11", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.frost, .collect(.feather, 15)], range: 20...30),
            Raw(layout: ["oooooooo", "oooooooo", "oooooooo", "ooo..ooo", "o11..11o", "o111111o", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.frost], range: 20...30),
            Raw(layout: ["oooooooo", "o2oooo2o", "oooooooo", "oo1111oo", "oo1111oo", "oooooooo", "o2oooo2o", "oooooooo"],
                kinds: 5, goals: [.frost, .collect(.moonflower, 20)], range: 22...32),
        ]),
        preset(4, "Ember Hearth", "Double frost needs two thaws; blooms crack it from afar", featuring: .ember, [
            Raw(layout: ["ooooooo", "ooooooo", "ooooooo", "o22222o", "ooooooo", "ooooooo", "ooooooo"],
                kinds: 5, goals: [.frost, .collect(.ember, 15)], range: 18...28),
            Raw(layout: s8, kinds: 5, goals: [.collect(.ember, 30), .collect(.mushroom, 20)], range: 20...30),
            Raw(layout: [".oooooo.", "oooooooo", "o1oooo1o", "o12oo21o", "o12oo21o", "o1oooo1o", "oooooooo", ".oooooo."],
                kinds: 5, goals: [.frost, .collect(.ember, 15)], range: 22...30),
            Raw(layout: ["..oooo..", "..oooo..", "oooooooo", "oo2222oo", "oo2222oo", "oooooooo", "..oooo..", "..oooo.."],
                kinds: 5, goals: [.frost, .collect(.ember, 20)], range: 22...32),
            Raw(layout: cut8, kinds: 5, goals: [.collect(.ember, 35), .score(10000)], range: 22...32),
            Raw(layout: ["oooooooo", "oooooooo", "oooooooo", "22222222", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.frost, .collect(.ember, 18)], range: 22...32),
            Raw(layout: ["ooooooo", "o2ooo2o", "ooooooo", "o11o11o", "ooooooo", "o2ooo2o", "ooooooo"],
                kinds: 5, goals: [.frost, .collect(.crystal, 18)], range: 22...32),
            Raw(layout: ["oooooooo", "oooooooo", "o222222o", "oooooooo", "oooooooo", "o111111o", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.frost, .collect(.ember, 20)], range: 24...34),
        ]),
        preset(5, "Sealed Storeroom", "Rune-sealed crates break when you match beside them", featuring: .feather, [
            Raw(layout: ["ooooooo", "ooooooo", "ooooooo", "ooooooo", "ooooooo", "AoAoAoA", "AAAAAAA"],
                kinds: 5, goals: [.crates], range: 16...26),
            Raw(layout: ["oooooooo", "oooooooo", "oooooooo", "oooooooo", "ooAAAAoo", "ooAAAAoo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.crates, .collect(.feather, 15)], range: 18...28),
            Raw(layout: [".oooooo.", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "BBooooBB", "BBBBBBBB", ".BBBBBB."],
                kinds: 5, goals: [.crates], range: 20...30),
            Raw(layout: s8, kinds: 5, goals: [.collect(.feather, 30), .collect(.crystal, 25)], range: 22...30),
            Raw(layout: ["oooooooo", "oooooooo", "AooooooA", "AAooooAA", "AAooooAA", "AooooooA", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.crates, .collect(.feather, 18)], range: 22...30),
            Raw(layout: ["ooooooo", "ooooooo", "ooBBBoo", "ooBCBoo", "ooBBBoo", "ooooooo", "ooooooo"],
                kinds: 5, goals: [.crates, .collect(.feather, 15)], range: 22...32),
            Raw(layout: ["oooooooo", "oooooooo", "oooooooo", "oooooooo", "11111111", "oooooooo", "AAAAAAAA", "BBBBBBBB"],
                kinds: 5, goals: [.crates, .frost], range: 22...32),
            Raw(layout: ["..oooo..", "..oooo..", "ooBBBBoo", "oooooooo", "oooooooo", "ooBBBBoo", "..oooo..", "..oooo.."],
                kinds: 5, goals: [.crates, .collect(.feather, 22)], range: 24...34),
        ]),
        preset(6, "Icefall Ridge", "Frost and crates together on the high slopes", featuring: .crystal, [
            Raw(layout: ["oooooooo", "oooooooo", "o2o22o2o", "oooooooo", "oooooooo", "o2o22o2o", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.frost, .collect(.crystal, 15)], range: 20...30),
            Raw(layout: ["ooooooo", "ooooooo", "ooooooo", "1111111", "ooooooo", "AAAAAAA", "AAAAAAA"],
                kinds: 5, goals: [.frost, .crates], range: 20...30),
            Raw(layout: ring8, kinds: 6, goals: [.collect(.crystal, 22), .collect(.ember, 18)], range: 22...32),
            Raw(layout: ["oooooooo", "oooooooo", "22oooo22", "22oooo22", "oo2222oo", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.frost, .collect(.crystal, 15)], range: 22...32),
            Raw(layout: [".oooooo.", "oooooooo", "oBBBBBBo", "oooooooo", "oooooooo", "oCooooCo", "oooooooo", ".oooooo."],
                kinds: 5, goals: [.crates, .collect(.crystal, 18)], range: 22...32),
            Raw(layout: ["..ooo..", ".o222o.", "ooooooo", "o22o22o", "ooooooo", ".oBBBo.", "..BBB.."],
                kinds: 5, goals: [.frost, .crates, .collect(.crystal, 12)], range: 22...32),
            Raw(layout: s8, kinds: 6, goals: [.collect(.crystal, 30), .score(12000)], range: 24...34),
            Raw(layout: ["oooooooo", "o222222o", "oooooooo", "oooooooo", "oooooooo", "oAAAAAAo", "oBBBBBBo", "oooooooo"],
                kinds: 5, goals: [.frost, .crates, .collect(.crystal, 15)], range: 24...35),
        ]),
        preset(7, "Bogwater Springs", "Bring the potion flasks down: clear the cells below them", featuring: .drop, [
            Raw(layout: ["oooFooo", "ooooooo", "ooooooo", "ooooooo", "ooooooo", "ooooooo", "ooooooo"],
                kinds: 5, goals: [.drops(2)], drops: M3Drops(total: 2, maxOnBoard: 1), range: 14...26),
            Raw(layout: ["ooFooFoo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .collect(.drop, 15)], drops: M3Drops(total: 3, maxOnBoard: 2), range: 18...28),
            Raw(layout: s8, kinds: 5, goals: [.collect(.drop, 30), .collect(.moonflower, 25)], range: 22...32),
            Raw(layout: [".ooFFoo.", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", ".oooooo."],
                kinds: 5, goals: [.drops(4)], drops: M3Drops(total: 4, maxOnBoard: 2, columns: [2, 3, 4, 5]), range: 20...30),
            Raw(layout: ["ooooFooo", "oooooooo", "oooooooo", "oooooooo", "11111111", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .frost], drops: M3Drops(total: 3, maxOnBoard: 1), range: 22...32),
            Raw(layout: ["..oFoo..", "..oooo..", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "..oooo..", "..oooo.."],
                kinds: 5, goals: [.drops(2), .collect(.drop, 18)], drops: M3Drops(total: 2, maxOnBoard: 1, columns: [2, 3, 4, 5]), range: 22...34),
            Raw(layout: ["oooFoooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "AAoooAAA", "AAAAAAAA"],
                kinds: 5, goals: [.drops(3), .crates], drops: M3Drops(total: 3, maxOnBoard: 1), range: 22...34),
            Raw(layout: ["oFooooFo", "oooooooo", "oooooooo", "ooo..ooo", "ooo..ooo", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .collect(.drop, 15)], drops: M3Drops(total: 3, maxOnBoard: 2), range: 24...36),
        ]),
        preset(8, "Windy Rookery", "Feathers drift high among the old towers", featuring: .feather, [
            Raw(layout: ring8, kinds: 5, goals: [.collect(.feather, 30), .collect(.ember, 20)], range: 22...32),
            Raw(layout: ["oooFoooo", "oooooooo", "oooooooo", "oooooooo", "ooBBBBoo", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .crates], drops: M3Drops(total: 3, maxOnBoard: 1), range: 22...32),
            Raw(layout: ["oooooooo", "oooooooo", "o2oooo2o", "oo2oo2oo", "ooo22ooo", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 6, goals: [.frost, .collect(.feather, 15)], range: 22...34),
            Raw(layout: ["..oooo..", "..oooo..", "oooooooo", "oCoooCoo", "oooooooo", "oooooooo", "..oBBo..", "..oBBo.."],
                kinds: 5, goals: [.crates, .collect(.feather, 20)], range: 22...34),
            Raw(layout: ["oooooooo", "oooooooo", "oooooooo", "11111111", "11111111", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.frost, .score(12000)], range: 24...34),
            Raw(layout: ["oFooooFo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "o222222o", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .frost], drops: M3Drops(total: 3, maxOnBoard: 2), range: 24...36),
            Raw(layout: s8, kinds: 6, goals: [.collect(.feather, 30), .collect(.crystal, 25)], range: 24...35),
            Raw(layout: ["ooooFooo", "oooooooo", "o2oooo2o", "oooooooo", "oooooooo", "oAAAAAAo", "oBBBBBBo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .crates, .frost], drops: M3Drops(total: 3, maxOnBoard: 1), range: 24...36),
        ]),
        preset(9, "Alchemist's Garden", "Every herb at once for the great brew", featuring: .moonflower, [
            Raw(layout: cut8, kinds: 6, goals: [.collect(.moonflower, 25), .collect(.mushroom, 25)], range: 22...34),
            Raw(layout: ["oooooooo", "o22oo22o", "o22oo22o", "oooooooo", "oooooooo", "oooooooo", "AAoooAAA", "AAAAAAAA"],
                kinds: 5, goals: [.frost, .crates], range: 24...35),
            Raw(layout: ["ooFooFoo", "oooooooo", "oooooooo", "ooo..ooo", "ooo..ooo", "oooooooo", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .collect(.moonflower, 20)], drops: M3Drops(total: 3, maxOnBoard: 2), range: 24...36),
            Raw(layout: ["..oooo..", ".o2oo2o.", "oooooooo", "o2oooo2o", "oooooooo", "oBBBBBBo", ".oooooo.", "..oooo.."],
                kinds: 5, goals: [.frost, .crates, .collect(.moonflower, 15)], range: 24...35),
            Raw(layout: s8, kinds: 6, goals: [.collect(.moonflower, 28), .score(15000)], range: 24...35),
            Raw(layout: ["oooFoooo", "oooooooo", "11111111", "oooooooo", "oooooooo", "oooooooo", "oCooooCo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .frost, .crates], drops: M3Drops(total: 3, maxOnBoard: 1), range: 24...36),
            Raw(layout: ring8, kinds: 6, goals: [.collect(.moonflower, 25), .collect(.feather, 25), .collect(.ember, 20)], range: 26...36),
            Raw(layout: ["oooooooo", "o222222o", "o2oooo2o", "o2oCCo2o", "o2oCCo2o", "o2oooo2o", "o222222o", "oooooooo"],
                kinds: 5, goals: [.frost, .crates], range: 26...38),
        ]),
        preset(10, "Dragon's Larder", "Rare ingredients from the hoard's own pantry", featuring: .ember, [
            Raw(layout: s8, kinds: 6, goals: [.collect(.ember, 30), .collect(.drop, 25)], range: 24...35),
            Raw(layout: ["oooFFooo", "oooooooo", "o2oooo2o", "oooooooo", "oooooooo", "oooooooo", "BBoooBBB", "BBBBBBBB"],
                kinds: 5, goals: [.drops(3), .crates, .frost], drops: M3Drops(total: 3, maxOnBoard: 2), range: 26...40),
            Raw(layout: ["..oooo..", "..o22o..", "oooooooo", "o2oooo2o", "o2oooo2o", "oooooooo", "..oCCo..", "..oooo.."],
                kinds: 6, goals: [.frost, .crates, .collect(.ember, 15)], range: 26...38),
            Raw(layout: cut8, kinds: 6, goals: [.collect(.ember, 30), .score(15000)], range: 26...38),
            Raw(layout: ["oFooooFo", "oooooooo", "o222222o", "oooooooo", "oooooooo", "ooo..ooo", "oBBooBBo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .frost, .crates], drops: M3Drops(total: 3, maxOnBoard: 2), range: 26...40),
            Raw(layout: ["oooooooo", "22222222", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "22222222", "oooooooo"],
                kinds: 6, goals: [.frost, .collect(.ember, 15)], range: 26...38),
            Raw(layout: ["ooooFooo", "oooooooo", "oBBooBBo", "oooooooo", "oooooooo", "o111111o", "oooooooo", "oooooooo"],
                kinds: 5, goals: [.drops(3), .crates, .frost], drops: M3Drops(total: 3, maxOnBoard: 1), range: 26...40),
            Raw(layout: ["oFooooFo", "o2oooo2o", "oooooooo", "ooBCCBoo", "ooBCCBoo", "oooooooo", "o222222o", "oooooooo"],
                kinds: 5, goals: [.drops(3), .frost, .crates, .collect(.ember, 20)], drops: M3Drops(total: 3, maxOnBoard: 2), range: 28...40),
        ]),
    ]
}
