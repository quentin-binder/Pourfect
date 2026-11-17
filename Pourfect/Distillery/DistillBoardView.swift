import BottleSortCore
import DistilleryCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Where the cells sit: square cells of side `s` in a slate well inside a wooden panel.
struct DistillLayout {
    let width: Int
    let height: Int
    let s: CGFloat
    let panel: CGRect
    let well: CGRect

    init(board: DistillBoard, size: CGSize, maxCell: CGFloat = 104) {
        width = board.width
        height = board.height
        // Panel margin is 0.32 cells on each side.
        let pad: CGFloat = 0.32
        let s = max(8, min(size.width / (CGFloat(board.width) + 2 * pad), size.height / (CGFloat(board.height) + 2 * pad), maxCell))
        self.s = s
        let w = CGFloat(board.width) * s, h = CGFloat(board.height) * s
        let panel = CGRect(x: (size.width - w) / 2 - pad * s, y: (size.height - h) / 2 - pad * s,
                           width: w + 2 * pad * s, height: h + 2 * pad * s)
        self.panel = panel
        well = CGRect(x: panel.minX + pad * s, y: panel.minY + pad * s, width: w, height: h).insetBy(dx: -s * 0.06, dy: -s * 0.06)
    }

    func center(_ p: DistillPos) -> CGPoint {
        CGPoint(x: well.minX + s * 0.06 + (CGFloat(p.c) + 0.5) * s, y: well.minY + s * 0.06 + (CGFloat(p.r) + 0.5) * s)
    }

    func cell(at point: CGPoint) -> DistillPos? {
        let x = point.x - well.minX - s * 0.06, y = point.y - well.minY - s * 0.06
        guard x >= 0, y >= 0 else { return nil }
        let p = DistillPos(Int(y / s), Int(x / s))
        return p.r < height && p.c < width ? p : nil
    }
}

/// What the renderer needs besides the board and flow: displayed angles and fills over time.
struct DistillDisplay {
    var angle: (Int, Date) -> Double
    var turning: (Int, Date) -> Bool
    var fill: (DistillNodeRef, Date) -> Double
    var hint: DistillPos? = nil
    var refused: (pos: DistillPos, at: Date)? = nil
    var celebrating = false
    var runes = false
    /// Drips fall and murk drifts (off with Reduce Motion and in still pictures).
    var live = true

    /// A still picture of a board (tips): everything at rest, every wet channel full.
    static func still(_ board: DistillBoard, runes: Bool) -> DistillDisplay {
        DistillDisplay(angle: { cell, _ in Double(board.pieces[cell].rotation) }, turning: { _, _ in false },
                       fill: { _, _ in 1 }, runes: runes, live: false)
    }
}

/// Draws a whole distillery board into a canvas.
enum DistillRenderer {
    static func draw(_ ctx: GraphicsContext, board: DistillBoard, flow: DistillFlow, layout: DistillLayout,
                     display: DistillDisplay, now: Date) {
        let s = layout.s
        DistillArt.drawPanel(ctx, rect: layout.panel, well: layout.well, s: s)
        let time = now.timeIntervalSinceReferenceDate
        let valveLinks = Dictionary(grouping: board.valvePositions, by: { board[$0].valve ?? -1 })

        for index in 0..<board.cellCount {
            let pos = board.pos(index)
            let c = layout.center(pos)
            var cell = ctx
            cell.translateBy(x: c.x, y: c.y)
            switch board.kind(at: pos) {
            case .piece(let piece):
                guard piece.shape != .empty else {
                    let r = s * 0.035
                    cell.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.08)))
                    continue
                }
                DistillArt.drawTile(cell, s: s, fixed: piece.fixed)
                drawPiece(cell, piece: piece, pos: pos, index: index, flow: flow, display: display, now: now, s: s)
                if let target = piece.valve, board.targets.indices.contains(target) {
                    DistillArt.drawTag(cell, at: CGPoint(x: s * 0.34, y: -s * 0.34), r: s * 0.1,
                                       color: board.targets[target].color, rune: false, number: target + 1)
                }
                if let coil = piece.coil {
                    drawRecipe(cell, coil: coil, s: s, runes: display.runes)
                }
                if display.hint == pos {
                    let glow = Path(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s).insetBy(dx: s * 0.04, dy: s * 0.04),
                                    cornerRadius: s * 0.12)
                    cell.stroke(glow, with: .color(DistillArt.gold), lineWidth: max(2, s * 0.05))
                }
                if let refused = display.refused, refused.pos == pos, now.timeIntervalSince(refused.at) < 0.3 {
                    let k = 1 - now.timeIntervalSince(refused.at) / 0.3
                    let flash = Path(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s).insetBy(dx: s * 0.04, dy: s * 0.04),
                                     cornerRadius: s * 0.12)
                    cell.stroke(flash, with: .color(DistillArt.valveShut.opacity(k)), lineWidth: max(2, s * 0.05))
                }
            case .source(let i):
                let source = board.sources[i]
                let arm = DistillArt.arm(.straight, side: source.outlet, s: s)
                DistillArt.drawPipe(cell, arms: [arm], s: s, junction: false)
                let ref = DistillNodeRef(pos: pos, channel: 0)
                DistillArt.drawLiquid(cell, arm: arm, s: s, color: Palette.color(source.color.rawValue),
                                      fill: display.fill(ref, now), inward: false, murky: false, glow: display.celebrating)
                DistillArt.drawCauldron(cell, s: s, color: source.color, runes: true,
                                        bubble: display.live ? (time * 0.7 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1) : 0.3)
            case .target(let i):
                let target = board.targets[i]
                let arm = DistillArt.arm(.straight, side: target.inlet, s: s)
                DistillArt.drawPipe(cell, arms: [arm], s: s, junction: false)
                let ref = DistillNodeRef(pos: pos, channel: 0)
                if let node = flow.nodes(at: pos).first, node.liquid.isWet {
                    DistillArt.drawLiquid(cell, arm: arm, s: s, color: DistillArt.liquid(node.liquid.color),
                                          fill: display.fill(ref, now), inward: true, murky: node.liquid == .murky,
                                          glow: display.celebrating)
                }
                // A little wooden stand for the flask, and its wanted color.
                let stand = Path(roundedRect: CGRect(x: -s * 0.24, y: s * 0.3, width: s * 0.48, height: s * 0.08), cornerRadius: s * 0.03)
                cell.fill(stand, with: .color(Color(red: 0.42, green: 0.27, blue: 0.14)))
                DistillArt.drawTag(cell, at: CGPoint(x: -s * 0.33, y: s * 0.3), r: s * 0.11, color: target.color, rune: true)
                if valveLinks[i] != nil {
                    DistillArt.drawTag(cell, at: CGPoint(x: s * 0.33, y: s * 0.3), r: s * 0.1, color: target.color,
                                       rune: false, number: i + 1)
                }
            }
        }

        // Murky seams between two cells, murky channels, and drips.
        let phase = display.live ? (time * 0.6).truncatingRemainder(dividingBy: 1) : 0.4
        for seam in flow.seams {
            let a = layout.center(seam.pos), e = DistillArt.edgePoint(seam.side, s)
            DistillArt.drawMurk(ctx, at: CGPoint(x: a.x + e.x, y: a.y + e.y), s: s, phase: phase)
        }
        for node in flow.nodes where node.liquid == .murky {
            let ref = DistillNodeRef(pos: node.pos, channel: node.channel)
            guard display.fill(ref, now) >= 1, !display.turning(board.index(node.pos), now) else { continue }
            DistillArt.drawMurk(ctx, at: layout.center(node.pos), s: s, phase: phase)
        }
        for leak in flow.leaks {
            guard let node = flow.node(at: leak.pos, side: leak.side) else { continue }
            let ref = DistillNodeRef(pos: node.pos, channel: node.channel)
            guard display.fill(ref, now) >= 1, !display.turning(board.index(leak.pos), now) else { continue }
            let a = layout.center(leak.pos), e = DistillArt.edgePoint(leak.side, s)
            let seed = Double(leak.pos.r * 7 + leak.pos.c * 3 + leak.side.rawValue) * 0.173
            let fall = display.live ? (time * 1.1 + seed).truncatingRemainder(dividingBy: 1) : 0.45
            DistillArt.drawLeak(ctx, at: CGPoint(x: a.x + e.x * 0.86, y: a.y + e.y * 0.86), s: s,
                                color: DistillArt.liquid(leak.color), phase: fall)
        }
    }

    /// A piece in its base orientation inside a context rotated to its displayed angle, with the liquid.
    private static func drawPiece(_ cell: GraphicsContext, piece: DistillPiece, pos: DistillPos, index: Int, flow: DistillFlow,
                                  display: DistillDisplay, now: Date, s: CGFloat) {
        var ctx = cell
        let angle = piece.isRotatable ? display.angle(index, now) : Double(piece.rotation)
        ctx.rotate(by: .degrees(angle * 90))
        let turning = display.turning(index, now)
        let rotation = piece.rotation
        let nodes = flow.nodes(at: pos)
        let channelSides: [[DistillDir]] = piece.shape == .cross
            ? [[.north, .south], [.east, .west]]
            : [DistillMask.dirs(piece.shape.baseMask)]
        for (k, sides) in channelSides.enumerated() {
            let arms = sides.map { DistillArt.arm(piece.shape, side: $0, s: s) }
            DistillArt.drawPipe(ctx, arms: arms, s: s, junction: piece.shape == .tee)
            guard !turning, let node = nodes.first(where: { $0.channel == k }), node.liquid.isWet else { continue }
            let f = display.fill(DistillNodeRef(pos: pos, channel: k), now)
            let murky = node.liquid == .murky
            let hasEntry = node.entry != 0
            for (side, arm) in zip(sides, arms) {
                // The world side of this base side (a cross never turns).
                let world = piece.shape == .cross ? side : DistillDir(rawValue: (side.rawValue + rotation) & 3)!
                let color: Color
                if murky {
                    color = DistillArt.murky
                } else if let c = node.sideColors[world.rawValue] {
                    color = Palette.color(c.rawValue)
                } else if node.shutValve {
                    continue   // liquid never got past the gate to this side
                } else {
                    color = DistillArt.liquid(node.liquid.color)
                }
                let inward = hasEntry && DistillMask.has(node.entry, world)
                var amount = hasEntry ? (inward ? min(1, f * 2) : max(0, f * 2 - 1)) : f
                if node.shutValve { amount = min(amount, 0.78) }
                DistillArt.drawLiquid(ctx, arm: arm, s: s, color: color, fill: amount, inward: inward, murky: murky,
                                      glow: display.celebrating)
            }
            if piece.shape == .tee, f >= 0.5, !node.shutValve {
                let r = s * 0.07
                ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                         with: .color(murky ? DistillArt.murky : DistillArt.liquid(node.liquid.color)))
            }
        }
        if piece.shape == .cap { DistillArt.drawCapEnd(ctx, s: s) }
        let hub = DistillArt.hub(piece.shape, s: s)
        let wet = !turning && nodes.contains { $0.liquid.isWet }
        if piece.coil != nil {
            let pulse = display.live ? 0.5 + 0.5 * sin(now.timeIntervalSinceReferenceDate * 3) : 0.5
            DistillArt.drawCoil(ctx, at: hub, angle: piece.shape == .elbow ? -Double.pi / 4 : 0, s: s, hot: wet, pulse: pulse)
        }
        if piece.valve != nil {
            let open = flow.isValveOpen(at: pos)
            DistillArt.drawValve(ctx, at: hub, s: s, open: open, spin: open ? .pi / 8 : 0)
        }
    }

    /// A coil's recipe in the cell's corner: the color it takes and the color it gives.
    private static func drawRecipe(_ ctx: GraphicsContext, coil: DistillCoil, s: CGFloat, runes: Bool) {
        let y = s * 0.36, r = s * 0.075
        DistillArt.drawTag(ctx, at: CGPoint(x: -s * 0.36, y: y), r: r, color: coil.from, rune: runes)
        var arrow = Path()
        arrow.move(to: CGPoint(x: -s * 0.27, y: y))
        arrow.addLine(to: CGPoint(x: -s * 0.2, y: y))
        arrow.move(to: CGPoint(x: -s * 0.23, y: y - s * 0.03))
        arrow.addLine(to: CGPoint(x: -s * 0.2, y: y))
        arrow.addLine(to: CGPoint(x: -s * 0.23, y: y + s * 0.03))
        ctx.stroke(arrow, with: .color(DistillArt.brassLight), style: StrokeStyle(lineWidth: max(1, s * 0.02), lineCap: .round))
        DistillArt.drawTag(ctx, at: CGPoint(x: -s * 0.11, y: y), r: r, color: coil.to, rune: runes)
    }
}

/// The flasks on a board: the game's own flask, filling as the liquid arrives, corked at the win.
struct DistillFlasks: View {
    let board: DistillBoard
    let flow: DistillFlow
    let layout: DistillLayout
    /// Whether the liquid has reached flask `i` on screen.
    var arrived: (Int) -> Bool
    var celebrations = 0
    var celebrating = false

    var body: some View {
        let s = layout.s
        ForEach(board.targets.indices, id: \.self) { i in
            let target = board.targets[i]
            let width = s * 0.27
            let height = BottleView.height(width: width, capacity: 3)
            BottleView(bottle: bottle(i), width: width, hidden: hidden(i), completions: celebrations)
                .frame(width: width, height: height)
                .animation(.easeOut(duration: 0.35), value: bottle(i).layers.count)
                .position(x: layout.center(target.pos).x, y: layout.center(target.pos).y + s * 0.3 - height / 2)
                .allowsHitTesting(false)
        }
    }

    private func bottle(_ i: Int) -> Bottle {
        guard arrived(i) else { return Bottle([Int](), capacity: 3) }
        switch flow.received[i] {
        case .dry: return Bottle([Int](), capacity: 3)
        case .murky: return Bottle([11, 11], capacity: 3)
        case .liquid(let c):
            let full = celebrating && c == board.targets[i].color
            return Bottle(Array(repeating: c.rawValue, count: full ? 3 : 2), capacity: 3)
        }
    }

    private func hidden(_ i: Int) -> [Bool] {
        flow.received[i] == .murky && arrived(i) ? [true, true] : []
    }
}

/// The distillery board in play: the canvas, the flasks, and one tappable, speakable element per cell.
struct DistillBoardView: View {
    let model: DistillBoardModel
    @Environment(\.colorRunesEnabled) private var runes
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let layout = DistillLayout(board: model.board, size: proxy.size)
            let flow = model.flow
            let live = !reduceMotion && (!flow.leaks.isEmpty || flow.murkyCount > 0)
            let _ = model.idleTick
            let busy = model.isBusy(at: Date())
            // Fills and turns at full rate; drips and murk alone at a gentler 30 fps.
            TimelineView(.animation(minimumInterval: busy ? nil : 1 / 30, paused: !live && !busy)) { _ in
                let now = Date()
                ZStack {
                    Canvas { ctx, _ in
                        DistillRenderer.draw(ctx, board: model.board, flow: flow, layout: layout,
                                             display: display(), now: now)
                    }
                    DistillFlasks(board: model.board, flow: flow, layout: layout,
                                  arrived: { model.flaskFilled($0, at: now) },
                                  celebrations: model.celebrations, celebrating: model.celebrations > 0 && model.isWon)
                }
            }
            .accessibilityHidden(true)
            cells(layout)
            #if os(macOS)
            SecondaryClickCatcher { point in
                if let pos = layout.cell(at: point) { model.tap(pos, clockwise: false) }
            }
            .accessibilityHidden(true)
            #endif
        }
    }

    private func display() -> DistillDisplay {
        DistillDisplay(angle: { model.angle($0, at: $1) }, turning: { model.isTurning($0, at: $1) },
                       fill: { model.fill($0, at: $1) }, hint: model.hintCell,
                       refused: model.refusedCell.map { ($0, model.refusedAt) },
                       celebrating: model.celebrations > 0 && model.isWon, runes: runes, live: !reduceMotion)
    }

    /// One transparent, tappable and speakable element per cell, in reading order.
    private func cells(_ layout: DistillLayout) -> some View {
        let board = model.board
        return ForEach(0..<board.cellCount, id: \.self) { index in
            let pos = board.pos(index)
            let center = layout.center(pos)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: layout.s, height: layout.s)
                #if os(macOS)
                .highPriorityGesture(TapGesture().modifiers(.option).onEnded { model.tap(pos, clockwise: false) })
                .highPriorityGesture(TapGesture().modifiers(.control).onEnded { model.tap(pos, clockwise: false) })
                #endif
                .onTapGesture { model.tap(pos) }
                .onLongPressGesture(minimumDuration: 0.4) { model.tap(pos, clockwise: false) }
                .position(center)
                .accessibilityElement()
                .accessibilityLabel(DistillSpeech.cell(pos, board: board, flow: model.flow))
                .accessibilityAddTraits(board.kind(at: pos).isTurnable ? .isButton : [])
                .accessibilityHint(board.kind(at: pos).isTurnable
                                   ? Text("Turns it a quarter clockwise.", comment: "VoiceOver hint of a distillery pipe piece")
                                   : Text(verbatim: ""))
                .accessibilityAction { model.tap(pos) }
                .accessibilityAction(named: Text("Turn counter-clockwise", comment: "VoiceOver action: turn a distillery pipe back")) {
                    model.tap(pos, clockwise: false)
                }
                .accessibilitySortPriority(Double(board.cellCount - index))
        }
    }
}

extension DistillCellKind {
    var isTurnable: Bool {
        if case .piece(let piece) = self { return piece.isRotatable }
        return false
    }
}

#if os(macOS)
/// Catches right-clicks over the board (and only those: every other event passes through to the
/// SwiftUI views below), reporting the point in the board's coordinates.
struct SecondaryClickCatcher: NSViewRepresentable {
    var onClick: (CGPoint) -> Void

    final class CatcherView: NSView {
        var onClick: ((CGPoint) -> Void)?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .rightMouseUp else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) {
            onClick?(convert(event.locationInWindow, from: nil))
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onClick = onClick }
}
#endif
