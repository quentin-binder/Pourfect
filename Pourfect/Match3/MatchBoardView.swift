import BottleSortCore
import Match3Core
import SwiftUI

/// The ingredient-gathering board (R9): the tray with its cell mask, sealed crates, the pieces and
/// flasks, the selection and hint glow and the effects. Swipe (drag) a piece onto a neighbour to
/// swap, or tap (click) one piece and then a neighbour. VoiceOver reads each cell and offers swap
/// actions.
struct MatchBoardView: View {
    let model: MatchBoardModel
    @Environment(\.colorRunesEnabled) private var runes
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    /// The drag in progress: its start cell, and whether it has already asked for a swap.
    @State private var dragStart: M3Pos?
    @State private var dragUsed = false

    var body: some View {
        GeometryReader { proxy in
            let cell = floor(min(proxy.size.width / CGFloat(model.width), proxy.size.height / CGFloat(model.height)))
            let size = CGSize(width: cell * CGFloat(model.width), height: cell * CGFloat(model.height))
            ZStack(alignment: .topLeading) {
                M3Tray(board: model.game.board, cell: cell)
                crateLayer(cell)
                tokenLayer(cell, size: size)
                markLayer(cell)
                BoardEffectsLayer(effects: model.effects, cell: cell, columns: model.width, rows: model.height)
                accessibilityGrid(cell)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(cell))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.spokenSummary))
    }

    private func point(_ p: M3Pos, _ cell: CGFloat, dx: Double = 0, dy: Double = 0) -> CGPoint {
        CGPoint(x: (CGFloat(p.col) + 0.5 + dx) * cell, y: (CGFloat(p.row) + 0.5 + dy) * cell)
    }

    /// Top-left corner of a cell (views are framed to one cell and offset there, so their scale
    /// effects and transitions stay centered on the cell).
    private func offset(_ p: M3Pos, _ cell: CGFloat, dx: Double = 0, dy: Double = 0) -> CGSize {
        CGSize(width: (CGFloat(p.col) + dx) * cell, height: (CGFloat(p.row) + dy) * cell)
    }

    // MARK: Layers

    private func crateLayer(_ cell: CGFloat) -> some View {
        let w = model.width
        let cells = model.crates.indices.filter { model.crates[$0] > 0 }
        return ZStack(alignment: .topLeading) {
            ForEach(cells, id: \.self) { i in
                M3CrateView(hits: model.crates[i], size: cell * 0.96)
                    .frame(width: cell, height: cell)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.25).combined(with: .opacity))
                    .offset(offset(M3Pos(i / w, i % w), cell))
            }
        }
        .allowsHitTesting(false)
    }

    private func tokenLayer(_ cell: CGFloat, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.tokens) { token in
                tokenView(token, cell: cell)
                    .frame(width: cell, height: cell)
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .identity, removal: .scale(scale: 1.45).combined(with: .opacity)))
                    .offset(offset(token.pos, cell, dx: token.dx, dy: token.dy))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // New pieces fall in from above the board: hidden until they enter it.
        .clipShape(Rectangle())
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func tokenView(_ token: MatchBoardModel.Token, cell: CGFloat) -> some View {
        Group {
            switch token.item {
            case .piece(let piece): M3PieceView(piece: piece, size: cell, runes: runes)
            case .flask: M3FlaskView(size: cell)
            }
        }
        .scaleEffect(x: token.scale * (1 + 0.16 * token.squash), y: token.scale * (1 - 0.16 * token.squash))
        .brightness(0.22 * token.squash + 0.25 * token.glow)
        .shadow(color: .white.opacity(0.7 * token.glow), radius: cell * 0.18 * token.glow)
        .rotationEffect(.degrees(token.spin))
        .opacity(token.opacity)
    }

    /// The selected piece's ring and the idle hint's glow.
    private func markLayer(_ cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let selected = model.selected {
                RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: max(2, cell * 0.06))
                    .background(RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous).fill(.white.opacity(0.12)))
                    .frame(width: cell * 0.96, height: cell * 0.96)
                    .position(point(selected, cell))
                    .transition(.opacity)
            }
            if let hint = model.hint {
                ForEach([hint.from, hint.to], id: \.self) { p in
                    HintGlow(size: cell, reduceMotion: reduceMotion,
                             toward: p == hint.from ? hint.to : hint.from, from: p)
                        .position(point(p, cell))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.selected)
        .animation(.easeInOut(duration: 0.4), value: model.hint)
        .allowsHitTesting(false)
    }

    // MARK: Input

    private func dragGesture(_ cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = cellAt(value.startLocation, cell)
                    dragUsed = false
                }
                guard !dragUsed, let start = dragStart else { return }
                let t = value.translation
                guard max(abs(t.width), abs(t.height)) > cell * 0.32 else { return }
                dragUsed = true
                let target = abs(t.width) > abs(t.height)
                    ? M3Pos(start.row, start.col + (t.width > 0 ? 1 : -1))
                    : M3Pos(start.row + (t.height > 0 ? 1 : -1), start.col)
                model.requestSwap(M3Swap(start, target))
            }
            .onEnded { value in
                defer { dragStart = nil; dragUsed = false }
                guard !dragUsed, let start = dragStart, cellAt(value.location, cell) == start else { return }
                model.tap(start)
            }
    }

    private func cellAt(_ location: CGPoint, _ cell: CGFloat) -> M3Pos? {
        let p = M3Pos(Int(floor(location.y / cell)), Int(floor(location.x / cell)))
        return model.game.board.contains(p) && model.game.board[p].exists ? p : nil
    }

    // MARK: VoiceOver

    /// One accessibility element per cell, with the swaps it allows as custom actions.
    private func accessibilityGrid(_ cell: CGFloat) -> some View {
        let board = model.game.board
        let cells = board.positions.filter { board[$0].exists }
        return ZStack(alignment: .topLeading) {
            ForEach(cells, id: \.self) { p in
                Color.clear
                    .frame(width: cell, height: cell)
                    .position(point(p, cell))
                    .accessibilityElement()
                    .accessibilityLabel(Text(model.spokenCell(p)))
                    .accessibilityHint(Text("Row \(p.row + 1), column \(p.col + 1)",
                                            comment: "VoiceOver: position of a match-3 cell"))
                    .accessibilityActions { swapActions(p) }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func swapActions(_ p: M3Pos) -> some View {
        let directions: [(M3Pos, Text)] = [
            (M3Pos(p.row - 1, p.col), Text("Swap up", comment: "VoiceOver action: swap a match-3 piece with the one above")),
            (M3Pos(p.row + 1, p.col), Text("Swap down", comment: "VoiceOver action: swap a match-3 piece with the one below")),
            (M3Pos(p.row, p.col - 1), Text("Swap left", comment: "VoiceOver action: swap a match-3 piece with the one on the left")),
            (M3Pos(p.row, p.col + 1), Text("Swap right", comment: "VoiceOver action: swap a match-3 piece with the one on the right")),
        ]
        if model.isPlaying, model.game.board.isSwappable(p) {
            ForEach(directions.indices, id: \.self) { k in
                let target = directions[k].0
                if model.game.board.isSwappable(target) {
                    Button { model.requestSwap(M3Swap(p, target)) } label: { directions[k].1 }
                }
            }
        }
    }
}

/// The idle hint: a soft breathing glow on the two pieces of a good swap, each leaning a little
/// towards the other (just the glow with Reduce Motion).
private struct HintGlow: View {
    let size: CGFloat
    let reduceMotion: Bool
    let toward: M3Pos
    let from: M3Pos

    var body: some View {
        let dx = CGFloat(toward.col - from.col), dy = CGFloat(toward.row - from.row)
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(RadialGradient(colors: [M3Colors.gold.opacity(0.5), M3Colors.gold.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: size * 0.6))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(M3Colors.gold.opacity(0.9), lineWidth: max(1.5, size * 0.045)))
            .frame(width: size * 0.96, height: size * 0.96)
            .phaseAnimator([false, true]) { content, on in
                content
                    .opacity(on ? 1 : 0.35)
                    .offset(x: reduceMotion || !on ? 0 : dx * size * 0.06, y: reduceMotion || !on ? 0 : dy * size * 0.06)
            } animation: { _ in .easeInOut(duration: 0.9) }
    }
}

/// The tray under the board: a dark wooden tray following the board's shape, with a soft tile per
/// cell (holes stay open).
struct M3Tray: View {
    let board: M3Board
    let cell: CGFloat

    var body: some View {
        Canvas { context, _ in
            let open = board.positions.filter { board[$0].exists }
            let rim = cell * 0.08
            for p in open {
                let r = CGRect(x: CGFloat(p.col) * cell - rim, y: CGFloat(p.row) * cell - rim, width: cell + 2 * rim, height: cell + 2 * rim)
                context.fill(Path(roundedRect: r, cornerRadius: cell * 0.24), with: .color(M3Colors.woodDark.opacity(0.9)))
            }
            for p in open {
                let r = CGRect(x: CGFloat(p.col) * cell - rim * 0.4, y: CGFloat(p.row) * cell - rim * 0.4,
                               width: cell + rim * 0.8, height: cell + rim * 0.8)
                context.fill(Path(roundedRect: r, cornerRadius: cell * 0.2), with: .color(M3Colors.tray.opacity(0.92)))
            }
            for p in open {
                let r = CGRect(x: CGFloat(p.col) * cell, y: CGFloat(p.row) * cell, width: cell, height: cell)
                    .insetBy(dx: cell * 0.035, dy: cell * 0.035)
                let tile = Path(roundedRect: r, cornerRadius: cell * 0.16)
                let light = (p.row + p.col) % 2 == 0
                context.fill(tile, with: .linearGradient(
                    Gradient(colors: [M3Colors.cellLight.opacity(light ? 0.16 : 0.1), M3Colors.cellLight.opacity(light ? 0.08 : 0.04)]),
                    startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                context.stroke(tile, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
