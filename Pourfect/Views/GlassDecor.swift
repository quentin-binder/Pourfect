import BottleSortCore
import SwiftUI

// Glass Works (chapter 5): the one visual signal of each flask modifier, drawn the same at rest
// (`BottleView`), in flight (`PourAnimationView`) and in the tips. All sizes follow the flask
// width `w`; positions are in the flask's own frame (0, 0 = top-left of the body; the neck and
// the funnel stand above it, the spigot sticks out on the right).
//
// - Narrow neck (C2): the body narrows into a glass neck above the mouth, with a brass collar
//   ring around it (`NeckedFlaskShape`, `NeckCollar`).
// - Funnel (C4): a brass funnel sitting in the mouth (`FunnelMark`).
// - Tap (C4): a brass spigot near the bottom on the right, with a turning valve handle; a tap
//   pour streams from its nozzle (`SpigotMark`, `Spigot.nozzle`).

/// Brass colors shared by the collar, the funnel and the spigot.
enum Brass {
    static let light = Color(red: 0.98, green: 0.84, blue: 0.50)
    static let mid = Color(red: 0.80, green: 0.60, blue: 0.27)
    static let dark = Color(red: 0.47, green: 0.31, blue: 0.11)

    /// Left-lit metal across `rect`; `flare` 0…1 brightens it (a refusal).
    static func shading(_ rect: CGRect, flare: Double = 0) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: [.init(color: light, location: 0),
                                         .init(color: flare > 0 ? .white : light, location: 0.18 - 0.1 * flare),
                                         .init(color: mid, location: 0.55),
                                         .init(color: dark, location: 1)]),
                        startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY))
    }
}

// MARK: Narrow neck

enum NarrowNeck {
    /// Outer width of the neck, and how far it stands above the body's top edge.
    static func width(_ w: CGFloat) -> CGFloat { w * 0.4 }
    static func height(_ w: CGFloat) -> CGFloat { w * 0.55 }

    /// The cork of a completed narrow-neck flask: a smaller cork seated in the neck.
    static func corkWidth(_ w: CGFloat) -> CGFloat { width(w) * 1.3 }
    static func corkOffsetY(_ w: CGFloat) -> CGFloat { Cork.offsetY(width: corkWidth(w)) - height(w) }

    /// The neck's pouring lip on one side, relative to the body's top corner on that side
    /// (where the plain flask's lip is): inward and up.
    static func lipOffset(_ w: CGFloat, right: Bool) -> CGPoint {
        let inset = (w - width(w)) / 2
        return CGPoint(x: right ? -inset : inset, y: -height(w))
    }
}

/// A narrow-neck flask's silhouette: the body (`BottleView.shape`) with shoulders rising into a
/// neck above the frame's top edge. Used for the glass fills and the outline only; the liquid
/// is still clipped to the body (it never reaches the shoulders: a full flask leaves 0.45 w).
struct NeckedFlaskShape: Shape {
    /// The body's style (R7): the shoulders rise from its mouth.
    var style: FlaskShapeStyle = .classic

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let nw = NarrowNeck.width(w), nh = NarrowNeck.height(w)
        let x0 = rect.minX + (w - nw) / 2, x1 = x0 + nw
        let left = rect.minX + style.lipInset(w), right = rect.maxX - style.lipInset(w)
        let top = rect.minY - nh, shoulder = rect.minY - nh * 0.3, side = rect.minY + w * 0.18
        let neck = Path { p in
            p.move(to: CGPoint(x: x0, y: top))
            p.addLine(to: CGPoint(x: x0, y: shoulder))
            p.addQuadCurve(to: CGPoint(x: left, y: side), control: CGPoint(x: left, y: shoulder))
            p.addLine(to: CGPoint(x: left, y: rect.minY + w * 0.3))
            p.addLine(to: CGPoint(x: right, y: rect.minY + w * 0.3))
            p.addLine(to: CGPoint(x: right, y: side))
            p.addQuadCurve(to: CGPoint(x: x1, y: shoulder), control: CGPoint(x: right, y: shoulder))
            p.addLine(to: CGPoint(x: x1, y: top))
            p.closeSubpath()
        }
        return BottleView.shape(width: w, style: style).path(in: rect).union(neck)
    }
}

/// The neck's brass collar ring and its glass lip. Place with `.overlay(alignment: .top)` on
/// the flask's frame (it draws above the frame); `color` follows the outline like `FlaskRim`.
struct NeckCollar: View {
    let width: CGFloat
    let color: Color

    var body: some View {
        let nw = NarrowNeck.width(width), nh = NarrowNeck.height(width)
        let collar = CGSize(width: nw * 1.3, height: max(3, width * 0.11))
        ZStack(alignment: .top) {
            FlaskRim(width: nw, color: color)
                .offset(y: -nh)
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let ring = Path(roundedRect: rect, cornerRadius: size.height / 2)
                context.fill(ring, with: Brass.shading(rect))
                context.stroke(ring, with: .color(Brass.dark), lineWidth: max(0.75, width * 0.015))
                context.fill(Path(CGRect(x: 0, y: size.height * 0.2, width: size.width, height: size.height * 0.18)),
                             with: .color(.white.opacity(0.35)))
            }
            .frame(width: collar.width, height: collar.height)
            .offset(y: -nh * 0.55 - collar.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Funnel

/// The brass funnel sitting in a funnel flask's mouth: a wide cone above the flask with its
/// spout reaching into the neck. Place with `.overlay(alignment: .top)` on the flask's frame.
/// `flare` 0…1 is the refusal glint (it brightens; with `swells` it also lifts a little).
struct FunnelMark: View {
    let width: CGFloat
    var flare: Double = 0
    var swells = true

    static func size(_ w: CGFloat) -> CGSize { CGSize(width: w * 0.94, height: w * 0.62) }
    /// How far the funnel's top stands above the body's top edge.
    static func rise(_ w: CGFloat) -> CGFloat { size(w).height - w * 0.2 }

    var body: some View {
        let size = Self.size(width)
        Canvas { context, canvas in
            let w = canvas.width, h = canvas.height
            let rimH = h * 0.2, spoutW = width * 0.2, coneBottom = h * 0.62
            let rect = CGRect(origin: .zero, size: canvas)
            let line = max(0.75, width * 0.018)
            // Spout, then the cone over it.
            let spout = Path { p in
                p.move(to: CGPoint(x: (w - spoutW) / 2, y: coneBottom - 1))
                p.addLine(to: CGPoint(x: (w + spoutW) / 2, y: coneBottom - 1))
                p.addLine(to: CGPoint(x: (w + spoutW * 0.7) / 2, y: h))
                p.addLine(to: CGPoint(x: (w - spoutW * 0.7) / 2, y: h))
                p.closeSubpath()
            }
            context.fill(spout, with: Brass.shading(rect, flare: flare))
            context.stroke(spout, with: .color(Brass.dark), lineWidth: line)
            let cone = Path { p in
                p.move(to: CGPoint(x: 0, y: rimH / 2))
                p.addLine(to: CGPoint(x: w, y: rimH / 2))
                p.addQuadCurve(to: CGPoint(x: (w + spoutW) / 2, y: coneBottom),
                               control: CGPoint(x: w * 0.72, y: coneBottom * 0.8))
                p.addLine(to: CGPoint(x: (w - spoutW) / 2, y: coneBottom))
                p.addQuadCurve(to: CGPoint(x: 0, y: rimH / 2), control: CGPoint(x: w * 0.28, y: coneBottom * 0.8))
                p.closeSubpath()
            }
            context.fill(cone, with: Brass.shading(rect, flare: flare))
            context.stroke(cone, with: .color(Brass.dark), lineWidth: line)
            // The opening: a dark inside with a bright rolled rim.
            let opening = Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: rimH))
            context.fill(opening, with: .linearGradient(Gradient(colors: [Brass.dark, .black.opacity(0.85)]),
                                                        startPoint: .zero, endPoint: CGPoint(x: 0, y: rimH)))
            context.stroke(opening, with: .color(Brass.light), lineWidth: max(1, width * 0.04))
            context.stroke(Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: rimH).insetBy(dx: -line, dy: -line / 2)),
                           with: .color(Brass.dark), lineWidth: line)
            // A highlight down the cone's left side.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: w * 0.16, y: rimH * 0.9))
                p.addQuadCurve(to: CGPoint(x: (w - spoutW) / 2 + width * 0.03, y: coneBottom * 0.95),
                               control: CGPoint(x: w * 0.3, y: coneBottom * 0.75))
            }, with: .color(.white.opacity(0.35 + 0.4 * flare)), lineWidth: max(1, width * 0.03))
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: Brass.light.opacity(0.8 * flare), radius: width * 0.12 * flare)
        .offset(y: -Self.rise(width) - (swells ? width * 0.08 * flare : 0))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Tap

enum Spigot {
    /// Height of the spigot's pipe center above the flask's bottom edge (on the bottom layer).
    static func pipeRise(_ w: CGFloat) -> CGFloat { w * 0.36 }
    /// The spigot is drawn at this scale around its flange (`anchor`), so it reads at a glance.
    static let scale: CGFloat = 1.35
    static func anchor(width w: CGFloat, height h: CGFloat) -> CGPoint { CGPoint(x: w * 0.95, y: h - pipeRise(w)) }
    /// How far the spigot sticks out past the flask's right edge.
    static func protrusion(_ w: CGFloat) -> CGFloat { w * (0.95 + 0.21 * scale - 1) }

    /// Where a tap pour leaves the nozzle, in the flask's frame (flask `w` × `h`).
    static func nozzle(width w: CGFloat, height h: CGFloat) -> CGPoint {
        let a = anchor(width: w, height: h)
        return CGPoint(x: a.x + w * 0.15 * scale, y: a.y + w * 0.19 * scale)
    }
}

/// A tap flask's brass spigot: a flange on the glass near the bottom, a short pipe out to the
/// right, a nozzle turned down, and a T-handle on top. `valve` 0…1 turns the handle a quarter
/// turn (closed → open) while the tap pours; `flare` 0…1 is the refusal glint. Place with
/// `.overlay(alignment: .topLeading)` on the flask's frame: it draws in flask coordinates and
/// sticks out `Spigot.protrusion` on the right.
struct SpigotMark: View {
    let width: CGFloat
    let height: CGFloat
    var valve: Double = 0
    var flare: Double = 0

    var body: some View {
        let w = width
        Canvas { context, _ in
            // Drawn at unit scale around the flange, then scaled up (`Spigot.scale`).
            let a = Spigot.anchor(width: w, height: height)
            context.translateBy(x: a.x, y: a.y)
            context.scaleBy(x: Spigot.scale, y: Spigot.scale)
            context.translateBy(x: -a.x, y: -a.y)
            let py = a.y
            let line = max(0.75, w * 0.018)
            let all = CGRect(x: w * 0.9, y: py - w * 0.3, width: w * 0.32, height: w * 0.52)
            let shade = Brass.shading(all, flare: flare)
            // Pipe and down-turned nozzle (one shape, so the elbow is seamless).
            let pipe = Path { p in
                p.move(to: CGPoint(x: w * 0.96, y: py - w * 0.06))
                p.addLine(to: CGPoint(x: w * 1.08, y: py - w * 0.06))
                p.addQuadCurve(to: CGPoint(x: w * 1.16, y: py + w * 0.02), control: CGPoint(x: w * 1.16, y: py - w * 0.06))
                p.addLine(to: CGPoint(x: w * 1.15, y: py + w * 0.17))
                p.addLine(to: CGPoint(x: w * 1.05, y: py + w * 0.17))
                p.addLine(to: CGPoint(x: w * 1.05, y: py + w * 0.06))
                p.addLine(to: CGPoint(x: w * 0.96, y: py + w * 0.06))
                p.closeSubpath()
            }
            context.fill(pipe, with: shade)
            context.stroke(pipe, with: .color(Brass.dark), lineWidth: line)
            // Nozzle lip.
            let lip = Path(roundedRect: CGRect(x: w * 1.035, y: py + w * 0.15, width: w * 0.13, height: w * 0.05),
                           cornerRadius: w * 0.02)
            context.fill(lip, with: shade)
            context.stroke(lip, with: .color(Brass.dark), lineWidth: line)
            // Flange on the glass.
            let flange = Path(roundedRect: CGRect(x: w * 0.9, y: py - w * 0.12, width: w * 0.1, height: w * 0.24),
                              cornerRadius: w * 0.04)
            context.fill(flange, with: shade)
            context.stroke(flange, with: .color(Brass.dark), lineWidth: line)
            // Valve stem and T-handle; turning it narrows the bar (seen end-on when open).
            let stem = Path(CGRect(x: w * 1.04, y: py - w * 0.15, width: w * 0.05, height: w * 0.1))
            context.fill(stem, with: .color(Brass.mid))
            context.stroke(stem, with: .color(Brass.dark), lineWidth: line * 0.8)
            let bar = max(w * 0.05, w * 0.22 * abs(cos(valve * .pi / 2)))
            let handle = Path(roundedRect: CGRect(x: w * 1.065 - bar / 2, y: py - w * 0.2, width: bar, height: w * 0.07),
                              cornerRadius: w * 0.035)
            context.fill(handle, with: Brass.shading(handle.boundingRect, flare: flare))
            context.stroke(handle, with: .color(Brass.dark), lineWidth: line)
            // Bright pin in the handle's center.
            context.fill(Path(ellipseIn: CGRect(x: w * 1.045, y: py - w * 0.185, width: w * 0.04, height: w * 0.04)),
                         with: .color(.white.opacity(0.6)))
        }
        .frame(width: w + Spigot.protrusion(w) + 2, height: height)
        .shadow(color: Brass.light.opacity(0.8 * flare), radius: w * 0.1 * flare)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: One place for every flask

/// What a flask carries from the glass works, read from its modifiers (display only).
struct GlassParts {
    let neck: Bool
    let funnel: Bool
    let tap: Bool

    init(_ bottle: Bottle) {
        neck = bottle.hasNarrowNeck
        funnel = bottle.isFunnel
        tap = bottle.hasTap
    }

    /// How far the flask's parts stand above its body (neck or funnel), for the board's
    /// headroom and for where a stream has to start above it.
    func rise(_ w: CGFloat) -> CGFloat {
        if funnel { return FunnelMark.rise(w) }
        if neck { return NarrowNeck.height(w) + FlaskRim.size(width: NarrowNeck.width(w)).height * 0.5 }
        return 0
    }

    /// The same rise in flask widths, for the board's layout before the width is known.
    /// The rim has a minimum height in points, so this is measured at a small flask (40 pt),
    /// where that minimum weighs the most; never call `rise(1)` for this.
    var riseInWidths: CGFloat { rise(Self.layoutWidth) / Self.layoutWidth }
    static let layoutWidth: CGFloat = 40
}

/// The flask's glass fill (body, plus shoulders and neck for a narrow neck).
struct FlaskGlass<S: ShapeStyle>: View {
    let style: S
    let width: CGFloat
    let necked: Bool
    @Environment(\.flaskStyle) private var flaskStyle

    var body: some View {
        if necked {
            NeckedFlaskShape(style: flaskStyle).fill(style)
        } else {
            BottleView.shape(width: width, style: flaskStyle).fill(style)
        }
    }
}

/// The flask's outline (the necked silhouette for a narrow neck, drawn centered on the edge;
/// a plain flask's border sits just inside it, as before).
struct FlaskOutline<S: ShapeStyle>: View {
    let style: S
    let width: CGFloat
    let necked: Bool
    let lineWidth: CGFloat
    @Environment(\.flaskStyle) private var flaskStyle

    var body: some View {
        if necked {
            NeckedFlaskShape(style: flaskStyle).stroke(style, lineWidth: lineWidth)
        } else {
            BottleView.shape(width: width, style: flaskStyle).strokeBorder(style, lineWidth: lineWidth)
        }
    }
}

extension Cork {
    /// The cork of `bottle` at rest: `Cork` width parameter and offset from the body's top.
    static func placement(for bottle: Bottle, width w: CGFloat,
                          style: FlaskShapeStyle = .classic) -> (width: CGFloat, offsetY: CGFloat) {
        if bottle.hasNarrowNeck { return (NarrowNeck.corkWidth(w), NarrowNeck.corkOffsetY(w)) }
        let cork = style.corkWidth(w)
        return (cork, offsetY(width: cork))
    }
}
