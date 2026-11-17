import Match3Core
import SwiftUI

/// One short-lived board effect (R9): sparkles of a popped piece, a comet's beam, a bloom's burst,
/// a prism's rays, ice shards, crate splinters, a score number… Effects draw themselves from their
/// age, so they never hold up the game; the model drops them once they are over.
struct BoardFX: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A popped piece (`strong`: blasted by a special).
        case sparkle(M3Pos, Color, Bool)
        /// A comet: the row (or column) lights up from the cell outwards; `span` 3 for comet + bloom.
        case beam(M3Pos, horizontal: Bool, span: Int, Color)
        /// A bloom: a square shock ring of `radius` cells.
        case burst(M3Pos, radius: Int)
        /// A prism: rays to every cell it reaches.
        case rays(M3Pos, [M3Pos], Color)
        /// Prism + prism: the whole board flashes.
        case flash
        /// A frost layer cracks: ice shards.
        case crack(M3Pos)
        /// A crate is hit (`broken`: it breaks apart).
        case splinters(M3Pos, broken: Bool)
        /// A special is made or changed: an expanding ring.
        case ring(M3Pos, Color)
        /// "+120" floating up from (col, row) in cells; `cascade` makes it bigger.
        case score(CGPoint, Int, Int)
        /// The reshuffle swirl around the board's middle.
        case swirl
        /// A flask collected: golden glitter rising.
        case glitter(M3Pos)
    }

    let id: Int
    let kind: Kind
    let start: Date
    let duration: Double
    let reduceMotion: Bool

    func progress(at date: Date) -> Double { min(1, max(0, date.timeIntervalSince(start) / duration)) }
    func isOver(at date: Date) -> Bool { date.timeIntervalSince(start) > duration }
}

/// Draws every live effect over the board (`cell` points per cell, `columns` × `rows`).
struct BoardEffectsLayer: View {
    let effects: [BoardFX]
    let cell: CGFloat
    let columns: Int
    let rows: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: effects.isEmpty)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                for fx in effects {
                    let t = fx.progress(at: now)
                    guard t < 1 else { continue }
                    draw(fx, t: t, in: &context, size: size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func center(_ p: M3Pos) -> CGPoint {
        CGPoint(x: (CGFloat(p.col) + 0.5) * cell, y: (CGFloat(p.row) + 0.5) * cell)
    }

    /// A small deterministic random sequence per effect, so particles don't flicker between frames.
    private func randoms(_ seed: Int, _ count: Int) -> [Double] {
        var state = UInt64(truncatingIfNeeded: seed &* 0x9E37_79B9) &+ 0x1234_5678
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private func draw(_ fx: BoardFX, t: Double, in context: inout GraphicsContext, size: CGSize) {
        let still = fx.reduceMotion
        let fade = 1 - t
        switch fx.kind {
        case .sparkle(let p, let color, let strong):
            let c = center(p)
            if still {
                context.fill(Path(ellipseIn: CGRect(x: c.x - cell * 0.4, y: c.y - cell * 0.4, width: cell * 0.8, height: cell * 0.8)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.7 * fade), color.opacity(0)]), center: c,
                                                   startRadius: 0, endRadius: cell * 0.4))
                return
            }
            // A quick glow, then a ring of little stars flying out.
            let glow = cell * (0.25 + 0.35 * t)
            var light = context
            light.blendMode = .plusLighter
            light.fill(Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: 2 * glow, height: 2 * glow)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.8 * fade * fade), color.opacity(0.45 * fade * fade),
                                                                 color.opacity(0)]),
                                               center: c, startRadius: 0, endRadius: glow))
            let count = strong ? 8 : 6
            let r = randoms(fx.id, count * 2)
            for k in 0..<count {
                let angle = (Double(k) + r[k] * 0.6) / Double(count) * 2 * .pi
                let distance = cell * (0.25 + (0.45 + 0.25 * r[count + k]) * easeOut(t))
                let pt = CGPoint(x: c.x + distance * cos(angle), y: c.y + distance * sin(angle) + cell * 0.15 * t * t)
                let s = cell * 0.09 * (1 - t * 0.7)
                context.fill(IngredientArt.sparkPath(center: pt, radius: s), with: .color((k % 2 == 0 ? Color.white : color).opacity(fade)))
            }
        case .beam(let p, let horizontal, let span, let color):
            let grow = still ? 1 : min(1, t / 0.3)
            let alpha = t < 0.3 ? 1 : 1 - (t - 0.3) / 0.7
            for offset in -(span / 2)...(span / 2) {
                let c = center(horizontal ? M3Pos(p.row + offset, p.col) : M3Pos(p.row, p.col + offset))
                let length = (horizontal ? size.width : size.height) * grow
                let thickness = cell * (0.42 + 0.2 * (1 - alpha))
                let rect = horizontal
                    ? CGRect(x: c.x - length, y: c.y - thickness / 2, width: 2 * length, height: thickness)
                    : CGRect(x: c.x - thickness / 2, y: c.y - length, width: thickness, height: 2 * length)
                let band = Path(roundedRect: rect, cornerRadius: thickness / 2)
                context.fill(band, with: .linearGradient(
                    Gradient(colors: [color.opacity(0), color.opacity(0.75 * alpha), color.opacity(0)]),
                    startPoint: horizontal ? CGPoint(x: c.x, y: rect.minY) : CGPoint(x: rect.minX, y: c.y),
                    endPoint: horizontal ? CGPoint(x: c.x, y: rect.maxY) : CGPoint(x: rect.maxX, y: c.y)))
                let core = horizontal
                    ? CGRect(x: rect.minX, y: c.y - cell * 0.05, width: rect.width, height: cell * 0.1)
                    : CGRect(x: c.x - cell * 0.05, y: rect.minY, width: cell * 0.1, height: rect.height)
                context.fill(Path(roundedRect: core, cornerRadius: cell * 0.05), with: .color(.white.opacity(alpha)))
                // The comet's head at both ends of the beam.
                if !still && t < 0.45 {
                    for sign in [-1.0, 1.0] {
                        let head = horizontal ? CGPoint(x: c.x + sign * length, y: c.y) : CGPoint(x: c.x, y: c.y + sign * length)
                        context.fill(IngredientArt.sparkPath(center: head, radius: cell * 0.3), with: .color(.white.opacity(alpha)))
                    }
                }
            }
        case .burst(let p, let radius):
            let c = center(p)
            let reach = cell * (CGFloat(radius) + 0.5)
            let extent = still ? reach : reach * (0.3 + 0.7 * easeOut(t))
            let square = CGRect(x: c.x - extent, y: c.y - extent, width: 2 * extent, height: 2 * extent)
            var light = context
            light.blendMode = .plusLighter
            light.fill(Path(roundedRect: square, cornerRadius: cell * 0.3),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.75 * fade), M3Colors.gold.opacity(0.45 * fade), M3Colors.gold.opacity(0)]),
                                               center: c, startRadius: 0, endRadius: extent * 1.2))
            context.stroke(Path(roundedRect: square, cornerRadius: cell * 0.3), with: .color(.white.opacity(fade)),
                           lineWidth: cell * 0.08 * (1 - t))
            if !still {
                let r = randoms(fx.id, 24)
                for k in 0..<12 {
                    let angle = r[k] * 2 * .pi
                    let d = reach * (0.4 + 0.8 * easeOut(t)) * (0.7 + 0.3 * r[12 + k])
                    let pt = CGPoint(x: c.x + d * cos(angle), y: c.y + d * sin(angle))
                    context.fill(IngredientArt.sparkPath(center: pt, radius: cell * 0.1 * fade), with: .color(M3Colors.gold.opacity(fade)))
                }
            }
        case .rays(let p, let cells, let color):
            let c = center(p)
            let reach = still ? 1 : min(1, t / 0.4)
            let alpha = t < 0.4 ? 1 : 1 - (t - 0.4) / 0.6
            for (k, target) in cells.enumerated() where target != p {
                let end = center(target)
                let tip = CGPoint(x: c.x + (end.x - c.x) * reach, y: c.y + (end.y - c.y) * reach)
                let hue = M3Colors.prismHues[k % (M3Colors.prismHues.count - 1)]
                context.stroke(Path { $0.move(to: c); $0.addLine(to: tip) }, with: .color(hue.opacity(0.7 * alpha)),
                               style: StrokeStyle(lineWidth: cell * 0.12, lineCap: .round))
                context.stroke(Path { $0.move(to: c); $0.addLine(to: tip) }, with: .color(.white.opacity(alpha)),
                               style: StrokeStyle(lineWidth: cell * 0.04, lineCap: .round))
                if reach >= 1 {
                    context.fill(Path(ellipseIn: CGRect(x: end.x - cell * 0.35, y: end.y - cell * 0.35, width: cell * 0.7, height: cell * 0.7)),
                                 with: .radialGradient(Gradient(colors: [.white.opacity(alpha), color.opacity(0)]), center: end,
                                                       startRadius: 0, endRadius: cell * 0.35))
                }
            }
            let orb = cell * (0.5 + 0.3 * fade)
            context.fill(Path(ellipseIn: CGRect(x: c.x - orb, y: c.y - orb, width: 2 * orb, height: 2 * orb)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(fade), color.opacity(0)]), center: c,
                                               startRadius: 0, endRadius: orb))
        case .flash:
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.55 * fade * fade)))
        case .crack(let p):
            let c = center(p)
            context.stroke(Path(roundedRect: CGRect(x: c.x - cell * 0.45, y: c.y - cell * 0.45, width: cell * 0.9, height: cell * 0.9),
                                cornerRadius: cell * 0.15),
                           with: .color(Ice.frost.opacity(fade)), lineWidth: cell * 0.06 * fade)
            guard !still else { return }
            let r = randoms(fx.id, 16)
            for k in 0..<8 {
                let angle = (Double(k) + r[k]) / 8 * 2 * .pi
                let d = cell * (0.3 + 0.55 * easeOut(t))
                let pt = CGPoint(x: c.x + d * cos(angle), y: c.y + d * sin(angle) + cell * 0.5 * t * t)
                var shard = context
                shard.translateBy(x: pt.x, y: pt.y)
                shard.rotate(by: .radians(angle + t * 4 * (r[8 + k] - 0.5)))
                let s = cell * 0.11
                shard.fill(Path { $0.addLines([CGPoint(x: -s, y: -s * 0.4), CGPoint(x: s, y: 0), CGPoint(x: -s * 0.3, y: s * 0.6)]); $0.closeSubpath() },
                           with: .color((k % 2 == 0 ? Ice.frost : Ice.light).opacity(fade)))
            }
        case .splinters(let p, let broken):
            let c = center(p)
            if !broken || still {
                let shake = still ? 0 : sin(t * 30) * cell * 0.04 * fade
                context.stroke(Path(roundedRect: CGRect(x: c.x - cell * 0.46 + shake, y: c.y - cell * 0.46, width: cell * 0.92, height: cell * 0.92),
                                    cornerRadius: cell * 0.1),
                               with: .color(M3Colors.gold.opacity(0.8 * fade)), lineWidth: cell * 0.06)
            }
            guard !still else { return }
            let count = broken ? 10 : 5
            let r = randoms(fx.id, count * 3)
            for k in 0..<count {
                let angle = -Double.pi / 2 + (r[k] - 0.5) * .pi * 1.6
                let speed = cell * (broken ? 1.1 : 0.6) * (0.6 + 0.4 * r[count + k])
                let pt = CGPoint(x: c.x + speed * t * cos(angle), y: c.y + speed * t * sin(angle) + cell * 1.4 * t * t)
                var chip = context
                chip.translateBy(x: pt.x, y: pt.y)
                chip.rotate(by: .radians(t * 8 * (r[2 * count + k] - 0.5)))
                let rect = CGRect(x: -cell * 0.1, y: -cell * 0.035, width: cell * 0.2, height: cell * 0.07)
                chip.fill(Path(rect), with: .color((k % 3 == 0 ? M3Colors.woodDark : M3Colors.woodLight).opacity(fade)))
            }
            if broken {
                let puff = cell * (0.3 + 0.5 * t)
                context.fill(Path(ellipseIn: CGRect(x: c.x - puff, y: c.y - puff, width: 2 * puff, height: 2 * puff)),
                             with: .radialGradient(Gradient(colors: [Color(white: 0.85).opacity(0.4 * fade), .clear]), center: c,
                                                   startRadius: 0, endRadius: puff))
            }
        case .ring(let p, let color):
            let c = center(p)
            let radius = cell * (still ? 0.5 : 0.3 + 0.5 * easeOut(t))
            let ring = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
            context.stroke(ring, with: .color(color.opacity(fade)), lineWidth: cell * 0.12 * fade)
            context.stroke(ring, with: .color(.white.opacity(fade)), lineWidth: cell * 0.04 * fade)
        case .score(let at, let points, let cascade):
            let c = CGPoint(x: (at.x + 0.5) * cell, y: (at.y + 0.5) * cell - (still ? 0 : cell * 0.7 * easeOut(t)))
            let scale = min(1.5, 1 + 0.12 * Double(cascade - 1))
            let text = Text(verbatim: "+\(points)")
                .font(.system(size: cell * 0.36 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(cascade > 1 ? M3Colors.gold : Color.white)
            var shadow = context
            shadow.opacity = fade
            shadow.draw(text.foregroundStyle(Color.black.opacity(0.6)), at: CGPoint(x: c.x + 1, y: c.y + 1.5))
            shadow.draw(text, at: c)
        case .swirl:
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) * 0.55
            let turn = still ? 0 : t * 2 * .pi
            for arm in 0..<3 {
                let path = Path { path in
                    for k in 0...40 {
                        let u = Double(k) / 40
                        let a = turn + Double(arm) * 2 * .pi / 3 + u * 3
                        let r = maxR * u
                        let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                        if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                context.stroke(path, with: .color(M3Colors.prismHues[arm * 2].opacity(0.5 * sin(.pi * t))),
                               style: StrokeStyle(lineWidth: cell * 0.12, lineCap: .round))
            }
        case .glitter(let p):
            let c = center(p)
            let r = randoms(fx.id, 20)
            for k in 0..<10 {
                let x = c.x + (r[k] - 0.5) * cell * 0.9
                let y = c.y - (still ? 0 : cell * 1.6 * easeOut(t) * (0.5 + 0.5 * r[10 + k]))
                context.fill(IngredientArt.sparkPath(center: CGPoint(x: x, y: y), radius: cell * 0.09 * fade),
                             with: .color(M3Colors.gold.opacity(fade)))
            }
        }
    }

    private func easeOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
}
