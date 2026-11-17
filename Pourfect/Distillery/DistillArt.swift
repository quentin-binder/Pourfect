import BottleSortCore
import DistilleryCore
import SwiftUI

/// The brass-and-glass look of the distillery (R10), drawn in a `GraphicsContext`: the panel, the
/// tiles, brass pipes with a liquid bore, cauldrons, valves, heat coils, murk and drips. One cell
/// is drawn at a time with the context's origin at the cell's center; pieces are drawn in their base
/// orientation inside a rotated context, so turning a piece is one transform.
enum DistillArt {
    static let brass = Color(red: 0.80, green: 0.62, blue: 0.30)
    static let brassDark = Color(red: 0.36, green: 0.24, blue: 0.10)
    static let brassLight = Color(red: 1.00, green: 0.89, blue: 0.60)
    static let bore = Color(red: 0.07, green: 0.06, blue: 0.05)
    static let murky = Color(red: 0.34, green: 0.31, blue: 0.21)
    static let copper = Color(red: 0.90, green: 0.46, blue: 0.22)
    static let iron = Color(red: 0.20, green: 0.20, blue: 0.22)
    static let valveShut = Color(red: 0.78, green: 0.22, blue: 0.18)
    static let valveOpen = Color(red: 0.40, green: 0.74, blue: 0.42)
    static let gold = Color(red: 1.00, green: 0.82, blue: 0.35)

    static func liquid(_ color: ColorID?) -> Color { color.map { Palette.color($0.rawValue) } ?? murky }

    // MARK: Geometry (local frame: cell center at the origin, side `s`)

    static func edgePoint(_ side: DistillDir, _ s: CGFloat) -> CGPoint {
        let h = s / 2
        switch side {
        case .north: return CGPoint(x: 0, y: -h)
        case .east: return CGPoint(x: h, y: 0)
        case .south: return CGPoint(x: 0, y: h)
        case .west: return CGPoint(x: -h, y: 0)
        }
    }

    /// The pipe arm from the opening on `side` to the hub, in the shape's base orientation. An elbow's
    /// arms are the halves of a quarter circle around its north-east corner; everything else runs straight
    /// to the center.
    static func arm(_ shape: DistillShape, side: DistillDir, s: CGFloat) -> [CGPoint] {
        guard shape == .elbow else { return [edgePoint(side, s), .zero] }
        let h = s / 2
        let center = CGPoint(x: h, y: -h)
        let (a0, a1): (Double, Double) = side == .north ? (.pi, .pi * 0.75) : (.pi / 2, .pi * 0.75)
        return (0...8).map { k in
            let a = a0 + (a1 - a0) * Double(k) / 8
            return CGPoint(x: center.x + h * cos(a), y: center.y + h * sin(a))
        }
    }

    static func hub(_ shape: DistillShape, s: CGFloat) -> CGPoint {
        shape == .elbow ? arm(.elbow, side: .north, s: s).last! : .zero
    }

    static func path(_ points: [CGPoint]) -> Path {
        Path { p in p.addLines(points) }
    }

    // MARK: Panel and tiles

    /// The wooden panel with its brass frame and the slate well the cells sit in.
    static func drawPanel(_ ctx: GraphicsContext, rect: CGRect, well: CGRect, s: CGFloat) {
        let outer = Path(roundedRect: rect, cornerRadius: s * 0.32)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.55), radius: s * 0.18, y: s * 0.08))
            layer.fill(outer, with: .linearGradient(Gradient(colors: [Color(red: 0.36, green: 0.23, blue: 0.13),
                                                                      Color(red: 0.22, green: 0.13, blue: 0.07)]),
                                                     startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        }
        // Wood grain.
        var grain = Path()
        let lines = 9
        for k in 1..<lines {
            let y = rect.minY + rect.height * CGFloat(k) / CGFloat(lines)
            grain.move(to: CGPoint(x: rect.minX + s * 0.1, y: y))
            grain.addCurve(to: CGPoint(x: rect.maxX - s * 0.1, y: y + s * 0.04),
                           control1: CGPoint(x: rect.midX - rect.width * 0.2, y: y - s * 0.08),
                           control2: CGPoint(x: rect.midX + rect.width * 0.2, y: y + s * 0.1))
        }
        ctx.stroke(grain, with: .color(.black.opacity(0.16)), lineWidth: max(1, s * 0.02))
        ctx.stroke(outer, with: .color(brass.opacity(0.85)), lineWidth: max(1.5, s * 0.05))
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: s * 0.05, dy: s * 0.05), cornerRadius: s * 0.28),
                   with: .color(brassDark), lineWidth: max(1, s * 0.02))
        // Corner bolts.
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            let c = CGPoint(x: corner.x + (corner.x < rect.midX ? 1 : -1) * s * 0.16,
                            y: corner.y + (corner.y < rect.midY ? 1 : -1) * s * 0.16)
            rivet(ctx, at: c, r: s * 0.05)
        }
        let wellPath = Path(roundedRect: well, cornerRadius: s * 0.14)
        ctx.fill(wellPath, with: .linearGradient(Gradient(colors: [Color(red: 0.10, green: 0.10, blue: 0.11),
                                                                   Color(red: 0.06, green: 0.06, blue: 0.07)]),
                                                 startPoint: CGPoint(x: well.midX, y: well.minY),
                                                 endPoint: CGPoint(x: well.midX, y: well.maxY)))
        ctx.stroke(wellPath, with: .color(.black.opacity(0.7)), lineWidth: max(1, s * 0.03))
    }

    /// A stone tile under a piece; a riveted piece sits on an iron plate with four rivets.
    static func drawTile(_ ctx: GraphicsContext, s: CGFloat, fixed: Bool) {
        let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s).insetBy(dx: s * 0.035, dy: s * 0.035)
        let tile = Path(roundedRect: rect, cornerRadius: s * 0.12)
        let colors = fixed ? [Color(red: 0.27, green: 0.26, blue: 0.28), Color(red: 0.15, green: 0.15, blue: 0.17)]
                           : [Color(red: 0.25, green: 0.21, blue: 0.18), Color(red: 0.16, green: 0.14, blue: 0.12)]
        ctx.fill(tile, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: rect.minY),
                                             endPoint: CGPoint(x: 0, y: rect.maxY)))
        ctx.stroke(tile, with: .color(.white.opacity(0.07)), lineWidth: max(0.5, s * 0.012))
        if fixed {
            let d = s * 0.36
            for p in [CGPoint(x: -d, y: -d), CGPoint(x: d, y: -d), CGPoint(x: -d, y: d), CGPoint(x: d, y: d)] {
                rivet(ctx, at: p, r: s * 0.045)
            }
        }
    }

    static func rivet(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: r * 0.35)), with: .color(.black.opacity(0.5)))
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [brassLight, brass, brassDark]),
                                                               center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.35),
                                                               startRadius: 0, endRadius: r * 1.4))
    }

    // MARK: Pipes

    /// The brass body of a pipe through `arms` (no liquid): shadow, dark rim, brass, highlight, bore,
    /// and a flange at each opening.
    static func drawPipe(_ ctx: GraphicsContext, arms: [[CGPoint]], s: CGFloat, junction: Bool) {
        var body = Path()
        for arm in arms { body.addPath(path(arm)) }
        let style = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .round) }
        ctx.stroke(body.offsetBy(dx: 0, dy: s * 0.035), with: .color(.black.opacity(0.45)), style: style(s * 0.31))
        ctx.stroke(body, with: .color(brassDark), style: style(s * 0.30))
        ctx.stroke(body, with: .color(brass), style: style(s * 0.245))
        ctx.stroke(body.offsetBy(dx: -s * 0.045, dy: -s * 0.045), with: .color(brassLight.opacity(0.35)), style: style(s * 0.05))
        if junction {
            let r = s * 0.17
            let hub = Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
            ctx.fill(hub, with: .color(brassDark))
            ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.84, y: -r * 0.84, width: 1.68 * r, height: 1.68 * r)), with: .color(brass))
        }
        ctx.stroke(body, with: .color(bore), style: StrokeStyle(lineWidth: s * 0.13, lineCap: .round, lineJoin: .round))
        // Flanges at the openings (across the pipe, just inside the cell edge).
        for arm in arms {
            let edge = arm[0], next = arm[1]
            let dx = next.x - edge.x, dy = next.y - edge.y
            let len = max(0.001, sqrt(dx * dx + dy * dy))
            let ux = dx / len, uy = dy / len
            let c = CGPoint(x: edge.x + ux * s * 0.05, y: edge.y + uy * s * 0.05)
            var flange = Path()
            flange.move(to: CGPoint(x: c.x - uy * s * 0.19, y: c.y + ux * s * 0.19))
            flange.addLine(to: CGPoint(x: c.x + uy * s * 0.19, y: c.y - ux * s * 0.19))
            ctx.stroke(flange, with: .color(brassDark), style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round))
            ctx.stroke(flange, with: .color(brass), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        }
    }

    /// Liquid in one arm: `fill` 0…1 of the way, from the opening inwards (`inward`) or from the hub out.
    static func drawLiquid(_ ctx: GraphicsContext, arm: [CGPoint], s: CGFloat, color: Color, fill: Double,
                           inward: Bool, murky: Bool, glow: Bool = false) {
        guard fill > 0 else { return }
        let full = path(arm)
        let part = fill >= 1 ? full : (inward ? full.trimmedPath(from: 0, to: fill) : full.trimmedPath(from: 1 - fill, to: 1))
        if glow {
            ctx.stroke(part, with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: s * 0.26, lineCap: .round, lineJoin: .round))
        }
        ctx.stroke(part, with: .color(color), style: StrokeStyle(lineWidth: s * 0.115, lineCap: .round, lineJoin: .round))
        if murky {
            ctx.stroke(part, with: .color(.black.opacity(0.35)),
                       style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round, dash: [s * 0.03, s * 0.07]))
        } else {
            ctx.stroke(part.offsetBy(dx: -s * 0.018, dy: -s * 0.018), with: .color(.white.opacity(0.35)),
                       style: StrokeStyle(lineWidth: s * 0.028, lineCap: .round, lineJoin: .round))
        }
    }

    /// A cap's closed end: a brass dome over the hub.
    static func drawCapEnd(_ ctx: GraphicsContext, s: CGFloat) {
        let r = s * 0.16
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r * 0.8, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.4)))
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(brassDark))
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.82, y: -r * 0.82, width: 1.64 * r, height: 1.64 * r)),
                 with: .radialGradient(Gradient(colors: [brassLight, brass]), center: CGPoint(x: -r * 0.3, y: -r * 0.3),
                                       startRadius: 0, endRadius: r))
    }

    /// A valve's handwheel at `at` (red while shut, green once open).
    static func drawValve(_ ctx: GraphicsContext, at c: CGPoint, s: CGFloat, open: Bool, spin: Double) {
        let r = s * 0.17
        let color = open ? valveOpen : valveShut
        let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.stroke(ring.offsetBy(dx: 0, dy: s * 0.02), with: .color(.black.opacity(0.5)), lineWidth: s * 0.06)
        var spokes = Path()
        for k in 0..<4 {
            let a = spin + Double(k) * .pi / 4
            spokes.move(to: CGPoint(x: c.x - r * cos(a), y: c.y - r * sin(a)))
            spokes.addLine(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
        }
        ctx.stroke(spokes, with: .color(color.opacity(0.9)), lineWidth: s * 0.025)
        ctx.stroke(ring, with: .color(color), lineWidth: s * 0.05)
        let hr = s * 0.045
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(brass))
        if !open {
            // The gate: a bar across the bore at the hub.
            var bar = Path()
            bar.move(to: CGPoint(x: c.x - s * 0.07, y: c.y))
            bar.addLine(to: CGPoint(x: c.x + s * 0.07, y: c.y))
            ctx.stroke(bar, with: .color(valveShut), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
        }
    }

    /// A heat coil: copper windings around the pipe at `at`, glowing (brighter while liquid runs through).
    static func drawCoil(_ ctx: GraphicsContext, at c: CGPoint, angle: Double, s: CGFloat, hot: Bool, pulse: Double) {
        let glowR = s * (hot ? 0.42 : 0.32)
        let glow = Color(red: 1.0, green: 0.45, blue: 0.12)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - glowR, y: c.y - glowR, width: 2 * glowR, height: 2 * glowR)),
                 with: .radialGradient(Gradient(colors: [glow.opacity(hot ? 0.55 + 0.2 * pulse : 0.28), glow.opacity(0)]),
                                       center: c, startRadius: 0, endRadius: glowR))
        var coil = ctx
        coil.translateBy(x: c.x, y: c.y)
        coil.rotate(by: .radians(angle))
        for k in -1...1 {
            let y = CGFloat(k) * s * 0.075
            let ring = Path(ellipseIn: CGRect(x: -s * 0.19, y: y - s * 0.035, width: s * 0.38, height: s * 0.07))
            coil.stroke(ring, with: .color(brassDark), lineWidth: s * 0.05)
            coil.stroke(ring, with: .color(hot ? Color(red: 1, green: 0.62, blue: 0.3) : copper), lineWidth: s * 0.03)
        }
    }

    // MARK: Cauldrons, murk and drips

    /// A cauldron outlet: an iron pot of its potion (with its rune) over a little fire.
    static func drawCauldron(_ ctx: GraphicsContext, s: CGFloat, color: ColorID, runes: Bool, bubble: Double) {
        // Fire glow under the pot.
        let fire = Path(ellipseIn: CGRect(x: -s * 0.3, y: s * 0.12, width: s * 0.6, height: s * 0.3))
        ctx.fill(fire, with: .radialGradient(Gradient(colors: [Color.orange.opacity(0.7), Color.orange.opacity(0)]),
                                             center: CGPoint(x: 0, y: s * 0.3), startRadius: 0, endRadius: s * 0.3))
        let body = Path(ellipseIn: CGRect(x: -s * 0.31, y: -s * 0.2, width: s * 0.62, height: s * 0.5))
        ctx.fill(body.offsetBy(dx: 0, dy: s * 0.03), with: .color(.black.opacity(0.5)))
        ctx.fill(body, with: .radialGradient(Gradient(colors: [Color(white: 0.36), iron, Color(white: 0.06)]),
                                             center: CGPoint(x: -s * 0.1, y: -s * 0.05), startRadius: 0, endRadius: s * 0.36))
        // Legs.
        for x in [-s * 0.18, s * 0.18] {
            ctx.fill(Path(roundedRect: CGRect(x: x - s * 0.03, y: s * 0.25, width: s * 0.06, height: s * 0.1),
                          cornerRadius: s * 0.02), with: .color(iron))
        }
        let rim = CGRect(x: -s * 0.33, y: -s * 0.27, width: s * 0.66, height: s * 0.17)
        ctx.fill(Path(ellipseIn: rim), with: .color(Color(white: 0.42)))
        let surface = rim.insetBy(dx: s * 0.04, dy: s * 0.025)
        let liquid = Palette.color(color.rawValue)
        ctx.fill(Path(ellipseIn: surface), with: .color(liquid))
        ctx.fill(Path(ellipseIn: surface.insetBy(dx: s * 0.06, dy: s * 0.02).offsetBy(dx: -s * 0.03, dy: -s * 0.01)),
                 with: .color(.white.opacity(0.22)))
        // A bubble or two.
        let bx = sin(bubble * 2 * .pi) * s * 0.12
        let br = s * 0.025 * (0.6 + 0.4 * abs(sin(bubble * .pi)))
        ctx.stroke(Path(ellipseIn: CGRect(x: bx - br, y: surface.midY - br, width: 2 * br, height: 2 * br)),
                   with: .color(.white.opacity(0.6)), lineWidth: max(0.6, s * 0.012))
        if runes, let rune = Rune(colorIndex: color.rawValue) {
            let side = s * 0.2
            rune.draw(in: ctx, rect: CGRect(x: -side / 2, y: s * 0.0, width: side, height: side))
        }
    }

    /// Murky liquid: a puff of dull smoke above the spot (`phase` 0…1 drifts it).
    static func drawMurk(_ ctx: GraphicsContext, at c: CGPoint, s: CGFloat, phase: Double) {
        for k in 0..<3 {
            let t = (phase + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let r = s * (0.05 + 0.05 * t)
            let p = CGPoint(x: c.x + CGFloat(k - 1) * s * 0.07, y: c.y - s * 0.08 - CGFloat(t) * s * 0.22)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Color(red: 0.45, green: 0.42, blue: 0.32).opacity(0.75 * (1 - t))))
        }
        // A warning ring around the spot.
        let r = s * 0.13
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(Color(red: 0.95, green: 0.35, blue: 0.25).opacity(0.85)), lineWidth: max(1, s * 0.03))
    }

    /// Liquid dripping out of an open end at `at` (`phase` 0…1 lets a drop fall).
    static func drawLeak(_ ctx: GraphicsContext, at c: CGPoint, s: CGFloat, color: Color, phase: Double) {
        let blob = Path(ellipseIn: CGRect(x: c.x - s * 0.08, y: c.y - s * 0.05, width: s * 0.16, height: s * 0.1))
        ctx.fill(blob, with: .color(color))
        let fall = CGFloat(phase) * s * 0.34
        let r = s * 0.045 * (1 - CGFloat(phase) * 0.3)
        var drop = Path()
        let p = CGPoint(x: c.x, y: c.y + s * 0.05 + fall)
        drop.move(to: CGPoint(x: p.x, y: p.y - r * 2))
        drop.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: CGPoint(x: p.x + r, y: p.y - r))
        drop.addArc(center: p, radius: r, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r * 2), control: CGPoint(x: p.x - r, y: p.y - r))
        ctx.fill(drop, with: .color(color.opacity(1 - phase * 0.6)))
        // A puddle mark below.
        let puddle = Path(ellipseIn: CGRect(x: c.x - s * 0.1, y: c.y + s * 0.4, width: s * 0.2, height: s * 0.05))
        ctx.fill(puddle, with: .color(color.opacity(0.45)))
    }

    /// A small round tag in a flask's wanted color with its rune (or a link number).
    static func drawTag(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, color: ColorID, rune: Bool, number: Int? = nil) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: r * 0.15)), with: .color(.black.opacity(0.5)))
        ctx.fill(Path(ellipseIn: rect), with: .color(Palette.color(color.rawValue)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(brass), lineWidth: max(1, r * 0.22))
        if let number {
            ctx.draw(Text(verbatim: "\(number)").font(.system(size: r * 1.25, weight: .heavy, design: .rounded))
                .foregroundColor(.white), at: c)
        } else if rune, let symbol = Rune(colorIndex: color.rawValue) {
            symbol.draw(in: ctx, rect: rect.insetBy(dx: r * 0.4, dy: r * 0.4))
        }
    }
}
