import BottleSortCore
import DistilleryCore
import SwiftUI

/// The pictures of the distillery tips (R10).
enum DistillTipScene: Equatable {
    case turn, goal, tee, cross, fixed, murk, coil, valve
}

/// First-time tips of the distillery: the basics on every level until seen, then one topic for each
/// piece type or rule a level brings. "?" in the level reopens all of the level's topics.
enum DistillTips {
    static func topics(for level: DistillLevel) -> [TutorialTopic] {
        let board = level.board
        var topics: [TutorialTopic] = [.distillBasics]
        let shapes = Set(board.pieces.map(\.shape))
        if shapes.contains(.tee) { topics.append(.distillTee) }
        if board.pieces.contains(where: \.fixed) { topics.append(.distillFixed) }
        if Set(board.sources.map(\.color)).count > 1 { topics.append(.distillColors) }
        if shapes.contains(.cross) { topics.append(.distillCross) }
        if board.pieces.contains(where: { $0.coil != nil }) { topics.append(.distillCoil) }
        if board.pieces.contains(where: { $0.valve != nil }) { topics.append(.distillValve) }
        return topics
    }

    static func steps(for topic: TutorialTopic) -> [TutorialStep] {
        func step(_ id: String, _ title: String, _ text: String, _ scene: DistillTipScene) -> TutorialStep {
            TutorialStep(id: id, topic: topic, title: title, text: text, scene: .distill(scene))
        }
        switch topic {
        case .distillBasics:
            #if os(macOS)
            let turn = String(localized: "Click a pipe to turn it a quarter clockwise; right-click or Option-click turns it back. Potion runs from the cauldron through every connected pipe.",
                              comment: "Distillery tip (Mac): how to turn pipes")
            #else
            let turn = String(localized: "Tap a pipe to turn it a quarter clockwise; touch and hold turns it back. Potion runs from the cauldron through every connected pipe.",
                              comment: "Distillery tip (iPhone, iPad): how to turn pipes")
            #endif
            return [
                step("distill.turn", String(localized: "Turn the pipes", comment: "Distillery tip title"), turn, .turn),
                step("distill.goal", String(localized: "Fill every flask", comment: "Distillery tip title"),
                     String(localized: "Each flask wants the potion on its tag. No open pipe end may drip; a cap closes a line. Pipes left dry don't matter. Fewer taps earn more stars.",
                            comment: "Distillery tip: the goal, leaks, caps and stars"), .goal),
            ]
        case .distillTee:
            return [step("distill.tee", String(localized: "Splitters", comment: "Distillery tip title: the tee piece"),
                         String(localized: "A splitter joins three pipes: whatever comes in runs out of both other ends. One cauldron can fill two flasks.",
                                comment: "Distillery tip: tee pieces"), .tee)]
        case .distillFixed:
            return [step("distill.fixed", String(localized: "Riveted pieces", comment: "Distillery tip title"),
                         String(localized: "Brass rivets hold a piece in place: it can't be turned. Build your pipes around it.",
                                comment: "Distillery tip: fixed pieces"), .fixed)]
        case .distillColors:
            return [step("distill.colors", String(localized: "Two potions", comment: "Distillery tip title"),
                         String(localized: "Where two potions meet, they turn murky and block the pipe. Give each color its own path to its flasks.",
                                comment: "Distillery tip: several colors and murk"), .murk)]
        case .distillCross:
            return [step("distill.cross", String(localized: "Crossings", comment: "Distillery tip title"),
                         String(localized: "A crossing carries two pipes over each other. They never mix, so two potions can pass through the same spot.",
                                comment: "Distillery tip: cross pieces"), .cross)]
        case .distillCoil:
            return [step("distill.coil", String(localized: "Heat coils", comment: "Distillery tip title"),
                         String(localized: "A glowing coil brews the potion passing through it: the tag in its corner shows what goes in and what comes out. Other potions pass unchanged.",
                                comment: "Distillery tip: heat coils change a color"), .coil)]
        case .distillValve:
            return [step("distill.valve", String(localized: "Valves", comment: "Distillery tip title"),
                         String(localized: "A valve stays shut until the flask with the same number holds its own potion. Then it opens and lets the liquid through.",
                                comment: "Distillery tip: valves linked to a flask"), .valve)]
        default:
            return []
        }
    }

    // MARK: Tip boards

    private static func board(_ width: Int, _ height: Int, _ pieces: [(Int, Int, DistillPiece)],
                              sources: [(Int, Int, ColorID, DistillDir)], targets: [(Int, Int, ColorID, DistillDir)]) -> DistillBoard {
        var all = Array(repeating: DistillPiece.empty, count: width * height)
        for (r, c, piece) in pieces { all[r * width + c] = piece }
        return DistillBoard(width: width, height: height, pieces: all,
                            sources: sources.map { DistillSource(pos: DistillPos($0.0, $0.1), color: $0.2, outlet: $0.3) },
                            targets: targets.map { DistillTarget(pos: DistillPos($0.0, $0.1), color: $0.2, inlet: $0.3) })
    }

    static func boards(_ scene: DistillTipScene) -> [DistillBoard] {
        switch scene {
        case .turn:
            let start = board(3, 1, [(0, 1, DistillPiece(.straight))], sources: [(0, 0, 1, .east)], targets: [(0, 2, 1, .west)])
            var done = start
            done[DistillPos(0, 1)].rotation = 1
            return [start, done]
        case .goal:
            return [board(3, 2, [(0, 1, DistillPiece(.elbow, rotation: 2)), (1, 1, DistillPiece(.elbow)),
                                 (0, 2, DistillPiece(.cap, rotation: 1)), (1, 0, DistillPiece(.straight))],
                          sources: [(0, 0, 2, .east)], targets: [(1, 2, 2, .west)])]
        case .tee:
            return [board(3, 3, [(1, 0, DistillPiece(.elbow)), (1, 1, DistillPiece(.tee, rotation: 1)),
                                 (1, 2, DistillPiece(.elbow, rotation: 3))],
                          sources: [(2, 1, 3, .north)], targets: [(0, 0, 3, .south), (0, 2, 3, .south)])]
        case .cross:
            return [board(3, 3, [(1, 1, DistillPiece(.cross))],
                          sources: [(1, 0, 0, .east), (0, 1, 1, .south)], targets: [(1, 2, 0, .west), (2, 1, 1, .north)])]
        case .fixed:
            return [board(3, 1, [(0, 1, DistillPiece(.straight, rotation: 1, fixed: true))],
                          sources: [(0, 0, 4, .east)], targets: [(0, 2, 4, .west)])]
        case .murk:
            return [board(3, 2, [(0, 1, DistillPiece(.tee, rotation: 1))],
                          sources: [(0, 0, 0, .east), (0, 2, 1, .west)], targets: [(1, 1, 0, .north)])]
        case .coil:
            return [board(3, 1, [(0, 1, DistillPiece(.straight, rotation: 1, coil: DistillCoil(from: 0, to: 5)))],
                          sources: [(0, 0, 0, .east)], targets: [(0, 2, 5, .west)])]
        case .valve:
            return [board(3, 2, [(0, 1, DistillPiece(.straight, rotation: 1)),
                                 (1, 1, DistillPiece(.straight, rotation: 1, valve: 0))],
                          sources: [(0, 0, 0, .east), (1, 0, 1, .east)], targets: [(0, 2, 0, .west), (1, 2, 1, .west)])]
        }
    }
}

/// A still distillery board for a tip (one or two, with an arrow between them).
struct DistillTipSceneView: View {
    let scene: DistillTipScene
    @Environment(\.colorRunesEnabled) private var runes

    var body: some View {
        let boards = DistillTips.boards(scene)
        HStack(spacing: 8) {
            ForEach(boards.indices, id: \.self) { i in
                if i > 0 {
                    Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                DistillStillBoard(board: boards[i], runes: runes)
            }
        }
        .padding(.horizontal, 8)
    }
}

/// A board drawn at rest, every wet channel full (tips, previews).
struct DistillStillBoard: View {
    let board: DistillBoard
    var runes = false

    var body: some View {
        GeometryReader { proxy in
            let layout = DistillLayout(board: board, size: proxy.size, maxCell: 54)
            let flow = board.flow
            ZStack {
                Canvas { ctx, _ in
                    DistillRenderer.draw(ctx, board: board, flow: flow, layout: layout,
                                         display: .still(board, runes: runes), now: Date())
                }
                DistillFlasks(board: board, flow: flow, layout: layout, arrived: { _ in true })
            }
        }
        .aspectRatio(CGFloat(board.width + 1) / CGFloat(board.height + 1), contentMode: .fit)
    }
}
