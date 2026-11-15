import BottleSortCore
import SwiftUI

// Shared look of a flask, used identically by `BottleView` (at rest) and `PourAnimationView`
// (in flight), so nothing jumps when one hands over to the other. All sizes follow the width.

/// Soft vertical sheen on the left of the glass (and a faint one on the right), drawn over the
/// liquid. Fills the bottle's frame; clipped to the bottle shape.
struct GlassSheen: View {
    let width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                 .init(color: .white.opacity(0.34), location: 0.45),
                                                 .init(color: .white.opacity(0), location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * 0.2, height: h - width * 0.62)
                    .offset(x: width * 0.12, y: width * 0.14)
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(width: width * 0.05, height: h * 0.45)
                    .offset(x: width * 0.83, y: width * 0.2)
            }
            .blur(radius: width * 0.02)
        }
        .clipShape(BottleView.shape(width: width))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A gentle glow behind liquid: a blurred, faded copy of it, so every layer glows in its own
    /// color without tinting the liquid itself. Apply to the liquid view (already clipped).
    func potionGlow(width: CGFloat) -> some View {
        background { self.blur(radius: width * 0.11).opacity(0.4).accessibilityHidden(true) }
    }
}

// MARK: Cork

/// Tapered cork with a little shading, sized for a bottle of `width`. Its frame is
/// `Cork.size(width:)`; place it with `Cork.offsetY(width:)` from the bottle's top edge.
struct Cork: View {
    let width: CGFloat

    static func size(width: CGFloat) -> CGSize { CGSize(width: width * 0.62, height: width * 0.44) }
    /// Cork frame's top relative to the bottle's top edge: it sits ~45% inside the mouth.
    static func offsetY(width: CGFloat) -> CGFloat { -width * 0.24 }

    private static let light = Color(red: 0.80, green: 0.61, blue: 0.40)
    private static let mid = Color(red: 0.66, green: 0.46, blue: 0.27)
    private static let dark = Color(red: 0.44, green: 0.29, blue: 0.15)

    var body: some View {
        let size = Self.size(width: width)
        Canvas { context, canvas in
            let w = canvas.width, h = canvas.height
            let top = h * 0.16   // height of the top face ellipse
            let body = Path { p in
                p.move(to: CGPoint(x: 0, y: top / 2))
                p.addLine(to: CGPoint(x: w, y: top / 2))
                p.addLine(to: CGPoint(x: w * 0.88, y: h - w * 0.04))
                p.addQuadCurve(to: CGPoint(x: w * 0.12, y: h - w * 0.04), control: CGPoint(x: w / 2, y: h + w * 0.04))
                p.closeSubpath()
            }
            context.fill(body, with: .linearGradient(
                Gradient(stops: [.init(color: Self.light, location: 0), .init(color: Self.mid, location: 0.55),
                                 .init(color: Self.dark, location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
            // Shadow where the cork enters the glass, and a highlight stripe on the left.
            context.fill(Path(CGRect(x: 0, y: h * 0.62, width: w, height: h * 0.38)).intersection(body),
                         with: .color(.black.opacity(0.16)))
            context.fill(Path(roundedRect: CGRect(x: w * 0.14, y: top * 0.9, width: w * 0.08, height: h * 0.6),
                              cornerRadius: w * 0.04), with: .color(.white.opacity(0.16)))
            // Pores.
            for (x, y, r) in [(0.36, 0.42, 0.035), (0.62, 0.55, 0.03), (0.48, 0.74, 0.028), (0.74, 0.36, 0.025)] {
                context.fill(Path(ellipseIn: CGRect(x: w * x, y: h * y, width: w * r * 2, height: w * r * 1.6)),
                             with: .color(Self.dark.opacity(0.55)))
            }
            let topFace = Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: top))
            context.fill(topFace, with: .color(Self.light))
            context.stroke(topFace, with: .color(Self.dark.opacity(0.5)), lineWidth: max(0.75, w * 0.025))
            context.stroke(body, with: .color(Self.dark.opacity(0.7)), lineWidth: max(0.75, w * 0.03))
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.25), radius: width * 0.03, y: width * 0.02)
        .accessibilityHidden(true)
    }
}

/// Where a dropping cork is, as an offset from its resting place.
struct CorkDrop {
    var y: CGFloat = 0
    var squash: CGFloat = 1
    var opacity: Double = 1
}

extension View {
    /// Drops the cork in with a small bounce each time `trigger` changes (0.4 s). Change `trigger`
    /// without animation (see `BottleView`): an ambient `withAnimation` would also ease the jump to
    /// the first keyframe, and its leftover pushes the cork down into the liquid.
    func corkDrop(width: CGFloat, trigger: Int) -> some View {
        keyframeAnimator(initialValue: CorkDrop(), trigger: trigger) { content, drop in
            content
                .scaleEffect(x: 1, y: drop.squash, anchor: .bottom)
                .offset(y: drop.y)
                .opacity(drop.opacity)
        } keyframes: { _ in
            // Eased linear segments: a cubic spline through the seat would dip slightly below it.
            KeyframeTrack(\.y) {
                MoveKeyframe(-width * 1.1)
                LinearKeyframe(0, duration: 0.14, timingCurve: .easeIn)            // falls into the mouth
                LinearKeyframe(-width * 0.12, duration: 0.1, timingCurve: .easeOut) // small bounce
                LinearKeyframe(0, duration: 0.12, timingCurve: .easeIn)
            }
            KeyframeTrack(\.squash) {
                MoveKeyframe(1)
                LinearKeyframe(1, duration: 0.14)
                LinearKeyframe(0.88, duration: 0.05, timingCurve: .easeOut)
                LinearKeyframe(1, duration: 0.12, timingCurve: .easeInOut)
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 0.06)
            }
        }
    }
}

// MARK: Sparkle burst

/// A short burst of sparkles in a potion's color, rising out of a flask's mouth (~0.6 s).
/// The view is `SparkleBurst.size(width:)`; center it on the mouth. Starts at `start`
/// (it draws nothing before that).
struct SparkleBurst: View {
    let start: Date
    let color: Color
    let width: CGFloat

    static let duration = 0.6
    static func size(width: CGFloat) -> CGSize { CGSize(width: width * 3.6, height: width * 3.6) }

    private struct Particle {
        let angle: Double     // radians, 0 = up
        let speed: CGFloat    // in widths per second
        let size: CGFloat     // in widths
        let spin: Double
        let white: Bool
    }

    private static let particles: [Particle] = (0..<16).map { i in
        // Deterministic spread: golden-angle offsets inside an upward fan.
        let u = (Double(i) * 0.618_034).truncatingRemainder(dividingBy: 1)
        let v = (Double(i) * 0.414_214 + 0.3).truncatingRemainder(dividingBy: 1)
        return Particle(angle: (u - 0.5) * 2.4, speed: CGFloat(2.0 + 2.6 * v), size: CGFloat(0.1 + 0.1 * (1 - v)),
                        spin: (v - 0.5) * 8, white: i % 4 == 0)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t >= 0, t <= Self.duration else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height / 2)
                let progress = t / Self.duration
                let fade = 1 - progress * progress
                for p in Self.particles {
                    let distance = p.speed * width * CGFloat(t) * CGFloat(1 - 0.45 * progress)
                    let fall = 2.2 * width * CGFloat(t * t)      // a little gravity
                    let center = CGPoint(x: origin.x + distance * CGFloat(sin(p.angle)),
                                         y: origin.y - distance * CGFloat(cos(p.angle)) + fall)
                    let r = p.size * width * CGFloat(0.6 + 0.4 * (1 - progress))
                    var c = context
                    c.opacity = fade
                    c.translateBy(x: center.x, y: center.y)
                    c.rotate(by: .radians(p.spin * t))
                    let star = Self.sparkle(radius: r)
                    c.fill(star, with: .color(p.white ? .white : color))
                    c.fill(Path(ellipseIn: CGRect(x: -r * 0.22, y: -r * 0.22, width: r * 0.44, height: r * 0.44)),
                           with: .color(.white.opacity(0.9)))
                }
            }
        }
        .frame(width: Self.size(width: width).width, height: Self.size(width: width).height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Four-pointed sparkle centered at the origin.
    private static func sparkle(radius r: CGFloat) -> Path {
        Path { p in
            let k = r * 0.28
            p.move(to: CGPoint(x: 0, y: -r))
            p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: k, y: -k))
            p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: k, y: k))
            p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -k, y: k))
            p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -k, y: -k))
            p.closeSubpath()
        }
    }
}

// MARK: Rim

/// The flask's lip: a thin glass ring a little wider than the neck, at the top edge. Purely
/// decorative and drawn over the flask, so the liquid's shape and clipping are unchanged.
/// Place with `.overlay(alignment: .top)` on the flask's frame; `color` follows the outline.
struct FlaskRim: View {
    let width: CGFloat
    let color: Color

    static func size(width: CGFloat) -> CGSize { CGSize(width: width * 1.1, height: max(4, width * 0.1)) }

    var body: some View {
        let size = Self.size(width: width)
        let rim = RoundedRectangle(cornerRadius: size.height / 2)
        rim.fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.08)],
                                startPoint: .top, endPoint: .bottom))
            .overlay(rim.strokeBorder(color, lineWidth: 1.5))
            .frame(width: size.width, height: size.height)
            .offset(y: -size.height * 0.45)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: Essence rune

/// The mark of an essence flask (C1): its color's rune etched into the glass near the neck,
/// glowing in that color, inside a thin etched ring. Drawn over the liquid so it reads on any
/// contents (including its own color). Same view at rest (`BottleView`), in flight
/// (`PourAnimationView`) and in the tips. Place with `.overlay(alignment: .top)` on the flask's
/// frame. `glow` 0…1 brightens the halo (a flask receiving its own color); `flare` 0…1 is the
/// refusal pulse (the rune flashes and swells briefly).
struct EssenceMark: View {
    let color: ColorID
    let width: CGFloat
    var glow: Double = 0
    var flare: Double = 0
    /// Whether a flare also swells the mark (off with reduce motion: it only brightens).
    var swells = true

    /// Side of the mark's square and its center below the flask's top edge: in the headroom
    /// above a full flask's liquid, just under the cork.
    static func side(width: CGFloat) -> CGFloat { width * 0.5 }
    static func centerY(width: CGFloat) -> CGFloat { width * 0.44 }

    /// Faint tint of the glass in the essence color (behind the liquid).
    static func tint(_ color: ColorID) -> Color { Palette.color(color.rawValue).opacity(0.2) }
    /// Outline of an essence flask at rest.
    static func outline(_ color: ColorID) -> Color { Palette.color(color.rawValue).opacity(0.75) }

    var body: some View {
        let side = Self.side(width: width)
        let tint = Palette.color(color.rawValue)
        let rune = Rune(colorIndex: color.rawValue)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.06, dy: size.height * 0.06)
            let ring = Path(ellipseIn: rect)
            let line = max(1, size.width * 0.06)
            // Dark etched disc so the mark reads over any liquid.
            context.fill(ring, with: .color(.black.opacity(0.42)))
            // Halo: the ring and rune blurred in the essence color.
            var halo = context
            halo.addFilter(.blur(radius: size.width * (0.08 + 0.06 * glow + 0.08 * flare)))
            halo.opacity = 0.75 + 0.25 * max(glow, flare)
            halo.stroke(ring, with: .color(tint), lineWidth: line * 2)
            if let rune {
                let inner = rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)
                halo.stroke(rune.path(in: inner), with: .color(tint),
                            style: StrokeStyle(lineWidth: line * 2.4, lineCap: .round, lineJoin: .round))
                context.stroke(rune.path(in: inner), with: .color(tint),
                               style: StrokeStyle(lineWidth: line * 1.5, lineCap: .round, lineJoin: .round))
                // Bright core: the "lit" groove of the etching.
                context.stroke(rune.path(in: inner),
                               with: .color(.white.opacity(0.55 + 0.35 * max(glow, flare))),
                               style: StrokeStyle(lineWidth: max(0.6, line * 0.45), lineCap: .round, lineJoin: .round))
            }
            context.stroke(ring, with: .color(tint.opacity(0.95)), lineWidth: line)
            context.stroke(Path(ellipseIn: rect.insetBy(dx: line, dy: line)),
                           with: .color(.white.opacity(0.25)), lineWidth: max(0.5, line * 0.35))
        }
        .frame(width: side, height: side)
        .scaleEffect(swells ? 1 + 0.25 * flare : 1)
        .offset(y: Self.centerY(width: width) - side / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
