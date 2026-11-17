import Match3Core
import SwiftUI

/// The pictures of the ingredient-gathering tips (R9).
enum M3TipScene: Equatable {
    case swap, goals, comet, bloom, prism, combo, frost, crate, flask
}

/// First-time tips of the gathering levels: the basics on every level until seen, then one topic
/// for each new thing a level brings. "?" in the level reopens all of the level's topics.
enum M3Tips {
    /// The topics a level shows, in teaching order. Specials are taught from episode 2 on (and in
    /// the daily), where the boards are made for them.
    static func topics(for level: M3Level) -> [TutorialTopic] {
        var topics: [TutorialTopic] = [.m3Swap]
        let episode = Match3Library.shared.episode(of: level.id)?.episode.number
        if episode.map({ $0 >= 2 }) ?? true { topics.append(.m3Specials) }
        if level.hasFrost { topics.append(.m3Frost) }
        if level.hasCrates { topics.append(.m3Crates) }
        if level.hasDrops { topics.append(.m3Flasks) }
        return topics
    }

    static func steps(for topic: TutorialTopic) -> [TutorialStep] {
        func step(_ id: String, _ title: String, _ text: String, _ scene: M3TipScene) -> TutorialStep {
            TutorialStep(id: id, topic: topic, title: title, text: text, scene: .m3(scene))
        }
        switch topic {
        case .m3Swap:
            return [
                step("m3.swap", String(localized: "Swap and match", comment: "Match-3 tip title"),
                     String(localized: "Swipe an ingredient onto a neighbor, or tap one and then the other, to swap them. Line up three or more of a kind and they're gathered.",
                            comment: "Match-3 tip: how to swap"), .swap),
                step("m3.goals", String(localized: "Fill the basket", comment: "Match-3 tip title"),
                     String(localized: "Reach every goal at the top before the moves run out. Out of moves? Retry is free, and the board starts the same way.",
                            comment: "Match-3 tip: goals, moves and free retry"), .goals),
            ]
        case .m3Specials:
            return [
                step("m3.comet", String(localized: "Comets", comment: "Match-3 tip title: the line-clear special"),
                     String(localized: "Four in a row leaves a comet. Match it and it sweeps its whole row or column, the way its trail points.",
                            comment: "Match-3 tip: comet special"), .comet),
                step("m3.bloom", String(localized: "Blooms", comment: "Match-3 tip title: the 3x3 special"),
                     String(localized: "Two lines crossing in an L or a T leave a bloom. It bursts open and clears the ingredients around it.",
                            comment: "Match-3 tip: bloom special"), .bloom),
                step("m3.prism", String(localized: "Prisms", comment: "Match-3 tip title: the color-clear special"),
                     String(localized: "Five in a row makes a prism. Swap it with any ingredient to gather every one of that kind.",
                            comment: "Match-3 tip: prism special"), .prism),
                step("m3.combo", String(localized: "Mix two specials", comment: "Match-3 tip title"),
                     String(localized: "Swap two specials together for a bigger blast: two comets make a cross, a comet and a bloom clear three rows and three columns.",
                            comment: "Match-3 tip: special combos"), .combo),
            ]
        case .m3Frost:
            return [
                step("m3.frost", String(localized: "Frost", comment: "Match-3 tip title"),
                     String(localized: "A frozen ingredient can't be swapped. Match it, or match right beside it, to crack one layer of ice. Thick frost needs two.",
                            comment: "Match-3 tip: frost tiles"), .frost),
            ]
        case .m3Crates:
            return [
                step("m3.crate", String(localized: "Sealed crates", comment: "Match-3 tip title"),
                     String(localized: "Crates hold their place. Match beside one, or catch it in a special's blast, to knock its seal. The dots show the knocks left.",
                            comment: "Match-3 tip: sealed crates"), .crate),
            ]
        case .m3Flasks:
            return [
                step("m3.flask", String(localized: "Potion flasks", comment: "Match-3 tip title"),
                     String(localized: "Flasks can't be matched. Clear the cells below one and it sinks; it's collected when it reaches the bottom of its column.",
                            comment: "Match-3 tip: drop-down flasks"), .flask),
            ]
        default:
            return []
        }
    }
}

/// A small still life of board pieces for one tip.
struct M3TipSceneView: View {
    let scene: M3TipScene
    @Environment(\.colorRunesEnabled) private var runes
    private let s: CGFloat = 42

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            switch scene {
            case .swap:
                grid([[.mushroom, .crystal, .mushroom], [.feather, .mushroom, .ember]],
                     marks: [M3Pos(row: 0, col: 1): .up, M3Pos(row: 1, col: 1): .down])
                arrow
                grid([[.mushroom, .mushroom, .mushroom], [.feather, .crystal, .ember]], glowRow: 0)
            case .goals:
                VStack(spacing: 4) {
                    Text(verbatim: "25").font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text("moves", comment: "Match-3 HUD caption under the moves left").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    M3KindIcon(kind: .moonflower, size: 30, runes: runes)
                    Text(verbatim: "20").font(.title2.bold().monospacedDigit())
                }
                Image(systemName: "arrow.counterclockwise.circle.fill").font(.largeTitle).foregroundStyle(.green)
            case .comet:
                row([.crystal, .crystal, .crystal, .crystal])
                arrow
                piece(M3Piece(kind: .crystal, special: .row))
            case .bloom:
                grid([[.ember, nil, nil], [.ember, nil, nil], [.ember, .ember, .ember]])
                arrow
                piece(M3Piece(kind: .ember, special: .bloom))
            case .prism:
                row([.feather, .feather, .feather, .feather, .feather])
                arrow
                piece(.prism())
            case .combo:
                piece(M3Piece(kind: .drop, special: .row))
                Image(systemName: "plus").font(.title3.weight(.bold)).foregroundStyle(.secondary)
                piece(M3Piece(kind: .mushroom, special: .bloom))
                arrow
                Image(systemName: "plus.square.dashed").font(.system(size: 46, weight: .bold)).foregroundStyle(M3Colors.gold)
            case .frost:
                VStack(spacing: 4) {
                    piece(M3Piece(kind: .moonflower, frost: 1))
                    row([.crystal, .crystal, .crystal], glow: true)
                }
                arrow
                VStack(spacing: 4) {
                    piece(M3Piece(kind: .moonflower))
                    Color.clear.frame(width: s * 3, height: s)
                }
            case .crate:
                VStack(spacing: 4) {
                    M3CrateView(hits: 2, size: s)
                    row([.mushroom, .mushroom, .mushroom], glow: true)
                }
                arrow
                VStack(spacing: 4) {
                    M3CrateView(hits: 1, size: s)
                    Color.clear.frame(width: s * 3, height: s)
                }
            case .flask:
                VStack(spacing: 2) {
                    M3FlaskView(size: s)
                    piece(M3Piece(kind: .ember)).opacity(0.5)
                    piece(M3Piece(kind: .feather)).opacity(0.5)
                }
                arrow
                VStack(spacing: 2) {
                    Color.clear.frame(width: s, height: s)
                    Color.clear.frame(width: s, height: s)
                    M3FlaskView(size: s)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green).offset(x: 6, y: 4)
                        }
                }
            }
        }
        .padding(.bottom, 14)
    }

    private enum Mark { case up, down }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func piece(_ piece: M3Piece) -> some View {
        M3PieceView(piece: piece, size: s, runes: runes)
    }

    private func row(_ kinds: [M3Kind], glow: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(kinds.indices, id: \.self) { i in piece(M3Piece(kind: kinds[i])) }
        }
        .background(glow ? RoundedRectangle(cornerRadius: 8).fill(M3Colors.gold.opacity(0.3)) : nil)
    }

    private func grid(_ rows: [[M3Kind?]], marks: [M3Pos: Mark] = [:], glowRow: Int? = nil) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        if let kind = rows[r][c] {
                            piece(M3Piece(kind: kind))
                                .overlay(alignment: marks[M3Pos(row: r, col: c)] == .up ? .bottom : .top) {
                                    if let mark = marks[M3Pos(row: r, col: c)] {
                                        Image(systemName: mark == .up ? "arrow.down" : "arrow.up")
                                            .font(.system(size: 11, weight: .black))
                                            .foregroundStyle(.white)
                                            .offset(y: mark == .up ? 6 : -6)
                                    }
                                }
                        } else {
                            Color.clear.frame(width: s, height: s)
                        }
                    }
                }
                .background(glowRow == r ? RoundedRectangle(cornerRadius: 8).fill(M3Colors.gold.opacity(0.3)) : nil)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(M3Colors.cellLight.opacity(0.12)))
    }
}
