import BottleSortCore
import Match3Core
import SwiftUI

// Ingredient gathering (R9): how the board's pieces look. Every ingredient has its own silhouette,
// its own palette color and that color's colorblind rune (`Rune`), so kinds never rely on color
// alone. Everything is drawn with paths in a unit square (no images): ingredients, the three
// specials (comet, bloom, prism), the potion flask (drop-down goal item) and the sealed crate.

extension M3Kind {
    /// Palette color index (and so its rune): red mushroom, cyan crystal, yellow feather,
    /// purple moonflower, orange ember, blue potion drop.
    var paletteIndex: Int {
        switch self {
        case .mushroom: 0
        case .crystal: 6
        case .feather: 2
        case .moonflower: 4
        case .ember: 5
        case .drop: 1
        }
    }

    var color: Color { Palette.color(paletteIndex) }
    var rune: Rune? { Rune(colorIndex: paletteIndex) }

    /// Localized ingredient name for the HUD and VoiceOver.
    var displayName: String {
        switch self {
        case .mushroom: String(localized: "Mushroom", comment: "Match-3 ingredient")
        case .crystal: String(localized: "Crystal", comment: "Match-3 ingredient")
        case .feather: String(localized: "Feather", comment: "Match-3 ingredient")
        case .moonflower: String(localized: "Moonflower", comment: "Match-3 ingredient")
        case .ember: String(localized: "Ember", comment: "Match-3 ingredient")
        case .drop: String(localized: "Potion Drop", comment: "Match-3 ingredient")
        }
    }
}

extension M3Special {
    var displayName: String {
        switch self {
        case .row: String(localized: "row comet", comment: "Match-3 special that clears its row")
        case .column: String(localized: "column comet", comment: "Match-3 special that clears its column")
        case .bloom: String(localized: "bloom", comment: "Match-3 special that clears the 3 by 3 square around it")
        case .prism: String(localized: "prism", comment: "Match-3 special that clears every piece of one kind")
        }
    }
}

/// Colors of the non-ingredient board items.
enum M3Colors {
    static let prismHues: [Color] = [Palette.color(0), Palette.color(5), Palette.color(2), Palette.color(9),
                                     Palette.color(6), Palette.color(1), Palette.color(4), Palette.color(0)]
    static let flaskLiquid = Color(red: 1.0, green: 0.78, blue: 0.32)
    static let flaskGlow = Color(red: 1.0, green: 0.88, blue: 0.55)
    static let woodLight = Color(red: 0.62, green: 0.42, blue: 0.24)
    static let woodDark = Color(red: 0.36, green: 0.22, blue: 0.12)
    static let tray = Color(red: 0.10, green: 0.07, blue: 0.06)
    static let cellLight = Color(red: 0.98, green: 0.90, blue: 0.78)
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.40)
}

/// Draws board pieces into a `GraphicsContext`. `rect` is the cell (any size); the art keeps a
/// margin so neighbours never touch.
enum IngredientArt {
    /// Draws an ingredient (or a prism) with its special adornments; `runes` adds the rune badge.
    static func draw(_ piece: M3Piece, in context: GraphicsContext, rect: CGRect, runes: Bool) {
        let s = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s)
        // Soft contact shadow under every piece.
        context.fill(Path(ellipseIn: CGRect(x: square.minX + s * 0.2, y: square.minY + s * 0.8,
                                            width: s * 0.6, height: s * 0.12)),
                     with: .color(.black.opacity(0.28)))
        if piece.isPrism {
            drawPrism(in: context, square: square)
            return
        }
        guard let kind = piece.kind else { return }
        switch piece.special {
        case .row: drawCometTrail(in: context, square: square, horizontal: true, color: kind.color)
        case .column: drawCometTrail(in: context, square: square, horizontal: false, color: kind.color)
        case .bloom: drawBloomHalo(in: context, square: square, color: kind.color)
        default: break
        }
        let inset = piece.special == .bloom ? 0.17 : 0.11
        let art = square.insetBy(dx: s * inset, dy: s * inset)
        drawKind(kind, in: context, square: art)
        if piece.special?.isLine == true {
            drawCometArrows(in: context, square: square, horizontal: piece.special == .row)
        }
        if runes, let rune = kind.rune {
            let r = s * 0.3
            let badge = CGRect(x: square.maxX - r - s * 0.03, y: square.maxY - r - s * 0.03, width: r, height: r)
            context.fill(Path(ellipseIn: badge), with: .color(.black.opacity(0.55)))
            rune.draw(in: context, rect: badge.insetBy(dx: r * 0.2, dy: r * 0.2))
        }
    }

    // MARK: Ingredients

    static func drawKind(_ kind: M3Kind, in context: GraphicsContext, square: CGRect) {
        let s = square.width
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: square.minX + x * s, y: square.minY + y * s) }
        let base = kind.color
        let outline = StrokeStyle(lineWidth: max(1, s * 0.035), lineCap: .round, lineJoin: .round)
        let ink = Color.black.opacity(0.45)
        let shade = { (path: Path, light: Color, dark: Color) in
            context.fill(path, with: .linearGradient(Gradient(colors: [light, base, dark]),
                                                     startPoint: p(0.25, 0.05), endPoint: p(0.75, 0.95)))
            context.stroke(path, with: .color(ink), style: outline)
        }
        switch kind {
        case .mushroom:
            let stem = Path(roundedRect: CGRect(x: square.minX + s * 0.36, y: square.minY + s * 0.46,
                                                width: s * 0.28, height: s * 0.46), cornerRadius: s * 0.11)
            context.fill(stem, with: .linearGradient(Gradient(colors: [Color(white: 0.98), Color(red: 0.86, green: 0.78, blue: 0.64)]),
                                                     startPoint: p(0.36, 0.5), endPoint: p(0.64, 0.9)))
            context.stroke(stem, with: .color(ink), style: outline)
            let cap = Path { path in
                path.move(to: p(0.06, 0.58))
                path.addCurve(to: p(0.94, 0.58), control1: p(0.04, 0.0), control2: p(0.96, 0.0))
                path.addCurve(to: p(0.06, 0.58), control1: p(0.7, 0.66), control2: p(0.3, 0.66))
                path.closeSubpath()
            }
            shade(cap, Color(red: 1, green: 0.55, blue: 0.5), Color(red: 0.55, green: 0.08, blue: 0.1))
            for (x, y, r) in [(0.34, 0.3, 0.07), (0.62, 0.22, 0.055), (0.7, 0.44, 0.05), (0.2, 0.47, 0.04)] {
                context.fill(Path(ellipseIn: CGRect(x: square.minX + (x - r) * s, y: square.minY + (y - r) * s,
                                                    width: 2 * r * s, height: 2 * r * s)),
                             with: .color(Color(white: 0.98).opacity(0.95)))
            }
        case .crystal:
            let outer = Path { path in
                path.addLines([p(0.5, 0.04), p(0.8, 0.28), p(0.76, 0.74), p(0.5, 0.96), p(0.24, 0.74), p(0.2, 0.28)])
                path.closeSubpath()
            }
            shade(outer, Color(red: 0.85, green: 1, blue: 1), Color(red: 0.08, green: 0.45, blue: 0.62))
            // Facets: a bright crown and a darker right flank.
            let crown = Path { path in
                path.addLines([p(0.5, 0.04), p(0.8, 0.28), p(0.5, 0.4), p(0.2, 0.28)])
                path.closeSubpath()
            }
            context.fill(crown, with: .color(.white.opacity(0.45)))
            let flank = Path { path in
                path.addLines([p(0.5, 0.4), p(0.8, 0.28), p(0.76, 0.74), p(0.5, 0.96)])
                path.closeSubpath()
            }
            context.fill(flank, with: .color(Color(red: 0.05, green: 0.3, blue: 0.45).opacity(0.3)))
            context.stroke(Path { $0.addLines([p(0.2, 0.28), p(0.5, 0.4), p(0.8, 0.28)]); $0.move(to: p(0.5, 0.4)); $0.addLine(to: p(0.5, 0.96)) },
                           with: .color(.white.opacity(0.55)), lineWidth: max(0.8, s * 0.025))
        case .feather:
            let vane = Path { path in
                path.move(to: p(0.18, 0.9))
                path.addCurve(to: p(0.82, 0.08), control1: p(0.0, 0.44), control2: p(0.42, 0.04))
                path.addCurve(to: p(0.18, 0.9), control1: p(0.98, 0.36), control2: p(0.62, 0.84))
                path.closeSubpath()
            }
            shade(vane, Color(red: 1, green: 0.95, blue: 0.62), Color(red: 0.75, green: 0.5, blue: 0.05))
            // Notches in the vane and the quill.
            for (a, b) in [((0.3, 0.42), (0.22, 0.36)), ((0.66, 0.5), (0.76, 0.52)), ((0.56, 0.66), (0.66, 0.7))] {
                context.stroke(Path { $0.move(to: p(a.0, a.1)); $0.addLine(to: p(b.0, b.1)) },
                               with: .color(Color(red: 0.55, green: 0.35, blue: 0.02).opacity(0.8)),
                               style: StrokeStyle(lineWidth: max(1, s * 0.035), lineCap: .round))
            }
            let quill = Path { path in
                path.move(to: p(0.1, 0.96))
                path.addQuadCurve(to: p(0.78, 0.14), control: p(0.4, 0.42))
            }
            context.stroke(quill, with: .color(Color(red: 0.98, green: 0.96, blue: 0.86)),
                           style: StrokeStyle(lineWidth: max(1.2, s * 0.05), lineCap: .round))
            context.stroke(quill, with: .color(ink), style: StrokeStyle(lineWidth: max(0.6, s * 0.015), lineCap: .round))
        case .moonflower:
            for k in 0..<5 {
                let angle = Angle.degrees(Double(k) * 72 - 90)
                var petal = context
                petal.translateBy(x: square.midX, y: square.midY)
                petal.rotate(by: angle)
                let shape = Path(ellipseIn: CGRect(x: s * 0.05, y: -s * 0.15, width: s * 0.43, height: s * 0.3))
                petal.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.95, green: 0.85, blue: 1), base,
                                                                          Color(red: 0.36, green: 0.14, blue: 0.6)]),
                                                        startPoint: CGPoint(x: s * 0.05, y: 0), endPoint: CGPoint(x: s * 0.48, y: 0)))
                petal.stroke(shape, with: .color(ink), style: outline)
            }
            let r = s * 0.13
            let heart = Path(ellipseIn: CGRect(x: square.midX - r, y: square.midY - r, width: 2 * r, height: 2 * r))
            context.fill(heart, with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.88, blue: 0.5)]),
                                                     center: CGPoint(x: square.midX - r * 0.3, y: square.midY - r * 0.3),
                                                     startRadius: 0, endRadius: r * 1.3))
            context.stroke(heart, with: .color(ink), style: outline)
        case .ember:
            let flame = Path { path in
                path.move(to: p(0.5, 0.95))
                path.addCurve(to: p(0.16, 0.6), control1: p(0.26, 0.95), control2: p(0.12, 0.8))
                path.addCurve(to: p(0.32, 0.26), control1: p(0.18, 0.44), control2: p(0.3, 0.4))
                path.addCurve(to: p(0.42, 0.42), control1: p(0.36, 0.34), control2: p(0.4, 0.38))
                path.addCurve(to: p(0.54, 0.04), control1: p(0.42, 0.24), control2: p(0.46, 0.1))
                path.addCurve(to: p(0.74, 0.36), control1: p(0.62, 0.16), control2: p(0.74, 0.24))
                path.addCurve(to: p(0.8, 0.28), control1: p(0.76, 0.33), control2: p(0.78, 0.3))
                path.addCurve(to: p(0.84, 0.62), control1: p(0.88, 0.4), control2: p(0.88, 0.52))
                path.addCurve(to: p(0.5, 0.95), control1: p(0.84, 0.84), control2: p(0.7, 0.95))
                path.closeSubpath()
            }
            context.fill(flame, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), base,
                                                                        Color(red: 0.75, green: 0.18, blue: 0.05)]),
                                                      startPoint: p(0.5, 0.05), endPoint: p(0.5, 0.95)))
            context.stroke(flame, with: .color(ink), style: outline)
            let core = Path { path in
                path.move(to: p(0.5, 0.9))
                path.addCurve(to: p(0.32, 0.7), control1: p(0.38, 0.9), control2: p(0.3, 0.82))
                path.addCurve(to: p(0.52, 0.4), control1: p(0.34, 0.56), control2: p(0.48, 0.52))
                path.addCurve(to: p(0.68, 0.7), control1: p(0.6, 0.52), control2: p(0.7, 0.58))
                path.addCurve(to: p(0.5, 0.9), control1: p(0.68, 0.82), control2: p(0.6, 0.9))
                path.closeSubpath()
            }
            context.fill(core, with: .color(Color(red: 1, green: 0.95, blue: 0.6).opacity(0.95)))
        case .drop:
            let drop = Path { path in
                path.move(to: p(0.5, 0.04))
                path.addCurve(to: p(0.84, 0.6), control1: p(0.6, 0.24), control2: p(0.84, 0.4))
                path.addCurve(to: p(0.5, 0.95), control1: p(0.84, 0.82), control2: p(0.68, 0.95))
                path.addCurve(to: p(0.16, 0.6), control1: p(0.32, 0.95), control2: p(0.16, 0.82))
                path.addCurve(to: p(0.5, 0.04), control1: p(0.16, 0.4), control2: p(0.4, 0.24))
                path.closeSubpath()
            }
            shade(drop, Color(red: 0.6, green: 0.8, blue: 1), Color(red: 0.05, green: 0.2, blue: 0.6))
            // Glossy highlight and a small bubble inside the potion.
            context.fill(Path(ellipseIn: CGRect(x: square.minX + s * 0.28, y: square.minY + s * 0.44, width: s * 0.13, height: s * 0.22)),
                         with: .color(.white.opacity(0.75)))
            context.stroke(Path(ellipseIn: CGRect(x: square.minX + s * 0.56, y: square.minY + s * 0.66, width: s * 0.12, height: s * 0.12)),
                           with: .color(.white.opacity(0.6)), lineWidth: max(0.8, s * 0.025))
        }
        // A shared soft gloss so every ingredient reads as a lit object.
        context.fill(Path(ellipseIn: CGRect(x: square.minX + s * 0.3, y: square.minY + s * 0.12, width: s * 0.16, height: s * 0.08)),
                     with: .color(.white.opacity(kind == .feather || kind == .ember ? 0.0 : 0.35)))
    }

    // MARK: Specials

    /// A comet: a glowing trail across the cell in its direction, behind the ingredient.
    static func drawCometTrail(in context: GraphicsContext, square: CGRect, horizontal: Bool, color: Color) {
        let s = square.width
        let band = horizontal
            ? CGRect(x: square.minX, y: square.midY - s * 0.17, width: s, height: s * 0.34)
            : CGRect(x: square.midX - s * 0.17, y: square.minY, width: s * 0.34, height: s)
        let path = Path(roundedRect: band, cornerRadius: s * 0.17)
        context.fill(path, with: .linearGradient(
            Gradient(stops: [.init(color: color.opacity(0.0), location: 0), .init(color: .white.opacity(0.9), location: 0.5),
                             .init(color: color.opacity(0.0), location: 1)]),
            startPoint: horizontal ? CGPoint(x: band.minX, y: band.midY) : CGPoint(x: band.midX, y: band.minY),
            endPoint: horizontal ? CGPoint(x: band.maxX, y: band.midY) : CGPoint(x: band.midX, y: band.maxY)))
        context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: max(1, s * 0.03))
    }

    /// The comet's two arrowheads at the cell's edges, over the ingredient.
    static func drawCometArrows(in context: GraphicsContext, square: CGRect, horizontal: Bool) {
        let s = square.width
        for sign in [-1.0, 1.0] {
            var arrow = context
            arrow.translateBy(x: square.midX, y: square.midY)
            arrow.rotate(by: .degrees(horizontal ? (sign > 0 ? 0 : 180) : (sign > 0 ? 90 : -90)))
            let tip = Path { path in
                path.addLines([CGPoint(x: s * 0.49, y: 0), CGPoint(x: s * 0.33, y: -s * 0.13), CGPoint(x: s * 0.33, y: s * 0.13)])
                path.closeSubpath()
            }
            arrow.fill(tip, with: .color(.white))
            arrow.stroke(tip, with: .color(.black.opacity(0.55)), lineWidth: max(1, s * 0.025))
        }
    }

    /// A bloom: a soft halo with a ring of eight sparks around the ingredient.
    static func drawBloomHalo(in context: GraphicsContext, square: CGRect, color: Color) {
        let s = square.width
        let c = CGPoint(x: square.midX, y: square.midY)
        context.fill(Path(ellipseIn: square.insetBy(dx: s * 0.02, dy: s * 0.02)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.9), color.opacity(0.55), color.opacity(0)]),
                                           center: c, startRadius: s * 0.1, endRadius: s * 0.5))
        let ring = Path(ellipseIn: square.insetBy(dx: s * 0.07, dy: s * 0.07))
        context.stroke(ring, with: .color(.white.opacity(0.9)),
                       style: StrokeStyle(lineWidth: max(1.2, s * 0.045), dash: [s * 0.06, s * 0.08]))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            let r = s * 0.45
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            let d = s * 0.07
            context.fill(sparkPath(center: pt, radius: d), with: .color(.white))
        }
    }

    /// A prism: a faceted rainbow gem with a white star at its heart (no ingredient kind).
    static func drawPrism(in context: GraphicsContext, square: CGRect) {
        let s = square.width
        let c = CGPoint(x: square.midX, y: square.midY)
        context.fill(Path(ellipseIn: square.insetBy(dx: s * 0.02, dy: s * 0.02)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.7), .white.opacity(0)]),
                                           center: c, startRadius: s * 0.2, endRadius: s * 0.5))
        let r = s * 0.36
        let gem = Path { path in
            path.addLines((0..<8).map { k in
                let a = Double(k) * .pi / 4 + .pi / 8
                return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            })
            path.closeSubpath()
        }
        context.fill(gem, with: .conicGradient(Gradient(colors: M3Colors.prismHues), center: c))
        // Facets: spokes and an inner octagon.
        let inner = (0..<8).map { k -> CGPoint in
            let a = Double(k) * .pi / 4 + .pi / 8
            return CGPoint(x: c.x + r * 0.5 * cos(a), y: c.y + r * 0.5 * sin(a))
        }
        context.fill(Path { $0.addLines(inner); $0.closeSubpath() }, with: .color(.white.opacity(0.45)))
        context.stroke(gem, with: .color(.white.opacity(0.95)), lineWidth: max(1.2, s * 0.04))
        context.stroke(gem, with: .color(.black.opacity(0.35)), lineWidth: max(0.6, s * 0.012))
        context.fill(sparkPath(center: c, radius: s * 0.16), with: .color(.white))
    }

    /// A four-pointed sparkle.
    static func sparkPath(center c: CGPoint, radius r: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: c.x, y: c.y - r))
            path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
            path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
            path.closeSubpath()
        }
    }

    // MARK: Flask and crate

    /// The potion flask that must be brought down: a round-bottomed flask of glowing amber potion.
    static func drawFlask(in context: GraphicsContext, rect: CGRect) {
        let s = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s)
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: square.minX + x * s, y: square.minY + y * s) }
        context.fill(Path(ellipseIn: square.insetBy(dx: s * 0.04, dy: s * 0.04)),
                     with: .radialGradient(Gradient(colors: [M3Colors.flaskGlow.opacity(0.55), M3Colors.flaskGlow.opacity(0)]),
                                           center: p(0.5, 0.6), startRadius: s * 0.15, endRadius: s * 0.5))
        let bulb = CGRect(x: square.minX + s * 0.2, y: square.minY + s * 0.34, width: s * 0.6, height: s * 0.58)
        let neck = CGRect(x: square.minX + s * 0.4, y: square.minY + s * 0.14, width: s * 0.2, height: s * 0.26)
        context.fill(Path(ellipseIn: bulb), with: .color(.white.opacity(0.18)))
        context.fill(Path(neck), with: .color(.white.opacity(0.18)))
        // Potion: the lower part of the bulb.
        var potion = context
        potion.clip(to: Path(ellipseIn: bulb))
        potion.fill(Path(CGRect(x: bulb.minX, y: bulb.minY + bulb.height * 0.32, width: bulb.width, height: bulb.height)),
                    with: .linearGradient(Gradient(colors: [M3Colors.flaskGlow, M3Colors.flaskLiquid, Color(red: 0.85, green: 0.45, blue: 0.1)]),
                                          startPoint: p(0.5, 0.5), endPoint: p(0.5, 0.92)))
        potion.fill(Path(CGRect(x: bulb.minX, y: bulb.minY + bulb.height * 0.32, width: bulb.width, height: s * 0.03)),
                    with: .color(.white.opacity(0.7)))
        context.stroke(Path(ellipseIn: bulb), with: .color(.white.opacity(0.9)), lineWidth: max(1, s * 0.04))
        context.stroke(Path(neck), with: .color(.white.opacity(0.9)), lineWidth: max(1, s * 0.035))
        // Cork.
        context.fill(Path(roundedRect: CGRect(x: square.minX + s * 0.37, y: square.minY + s * 0.06, width: s * 0.26, height: s * 0.12),
                          cornerRadius: s * 0.03),
                     with: .color(Color(red: 0.72, green: 0.5, blue: 0.3)))
        // Shine and a downward chevron: it wants to go down.
        context.fill(Path(ellipseIn: CGRect(x: bulb.minX + bulb.width * 0.16, y: bulb.minY + bulb.height * 0.14,
                                            width: bulb.width * 0.16, height: bulb.height * 0.28)),
                     with: .color(.white.opacity(0.6)))
        context.stroke(Path { $0.addLines([p(0.4, 0.66), p(0.5, 0.76), p(0.6, 0.66)]) },
                       with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: max(1.2, s * 0.05), lineCap: .round, lineJoin: .round))
    }

    /// A sealed crate: dark wooden planks with an iron frame (the seal sits on top as a view).
    static func drawCrate(in context: GraphicsContext, rect: CGRect, hits: Int) {
        let s = min(rect.width, rect.height)
        let box = rect.insetBy(dx: s * 0.04, dy: s * 0.04)
        let corner = s * 0.1
        let outer = Path(roundedRect: box, cornerRadius: corner)
        context.fill(outer, with: .linearGradient(Gradient(colors: [M3Colors.woodLight, M3Colors.woodDark]),
                                                  startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)))
        // Planks.
        for k in 1..<3 {
            let y = box.minY + box.height * CGFloat(k) / 3
            context.stroke(Path { $0.move(to: CGPoint(x: box.minX, y: y)); $0.addLine(to: CGPoint(x: box.maxX, y: y)) },
                           with: .color(.black.opacity(0.35)), lineWidth: max(1, s * 0.025))
        }
        // Brace and frame; a heavier crate (more hits) has a thicker iron band.
        context.stroke(Path { $0.move(to: CGPoint(x: box.minX + corner, y: box.maxY - corner)); $0.addLine(to: CGPoint(x: box.maxX - corner, y: box.minY + corner)) },
                       with: .color(M3Colors.woodDark.opacity(0.9)), lineWidth: max(2, s * 0.08))
        let band = max(1.5, s * (0.04 + 0.02 * CGFloat(hits)))
        context.stroke(Path(roundedRect: box.insetBy(dx: band / 2, dy: band / 2), cornerRadius: corner),
                       with: .color(Color(white: hits >= 3 ? 0.62 : 0.42)), lineWidth: band)
        for (x, y) in [(box.minX, box.minY), (box.maxX, box.minY), (box.minX, box.maxY), (box.maxX, box.maxY)] {
            let r = s * 0.045
            let cx = x + (x == box.minX ? 1 : -1) * band * 1.4, cy = y + (y == box.minY ? 1 : -1) * band * 1.4
            context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(Color(white: 0.75)))
        }
    }

    /// Seal metal by hits left: copper (1), steel (2), gold (3), like the rune keys' seals.
    static func sealKey(hits: Int) -> KeyID {
        KeyID(hits >= 3 ? 1 : hits == 2 ? 2 : 0)
    }
}

/// One board piece as a view (ingredient, special or prism, with its frost).
struct M3PieceView: View {
    let piece: M3Piece
    let size: CGFloat
    var runes = false

    var body: some View {
        ZStack {
            Canvas { context, canvas in
                IngredientArt.draw(piece, in: context, rect: CGRect(origin: .zero, size: canvas), runes: runes)
            }
            if piece.frost > 0 {
                M3FrostCover(layers: piece.frost, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Frost over a piece, in the Frost Peak ice look (`Ice` colors, bright top face, facets, frost
/// specks) but see-through, so the ingredient stays readable. Two layers are thicker and carry a
/// small ice crystal with a 2.
struct M3FrostCover: View {
    let layers: Int
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
        ZStack(alignment: .topTrailing) {
            Canvas { context, canvas in
                let w = canvas.width, h = canvas.height
                let thick = layers >= 2
                context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .linearGradient(
                    Gradient(stops: [.init(color: Ice.frost.opacity(thick ? 0.62 : 0.45), location: 0),
                                     .init(color: Ice.light.opacity(thick ? 0.32 : 0.14), location: 0.5),
                                     .init(color: Ice.mid.opacity(thick ? 0.5 : 0.32), location: 1)]),
                    startPoint: .zero, endPoint: CGPoint(x: w * 0.4, y: h)))
                context.fill(Path(CGRect(x: 0, y: 0, width: w, height: max(1.5, h * 0.08))), with: .color(.white.opacity(0.8)))
                context.fill(Path(CGRect(x: 0, y: h - max(1, h * 0.07), width: w, height: max(1, h * 0.07))),
                             with: .color(Ice.deep.opacity(0.45)))
                let line = max(0.75, w * 0.018)
                for facet in [[(0.04, 0.3), (0.18, 0.5), (0.1, 0.96)], [(0.74, 0.04), (0.86, 0.4), (0.98, 0.5)],
                              [(0.86, 0.4), (0.8, 0.96)]] {
                    context.stroke(Path { $0.addLines(facet.map { CGPoint(x: $0.0 * w, y: $0.1 * h) }) },
                                   with: .color(.white.opacity(0.65)), lineWidth: line)
                }
                for (x, y) in [(0.12, 0.14), (0.62, 0.86), (0.9, 0.2), (0.3, 0.8)] {
                    let r = max(0.8, w * 0.02)
                    context.fill(Path(ellipseIn: CGRect(x: x * w - r, y: y * h - r, width: 2 * r, height: 2 * r)),
                                 with: .color(.white.opacity(0.85)))
                }
            }
            if layers >= 2 {
                IceCrystal(size: size * 0.36, turns: 2)
                    .padding(size * 0.02)
            }
        }
        .frame(width: size * 0.94, height: size * 0.94)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Ice.outline, lineWidth: max(1, size * (layers >= 2 ? 0.05 : 0.03))) }
        .allowsHitTesting(false)
    }
}

/// A sealed crate with its rune seal and hit pips.
struct M3CrateView: View {
    let hits: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            Canvas { context, canvas in
                IngredientArt.drawCrate(in: context, rect: CGRect(origin: .zero, size: canvas), hits: hits)
            }
            VStack(spacing: size * 0.04) {
                BottleView.lockBadge(IngredientArt.sealKey(hits: hits), width: size * 0.5)
                    .scaleEffect(0.9)
                HStack(spacing: size * 0.05) {
                    ForEach(0..<hits, id: \.self) { _ in
                        Circle().fill(Palette.keyColor(IngredientArt.sealKey(hits: hits).rawValue))
                            .frame(width: size * 0.08, height: size * 0.08)
                            .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 0.5))
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The potion flask (drop-down goal item) as a view.
struct M3FlaskView: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in IngredientArt.drawFlask(in: context, rect: CGRect(origin: .zero, size: canvas)) }
            .frame(width: size, height: size)
    }
}

/// A small icon of an ingredient for the HUD and cards.
struct M3KindIcon: View {
    let kind: M3Kind
    var size: CGFloat = 26
    var runes = false

    var body: some View {
        Canvas { context, canvas in
            IngredientArt.drawKind(kind, in: context, square: CGRect(origin: .zero, size: canvas).insetBy(dx: 1, dy: 1))
            if runes, let rune = kind.rune {
                let r = canvas.width * 0.42
                let badge = CGRect(x: canvas.width - r, y: canvas.height - r, width: r, height: r)
                context.fill(Path(ellipseIn: badge), with: .color(.black.opacity(0.6)))
                rune.draw(in: context, rect: badge.insetBy(dx: r * 0.2, dy: r * 0.2))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
