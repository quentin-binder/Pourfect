import BottleSortCore
import SwiftUI

// Twin Towers (chapter 8): links between two flasks, drawn between the flasks' actual frames on
// the board (after the shuffle, across rows, after a resize), in flight and in the tips.
//
// - Twin flasks (F1): each twin wears a silver band around its shoulder with a ring on either
//   side (`TwinBand`), and a silver chain hangs between the rings of the two (`ChainView`).
// - Overflow pipe (F2): a glass tube with brass fittings rises from the rim of the first flask
//   and comes down over the mouth of the second, a brass arrow on it pointing the way
//   (`PipeView`). Overflowing potion runs through it (`PipeGeometry.path`, drawn by the pour).
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

// MARK: Overflow pipe

/// Where an overflow pipe runs: from the rim of flask `a` on the side facing `b`, up and over,
/// and down onto `b`'s mouth (its end points straight down, a little off center, so a stream
/// poured into `b` from above still has room).
struct PipeGeometry {
    let start: CGPoint
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    /// Tube width.
    let tube: CGFloat

    init(from a: CGRect, to b: CGRect) {
        let w = a.width
        let dir: CGFloat = abs(b.midX - a.midX) < 1 ? 1 : (b.midX > a.midX ? 1 : -1)
        start = CGPoint(x: a.midX + dir * w * 0.40, y: a.minY - w * 0.05)
        end = CGPoint(x: b.midX - dir * b.width * 0.16, y: b.minY - b.width * 0.16)
        let lift = w * 0.72 + max(0, start.y - end.y) * 0.3
        let top = min(start.y, end.y) - lift
        control1 = CGPoint(x: start.x + dir * w * 0.05, y: top)
        control2 = CGPoint(x: end.x, y: top - w * 0.05)
        tube = max(5, w * 0.16)
    }

    var path: Path {
        Path { p in
            p.move(to: start)
            p.addCurve(to: end, control1: control1, control2: control2)
        }
    }

    /// Point and direction (radians) at `t` along the curve (0 = start).
    func point(at t: CGFloat) -> (CGPoint, CGFloat) {
        let u = 1 - t
        let x = u * u * u * start.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * end.x
        let y = u * u * u * start.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * end.y
        let dx = 3 * u * u * (control1.x - start.x) + 6 * u * t * (control2.x - control1.x) + 3 * t * t * (end.x - control2.x)
        let dy = 3 * u * u * (control1.y - start.y) + 6 * u * t * (control2.y - control1.y) + 3 * t * t * (end.y - control2.y)
        return (CGPoint(x: x, y: y), atan2(dy, dx))
    }
}

/// The overflow pipe at rest: a glass tube with a brass clamp on the first flask's rim, a brass
/// nozzle over the second's mouth, and a brass arrow halfway along pointing the way.
struct PipeView: View {
    let geometry: PipeGeometry

    var body: some View {
        let g = geometry
        let path = g.path
        let (mid, angle) = g.point(at: 0.5)
        ZStack {
            // Glass like the flasks': a light outline, a smoky inside, a highlight along the top.
            path.stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: g.tube + 3, lineCap: .butt))
            path.stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: g.tube + 1.5, lineCap: .butt))
            path.stroke(Color(white: 0.1), style: StrokeStyle(lineWidth: g.tube - 1, lineCap: .butt))
            path.stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: g.tube - 1, lineCap: .butt))
            path.stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: max(1, g.tube * 0.16), lineCap: .round))
                .offset(x: -g.tube * 0.16, y: -g.tube * 0.2)
            fitting(at: g.start, angle: 0, length: g.tube * 1.9, thickness: g.tube * 0.9)
            fitting(at: g.end, angle: .pi / 2, length: g.tube * 1.15, thickness: g.tube * 1.45)
            PipeArrow(size: g.tube * 2.4)
                .rotationEffect(.radians(Double(angle)))
                .position(mid)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A brass ring around the tube: `length` along `angle`, `thickness` across.
    private func fitting(at point: CGPoint, angle: CGFloat, length: CGFloat, thickness: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: thickness * 0.3)
            .fill(LinearGradient(colors: [Brass.light, Brass.mid, Brass.dark], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: thickness * 0.3).stroke(Brass.dark, lineWidth: 0.8))
            .frame(width: length, height: thickness)
            .rotationEffect(.radians(Double(angle)))
            .position(point)
    }
}

/// The brass arrowhead on a pipe, pointing right (turn it along the pipe).
private struct PipeArrow: View {
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

// MARK: One link

/// How a flask takes part in a link (display only).
enum LinkRole: Equatable {
    case twin(of: Int)
    case pipeOut(to: Int)
    case pipeIn(from: Int)

    init?(_ state: GameState, bottle: Int) {
        if let other = state.twin(of: bottle) { self = .twin(of: other) }
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
    var flare: Double = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(liftA, liftB) }
        set { liftA = newValue.first; liftB = newValue.second }
    }

    var body: some View {
        let a = self.a.offsetBy(dx: 0, dy: -liftA)
        let b = self.b.offsetBy(dx: 0, dy: -liftB)
        switch link {
        case .twins:
            ChainView(a: a, b: b, flare: flare)
        case .overflow:
            PipeView(geometry: PipeGeometry(from: a, to: b))
        case .switchGate:
            EmptyView()
        }
    }
}

// MARK: Tips

/// Two flasks side by side with their link, for the tips: twins on a chain, or a pipe from the
/// first to the second (drawn with `BottleView`, like every tip). Both flasks hold 4 layers.
/// `firstSelected`: the first flask is picked up (it rises, and its chain follows).
struct LinkedPair: View {
    enum Kind { case twins, pipe }
    let kind: Kind
    let first: Bottle
    let second: Bottle
    let width: CGFloat
    var firstSelected = false
    var spacing: CGFloat = 18

    var body: some View {
        let h = BottleView.height(width: width, capacity: first.capacity)
        let a = CGRect(x: 0, y: 0, width: width, height: h)
        let b = CGRect(x: width + spacing, y: 0, width: width, height: h)
        let link: BottleSortCore.Link = kind == .twins ? .twins(0, 1) : .overflow(from: 0, to: 1)
        HStack(alignment: .bottom, spacing: spacing) {
            BottleView(bottle: first, width: width, isSelected: firstSelected, twin: kind == .twins)
            BottleView(bottle: second, width: width, twin: kind == .twins)
        }
        .overlay(alignment: .topLeading) {
            LinkView(link: link, a: a, b: b, liftA: firstSelected ? width * 0.3 : 0)
                .frame(width: 2 * width + spacing, height: h, alignment: .topLeading)
        }
        // Room for the pipe's arch above the rims.
        .padding(.top, kind == .pipe ? width * 0.5 : 0)
    }
}
