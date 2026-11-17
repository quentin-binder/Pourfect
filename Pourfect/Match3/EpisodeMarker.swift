import BottleSortCore
import Match3Core
import SwiftUI

/// Where the gathering episodes sit on `chapter_map`: on the path between chapter N and N + 1
/// (fractions of the image size, like `ChapterArt.mapSpots`); episode 10 by the hoard at the top.
enum EpisodeArt {
    static let mapSpots: [CGPoint] = [
        CGPoint(x: 0.72, y: 0.872),   //  1 between cellar and vault
        CGPoint(x: 0.50, y: 0.812),   //  2
        CGPoint(x: 0.50, y: 0.731),   //  3
        CGPoint(x: 0.53, y: 0.655),   //  4
        CGPoint(x: 0.49, y: 0.575),   //  5
        CGPoint(x: 0.52, y: 0.487),   //  6
        CGPoint(x: 0.53, y: 0.394),   //  7
        CGPoint(x: 0.52, y: 0.270),   //  8
        CGPoint(x: 0.56, y: 0.112),   //  9
        CGPoint(x: 0.80, y: 0.058),   // 10 the dragon's larder, up in the tower
    ]

    /// The ingredient an episode is named after (its basket shows it on top).
    static func featured(_ file: M3EpisodeFile) -> M3Kind {
        for level in file.levels {
            if let kind = level.goals.first(where: { $0.type == .collect })?.kind { return kind }
        }
        return file.levels.first?.kinds.first ?? .mushroom
    }
}

/// A woven ingredient basket with a few ingredients peeking out, drawn in Canvas.
struct IngredientBasket: View {
    let kinds: [M3Kind]
    var size: CGFloat = 40
    var dimmed = false

    var body: some View {
        Canvas { context, canvas in
            let w = canvas.width, h = canvas.height
            // Ingredients first, so the basket's rim covers their lower half.
            let shown = Array(kinds.prefix(3))
            let slots: [(CGFloat, CGFloat, CGFloat)] = shown.count == 1 ? [(0.5, 0.36, 0.5)]
                : [(0.3, 0.42, 0.4), (0.68, 0.40, 0.4), (0.5, 0.3, 0.46)]
            for (i, kind) in shown.enumerated().reversed() where i < slots.count {
                let (x, y, s) = slots[i]
                let rect = CGRect(x: (x - s / 2) * w, y: (y - s / 2) * h, width: s * w, height: s * h)
                IngredientArt.drawKind(kind, in: context, square: rect)
            }
            // Handle.
            var handle = Path()
            handle.addArc(center: CGPoint(x: w * 0.5, y: h * 0.52), radius: w * 0.36,
                          startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
            context.stroke(handle, with: .color(M3Colors.woodDark), style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
            context.stroke(handle, with: .color(M3Colors.woodLight), style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round))
            // Body: a tapered tub.
            var body = Path()
            body.move(to: CGPoint(x: w * 0.1, y: h * 0.52))
            body.addLine(to: CGPoint(x: w * 0.9, y: h * 0.52))
            body.addLine(to: CGPoint(x: w * 0.78, y: h * 0.92))
            body.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.92), control: CGPoint(x: w * 0.5, y: h * 0.98))
            body.closeSubpath()
            context.fill(body, with: .linearGradient(Gradient(colors: [M3Colors.woodLight, M3Colors.woodDark]),
                                                     startPoint: CGPoint(x: 0, y: h * 0.5), endPoint: CGPoint(x: 0, y: h)))
            // Weave: rows of short strokes, alternating.
            context.drawLayer { layer in
                layer.clip(to: body)
                for row in 0..<4 {
                    let y = h * (0.6 + CGFloat(row) * 0.09)
                    for col in 0..<7 {
                        let x = w * (0.1 + CGFloat(col) * 0.13 + (row.isMultiple(of: 2) ? 0 : 0.065))
                        layer.stroke(Path { $0.move(to: CGPoint(x: x, y: y - h * 0.03)); $0.addLine(to: CGPoint(x: x + w * 0.06, y: y + h * 0.03)) },
                                     with: .color(.black.opacity(0.28)), lineWidth: max(0.6, w * 0.02))
                    }
                }
            }
            context.stroke(body, with: .color(M3Colors.woodDark), lineWidth: max(0.8, w * 0.03))
            // Rim.
            let rim = Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.47, width: w * 0.88, height: h * 0.1), cornerRadius: h * 0.05)
            context.fill(rim, with: .color(Color(red: 0.74, green: 0.53, blue: 0.3)))
            context.stroke(rim, with: .color(M3Colors.woodDark), lineWidth: max(0.8, w * 0.03))
        }
        .frame(width: size, height: size)
        .saturation(dimmed ? 0.1 : 1)
        .brightness(dimmed ? -0.25 : 0)
        .accessibilityHidden(true)
    }
}

/// An episode's small button on the chapter map: a basket on a round wooden token, with its stars
/// or a lock below. Locked episodes do nothing; they never block the chapter path.
struct EpisodeMarker: View {
    let entry: MapEpisode
    let scale: CGFloat
    let action: () -> Void

    private var size: CGFloat { 40 * scale }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                token
                plate
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(entry.isOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .help(Text("Ingredient gathering: \(entry.name)", comment: "Tooltip of an episode marker on the map"))
    }

    private var ring: Color {
        guard entry.isOpen else { return .gray }
        if entry.stars >= entry.maxStars, entry.maxStars > 0 { return .yellow }
        return entry.isComplete ? Color(red: 0.55, green: 0.85, blue: 0.45) : Color(red: 0.95, green: 0.8, blue: 0.55)
    }

    private var token: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.16), Color(red: 0.17, green: 0.12, blue: 0.08)],
                                         center: .center, startRadius: 1, endRadius: size * 0.6))
            Circle().strokeBorder(ring, lineWidth: 2 * scale)
            IngredientBasket(kinds: [EpisodeArt.featured(entry.file)], size: size * 0.82, dimmed: !entry.isOpen)
                .offset(y: -size * 0.03)
            if !entry.isOpen {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            } else if entry.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(.white, .green)
                    .offset(x: size * 0.38, y: -size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
    }

    private var plate: some View {
        Group {
            if entry.isOpen {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text("\(entry.stars) / \(entry.maxStars)").monospacedDigit()
                }
            } else {
                Text("Gathering \(entry.number)", comment: "Map plate of a locked ingredient-gathering episode")
            }
        }
        .font(.system(size: 9.5 * scale, weight: .semibold))
        .foregroundStyle(.white.opacity(entry.isOpen ? 0.95 : 0.7))
        .padding(.horizontal, 6 * scale).padding(.vertical, 2 * scale)
        .background(Capsule().fill(Color(red: 0.2, green: 0.13, blue: 0.07).opacity(0.85)))
        .overlay(Capsule().strokeBorder(ring.opacity(0.5)))
        .fixedSize()
    }

    private var accessibilityText: Text {
        switch entry.state {
        case .open:
            return Text("Ingredient gathering \(entry.number), \(entry.name), \(entry.stars) of \(entry.maxStars) stars",
                        comment: "VoiceOver: an open gathering episode on the map")
        case .locked(_, true):
            return Text("Ingredient gathering \(entry.number), \(entry.name), locked. Opens when chapter 10's last recipe is brewed",
                        comment: "VoiceOver: the last gathering episode, locked")
        case .locked(let chapter, false):
            return Text("Ingredient gathering \(entry.number), \(entry.name), locked. Opens with chapter \(chapter)",
                        comment: "VoiceOver: a locked gathering episode on the map")
        }
    }
}
