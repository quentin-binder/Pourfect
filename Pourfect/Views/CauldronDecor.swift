import BottleSortCore
import SwiftUI

// Alchemist's Hall (chapter 9): the one visual signal of a mixing cauldron (E1), drawn the same
// at rest (`BottleView`), in flight (`PourAnimationView`) and in the tips. All sizes follow the
// flask width `w`; positions are in the flask's own frame (0, 0 = top-left of the body).
//
// - The glass stands in a wide iron cauldron: a pot bulging out on both sides behind the glass,
//   on two stubby legs over a faint ember glow, with a thick iron rim and two ring handles at
//   the mouth (`CauldronPot`, `CauldronRim`). The potion area is the same as any flask's, so
//   layers, capacity and the pour line up exactly.
// - Under it hangs a parchment recipe card: one row per recipe, "X + Y → Z" as potion drops
//   with their runes (`RecipeCard`). The row that is mixing glows.
// - When a pour mixes (`TurnEvent.mixed`), after it lands the two ingredients swirl into each
//   other where they meet, the new potion blooms out from the middle of the swirl, bubbles rise
//   and a puff of colored steam leaves the mouth (`MixSwirl`). Reduce Motion cross-fades.

/// Cauldron colors: cast iron, the ember glow, the coppery glass outline and the recipe card.
enum Iron {
    static let light = Color(red: 0.60, green: 0.58, blue: 0.58)
    static let mid = Color(red: 0.34, green: 0.33, blue: 0.34)
    static let dark = Color(red: 0.15, green: 0.14, blue: 0.15)
    static let ember = Color(red: 1.0, green: 0.48, blue: 0.14)
    /// The glass outline of a cauldron at rest: a warm copper tone (the selection and hint
    /// outlines still take over).
    static let outline = Color(red: 0.80, green: 0.58, blue: 0.40).opacity(0.85)
    static let parchment = Color(red: 0.95, green: 0.88, blue: 0.72)
    static let parchmentShade = Color(red: 0.86, green: 0.76, blue: 0.56)
    static let parchmentEdge = Color(red: 0.55, green: 0.40, blue: 0.22)
    static let ink = Color(red: 0.32, green: 0.21, blue: 0.10)
    static let glow = Color(red: 1.0, green: 0.84, blue: 0.40)
}

// MARK: Pot

/// The iron pot behind a cauldron's glass (`width` × `height` = the flask's body): it bulges out
/// on both sides (widest about two thirds down), rounds under the base and stands on two legs
/// over an ember glow.
struct CauldronPot: View {
    let width: CGFloat
    let height: CGFloat
    /// What to draw: the ember glow (it stays on the table while a cauldron source flies) and
    /// the pot itself (legs, iron, band).
    var embers = true
    var drawsPot = true

    /// How far the pot reaches out on each side of the glass, and below the base (with legs).
    static func bulge(_ w: CGFloat) -> CGFloat { w * 0.24 }
    static func legDrop(_ w: CGFloat) -> CGFloat { w * 0.16 }

    var body: some View {
        let w = width, h = height
        let side = Self.bulge(w)
        Canvas { context, size in
            let ox = side + w * 0.02   // the glass's left edge in this canvas
            // Embers under the pot.
            if embers {
                let glowRect = CGRect(x: ox - w * 0.05, y: h - w * 0.06, width: w * 1.1, height: w * 0.32)
                context.fill(Path(ellipseIn: glowRect), with: .radialGradient(
                    Gradient(colors: [Iron.ember.opacity(0.55), Iron.ember.opacity(0)]),
                    center: CGPoint(x: glowRect.midX, y: glowRect.midY), startRadius: 0, endRadius: w * 0.5))
            }
            guard drawsPot else { return }
            // Two stubby legs, splayed a little.
            for (x, lean) in [(ox + w * 0.1, -1.0), (ox + w * 0.9, 1.0)] {
                let leg = Path { p in
                    p.move(to: CGPoint(x: x - w * 0.07, y: h - w * 0.2))
                    p.addLine(to: CGPoint(x: x + w * 0.07, y: h - w * 0.2))
                    p.addLine(to: CGPoint(x: x + w * (0.05 + 0.04 * lean), y: h + Self.legDrop(w)))
                    p.addLine(to: CGPoint(x: x + w * (-0.05 + 0.04 * lean), y: h + Self.legDrop(w)))
                    p.closeSubpath()
                }
                context.fill(leg, with: .linearGradient(Gradient(colors: [Iron.mid, Iron.dark]),
                                                        startPoint: CGPoint(x: x - w * 0.07, y: 0),
                                                        endPoint: CGPoint(x: x + w * 0.07, y: 0)))
            }
            // The pot: from the rim, out to the belly and round under the base.
            let belly = h * 0.64
            let pot = Path { p in
                p.move(to: CGPoint(x: ox, y: w * 0.06))
                p.addCurve(to: CGPoint(x: ox - side, y: belly), control1: CGPoint(x: ox - side * 0.2, y: h * 0.3),
                           control2: CGPoint(x: ox - side, y: belly - h * 0.18))
                p.addCurve(to: CGPoint(x: ox + w / 2, y: h + w * 0.05), control1: CGPoint(x: ox - side, y: h - w * 0.05),
                           control2: CGPoint(x: ox + w * 0.05, y: h + w * 0.05))
                p.addCurve(to: CGPoint(x: ox + w + side, y: belly), control1: CGPoint(x: ox + w * 0.95, y: h + w * 0.05),
                           control2: CGPoint(x: ox + w + side, y: h - w * 0.05))
                p.addCurve(to: CGPoint(x: ox + w, y: w * 0.06), control1: CGPoint(x: ox + w + side, y: belly - h * 0.18),
                           control2: CGPoint(x: ox + w + side * 0.2, y: h * 0.3))
                p.closeSubpath()
            }
            context.fill(pot, with: .linearGradient(
                Gradient(stops: [.init(color: Iron.mid, location: 0), .init(color: Iron.light, location: 0.1),
                                 .init(color: Iron.mid, location: 0.3), .init(color: Iron.dark, location: 1)]),
                startPoint: CGPoint(x: ox - side, y: 0), endPoint: CGPoint(x: ox + w + side, y: 0)))
            // The band and the warm reflection are on the outside of the iron: they stop at the
            // glass, so only the potion (or the dark pot behind empty glass) reads inside it.
            var outside = context
            outside.clip(to: Path { p in
                p.addPath(pot)
                p.addRect(CGRect(x: ox, y: 0, width: w, height: h))
            }, style: FillStyle(eoFill: true))
            // A warm reflection of the embers on the underside.
            outside.fill(pot, with: .linearGradient(
                Gradient(colors: [Iron.ember.opacity(0), Iron.ember.opacity(0.16)]),
                startPoint: CGPoint(x: 0, y: belly), endPoint: CGPoint(x: 0, y: h + w * 0.05)))
            // Highlight down the left bulge, and a hoop band around the belly.
            let shine = Path { p in
                p.move(to: CGPoint(x: ox - side * 0.35, y: h * 0.38))
                p.addQuadCurve(to: CGPoint(x: ox - side * 0.45, y: belly + h * 0.12), control: CGPoint(x: ox - side * 0.95, y: belly))
            }
            context.stroke(shine, with: .color(.white.opacity(0.28)),
                           style: StrokeStyle(lineWidth: max(1, w * 0.035), lineCap: .round))
            outside.fill(Path(CGRect(x: 0, y: belly - w * 0.05, width: size.width, height: w * 0.07)),
                      with: .color(Iron.dark.opacity(0.75)))
            outside.fill(Path(CGRect(x: 0, y: belly - w * 0.05, width: size.width, height: max(0.5, w * 0.015))),
                      with: .color(.white.opacity(0.18)))
            context.stroke(pot, with: .color(.black.opacity(0.55)), lineWidth: max(0.75, w * 0.02))
        }
        .frame(width: w + 2 * side + w * 0.04, height: h + Self.legDrop(w) + w * 0.2, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Rim

/// The cauldron's thick iron rim at the mouth, wider than the glass, with a ring handle hanging
/// from each end. Place with `.overlay(alignment: .top)` on the flask's frame.
struct CauldronRim: View {
    let width: CGFloat

    static func height(_ w: CGFloat) -> CGFloat { max(5, w * 0.15) }

    var body: some View {
        let w = width
        let rimH = Self.height(w)
        let frameW = w * 1.56
        Canvas { context, size in
            let rim = CGRect(x: (size.width - w * 1.26) / 2, y: 0, width: w * 1.26, height: rimH)
            // Ring handles, behind the rim's ends.
            let ring = w * 0.2
            for x in [rim.minX - ring * 0.18, rim.maxX + ring * 0.18] {
                let circle = Path(ellipseIn: CGRect(x: x - ring / 2, y: rimH * 0.55, width: ring, height: ring))
                context.stroke(circle, with: .color(Iron.dark), lineWidth: max(1.6, w * 0.06))
                context.stroke(circle, with: .color(Iron.light.opacity(0.8)), lineWidth: max(0.6, w * 0.02))
            }
            let shape = Path(roundedRect: rim, cornerRadius: rimH / 2)
            context.fill(shape, with: .linearGradient(
                Gradient(stops: [.init(color: Iron.light, location: 0), .init(color: Iron.mid, location: 0.45),
                                 .init(color: Iron.dark, location: 1)]),
                startPoint: CGPoint(x: 0, y: rim.minY), endPoint: CGPoint(x: 0, y: rim.maxY)))
            context.fill(Path(roundedRect: rim.insetBy(dx: rimH * 0.6, dy: rimH * 0.22).offsetBy(dx: 0, dy: -rimH * 0.12),
                              cornerRadius: rimH * 0.2), with: .color(.white.opacity(0.14)))
            context.stroke(shape, with: .color(.black.opacity(0.6)), lineWidth: max(0.75, w * 0.02))
        }
        .frame(width: frameW, height: rimH * 0.55 + w * 0.26)
        .offset(y: -rimH * 0.45)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Recipe card

/// A potion drop of palette color `color` with its rune, for the recipe card.
struct PotionDrop: View {
    let color: ColorID
    let size: CGFloat

    var body: some View {
        let tint = Palette.color(color.rawValue)
        Canvas { context, canvas in
            let w = canvas.width, h = canvas.height
            let drop = Path { p in
                p.move(to: CGPoint(x: w / 2, y: 0))
                p.addCurve(to: CGPoint(x: w * 0.92, y: h * 0.64), control1: CGPoint(x: w * 0.62, y: h * 0.2),
                           control2: CGPoint(x: w * 0.92, y: h * 0.38))
                p.addArc(center: CGPoint(x: w / 2, y: h * 0.64), radius: w * 0.42, startAngle: .degrees(0),
                         endAngle: .degrees(180), clockwise: false)
                p.addCurve(to: CGPoint(x: w / 2, y: 0), control1: CGPoint(x: w * 0.08, y: h * 0.38),
                           control2: CGPoint(x: w * 0.38, y: h * 0.2))
                p.closeSubpath()
            }
            context.fill(drop, with: .linearGradient(Gradient(colors: [tint.opacity(0.85), tint]),
                                                     startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            context.stroke(drop, with: .color(Iron.ink.opacity(0.75)), lineWidth: max(0.75, w * 0.06))
            if let rune = Rune(colorIndex: color.rawValue) {
                let box = CGRect(x: w * 0.27, y: h * 0.42, width: w * 0.46, height: w * 0.46)
                context.stroke(rune.path(in: box), with: .color(.white.opacity(0.92)),
                               style: StrokeStyle(lineWidth: max(0.8, w * 0.07), lineCap: .round, lineJoin: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: w * 0.28, y: h * 0.4, width: w * 0.12, height: h * 0.14)),
                         with: .color(.white.opacity(0.35)))
        }
        .frame(width: size, height: size * 1.2)
    }
}

/// The parchment card under a cauldron: one row "X + Y → Z" per recipe, as potion drops with
/// their runes. The row of `lit` glows with `glow` (0…1) while it mixes.
struct RecipeCard: View {
    let recipes: [Recipe]
    let width: CGFloat
    var lit: Recipe? = nil
    var glow: Double = 0

    static func drop(_ w: CGFloat) -> CGFloat { max(10, w * 0.32) }
    static func padding(_ w: CGFloat) -> CGFloat { max(3, w * 0.07) }
    static func rowHeight(_ w: CGFloat) -> CGFloat { drop(w) * 1.2 }
    static func height(_ w: CGFloat, rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight(w) + CGFloat(max(rows - 1, 0)) * padding(w) * 0.6 + 2 * padding(w)
    }
    static func gap(_ w: CGFloat) -> CGFloat { max(2, w * 0.05) }
    /// Room a card of `rows` recipes takes under a flask of width `w` (legs, gap and card).
    static func room(_ w: CGFloat, rows: Int) -> CGFloat {
        rows > 0 ? CauldronPot.legDrop(w) + gap(w) + height(w, rows: rows) : 0
    }
    /// The same room in flask widths, measured at a small flask (the minimum sizes weigh most).
    static func roomInWidths(rows: Int) -> CGFloat { room(40, rows: rows) / 40 }

    var body: some View {
        let d = Self.drop(width)
        let pad = Self.padding(width)
        VStack(spacing: pad * 0.6) {
            ForEach(recipes, id: \.self) { recipe in
                let isLit = recipe == lit
                HStack(spacing: max(1, width * 0.025)) {
                    PotionDrop(color: recipe.a, size: d)
                    glyph("plus")
                    PotionDrop(color: recipe.b, size: d)
                    glyph("arrow.right")
                    PotionDrop(color: recipe.result, size: d)
                        .scaleEffect(isLit ? 1 + 0.15 * glow : 1)
                }
                .frame(height: Self.rowHeight(width))
                .padding(.horizontal, pad * 0.5)
                .background {
                    if isLit {
                        Capsule().fill(Iron.glow.opacity(0.55 * glow))
                            .blur(radius: pad * 0.8)
                    }
                }
            }
        }
        .padding(pad)
        .background {
            RoundedRectangle(cornerRadius: pad * 1.2, style: .continuous)
                .fill(LinearGradient(colors: [Iron.parchment, Iron.parchmentShade], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: pad * 1.2, style: .continuous)
                        .strokeBorder(Iron.parchmentEdge.opacity(0.85), lineWidth: max(1, width * 0.03))
                }
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .shadow(color: Iron.glow.opacity(0.7 * glow * (lit == nil ? 0 : 1)), radius: pad * 2)
        }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: max(7, width * 0.17), weight: .heavy))
            .foregroundStyle(Iron.ink)
    }
}

extension View {
    /// Dresses a cauldron flask (`width` × `height` = its body): the iron pot behind it and the
    /// rim with handles on top. `heat` 0…1 brightens the embers. Does nothing for other flasks.
    @ViewBuilder
    func cauldronDress(_ bottle: Bottle, width: CGFloat, height: CGFloat, heat: Double = 0,
                       embers: Bool = true) -> some View {
        if bottle.isCauldron {
            background(alignment: .top) {
                ZStack(alignment: .top) {
                    CauldronPot(width: width, height: height, embers: embers)
                    // The embers flare while it mixes.
                    Ellipse()
                        .fill(RadialGradient(colors: [Iron.ember.opacity(0.85), Iron.ember.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: width * 0.62))
                        .frame(width: width * 1.35, height: width * 0.42)
                        .offset(y: height - width * 0.1)
                        .opacity(heat)
                        // Lit at once when the swirl takes over from the pour (which left it
                        // lit), faded out when the mix settles.
                        .animation(heat > 0 ? nil : .easeInOut(duration: 0.4), value: heat)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) { CauldronRim(width: width) }
        } else {
            self
        }
    }

    /// The ember glow under a cauldron's pot alone, where `cauldronDress` draws it: it stays on
    /// the table while the cauldron flies as a pour's source.
    func cauldronEmbers(width: CGFloat, height: CGFloat) -> some View {
        background(alignment: .top) { CauldronPot(width: width, height: height, drawsPot: false) }
    }

    /// Hangs a cauldron's recipe card under its legs (`width` = the flask's width).
    @ViewBuilder
    func recipeCard(_ recipes: [Recipe], width: CGFloat, lit: Recipe? = nil, glow: Double = 0) -> some View {
        if recipes.isEmpty {
            self
        } else {
            overlay(alignment: .bottom) {
                RecipeCard(recipes: recipes, width: width, lit: lit, glow: glow)
                    .offset(y: CauldronPot.legDrop(width) + RecipeCard.gap(width)
                               + RecipeCard.height(width, rows: recipes.count))
            }
        }
    }
}

// MARK: Mixing

/// One pour that mixed in a cauldron (`GameViewModel.mixes`): animated once after the pour
/// lands, then removed. `before` is the cauldron as the pour left it (`Rules.beforeMixing`),
/// `after` its layers once mixed; both are as long (mixing keeps every layer).
struct MixMark: Identifiable, Equatable {
    let id: Int
    let bottle: Int
    let recipe: Recipe
    let pairs: Int
    /// The poured color and how many layers of it landed.
    let poured: ColorID
    let amount: Int
    let before: [Layer]
    let after: [Layer]

    /// The lowest layer the mix changed: the bottom of the part of the run that mixed. Layers
    /// `start ..< start + 2 × pairs` turn from the partner and the poured color into the result.
    var start: Int { max(0, after.count - amount - pairs) }
    var partner: ColorID { recipe.partner(of: poured) ?? recipe.a }
}

/// Timing of the mix animation.
nonisolated enum MixPose {
    /// The boundary churns and the ingredients swirl (0–0.8 s), the new potion blooms from the
    /// middle (0.25–0.85 s), the bands settle (to 1.0 s); bubbles rise and steam leaves the
    /// mouth until 1.25 s.
    static let duration = 1.25
    /// Reduce Motion: the stack cross-fades to the brewed potion.
    static let reducedDuration = 0.45
    /// When the new potion has bloomed (the sound's chime).
    static let bloom = 0.6

    static func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(max((t - a) / (b - a), 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// The mixing in a cauldron, drawn in place of its potion (`width` × `height` = the flask's
/// body), from `mark.before` to `mark.after`. `hidden` is the flask's murky mask (mixing only
/// touches layers in view). With Reduce Motion the stack cross-fades.
struct MixSwirl: View {
    let mark: MixMark
    let hidden: [Bool]
    let width: CGFloat
    let height: CGFloat
    let runes: Bool
    let reduceMotion: Bool
    @State private var start = Date()

    private var duration: Double { reduceMotion ? MixPose.reducedDuration : MixPose.duration }
    private var layerHeight: CGFloat { BottleView.layerHeight(width: width) }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = min(timeline.date.timeIntervalSince(start) / DebugTiming.slow, duration)
            ZStack(alignment: .top) {
                content(t: t)
                    .frame(width: width, height: height)
                    .flaskClip(width: width)
                if !reduceMotion { steam(t: t) }
            }
            .frame(width: width, height: height, alignment: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(t: Double) -> some View {
        if reduceMotion {
            let p = MixPose.ease(t, 0, MixPose.reducedDuration)
            ZStack(alignment: .bottom) {
                stack(mark.before)
                stack(mark.after).opacity(p)
            }
        } else {
            let merge = MixPose.ease(t, 0.84, 1.0)
            ZStack(alignment: .bottom) {
                // The final bands everywhere; the swirl covers the mixing zone until it settles.
                stack(mark.after)
                Canvas { context, _ in drawZone(in: &context, t: t) }
                    .opacity(1 - merge)
                Canvas { context, _ in drawBubbles(in: &context, t: t) }
            }
        }
    }

    /// Bands of `layers` from the bottom, like `BottleView` (one gradient per run).
    private func stack(_ layers: [Layer]) -> some View {
        VStack(spacing: 0) {
            ForEach(BottleView.runs(layers, hidden: hidden).reversed(), id: \.start) { run in
                LayerView(layer: run.layer, hidden: run.hidden, count: run.count, height: layerHeight,
                          width: width, runes: runes)
                    .frame(height: CGFloat(run.count) * layerHeight)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }

    /// Where the mix happens: the part of the run that mixed and the poured layers on it.
    private var zone: CGRect {
        let rows = CGFloat(2 * mark.pairs)
        return CGRect(x: 0, y: height - CGFloat(mark.start) * layerHeight - rows * layerHeight,
                      width: width, height: rows * layerHeight)
    }

    /// The two ingredients churn at their boundary and swirl into each other in two spiral arms
    /// while the result blooms from the middle and swallows them.
    private func drawZone(in context: inout GraphicsContext, t: Double) {
        let zone = self.zone
        guard zone.height > 0 else { return }
        var c = context
        c.clip(to: Path(zone))
        let x = Palette.color(mark.poured.rawValue), y = Palette.color(mark.partner.rawValue)
        let z = Palette.color(mark.recipe.result.rawValue)
        let churn = sin(.pi * min(1, t / 0.9))
        // 1. The poured color above, the partner below, their boundary waving harder and harder.
        let amp = zone.height * 0.24 * churn
        let wave = { (px: CGFloat) -> CGFloat in
            zone.midY + amp * CGFloat(sin(Double(px / width) * 2 * .pi * 1.3 + t * 11))
        }
        let below = Path { p in
            p.move(to: CGPoint(x: 0, y: zone.maxY))
            for i in 0...24 {
                let px = width * CGFloat(i) / 24
                p.addLine(to: CGPoint(x: px, y: wave(px)))
            }
            p.addLine(to: CGPoint(x: width, y: zone.maxY))
            p.closeSubpath()
        }
        c.fill(Path(zone), with: .color(x))
        c.fill(below, with: .color(y))
        // 2. Two spiral arms, one of each ingredient, turning.
        let center = CGPoint(x: zone.midX, y: zone.midY)
        let rx = width * 0.62, ry = zone.height * 0.62
        let turn = t * 7
        for arm in 0..<2 {
            let spiral = Path { p in
                for k in 0...48 {
                    let f = Double(k) / 48
                    let a = f * 3.4 * .pi + turn + Double(arm) * .pi
                    let point = CGPoint(x: center.x + rx * CGFloat(f * cos(a)), y: center.y + ry * CGFloat(f * sin(a)))
                    if k == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
            }
            c.stroke(spiral, with: .color((arm == 0 ? x : y).opacity(0.95 * churn)),
                     style: StrokeStyle(lineWidth: layerHeight * 0.34, lineCap: .round, lineJoin: .round))
        }
        // 3. The result blooms from the middle, with a bright rim while it grows.
        let b = MixPose.ease(t, 0.25, 0.85)
        if b > 0 {
            let bloom = CGRect(x: center.x - rx * 1.7 * b, y: center.y - ry * 1.7 * b,
                               width: 2 * rx * 1.7 * b, height: 2 * ry * 1.7 * b)
            let disc = Path(ellipseIn: bloom)
            c.fill(disc, with: .radialGradient(Gradient(colors: [z.opacity(0.9), z]), center: center,
                                               startRadius: 0, endRadius: max(rx, ry) * 1.7 * b))
            c.stroke(disc, with: .color(.white.opacity(0.65 * (1 - b))), lineWidth: max(1, width * 0.05))
        }
        // A few glints swirling in the zone.
        for k in 0..<5 {
            let a = turn * 1.3 + Double(k) * 1.26
            let r = 0.25 + 0.12 * Double(k % 3)
            let p = CGPoint(x: center.x + rx * CGFloat(r * cos(a)), y: center.y + ry * CGFloat(r * sin(a)))
            let s = max(1, width * 0.035)
            c.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s)),
                   with: .color(.white.opacity(0.7 * churn)))
        }
    }

    /// Bubbles of the new potion rising from the zone to the surface, where they pop.
    private func drawBubbles(in context: inout GraphicsContext, t: Double) {
        let zone = self.zone
        let surface = height - CGFloat(mark.after.count) * layerHeight
        let z = Palette.color(mark.recipe.result.rawValue)
        for k in 0..<10 {
            let born = 0.22 + Double(k) * 0.07
            let age = (t - born) / 0.5
            guard age > 0, age < 1 else { continue }
            let px = width * CGFloat(0.22 + 0.56 * ((Double(k) * 0.618).truncatingRemainder(dividingBy: 1)))
                + CGFloat(sin(t * 12 + Double(k))) * width * 0.03
            let from = zone.midY + zone.height * 0.2
            let py = from - (from - surface - layerHeight * 0.1) * CGFloat(age)
            let r = max(1.2, width * CGFloat(0.035 + 0.015 * Double(k % 3)))
            let fade = min(1, (1 - age) * 5) * min(1, age * 6)
            let circle = Path(ellipseIn: CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r))
            context.fill(circle, with: .color(z.opacity(0.5 * fade)))
            context.stroke(circle, with: .color(.white.opacity(0.8 * fade)), lineWidth: max(0.7, r * 0.3))
        }
    }

    /// Puffs of steam in the new potion's color leaving the mouth, with a few sparks.
    private func steam(t: Double) -> some View {
        let z = Palette.color(mark.recipe.result.rawValue)
        let size = CGSize(width: width * 1.8, height: width * 1.6)
        return Canvas { context, canvas in
            let mouth = CGPoint(x: canvas.width / 2, y: canvas.height)
            for k in 0..<5 {
                let born = 0.4 + Double(k) * 0.08
                let age = (t - born) / 0.75
                guard age > 0, age < 1 else { continue }
                let drift = CGFloat(k % 2 == 0 ? -1 : 1) * width * CGFloat(0.12 + 0.05 * Double(k % 3)) * CGFloat(age)
                let p = CGPoint(x: mouth.x + drift + CGFloat(sin(age * 5 + Double(k))) * width * 0.05,
                                y: mouth.y - width * 0.1 - CGFloat(age) * width * 1.2)
                let r = width * CGFloat(0.14 + 0.2 * age)
                var puff = context
                puff.addFilter(.blur(radius: r * 0.35))
                puff.opacity = 0.55 * sin(.pi * age)
                puff.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.8, width: 2 * r, height: 1.6 * r)),
                          with: .color(z))
                puff.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.5, width: r, height: r * 0.7)),
                          with: .color(.white.opacity(0.35)))
            }
            for k in 0..<6 {
                let age = (t - 0.5 - Double(k) * 0.05) / 0.5
                guard age > 0, age < 1 else { continue }
                let angle = (Double(k) / 6 - 0.5) * 1.6
                let d = width * CGFloat(0.3 + 0.7 * age)
                let p = CGPoint(x: mouth.x + d * CGFloat(sin(angle)), y: mouth.y - width * 0.1 - d * CGFloat(cos(angle)))
                let s = max(1, width * 0.04 * CGFloat(1 - age))
                context.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s)),
                             with: .color((k % 2 == 0 ? Color.white : z).opacity(1 - age)))
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(y: -size.height)
    }
}
