import BottleSortCore
import SwiftUI

// Dragon's Hoard (chapter 10): switch flasks and gates (A3), drawn between the flasks' actual
// frames on the board (after the shuffle, across rows, after a resize) and in the tips.
//
// - The switch wears a gem in a brass mount on its shoulder, on the side facing its gate. The
//   gem is dark while the switch is off and lights up gold once it is full of one potion.
// - A brass rod runs from the gem's mount up and over to a brass housing above the gate's
//   mouth, with a lever halfway along: the lever leans towards the switch while the gate is
//   shut and swings over towards the gate when it opens.
// - While the gate is shut, an iron portcullis hangs from the housing over its mouth. When it
//   opens, the bars slide up into the housing (Reduce Motion: they fade), and drop back when
//   it closes again.
//
// The gate's state is never stored: it comes from `Rules.isSwitchOn` of the switch (through
// `GameViewModel.gateOpen`, which holds the state from before a move until its pour lands).

/// Colors of the portcullis and the switch gem.
enum GateMetal {
    static let iron = Color(red: 0.20, green: 0.20, blue: 0.23)
    static let ironLight = Color(red: 0.47, green: 0.47, blue: 0.52)
    static let gemOff = Color(red: 0.30, green: 0.18, blue: 0.16)
    static let gemOffLight = Color(red: 0.52, green: 0.36, blue: 0.30)
    static let gemOn = Color(red: 1.00, green: 0.80, blue: 0.25)
    static let gemOnLight = Color(red: 1.00, green: 0.97, blue: 0.78)

    static var brass: LinearGradient {
        LinearGradient(colors: [Brass.light, Brass.mid, Brass.dark], startPoint: .top, endPoint: .bottom)
    }
}

/// How long the portcullis takes to slide (or fade) open or shut.
enum GatePose {
    static let duration: Double = 0.55
    static let reducedDuration: Double = 0.3

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: reducedDuration * DebugTiming.slow)
                     : .spring(duration: duration * DebugTiming.slow, bounce: 0.25)
    }
}

// MARK: Geometry

/// Where the parts of one switch link sit, from the two flasks' frames in the drawing's space.
struct LeverGeometry {
    /// Center of the switch's gem (on its shoulder, on the side facing the gate).
    let gem: CGPoint
    let gemSize: CGFloat
    /// Center of the brass housing above the gate's mouth.
    let housing: CGPoint
    let housingSize: CGSize
    /// Lowest point of the shut portcullis (just inside the gate's mouth).
    let barsBottom: CGFloat
    /// The rod from the gem's mount to the top of the housing.
    let start: CGPoint
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let rod: CGFloat
    /// +1 if the gate stands right of the switch, -1 left.
    let dir: CGFloat

    /// `gateRise`: how far the gate's own parts (a narrow neck, a funnel) stand above its body.
    init(switch s: CGRect, gate g: CGRect, gateRise: CGFloat = 0) {
        let w = s.width
        dir = abs(g.midX - s.midX) < w * 0.5 ? 1 : (g.midX > s.midX ? 1 : -1)
        gemSize = Self.gemSize(w)
        gem = CGPoint(x: s.midX + dir * (w * 0.5 + gemSize * 0.12), y: s.minY + w * 0.24)
        let gw = g.width
        housingSize = CGSize(width: gw * 1.12, height: max(4, gw * 0.14))
        housing = CGPoint(x: g.midX, y: g.minY - gateRise - gw * 0.2)
        barsBottom = g.minY + gw * 0.36
        rod = max(2.5, w * 0.08)
        start = CGPoint(x: gem.x, y: gem.y - gemSize * 0.55)
        end = CGPoint(x: housing.x - dir * gw * 0.18, y: housing.y - housingSize.height * 0.5)
        let top = min(start.y, end.y) - w * 0.5
        control1 = CGPoint(x: start.x + dir * w * 0.04, y: top)
        control2 = CGPoint(x: end.x - dir * w * 0.06, y: top)
    }

    static func gemSize(_ w: CGFloat) -> CGFloat { max(10, w * 0.34) }

    var path: Path {
        Path { p in
            p.move(to: start)
            p.addCurve(to: end, control1: control1, control2: control2)
        }
    }

    /// Point on the rod at `t` (0 = gem, 1 = housing).
    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * u * start.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * end.x,
                       y: u * u * u * start.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * end.y)
    }
}

// MARK: Parts

/// The switch's gem in its brass mount: dark while off, glowing gold while the switch is full
/// of one potion. `lit` 0…1 (animatable through `LeverView`), `flare` 0…1 the refusal pulse.
struct SwitchGem: View {
    let size: CGFloat
    var lit: Double = 0
    var flare: Double = 0

    var body: some View {
        let glow = max(lit, flare * 0.6)
        ZStack {
            // Brass mount: a ring with four little claws.
            Circle().fill(GateMetal.brass).frame(width: size, height: size)
            Circle().stroke(Brass.dark, lineWidth: 0.8).frame(width: size, height: size)
            ForEach(0..<4, id: \.self) { k in
                Capsule().fill(Brass.light)
                    .frame(width: size * 0.12, height: size * 0.22)
                    .offset(y: -size * 0.42)
                    .rotationEffect(.degrees(45 + Double(k) * 90))
            }
            // The cut stone: a diamond, faceted by a lighter top half.
            let stone = size * 0.66
            ForEach([false, true], id: \.self) { on in
                GemShape()
                    .fill(RadialGradient(colors: on ? [GateMetal.gemOnLight, GateMetal.gemOn]
                                                    : [GateMetal.gemOffLight, GateMetal.gemOff],
                                         center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: stone * 0.6))
                    .opacity(on ? glow : 1)
                    .frame(width: stone, height: stone)
            }
            GemShape()
                .stroke(Color.black.opacity(0.55), lineWidth: 0.7)
                .frame(width: stone, height: stone)
            Circle().fill(.white.opacity(0.35 + 0.5 * glow))
                .frame(width: stone * 0.18, height: stone * 0.18)
                .offset(x: -stone * 0.14, y: -stone * 0.16)
        }
        .frame(width: size, height: size)
        .shadow(color: GateMetal.gemOn.opacity(0.9 * glow), radius: size * 0.55 * glow)
        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
    }
}

/// A cut gem's outline: a crown on top, a pointed pavilion below.
private struct GemShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.12))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.12))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.4))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.4))
            p.closeSubpath()
        }
    }
}

/// The iron bars of a gate: they hang from `top` down to `bottom` over a mouth `width` wide,
/// each ending in a spike, with two crossbars. `shift` moves them sideways (the rattle).
private struct PortcullisBars: Shape {
    let width: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    /// Where the crossbars sit when the portcullis is fully down (they ride up with it).
    let closedBottom: CGFloat
    let centerX: CGFloat
    var shift: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path { p in
            guard bottom > top + 0.5 else { return }
            let bar = max(1.6, width * 0.07)
            let count = 4
            let left = centerX - width * 0.39 + shift
            let gap = width * 0.78 / CGFloat(count - 1)
            let spike = min(bar * 1.6, bottom - top)
            for k in 0..<count {
                let x = left + CGFloat(k) * gap
                p.addRect(CGRect(x: x - bar / 2, y: top, width: bar, height: max(0, bottom - top - spike)))
                p.move(to: CGPoint(x: x - bar / 2, y: bottom - spike))
                p.addLine(to: CGPoint(x: x + bar / 2, y: bottom - spike))
                p.addLine(to: CGPoint(x: x, y: bottom))
                p.closeSubpath()
            }
            // The crossbars ride up with the bars; one that has gone into the housing is gone.
            let rise = closedBottom - bottom
            for f in [0.3, 0.68] as [CGFloat] {
                let y = top + (closedBottom - top) * f - rise
                guard y > top + bar * 0.5 else { continue }
                p.addRoundedRect(in: CGRect(x: left - bar * 0.9, y: y - bar * 0.45,
                                            width: gap * CGFloat(count - 1) + bar * 1.8, height: bar * 0.9),
                                 cornerSize: CGSize(width: bar * 0.3, height: bar * 0.3))
            }
        }
    }
}

// MARK: The whole link

/// A switch link drawn between its flasks' frames: the gem on the switch, the rod and lever, the
/// housing and the portcullis over the gate. `open` 0 (shut) … 1 (open); `slides`: the bars
/// slide up into the housing (false with Reduce Motion: they fade). `flare` 0…1: the gate just
/// refused a pour, the bars rattle and the brass glints.
struct LeverView: View {
    let geometry: LeverGeometry
    var open: Double
    var slides = true
    var flare: Double = 0
    /// The switch is in the air pouring: the rod, lever and gem fade (they hang on the switch);
    /// the housing and the portcullis stay on the gate.
    var switchAway = false

    var body: some View {
        let g = geometry
        let w = g.gemSize / 0.34
        let rodPath = g.path
        let pivot = g.point(at: 0.5)
        let travel = g.barsBottom - g.housing.y
        let bottom = slides ? g.barsBottom - travel * CGFloat(open) : g.barsBottom
        let barsOpacity = slides ? 1 : 1 - open
        let rattle = CGFloat(sin(flare * .pi * 6)) * w * 0.035 * CGFloat(flare)
        let bars = PortcullisBars(width: g.housingSize.width / 1.12, top: g.housing.y, bottom: bottom,
                                  closedBottom: g.barsBottom, centerX: g.housing.x, shift: rattle)
        ZStack {
            // Rod: a dark rim, brass, and a thin highlight.
            ZStack {
                rodPath.stroke(Brass.dark, style: StrokeStyle(lineWidth: g.rod + 1.6, lineCap: .round))
                rodPath.stroke(Brass.mid, style: StrokeStyle(lineWidth: g.rod, lineCap: .round))
                rodPath.stroke(Brass.light.opacity(0.75 + 0.25 * flare),
                               style: StrokeStyle(lineWidth: max(0.8, g.rod * 0.3), lineCap: .round))
                    .offset(y: -g.rod * 0.2)
            }
            .opacity(switchAway ? 0 : 1)
            // Portcullis under the housing.
            bars.fill(GateMetal.iron).opacity(barsOpacity)
            bars.stroke(GateMetal.ironLight.opacity(0.9), lineWidth: 0.7).opacity(barsOpacity)
            // Housing: a brass beam with rivets.
            RoundedRectangle(cornerRadius: g.housingSize.height * 0.35)
                .fill(GateMetal.brass)
                .overlay(RoundedRectangle(cornerRadius: g.housingSize.height * 0.35).stroke(Brass.dark, lineWidth: 0.8))
                .overlay {
                    HStack(spacing: g.housingSize.width * 0.5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Brass.dark).frame(width: g.housingSize.height * 0.32)
                        }
                    }
                }
                .frame(width: g.housingSize.width, height: g.housingSize.height)
                .position(g.housing)
            Group {
                lever(at: pivot, w: w)
                SwitchGem(size: g.gemSize, lit: open, flare: flare)
                    .position(g.gem)
            }
            .opacity(switchAway ? 0 : 1)
        }
        .shadow(color: Brass.light.opacity(0.7 * flare), radius: 5 * flare)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The lever on the rod: a brass hub with a handle and a red knob. It leans towards the
    /// switch while the gate is shut and swings over towards the gate as it opens.
    private func lever(at pivot: CGPoint, w: CGFloat) -> some View {
        let length = max(9, w * 0.42)
        let angle = Double(geometry.dir) * (-40 + 80 * open)
        return ZStack {
            Capsule()
                .fill(GateMetal.brass)
                .overlay(Capsule().stroke(Brass.dark, lineWidth: 0.7))
                .frame(width: max(2.2, w * 0.07), height: length)
                .offset(y: -length / 2)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.45), Color(red: 0.6, green: 0.08, blue: 0.08)],
                                     center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: w * 0.1))
                .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 0.6))
                .frame(width: max(5, w * 0.16), height: max(5, w * 0.16))
                .offset(y: -length)
        }
        .rotationEffect(.degrees(angle), anchor: .center)
        .frame(width: 1, height: 1)
        .overlay {
            Circle().fill(GateMetal.brass)
                .overlay(Circle().stroke(Brass.dark, lineWidth: 0.8))
                .frame(width: max(5, w * 0.17), height: max(5, w * 0.17))
        }
        .position(pivot)
    }
}
