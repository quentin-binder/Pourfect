import BottleSortCore
import SwiftUI

// Frost Peak (chapter 6): the one visual signal of frozen layers (D1), drawn the same at rest
// (`BottleView`), in flight (`PourAnimationView`) and in the tips. All sizes follow the flask
// width `w`; positions are in the flask's own frame (0, 0 = top-left of the body).
//
// - A frozen layer is covered by a frosted ice slab with facets and a hexagonal crystal that
//   shows its thaw counter (`IceSlab`, `IceLayers`).
// - A flask that holds ice gets a frost rim: a frosted crust with small icicles on its lip and
//   frost along the glass edges (`FrostRim`, `FrostGlass`).
// - When a layer thaws (`TurnEvent.thawed`), the ice cracks, the crystal pops, and the slab
//   melts into the potion with a few drips and a breath of cold mist (`ThawingIce`).

/// Ice colors: frost white, pale and mid ice blue, and the deep blue of the counter.
enum Ice {
    static let frost = Color(red: 0.94, green: 0.98, blue: 1.0)
    static let light = Color(red: 0.78, green: 0.91, blue: 0.99)
    static let mid = Color(red: 0.55, green: 0.78, blue: 0.95)
    static let deep = Color(red: 0.16, green: 0.36, blue: 0.62)
    /// Outline of a flask that holds ice.
    static let outline = Color(red: 0.74, green: 0.90, blue: 1.0).opacity(0.85)
}

/// Debug timing (`-LPSlowMotion F`, DEBUG only): stretches the pour and thaw animations F times,
/// to look at single frames. 1 in release builds.
enum DebugTiming {
    static let slow: Double = {
        #if DEBUG
        let value = UserDefaults.standard.double(forKey: "LPSlowMotion")
        return value >= 1 ? value : 1
        #else
        return 1
        #endif
    }()
}

// MARK: Ice slab

/// The ice over one frozen layer, sized to that layer (`width` × `layerHeight`): a frosted,
/// translucent slab (the potion shows through) with a bright top edge, a few facet lines and,
/// in the middle, a hexagonal ice crystal with the moves left until it thaws.
///
/// `flare` 0…1 brightens it (the ice refused a pour; with `swells` the crystal also swells).
/// `crack` 0…1 grows cracks across it, `melt` 0…1 fades and sinks it (a thaw, `ThawingIce`).
/// `badgeAside` moves the crystal to the right, so a colorblind rune in the middle stays visible.
struct IceSlab: View {
    let width: CGFloat
    let layerHeight: CGFloat
    /// Moves until it thaws (the crystal's number); nil draws the crystal without a number.
    let turns: Int?
    var flare: Double = 0
    var swells = true
    var crack: Double = 0
    var melt: Double = 0
    var badgeAside = false

    /// Side of the crystal badge.
    static func badgeSize(width w: CGFloat, layerHeight h: CGFloat) -> CGFloat { min(h * 0.74, w * 0.52) }

    var body: some View {
        let badge = Self.badgeSize(width: width, layerHeight: layerHeight) * (badgeAside ? 0.66 : 1)
        ZStack {
            Canvas { context, size in draw(in: &context, size: size) }
            IceCrystal(size: badge, turns: turns, flare: flare)
                .scaleEffect(swells ? 1 + 0.22 * flare : 1)
                .offset(x: badgeAside ? width * 0.31 : 0)
                .opacity(badgeOpacity)
                .scaleEffect(1 + 0.5 * badgePop)
        }
        .frame(width: width, height: layerHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The crystal pops (swells and fades) early in the melt.
    private var badgePop: Double { min(1, melt * 3) }
    private var badgeOpacity: Double { 1 - min(1, melt * 3) }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        // Melting: the slab sinks into the potion from the top and fades.
        let top = h * 0.45 * melt
        let alpha = 1 - melt
        guard alpha > 0.01 else { return }
        let slab = CGRect(x: 0, y: top, width: w, height: h - top)
        context.opacity = alpha
        context.fill(Path(slab), with: .linearGradient(
            Gradient(stops: [.init(color: Ice.frost.opacity(0.5), location: 0),
                             .init(color: Ice.light.opacity(0.16), location: 0.45),
                             .init(color: Ice.mid.opacity(0.3), location: 1)]),
            startPoint: CGPoint(x: 0, y: slab.minY), endPoint: CGPoint(x: w * 0.35, y: slab.maxY)))
        if flare > 0 { context.fill(Path(slab), with: .color(.white.opacity(0.35 * flare))) }
        // Bright top face and a darker underside: reads as a block, not a stain.
        context.fill(Path(CGRect(x: 0, y: slab.minY, width: w, height: max(1.5, h * 0.09))),
                     with: .color(.white.opacity(0.85)))
        context.fill(Path(CGRect(x: 0, y: h - max(1, h * 0.07), width: w, height: max(1, h * 0.07))),
                     with: .color(Ice.deep.opacity(0.45)))
        // Facets (unit coordinates), kept away from the crystal in the middle.
        let line = max(0.75, w * 0.016)
        let facets: [[CGPoint]] = [
            [CGPoint(x: 0.04, y: 0.28), CGPoint(x: 0.22, y: 0.52), CGPoint(x: 0.12, y: 0.96)],
            [CGPoint(x: 0.22, y: 0.52), CGPoint(x: 0.3, y: 0.18)],
            [CGPoint(x: 0.7, y: 0.12), CGPoint(x: 0.82, y: 0.46), CGPoint(x: 0.98, y: 0.58)],
            [CGPoint(x: 0.82, y: 0.46), CGPoint(x: 0.74, y: 0.94)],
        ]
        for facet in facets {
            let points = facet.map { CGPoint(x: $0.x * w, y: max(slab.minY, $0.y * h)) }
            context.stroke(Path { $0.addLines(points) }, with: .color(.white.opacity(0.6)), lineWidth: line)
        }
        // A few frost specks.
        for (x, y) in [(0.1, 0.12), (0.42, 0.2), (0.6, 0.84), (0.9, 0.24), (0.33, 0.78)] where y * h > slab.minY {
            let r = max(0.8, w * 0.018)
            context.fill(Path(ellipseIn: CGRect(x: x * w - r, y: y * h - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white.opacity(0.85)))
        }
        // Cracks spreading from the crystal while it thaws.
        if crack > 0 {
            for branch in Self.cracks {
                let path = Path { p in p.addLines(branch.map { CGPoint(x: $0.x * w, y: $0.y * h) }) }
                    .trimmedPath(from: 0, to: crack)
                context.stroke(path, with: .color(Ice.deep.opacity(0.55)), lineWidth: line * 2.4)
                context.stroke(path, with: .color(.white), lineWidth: line * 1.2)
            }
        }
    }

    /// Crack branches from the middle outwards (unit coordinates).
    private static let cracks: [[CGPoint]] = [
        [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.36, y: 0.36), CGPoint(x: 0.24, y: 0.4), CGPoint(x: 0.02, y: 0.18)],
        [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.62, y: 0.3), CGPoint(x: 0.8, y: 0.22), CGPoint(x: 0.98, y: 0.04)],
        [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.66, y: 0.66), CGPoint(x: 0.86, y: 0.7), CGPoint(x: 1.0, y: 0.92)],
        [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.4, y: 0.7), CGPoint(x: 0.3, y: 0.98)],
        [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.16), CGPoint(x: 0.56, y: 0.0)],
    ]
}

/// A hexagonal ice crystal with six short spikes and the thaw counter inside, in deep ice blue.
struct IceCrystal: View {
    let size: CGFloat
    let turns: Int?
    var flare: Double = 0

    var body: some View {
        ZStack {
            Canvas { context, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = canvas.width * 0.4
                let corners = (0..<6).map { k -> CGPoint in
                    let a = Double(k) * .pi / 3 - .pi / 2
                    return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                }
                let line = max(0.8, size * 0.06)
                for p in corners {
                    let tip = CGPoint(x: c.x + (p.x - c.x) * 1.25, y: c.y + (p.y - c.y) * 1.25)
                    context.stroke(Path { $0.move(to: p); $0.addLine(to: tip) },
                                   with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: line, lineCap: .round))
                }
                let hex = Path { $0.addLines(corners); $0.closeSubpath() }
                context.fill(hex, with: .linearGradient(Gradient(colors: [.white, flare > 0 ? .white : Ice.light]),
                                                         startPoint: CGPoint(x: c.x, y: c.y - r),
                                                         endPoint: CGPoint(x: c.x, y: c.y + r)))
                context.stroke(hex, with: .color(Ice.deep.opacity(0.85)), lineWidth: line)
            }
            if let turns {
                Text(verbatim: "\(turns)")
                    .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Ice.deep)
                    .contentTransition(.numericText(countsDown: true))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Ice.deep.opacity(0.35), radius: 1.5, y: 0.5)
    }
}

/// Every frozen layer of a flask, each under its `IceSlab`, in a frame of the flask body
/// (`width` × `height`, layers stacked from the bottom). Clipped to the flask's shape so the ice
/// follows the glass. Place it over the liquid with `.overlay(alignment: .bottom)` or in a
/// bottom-aligned ZStack.
struct IceLayers: View {
    let ice: [FrozenLayer]
    let width: CGFloat
    let height: CGFloat
    var runes = false
    /// Per layer (0 = bottom): shown as "?" (murky). The crystal moves aside so the "?" shows.
    var hidden: [Bool] = []
    var flare: Double = 0
    var swells = true

    var body: some View {
        let layerHeight = BottleView.layerHeight(width: width)
        ZStack(alignment: .topLeading) {
            ForEach(ice, id: \.layer) { frozen in
                let murky = hidden.indices.contains(frozen.layer) && hidden[frozen.layer]
                IceSlab(width: width, layerHeight: layerHeight, turns: frozen.turns, flare: flare, swells: swells,
                        badgeAside: runes || murky)
                    .position(x: width / 2, y: height - (CGFloat(frozen.layer) + 0.5) * layerHeight)
                    // A thawed slab goes at once: `ThawingIce` takes over and melts it.
                    .transition(.identity)
            }
        }
        .frame(width: width, height: height)
        .clipShape(BottleView.shape(width: width))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Thaw

/// One frozen layer that just thawed (`GameViewModel.thaws`): animated once, then removed.
struct ThawMark: Identifiable, Equatable {
    let id: Int
    let bottle: Int
    let layer: Int
}

/// Timing of the thaw animation.
enum ThawPose {
    /// Cracks spread (0–0.35 s), the crystal pops, the slab sinks and fades with drips and a puff
    /// of cold mist (0.35–1.0 s).
    static let duration = 1.0
    /// Reduce Motion: the ice only fades.
    static let reducedDuration = 0.45
    static let crackEnd = 0.35

    static func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(max((t - a) / (b - a), 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// The crack-and-melt of thawed layers, drawn over the flask body (`width` × `height`) after the
/// pour lands: the ice cracks with a small shiver, the crystal pops, the slab sinks into the
/// potion and fades while a few drops fall through it and a breath of mist rises. With Reduce
/// Motion the ice just fades.
struct ThawingIce: View {
    let thaws: [ThawMark]
    let width: CGFloat
    let height: CGFloat
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(thaws) { thaw in
                ThawingLayer(width: width, height: height, layer: thaw.layer, reduceMotion: reduceMotion)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ThawingLayer: View {
    let width: CGFloat
    let height: CGFloat
    let layer: Int
    let reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        let duration = (reduceMotion ? ThawPose.reducedDuration : ThawPose.duration) * DebugTiming.slow
        TimelineView(.animation(paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            if elapsed < duration {
                content(t: elapsed / DebugTiming.slow)
            }
        }
    }

    @ViewBuilder
    private func content(t: Double) -> some View {
        let layerHeight = BottleView.layerHeight(width: width)
        let centerY = height - (CGFloat(layer) + 0.5) * layerHeight
        if reduceMotion {
            IceSlab(width: width, layerHeight: layerHeight, turns: 0, crack: 1,
                    melt: ThawPose.ease(t, 0, ThawPose.reducedDuration))
                .position(x: width / 2, y: centerY)
                .frame(width: width, height: height)
                .clipShape(BottleView.shape(width: width))
        } else {
            let crack = ThawPose.ease(t, 0.02, ThawPose.crackEnd)
            let melt = ThawPose.ease(t, ThawPose.crackEnd, ThawPose.duration - 0.05)
            let shiver = t < ThawPose.crackEnd ? sin(t * 90) * width * 0.025 * (1 - crack * 0.5) : 0
            ZStack(alignment: .topLeading) {
                IceSlab(width: width, layerHeight: layerHeight, turns: 0, crack: crack, melt: melt)
                    .position(x: width / 2 + shiver, y: centerY)
                drips(t: t, top: centerY - layerHeight / 2, layerHeight: layerHeight)
            }
            .frame(width: width, height: height)
            .clipShape(BottleView.shape(width: width))
            .overlay(alignment: .topLeading) { mist(t: t, y: centerY - layerHeight / 2) }
        }
    }

    /// Melt water: a few drops slide down from the slab through the layers below.
    private func drips(t: Double, top: CGFloat, layerHeight: CGFloat) -> some View {
        Canvas { context, _ in
            for (k, x) in [0.22, 0.5, 0.74, 0.36].enumerated() {
                let begin = ThawPose.crackEnd + Double(k) * 0.08
                let p = min(max((t - begin) / 0.45, 0), 1)
                guard p > 0, p < 1 else { continue }
                let y = top + layerHeight * 0.6 + CGFloat(p * p) * layerHeight * 1.6
                let r = max(1.2, width * 0.035) * (1 - CGFloat(p) * 0.4)
                let drop = Path { d in
                    d.move(to: CGPoint(x: x * width, y: y - r * 2.2))
                    d.addQuadCurve(to: CGPoint(x: x * width, y: y + r), control: CGPoint(x: x * width + r * 1.6, y: y + r * 0.2))
                    d.addQuadCurve(to: CGPoint(x: x * width, y: y - r * 2.2), control: CGPoint(x: x * width - r * 1.6, y: y + r * 0.2))
                }
                context.fill(drop, with: .color(Ice.frost.opacity(0.85 * (1 - p))))
            }
        }
        .frame(width: width, height: height)
    }

    /// A breath of cold mist rising from the slab as it breaks (not clipped: it leaves the flask
    /// when the ice is at the top).
    private func mist(t: Double, y: CGFloat) -> some View {
        let p = min(max((t - ThawPose.crackEnd + 0.05) / 0.6, 0), 1)
        return Canvas { context, _ in
            guard p > 0, p < 1 else { return }
            context.addFilter(.blur(radius: width * 0.06))
            for (k, x) in [0.25, 0.5, 0.75].enumerated() {
                let rise = CGFloat(p) * width * (0.5 + 0.15 * CGFloat(k % 2))
                let r = width * (0.12 + 0.1 * CGFloat(p))
                let cx = x * width + CGFloat(sin(p * 4 + Double(k))) * width * 0.04
                context.fill(Path(ellipseIn: CGRect(x: cx - r, y: y - rise - r, width: 2 * r, height: 2 * r)),
                             with: .color(.white.opacity(0.5 * sin(.pi * p))))
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: Frost rim

/// The frost of a flask that holds ice: a frosted crust on the lip with small icicles hanging
/// from it. Place with `.overlay(alignment: .top)` on the flask's frame, like `FlaskRim`; a
/// narrow neck gets it on its own, narrower lip.
struct FrostRim: View {
    let width: CGFloat
    var necked = false

    var body: some View {
        let lip = necked ? NarrowNeck.width(width) : width
        let rim = FlaskRim.size(width: lip)
        let size = CGSize(width: rim.width * 1.04, height: rim.height + width * 0.36)
        Canvas { context, canvas in
            let w = canvas.width
            let crustH = rim.height * 1.1
            // Icicles under the lip: tapered, frosted at the root, clear at the tip.
            let icicles: [(x: Double, length: Double)] = [(0.13, 0.26), (0.3, 0.14), (0.47, 0.21),
                                                          (0.68, 0.12), (0.86, 0.28)]
            for icicle in icicles {
                let x = icicle.x * w, half = max(1.4, w * 0.045)
                let len = icicle.length * width * (necked ? 0.6 : 1)
                let path = Path { p in
                    p.move(to: CGPoint(x: x - half, y: crustH * 0.6))
                    p.addLine(to: CGPoint(x: x + half, y: crustH * 0.6))
                    p.addQuadCurve(to: CGPoint(x: x, y: crustH * 0.6 + len), control: CGPoint(x: x + half * 0.4, y: crustH + len * 0.4))
                    p.closeSubpath()
                }
                context.fill(path, with: .linearGradient(Gradient(colors: [Ice.frost, Ice.mid.opacity(0.5)]),
                                                          startPoint: CGPoint(x: x, y: crustH * 0.6),
                                                          endPoint: CGPoint(x: x, y: crustH * 0.6 + len)))
            }
            // The crust: a frosted band over the rim, bumpy along its top.
            let band = CGRect(x: 0, y: 0, width: w, height: crustH)
            context.fill(Path(roundedRect: band, cornerRadius: crustH / 2),
                         with: .linearGradient(Gradient(colors: [Ice.frost, Ice.light]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: crustH)))
            let bumps = 7
            for k in 0..<bumps {
                let r = crustH * (k % 2 == 0 ? 0.42 : 0.32)
                let cx = w * (CGFloat(k) + 0.5) / CGFloat(bumps)
                context.fill(Path(ellipseIn: CGRect(x: cx - r, y: -r * 0.55, width: 2 * r, height: 2 * r)),
                             with: .color(Ice.frost))
            }
            context.stroke(Path(roundedRect: band, cornerRadius: crustH / 2),
                           with: .color(Ice.mid.opacity(0.8)), lineWidth: 0.75)
        }
        .frame(width: size.width, height: size.height)
        .offset(y: -rim.height * 0.55 - (necked ? NarrowNeck.height(width) : 0))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Frost creeping along the inside of the glass of a flask that holds ice: a soft pale band
/// on the edges, over the liquid. Fills the flask body's frame.
struct FrostGlass: View {
    let width: CGFloat

    var body: some View {
        let shape = BottleView.shape(width: width)
        shape.strokeBorder(Ice.frost.opacity(0.5), lineWidth: max(2, width * 0.09))
            .blur(radius: max(1, width * 0.05))
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
