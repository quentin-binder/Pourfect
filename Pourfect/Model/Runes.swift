import SwiftUI

/// Colorblind runes: one simple vector symbol per palette color (`rawValue` = `ColorID.rawValue`).
/// The only place the rune shapes are defined; the bottles, the pour animation and (later)
/// a legend or tutorial all draw them from here. Each rune is a stroke path in a square.
enum Rune: Int, CaseIterable {
    case triangle   //  0 red (fire)
    case wave       //  1 blue (water)
    case star       //  2 yellow (sun)
    case chevron    //  3 green (sprout)
    case crescent   //  4 purple (moon)
    case bolt       //  5 orange (spark)
    case diamond    //  6 cyan (crystal)
    case heart      //  7 pink
    case square     //  8 brown (earth)
    case cross      //  9 lime
    case hexagon    // 10 navy
    case ring       // 11 grey (ring with a dot)

    /// The rune for a palette color index, if there is one.
    init?(colorIndex: Int) { self.init(rawValue: colorIndex) }

    var name: String {
        switch self {
        case .triangle: String(localized: "Triangle", comment: "Name of a colorblind rune")
        case .wave: String(localized: "Wave", comment: "Name of a colorblind rune")
        case .star: String(localized: "Star", comment: "Name of a colorblind rune")
        case .chevron: String(localized: "Chevron", comment: "Name of a colorblind rune")
        case .crescent: String(localized: "Crescent", comment: "Name of a colorblind rune")
        case .bolt: String(localized: "Bolt", comment: "Name of a colorblind rune")
        case .diamond: String(localized: "Diamond", comment: "Name of a colorblind rune")
        case .heart: String(localized: "Heart", comment: "Name of a colorblind rune")
        case .square: String(localized: "Square", comment: "Name of a colorblind rune")
        case .cross: String(localized: "Cross", comment: "Name of a colorblind rune")
        case .hexagon: String(localized: "Hexagon", comment: "Name of a colorblind rune")
        case .ring: String(localized: "Ring", comment: "Name of a colorblind rune")
        }
    }

    /// Stroke path of the rune, fitted in `rect` (drawn centered in its largest square).
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        // Points in a unit square (0…1, y down).
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: origin.x + x * s, y: origin.y + y * s) }
        let polygon = { (points: [CGPoint]) in Path { $0.addLines(points); $0.closeSubpath() } }
        let regular = { (count: Int, radius: CGFloat, rotation: Double) -> [CGPoint] in
            (0..<count).map { i in
                let a = rotation + Double(i) * 2 * .pi / Double(count)
                return p(0.5 + radius * CGFloat(cos(a)), 0.5 + radius * CGFloat(sin(a)))
            }
        }

        switch self {
        case .triangle:
            return polygon([p(0.5, 0.1), p(0.92, 0.84), p(0.08, 0.84)])
        case .wave:
            return Path { path in
                path.move(to: p(0.06, 0.5))
                path.addCurve(to: p(0.5, 0.5), control1: p(0.2, 0.18), control2: p(0.36, 0.18))
                path.addCurve(to: p(0.94, 0.5), control1: p(0.64, 0.82), control2: p(0.8, 0.82))
            }
        case .star:
            let outer = regular(5, 0.46, -.pi / 2)
            let inner = regular(5, 0.19, -.pi / 2 + .pi / 5)
            return polygon(zip(outer, inner).flatMap { [$0, $1] }.map { CGPoint(x: $0.x, y: $0.y + s * 0.04) })
        case .chevron:
            return Path { path in
                path.addLines([p(0.1, 0.72), p(0.5, 0.28), p(0.9, 0.72)])
            }
        case .crescent:
            return Path { path in
                // Outer arc of a circle, closed by a smaller offset arc.
                path.addArc(center: p(0.5, 0.5), radius: s * 0.4, startAngle: .degrees(-60),
                            endAngle: .degrees(60), clockwise: true)
                path.addArc(center: p(0.66, 0.5), radius: s * 0.4 * 0.8, startAngle: .degrees(77),
                            endAngle: .degrees(-77), clockwise: false)
                path.closeSubpath()
            }
        case .bolt:
            return Path { path in
                path.addLines([p(0.62, 0.06), p(0.3, 0.52), p(0.6, 0.48), p(0.38, 0.94)])
            }
        case .diamond:
            return polygon([p(0.5, 0.06), p(0.86, 0.5), p(0.5, 0.94), p(0.14, 0.5)])
        case .heart:
            return Path { path in
                path.move(to: p(0.5, 0.88))
                path.addCurve(to: p(0.5, 0.3), control1: p(0.08, 0.6), control2: p(0.1, 0.06))
                path.addCurve(to: p(0.5, 0.88), control1: p(0.9, 0.06), control2: p(0.92, 0.6))
                path.closeSubpath()
            }
        case .square:
            return polygon([p(0.16, 0.16), p(0.84, 0.16), p(0.84, 0.84), p(0.16, 0.84)])
        case .cross:
            return Path { path in
                path.move(to: p(0.5, 0.1)); path.addLine(to: p(0.5, 0.9))
                path.move(to: p(0.1, 0.5)); path.addLine(to: p(0.9, 0.5))
            }
        case .hexagon:
            return polygon(regular(6, 0.42, 0))
        case .ring:
            return Path { path in
                path.addEllipse(in: CGRect(x: origin.x + s * 0.1, y: origin.y + s * 0.1, width: s * 0.8, height: s * 0.8))
                path.addEllipse(in: CGRect(x: origin.x + s * 0.47, y: origin.y + s * 0.47, width: s * 0.06, height: s * 0.06))
            }
        }
    }

    /// Draws the rune white-ish over a subtle dark outline, so it reads on light and dark liquids.
    func draw(in context: GraphicsContext, rect: CGRect) {
        let s = min(rect.width, rect.height)
        let path = path(in: rect)
        let line = max(1.2, s * 0.11)
        context.stroke(path, with: .color(.black.opacity(0.45)),
                       style: StrokeStyle(lineWidth: line + max(1.2, s * 0.08), lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(.white.opacity(0.93)),
                       style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
    }
}

/// A rune as a view (for bottles, a legend or a tutorial), centered in its frame. The rune's
/// square is `scale` × the frame's shorter side; the rest leaves room for the outline.
struct RuneView: View {
    let rune: Rune
    var scale: CGFloat = 0.7

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) * scale
            rune.draw(in: context, rect: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                                                width: side, height: side))
        }
        .accessibilityHidden(true)
    }
}
