import Match3Core
import SecretRecipeCore
import SwiftUI

// Secret Recipe (R10b): how the eight tray ingredients and the gold / silver drops look. The six
// gathering ingredients are drawn by `IngredientArt` (the match-3 board's own paths); honeycomb and
// starleaf are new, drawn the same way (unit square, gradient body, dark ink outline, soft gloss).
// Each has its own palette color and that color's colorblind rune.

extension RecipeIngredient {
    /// The gathering ingredient with the same look (nil for the two new ones).
    var gatheringKind: M3Kind? {
        switch self {
        case .mushroom: .mushroom
        case .crystal: .crystal
        case .feather: .feather
        case .moonflower: .moonflower
        case .ember: .ember
        case .drop: .drop
        case .honeycomb, .starleaf: nil
        }
    }

    /// Palette index (and so its rune): the gathering colors, then brown honeycomb and green starleaf.
    var paletteIndex: Int {
        switch self {
        case .honeycomb: 8
        case .starleaf: 3
        default: gatheringKind?.paletteIndex ?? 11
        }
    }

    var color: Color { Palette.color(paletteIndex) }
    var rune: Rune? { Rune(colorIndex: paletteIndex) }

    var displayName: String {
        switch self {
        case .honeycomb: String(localized: "Honeycomb", comment: "Secret Recipe ingredient")
        case .starleaf: String(localized: "Starleaf", comment: "Secret Recipe ingredient: a star-shaped leaf")
        default: gatheringKind?.displayName ?? name
        }
    }

    /// The Mac keyboard key that picks it (1–8, tray order).
    var key: Character { Character(String(rawValue + 1)) }
}

enum RecipeArt {
    static func draw(_ ingredient: RecipeIngredient, in context: GraphicsContext, square: CGRect) {
        if let kind = ingredient.gatheringKind {
            IngredientArt.drawKind(kind, in: context, square: square)
            return
        }
        let s = square.width
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: square.minX + x * s, y: square.minY + y * s) }
        let outline = StrokeStyle(lineWidth: max(1, s * 0.035), lineCap: .round, lineJoin: .round)
        let ink = Color.black.opacity(0.45)
        switch ingredient {
        case .honeycomb:
            // Four wax cells in a cluster, filled with amber honey; one drip hangs from the bottom.
            let r = s * 0.19
            let h = r * sqrt(3) / 2
            let centers = [p(0.5, 0.3), p(0.5 - 1.5 * r / s, 0.3 + h / s), p(0.5 + 1.5 * r / s, 0.3 + h / s), p(0.5, 0.3 + 2 * h / s)]
            let drip = Path { path in
                path.move(to: CGPoint(x: centers[3].x - r * 0.3, y: centers[3].y + h * 0.9))
                path.addCurve(to: CGPoint(x: centers[3].x, y: centers[3].y + h * 2.2),
                              control1: CGPoint(x: centers[3].x - r * 0.35, y: centers[3].y + h * 1.6),
                              control2: CGPoint(x: centers[3].x - r * 0.3, y: centers[3].y + h * 2.2))
                path.addCurve(to: CGPoint(x: centers[3].x + r * 0.3, y: centers[3].y + h * 0.9),
                              control1: CGPoint(x: centers[3].x + r * 0.3, y: centers[3].y + h * 2.2),
                              control2: CGPoint(x: centers[3].x + r * 0.35, y: centers[3].y + h * 1.6))
                path.closeSubpath()
            }
            context.fill(drip, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.78, blue: 0.3), Color(red: 0.78, green: 0.45, blue: 0.08)]),
                                                     startPoint: p(0.5, 0.7), endPoint: p(0.5, 0.98)))
            context.stroke(drip, with: .color(ink), style: outline)
            for (k, c) in centers.enumerated() {
                let hex = Path { path in
                    path.addLines((0..<6).map { i in
                        let a = Double(i) * .pi / 3
                        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    })
                    path.closeSubpath()
                }
                context.fill(hex, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.86, blue: 0.45), Color(red: 0.86, green: 0.55, blue: 0.12),
                                                                          Color(red: 0.5, green: 0.28, blue: 0.08)]),
                                                        startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: CGPoint(x: c.x + r, y: c.y + r)))
                context.stroke(hex, with: .color(Color(red: 0.36, green: 0.2, blue: 0.06).opacity(0.9)), style: outline)
                // A glint of honey in each cell; the top cell is capped with pale wax.
                let inner = CGRect(x: c.x - r * 0.45, y: c.y - r * 0.45, width: r * 0.9, height: r * 0.9)
                if k == 0 {
                    context.fill(Path(ellipseIn: inner), with: .color(Color(red: 1, green: 0.95, blue: 0.75).opacity(0.85)))
                } else {
                    context.fill(Path(ellipseIn: inner.offsetBy(dx: -r * 0.12, dy: -r * 0.18).insetBy(dx: r * 0.2, dy: r * 0.25)),
                                 with: .color(.white.opacity(0.5)))
                }
            }
        case .starleaf:
            // A five-pointed leaf with a stem and veins to each point.
            let c = p(0.5, 0.48)
            let outer = s * 0.44, inner = s * 0.2
            let leaf = Path { path in
                for i in 0..<10 {
                    let a = Double(i) * .pi / 5 - .pi / 2
                    let radius = i % 2 == 0 ? outer : inner
                    let pt = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
                    if i == 0 {
                        path.move(to: pt)
                    } else {
                        // Points stay sharp, the notches between them curve in like leaf lobes.
                        let mid = Double(i) - 0.5
                        let ma = mid * .pi / 5 - .pi / 2
                        let mr = (outer + inner) * 0.62
                        path.addQuadCurve(to: pt, control: CGPoint(x: c.x + mr * cos(ma), y: c.y + mr * sin(ma)))
                    }
                }
                let ma = 9.5 * .pi / 5 - .pi / 2
                let mr = (outer + inner) * 0.62
                path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - outer), control: CGPoint(x: c.x + mr * cos(ma), y: c.y + mr * sin(ma)))
                path.closeSubpath()
            }
            let stem = Path { path in
                path.move(to: c)
                path.addQuadCurve(to: p(0.62, 0.97), control: p(0.5, 0.8))
            }
            context.stroke(stem, with: .color(Color(red: 0.25, green: 0.45, blue: 0.15)),
                           style: StrokeStyle(lineWidth: max(1.2, s * 0.06), lineCap: .round))
            context.fill(leaf, with: .linearGradient(Gradient(colors: [Color(red: 0.7, green: 0.95, blue: 0.55), ingredient.color,
                                                                       Color(red: 0.05, green: 0.38, blue: 0.15)]),
                                                     startPoint: p(0.2, 0.05), endPoint: p(0.8, 0.95)))
            context.stroke(leaf, with: .color(ink), style: outline)
            for i in 0..<5 {
                let a = Double(i) * 2 * .pi / 5 - .pi / 2
                context.stroke(Path { $0.move(to: c); $0.addLine(to: CGPoint(x: c.x + outer * 0.78 * cos(a), y: c.y + outer * 0.78 * sin(a))) },
                               with: .color(Color(red: 0.88, green: 1, blue: 0.75).opacity(0.75)),
                               style: StrokeStyle(lineWidth: max(0.8, s * 0.025), lineCap: .round))
            }
            // A tiny star-shaped dewdrop at the heart.
            context.fill(IngredientArt.sparkPath(center: c, radius: s * 0.07), with: .color(.white.opacity(0.9)))
        default:
            break
        }
    }
}

/// One tray ingredient as a picture (with its rune badge when color runes are on).
struct RecipeIngredientIcon: View {
    let ingredient: RecipeIngredient
    var size: CGFloat = 32
    var runes = false

    var body: some View {
        Canvas { context, canvas in
            let square = CGRect(origin: .zero, size: canvas).insetBy(dx: canvas.width * 0.04, dy: canvas.width * 0.04)
            RecipeArt.draw(ingredient, in: context, square: square)
            if runes, let rune = ingredient.rune {
                let r = canvas.width * 0.38
                let badge = CGRect(x: canvas.width - r, y: canvas.height - r, width: r, height: r)
                context.fill(Path(ellipseIn: badge), with: .color(.black.opacity(0.6)))
                rune.draw(in: context, rect: badge.insetBy(dx: r * 0.2, dy: r * 0.2))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The feedback markers: gold drops (in the right slot) and silver drops (in the recipe, another
/// slot). They differ in shape as well as color: a gold drop carries a spark, a silver one is ringed.
enum RecipeDrop {
    case gold, silver, none

    static let goldLight = Color(red: 1.0, green: 0.92, blue: 0.55)
    static let goldDark = Color(red: 0.82, green: 0.55, blue: 0.08)
    static let silverLight = Color(white: 0.97)
    static let silverDark = Color(white: 0.55)

    static func drops(for feedback: RecipeFeedback) -> [RecipeDrop] {
        Array(repeating: .gold, count: feedback.exact) + Array(repeating: .silver, count: feedback.misplaced)
            + Array(repeating: .none, count: max(0, RecipeCode.length - feedback.common))
    }

    static func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let sq = CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s)
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: sq.minX + x * s, y: sq.minY + y * s) }
        return Path { path in
            path.move(to: p(0.5, 0.02))
            path.addCurve(to: p(0.88, 0.62), control1: p(0.62, 0.24), control2: p(0.88, 0.4))
            path.addCurve(to: p(0.5, 0.98), control1: p(0.88, 0.84), control2: p(0.7, 0.98))
            path.addCurve(to: p(0.12, 0.62), control1: p(0.3, 0.98), control2: p(0.12, 0.84))
            path.addCurve(to: p(0.5, 0.02), control1: p(0.12, 0.4), control2: p(0.38, 0.24))
            path.closeSubpath()
        }
    }

    func draw(in context: GraphicsContext, rect: CGRect) {
        let shape = RecipeDrop.path(in: rect)
        let s = min(rect.width, rect.height)
        let line = max(0.8, s * 0.08)
        switch self {
        case .gold:
            context.fill(shape, with: .linearGradient(Gradient(colors: [RecipeDrop.goldLight, RecipeDrop.goldDark]),
                                                      startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            context.stroke(shape, with: .color(Color(red: 0.45, green: 0.28, blue: 0.02)), lineWidth: line)
            context.fill(IngredientArt.sparkPath(center: CGPoint(x: rect.midX, y: rect.midY + s * 0.14), radius: s * 0.2),
                         with: .color(.white.opacity(0.95)))
        case .silver:
            context.fill(shape, with: .linearGradient(Gradient(colors: [RecipeDrop.silverLight, RecipeDrop.silverDark]),
                                                      startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            context.stroke(shape, with: .color(Color(white: 0.25)), lineWidth: line)
            let r = s * 0.15
            context.stroke(Path(ellipseIn: CGRect(x: rect.midX - r, y: rect.midY + s * 0.14 - r, width: 2 * r, height: 2 * r)),
                           with: .color(Color(white: 0.3)), lineWidth: max(0.8, s * 0.07))
        case .none:
            context.stroke(shape, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: line * 0.8, dash: [s * 0.12, s * 0.1]))
        }
    }
}

/// A guess's five drops in a row, gold first (they never say which slot).
struct RecipeDropsView: View {
    let feedback: RecipeFeedback
    var size: CGFloat = 14
    /// How many drops are shown so far (they appear one by one after a brew).
    var revealed = RecipeCode.length

    var body: some View {
        Canvas { context, canvas in
            let drops = RecipeDrop.drops(for: feedback)
            let step = canvas.width / CGFloat(drops.count)
            for (i, drop) in drops.enumerated() where i < revealed {
                drop.draw(in: context, rect: CGRect(x: CGFloat(i) * step + step * 0.08, y: (canvas.height - step * 0.84) / 2,
                                                    width: step * 0.84, height: step * 0.84))
            }
        }
        .frame(width: size * CGFloat(RecipeCode.length) * 1.1, height: size)
        .accessibilityElement()
        .accessibilityLabel(RecipeText.feedback(feedback))
    }
}
