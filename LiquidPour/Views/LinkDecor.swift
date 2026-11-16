import BottleSortCore
import SwiftUI

// Twin Towers (chapter 8): links between two flasks, drawn between the flasks' actual frames on
// the board (after the shuffle, across rows, after a resize), in flight and in the tips.
//
// - Twin flasks (F1): each twin wears a silver band around its shoulder with a ring on either
//   side (`TwinBand`), and a silver chain hangs between the rings of the two (`ChainView`).
// - Pressure pipe (F2): a brass pipe leaves a spout under the first flask's base, runs along the
//   floor under the flasks and enters a spout under the second's base, a brass arrow on it
//   pointing the way (`PipeView`). Pushed layers run through it (`PipeGeometry.path`, drawn by
//   the pour). It is drawn behind the flasks, so where it crosses to another row it passes
//   behind the glass.
//
// All sizes follow the flask width `w`. Everything here is drawn with paths, which aren't
// clipped by their frame, so a link may reach outside the view it sits in.

/// Silver of the twins' bands and chain.
enum Silver {
    static let light = Color(red: 0.95, green: 0.96, blue: 0.99)
    static let mid = Color(red: 0.70, green: 0.74, blue: 0.80)
    static let dark = Color(red: 0.30, green: 0.33, blue: 0.39)

    static func gradient(flare: Double = 0) -> LinearGradient {
        LinearGradient(colors: [flare > 0 ? .white : light, mid, dark],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: Twin band

/// The band a twin wears around its shoulder (in the headroom above the potion, so it never
/// covers a layer), with a ring on each side for the chain. Place with `.overlay(alignment: .top)`
/// on the flask's frame. `flare` 0…1 brightens it (the chain refused a pour).
struct TwinBand: View {
    let width: CGFloat
    var flare: Double = 0

    /// Height of the band's middle below the flask's top edge.
    static func centerY(_ w: CGFloat) -> CGFloat { w * 0.27 }
    static func ringSize(_ w: CGFloat) -> CGFloat { max(6, w * 0.2) }
    /// Where the chain hooks on, in the flask's frame: the outer edge of the ring on `side`
    /// (+1 right, -1 left).
    static func hook(_ w: CGFloat, side: CGFloat) -> CGPoint {
        CGPoint(x: w / 2 + side * (w / 2 + ringSize(w) * 0.3), y: centerY(w))
    }

    var body: some View {
        let w = width
        let band = max(2.5, w * 0.075)
        let ring = Self.ringSize(w)
        let line = max(1.2, w * 0.035)
        ZStack {
            Capsule()
                .fill(Silver.gradient(flare: flare))
                .overlay(Capsule().stroke(Silver.dark.opacity(0.8), lineWidth: 0.6))
                .frame(width: w * 0.98, height: band)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle()
                    .stroke(Silver.dark, lineWidth: line + 1)
                    .overlay(Circle().stroke(Silver.gradient(flare: flare), lineWidth: line))
                    .frame(width: ring, height: ring)
                    .offset(x: side * w / 2)
            }
        }
        .shadow(color: .white.opacity(0.6 * flare), radius: 4 * flare)
        .frame(width: w, height: ring)
        .offset(y: Self.centerY(w) - ring / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Chain

/// The silver chain between two twins: hooked on the facing rings of their bands, hanging in a
/// gentle curve. Frames are the two flasks' bodies in the drawing's coordinate space.
enum ChainGeometry {
    /// The two hook points: on the facing sides of the flasks (if one stands right above the
    /// other, both on the right).
    static func hooks(_ a: CGRect, _ b: CGRect) -> (CGPoint, CGPoint) {
        let w = a.width
        let side: CGFloat = abs(a.midX - b.midX) < w * 0.5 ? 1 : (b.midX > a.midX ? 1 : -1)
        let sideB: CGFloat = abs(a.midX - b.midX) < w * 0.5 ? 1 : -side
        let ha = TwinBand.hook(w, side: side), hb = TwinBand.hook(b.width, side: sideB)
        return (CGPoint(x: a.minX + ha.x, y: a.minY + ha.y), CGPoint(x: b.minX + hb.x, y: b.minY + hb.y))
    }

    /// The curve the chain hangs along (a quadratic, like a short catenary), as points from `p`
    /// to `q`. `swing` moves the lowest point sideways a little (the chain rattling).
    static func curve(_ p: CGPoint, _ q: CGPoint, width w: CGFloat, swing: CGFloat = 0) -> [CGPoint] {
        let distance = hypot(q.x - p.x, q.y - p.y)
        let sag = max(w * 0.22, distance * 0.28)
        let c = CGPoint(x: (p.x + q.x) / 2 + swing, y: max(p.y, q.y) + sag * 2 - abs(q.y - p.y) * 0.5)
        return (0...40).map { i in
            let t = CGFloat(i) / 40, u = 1 - t
            return CGPoint(x: u * u * p.x + 2 * u * t * c.x + t * t * q.x,
                           y: u * u * p.y + 2 * u * t * c.y + t * t * q.y)
        }
    }

    /// The links along the curve: every other link lies flat (an oval), the ones between are
    /// seen edge-on (a short bar), each turned along the curve.
    static func links(along samples: [CGPoint], width w: CGFloat) -> (flat: Path, edge: Path) {
        let step = max(4.5, w * 0.15)
        var flat = Path(), edge = Path()
        var travelled: CGFloat = 0, next: CGFloat = step * 0.5, index = 0
        for i in 1..<samples.count {
            let a = samples[i - 1], b = samples[i]
            let length = hypot(b.x - a.x, b.y - a.y)
            while length > 0, next <= travelled + length {
                let t = (next - travelled) / length
                let center = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
                if index % 2 == 0 {
                    let rect = CGRect(x: -step * 0.8, y: -step * 0.42, width: step * 1.6, height: step * 0.84)
                    flat.addEllipse(in: rect, transform: transform)
                } else {
                    let rect = CGRect(x: -step * 0.75, y: -step * 0.11, width: step * 1.5, height: step * 0.22)
                    edge.addRoundedRect(in: rect, cornerSize: CGSize(width: step * 0.1, height: step * 0.1),
                                        transform: transform)
                }
                index += 1
                next += step
            }
            travelled += length
        }
        return (flat, edge)
    }
}

/// The chain between two twins. `flare` 0…1: the chain refused a pour, it glints and swings.
struct ChainView: View {
    let a: CGRect
    let b: CGRect
    var flare: Double = 0

    var body: some View {
        let w = a.width
        let (p, q) = ChainGeometry.hooks(a, b)
        let swing = CGFloat(sin(flare * .pi * 3)) * w * 0.12 * CGFloat(flare)
        let links = ChainGeometry.links(along: ChainGeometry.curve(p, q, width: w, swing: swing), width: w)
        let line = max(1.4, w * 0.042)
        ZStack {
            // A dark rim first, so the chain reads on light potions and on the dark workbench.
            links.flat.stroke(Silver.dark, lineWidth: line + 1.4)
            links.edge.stroke(Silver.dark, lineWidth: 1.4)
            // Path strokes span the whole drawing, so the metal is two flat tones, not a gradient.
            links.flat.stroke(Silver.mid, lineWidth: line)
            links.edge.fill(Silver.mid)
            links.flat.stroke(Silver.light.opacity(0.6 + 0.4 * flare), lineWidth: line * 0.45)
        }
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        .shadow(color: .white.opacity(0.7 * flare), radius: 5 * flare)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Pressure pipe

/// Where a pressure pipe runs: out of a brass spout under flask `a`'s base, down to the floor,
/// along the floor under the flasks and up into a spout under flask `b`'s base. Flasks in
/// different rows: along `a`'s floor to the gap beside `b`, down (or up) that gap to `b`'s
/// floor, then under `b`. A polyline with rounded corners, so liquid can run along it
/// (`path`, trimmed) and the arrow sits on its longest level run.
struct PipeGeometry {
    /// Corner points from `a`'s spout to `b`'s spout.
    let points: [CGPoint]
    /// Tube width.
    let tube: CGFloat

    /// `a`, `b`: the flasks' frames at rest; `liftA` / `liftB`: how far each is raised (picked
    /// up): its spout rises with it and the pipe stretches, its run along the floor stays put.
    init(from a: CGRect, to b: CGRect, liftA: CGFloat = 0, liftB: CGFloat = 0) {
        let w = a.width
        tube = max(5, w * 0.15)
        let drop = Self.drop(w)
        let floorA = a.maxY + drop, floorB = b.maxY + drop
        let start = CGPoint(x: a.midX, y: a.maxY - liftA + tube * 0.2)
        let end = CGPoint(x: b.midX, y: b.maxY - liftB + tube * 0.2)
        if abs(floorA - floorB) < 1 {
            points = [start, CGPoint(x: a.midX, y: floorA), CGPoint(x: b.midX, y: floorB), end]
        } else {
            // The gap beside `b` on the side facing `a` (the right side if `a` stands above or below).
            let side: CGFloat = abs(b.midX - a.midX) < w * 0.5 ? 1 : (a.midX > b.midX ? 1 : -1)
            let gap = b.midX + side * (b.width / 2 + max(7, b.width * 0.13))
            points = [start, CGPoint(x: a.midX, y: floorA), CGPoint(x: gap, y: floorA),
                      CGPoint(x: gap, y: floorB), CGPoint(x: b.midX, y: floorB), end]
        }
    }

    /// How far below the flasks' bases the pipe runs along the floor (room the board keeps
    /// under a row with a pipe: `room`).
    static func drop(_ w: CGFloat) -> CGFloat { w * 0.26 }
    /// Room under a flask's base for its pipe (the drop plus half a tube and the shadow).
    static func room(_ w: CGFloat) -> CGFloat { drop(w) + max(5, w * 0.15) * 0.5 + 4 }

    var start: CGPoint { points[0] }
    var end: CGPoint { points[points.count - 1] }

    var path: Path {
        Path { p in
            let r = tube * 1.1
            p.move(to: points[0])
            for i in 1..<points.count - 1 {
                // Round each corner, never more than half of either leg.
                let legs = min(hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y),
                               hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y))
                p.addArc(tangent1End: points[i], tangent2End: points[i + 1], radius: min(r, legs / 2))
            }
            p.addLine(to: points[points.count - 1])
        }
    }

    /// The middle of the longest level run and the way the potion flows there (radians).
    var arrow: (CGPoint, CGFloat) {
        var best = (CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), CGFloat(0)), length: CGFloat = -1
        for i in 1..<points.count {
            let p = points[i - 1], q = points[i]
            guard abs(p.y - q.y) < 0.5, abs(q.x - p.x) > length else { continue }
            length = abs(q.x - p.x)
            best = (CGPoint(x: (p.x + q.x) / 2, y: p.y), q.x >= p.x ? 0 : .pi)
        }
        return best
    }
}

/// The pressure pipe at rest: a brass tube with a spout under each flask's base (a brass
/// collar under the first, a flared inlet under the second) and a brass arrow on its floor run
/// pointing the way the bottom layers are pushed. `flare` 0…1 brightens it (it refused a pour).
/// `preview`: the held flask would push through this pipe if poured into its flask (the push
/// preview): the pipe glows, and unless `flows` is off (Reduce Motion) light runs along it and
/// the arrow nudges forward.
struct PipeView: View {
    let geometry: PipeGeometry
    var flare: Double = 0
    var preview = false
    var flows = true

    var body: some View {
        TimelineView(.animation(paused: !(preview && flows))) { context in
            pipe(time: preview && flows ? context.date.timeIntervalSinceReferenceDate : 0)
        }
        .shadow(color: Brass.light.opacity(preview ? 0.9 : 0), radius: preview ? 7 : 0)
        .animation(.easeInOut(duration: 0.25), value: preview)
    }

    private func pipe(time: TimeInterval) -> some View {
        let g = geometry
        let path = g.path
        let (mid, angle) = g.arrow
        // The preview's run of light: short bright dashes marching from A's spout to B's.
        let dash = g.tube * 1.1, gap = g.tube * 1.6
        let phase = -CGFloat(time.truncatingRemainder(dividingBy: 1)) * (dash + gap) * 1.6
        // The arrow nudges forward and back along its run.
        let nudge = CGFloat(sin(time * 2 * .pi * 1.6)) * g.tube * 0.35
        return ZStack {
            // Brass: a dark rim, the metal, a light streak along the top.
            path.stroke(Brass.dark, style: StrokeStyle(lineWidth: g.tube + 2, lineCap: .butt, lineJoin: .round))
            path.stroke(Brass.mid, style: StrokeStyle(lineWidth: g.tube, lineCap: .butt, lineJoin: .round))
            path.stroke(Color(white: 0.08).opacity(0.55),
                        style: StrokeStyle(lineWidth: g.tube * 0.5, lineCap: .butt, lineJoin: .round))
            path.stroke(Brass.light.opacity(0.75 + 0.25 * flare),
                        style: StrokeStyle(lineWidth: max(1, g.tube * 0.16), lineCap: .round, lineJoin: .round))
                .offset(x: -g.tube * 0.12, y: -g.tube * 0.22)
            if preview {
                path.stroke(Brass.light.opacity(0.55),
                            style: StrokeStyle(lineWidth: g.tube * 0.5, lineCap: .butt, lineJoin: .round))
                if flows {
                    path.stroke(Color.white.opacity(0.9),
                                style: StrokeStyle(lineWidth: g.tube * 0.32, lineCap: .round, lineJoin: .round,
                                                   dash: [dash, gap], dashPhase: phase))
                }
            }
            spout(at: g.start, width: g.tube * 1.9, height: g.tube * 0.85)
            spout(at: g.end, width: g.tube * 2.2, height: g.tube * 0.85)
            PipeArrow(size: g.tube * 2.2 * (preview ? 1.15 : 1))
                .rotationEffect(.radians(Double(angle)))
                .position(x: mid.x + nudge * cos(angle), y: mid.y)
                .shadow(color: .white.opacity(preview ? 0.8 : 0), radius: preview ? 4 : 0)
        }
        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
        .shadow(color: Brass.light.opacity(0.8 * flare), radius: 6 * flare)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A brass spout under a flask's base: a flange where the pipe meets the glass.
    private func spout(at point: CGPoint, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height * 0.35)
            .fill(LinearGradient(colors: [flare > 0 ? .white : Brass.light, Brass.mid, Brass.dark],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: height * 0.35).stroke(Brass.dark, lineWidth: 0.8))
            .frame(width: width, height: height)
            .position(x: point.x, y: point.y + height * 0.15)
    }
}

/// The brass arrowhead on a pipe, pointing right (turn it along the pipe).
struct PipeArrow: View {
    let size: CGFloat

    var body: some View {
        let shape = Path { p in
            p.move(to: CGPoint(x: size * 0.5, y: 0))
            p.addLine(to: CGPoint(x: -size * 0.35, y: -size * 0.42))
            p.addLine(to: CGPoint(x: -size * 0.15, y: 0))
            p.addLine(to: CGPoint(x: -size * 0.35, y: size * 0.42))
            p.closeSubpath()
        }
        .offsetBy(dx: size / 2, dy: size / 2)
        ZStack {
            shape.fill(LinearGradient(colors: [Brass.light, Brass.mid, Brass.dark], startPoint: .top, endPoint: .bottom))
            shape.stroke(Brass.dark, lineWidth: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
    }
}

/// The push preview's mark under the far flask of a pressure pipe: a small brass tag with an
/// up chevron and "+N", the layers a pour into the pipe's flask would push into this flask's
/// bottom. Place its center under the far flask's base (`center(under:)`).
struct PushBadge: View {
    let amount: Int
    let width: CGFloat

    /// Where the tag sits: centered under `flask`'s base, over the pipe's inlet.
    static func center(under flask: CGRect) -> CGPoint {
        CGPoint(x: flask.midX, y: flask.maxY + PipeGeometry.drop(flask.width) * 0.6)
    }

    var body: some View {
        let font = max(9, width * 0.2)
        HStack(spacing: font * 0.12) {
            Image(systemName: "chevron.up")
                .font(.system(size: font * 0.8, weight: .heavy))
            Text("+\(amount)", comment: "Push preview under a flask: how many layers a pour would push into its bottom through a pressure pipe")
                .font(.system(size: font, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(Color(white: 0.12))
        .padding(.horizontal, font * 0.45)
        .padding(.vertical, font * 0.15)
        .background(Capsule().fill(LinearGradient(colors: [Brass.light, Brass.mid],
                                                  startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().stroke(Brass.dark, lineWidth: 1))
        .shadow(color: Brass.light.opacity(0.8), radius: 4)
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: One link

/// How a flask takes part in a link (display only).
enum LinkRole: Equatable {
    case twin(of: Int)
    case pipeOut(to: Int)
    case pipeIn(from: Int)

    case switchOf(gate: Int)
    case gateOf(switch: Int)

    init?(_ state: GameState, bottle: Int) {
        if let other = state.twin(of: bottle) { self = .twin(of: other) }
        else if let gate = state.gate(of: bottle) { self = .switchOf(gate: gate) }
        else if let s = state.switchFlask(of: bottle) { self = .gateOf(switch: s) }
        else if let to = state.overflowTarget(of: bottle) { self = .pipeOut(to: to) }
        else if let from = state.overflowSource(of: bottle) { self = .pipeIn(from: from) }
        else { return nil }
    }
}

/// One link drawn between the frames of its flasks. A flask picked up rises by `liftA` / `liftB`
/// (points, animatable), and the chain or pipe follows it.
struct LinkView: View, Animatable {
    let link: BottleSortCore.Link
    let a: CGRect
    let b: CGRect
    var liftA: CGFloat = 0
    var liftB: CGFloat = 0
    /// Each flask's shake count (`ShakeEffect`): an end follows its flask's wiggle, so the chain
    /// stays hooked to the rings while the twins shake.
    var shakeA: CGFloat = 0
    var shakeB: CGFloat = 0
    var flare: Double = 0
    /// A switch link (A3): 0 = its gate is shut … 1 = open (the portcullis slides away and the
    /// gem lights up as this animates).
    var open: Double = 0
    /// A switch link: how far the gate's own parts (neck, funnel) stand above its body.
    var gateRise: CGFloat = 0
    /// A switch link: the portcullis slides (false with Reduce Motion: it fades).
    var slides = true
    /// A switch link whose switch is in the air pouring: only the gate's housing and portcullis
    /// stay (the rest hangs on the switch).
    var switchAway = false
    /// A switch link whose gate is in the air pouring: only the gem, rod and lever stay (the
    /// housing and the portcullis sit on the gate).
    var gateAway = false
    /// A pressure pipe: the held flask would push through it (`PipeView.preview`), and whether the
    /// preview's light runs (off with Reduce Motion: a static glow).
    var pushPreview = false
    var previewFlows = true

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>, Double> {
        get { AnimatablePair(AnimatablePair(AnimatablePair(liftA, liftB), AnimatablePair(shakeA, shakeB)), open) }
        set {
            liftA = newValue.first.first.first
            liftB = newValue.first.first.second
            shakeA = newValue.first.second.first
            shakeB = newValue.first.second.second
            open = newValue.second
        }
    }

    var body: some View {
        let a = self.a.offsetBy(dx: ShakeEffect.offset(shakeA), dy: -liftA)
        let b = self.b.offsetBy(dx: ShakeEffect.offset(shakeB), dy: -liftB)
        switch link {
        case .twins:
            ChainView(a: a, b: b, flare: flare)
        case .overflow:
            // The floor run stays put; only the spout of a raised flask rises with it.
            PipeView(geometry: PipeGeometry(from: self.a.offsetBy(dx: ShakeEffect.offset(shakeA), dy: 0),
                                            to: self.b.offsetBy(dx: ShakeEffect.offset(shakeB), dy: 0),
                                            liftA: liftA, liftB: liftB),
                     flare: flare, preview: pushPreview, flows: previewFlows)
        case .switchGate:
            LeverView(geometry: LeverGeometry(switch: a, gate: b, gateRise: gateRise),
                      open: open, slides: slides, flare: flare, switchAway: switchAway,
                      gateAway: gateAway)
        }
    }
}

// MARK: Tips

/// Two flasks side by side with their link, for the tips: twins on a chain, a pressure pipe
/// from the first's base to the second's, or a switch (first) and its gate (drawn with
/// `BottleView`, like every tip). Both flasks hold 4 layers.
/// `firstSelected`: the first flask is picked up (it rises, and its chain follows).
struct LinkedPair: View {
    /// `.switchGate`: the first flask is the switch, the second its gate (open while the switch
    /// is full of one potion, `Rules.isSwitchOn`).
    enum Kind { case twins, pipe, switchGate }
    let kind: Kind
    let first: Bottle
    let second: Bottle
    let width: CGFloat
    var firstSelected = false
    var spacing: CGFloat = 18
    /// A switch pair: the second flask is picked up (it rises, and the lever follows).
    var secondSelected = false

    var body: some View {
        let h = BottleView.height(width: width, capacity: first.capacity)
        let a = CGRect(x: 0, y: 0, width: width, height: h)
        let b = CGRect(x: width + spacing, y: 0, width: width, height: h)
        HStack(alignment: .bottom, spacing: spacing) {
            BottleView(bottle: first, width: width, isSelected: firstSelected, twin: kind == .twins)
            BottleView(bottle: second, width: width, isSelected: secondSelected, twin: kind == .twins)
        }
        .background(alignment: .topLeading) {
            // A pipe runs behind the flasks (`GameView`), a chain or a lever in front of them.
            if kind == .pipe { link(a, b, h) }
        }
        .overlay(alignment: .topLeading) {
            if kind != .pipe { link(a, b, h) }
        }
        // Room for the lever's arch above the rims, and for the pipe under the bases.
        .padding(.top, kind == .switchGate ? width * 0.7 : 0)
        .padding(.bottom, kind == .pipe ? PipeGeometry.room(width) : 0)
    }

    private func link(_ a: CGRect, _ b: CGRect, _ h: CGFloat) -> some View {
        let link: BottleSortCore.Link = switch kind {
        case .twins: .twins(0, 1)
        case .pipe: .overflow(from: 0, to: 1)
        case .switchGate: .switchGate(switch: 0, gate: 1)
        }
        return LinkView(link: link, a: a, b: b, liftA: firstSelected ? width * 0.3 : 0,
                        liftB: secondSelected ? width * 0.3 : 0,
                        open: Rules.isSwitchOn(first) ? 1 : 0, gateRise: GlassParts(second).rise(width))
            .frame(width: 2 * width + spacing, height: h, alignment: .topLeading)
    }
}

extension BottleSortCore.Link {
    /// A pressure pipe (`overflow`, F2): drawn behind the flasks, along the floor.
    var isPipe: Bool {
        if case .overflow = self { return true } else { return false }
    }
}
