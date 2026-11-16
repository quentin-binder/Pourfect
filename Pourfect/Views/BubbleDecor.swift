import BottleSortCore
import SwiftUI

// Bubbling Bog (chapter 7): the one visual signal of bubbling flasks (D2), drawn the same at
// rest (`BottleView`), in flight (`PourAnimationView`) and in the tips. All sizes follow the
// flask width `w`; positions are in the flask's own frame (0, 0 = top-left of the body).
//
// - Bubbles rise through the potion all the time, livelier when the next rise is one move away
//   (`BubbleStream`).
// - A small brass dial under the flask, like a burner: one segment per move of its period lights
//   up after every move, and the number in the middle is the moves left until the bottom layer
//   rises (`BubbleGauge`).
// - When the bottom layer rises (`TurnEvent.bubbled`), it swells into a big bubble that climbs
//   through the stack while the layers above settle down one place, and flattens out on top
//   (`BubbleRise`).

/// Bog colors: the lit segments and bubbles' green glow, the unlit segments and the dial's face.
enum Bog {
    static let glow = Color(red: 0.70, green: 0.97, blue: 0.50)
    static let dim = Color(red: 0.27, green: 0.36, blue: 0.22)
    static let face = Color(red: 0.08, green: 0.11, blue: 0.08)
}

// MARK: Gauge

/// The bubbling dial under a flask: a brass bezel, `every` segments around a dark face (`filled`
/// of them lit: the moves made since the last rise) and the moves left in the middle. While the
/// bottom layer rises (`rising`) every segment glows and the middle shows an up arrow.
struct BubbleGauge: View {
    let width: CGFloat
    let every: Int
    let filled: Int
    var rising = false

    /// Diameter of the dial, and how far it hangs below the flask's base: all of it, with a
    /// small gap, so it never covers the bottom layer (`bubbleGauge` aligns its bottom edge
    /// on the base, so the drop is a whole diameter plus the gap).
    static func diameter(_ w: CGFloat) -> CGFloat { max(18, w * 0.48) }
    static func drop(_ w: CGFloat) -> CGFloat { diameter(w) + gap(w) }
    static func gap(_ w: CGFloat) -> CGFloat { max(2, w * 0.04) }
    /// Room the dial takes under a flask of width `w` (the board leaves it under every row).
    static func room(_ w: CGFloat) -> CGFloat { drop(w) }

    private var movesLeft: Int { max(1, every - filled) }

    var body: some View {
        let d = Self.diameter(width)
        let last = !rising && movesLeft == 1
        ZStack {
            Circle().fill(LinearGradient(colors: [Brass.light, Brass.mid, Brass.dark],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(Bog.face).padding(d * 0.09)
            ForEach(0..<max(every, 1), id: \.self) { k in
                GaugeSegment(index: k, count: max(every, 1))
                    .stroke(rising || k < filled ? Bog.glow : Bog.dim,
                            style: StrokeStyle(lineWidth: d * 0.12, lineCap: .butt))
                    .padding(d * 0.19)
            }
            if rising {
                Image(systemName: "arrow.up")
                    .font(.system(size: d * 0.34, weight: .black))
                    .foregroundStyle(Bog.glow)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(movesLeft, format: .number)
                    .font(.system(size: d * 0.36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(last ? Bog.glow : .white.opacity(0.92))
                    .contentTransition(.numericText(countsDown: true))
            }
        }
        .frame(width: d, height: d)
        .shadow(color: Bog.glow.opacity(rising ? 0.9 : last ? 0.45 : 0), radius: d * 0.22)
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Segment `index` of `count` around a ring (clockwise from the top), with a small gap.
private struct GaugeSegment: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let step = 360.0 / Double(count)
        let gap = count > 1 ? min(14.0, step * 0.18) : 0
        let start = -90 + Double(index) * step + gap / 2
        return Path { p in
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                     startAngle: .degrees(start), endAngle: .degrees(start + step - gap), clockwise: false)
        }
    }
}

extension View {
    /// Hangs `gauge` under a flask's base (`width` = the flask's width), like a burner.
    func bubbleGauge(_ gauge: Bubbling?, width: CGFloat, rising: Bool = false) -> some View {
        overlay(alignment: .bottom) {
            if let gauge {
                BubbleGauge(width: width, every: gauge.every, filled: rising ? gauge.every : gauge.phase,
                            rising: rising)
                    .offset(y: BubbleGauge.drop(width))
                    .animation(.easeInOut(duration: 0.35), value: rising)
            }
        }
    }
}

// MARK: Bubbles

/// Bubbles rising through the potion of a bubbling flask (`width` × `height` = the flask's body,
/// `level` = height of the potion from the bottom). `eager`: the bottom layer rises after the
/// next move, so more bubbles climb, faster. `paused` (Reduce Motion) keeps them still.
struct BubbleStream: View {
    let width: CGFloat
    let height: CGFloat
    let level: CGFloat
    var eager = false
    var paused = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            let t = paused ? 0.9 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in
                Self.draw(in: &context, t: t, width: width, bottom: height, level: level, eager: eager)
            }
        }
        .frame(width: width, height: height)
        .flaskClip(width: width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// x (0…1), size (in widths), seconds per climb, phase offset (0…1).
    private static let bubbles: [(x: Double, size: Double, climb: Double, offset: Double)] = [
        (0.30, 0.050, 2.6, 0.00), (0.62, 0.040, 2.2, 0.35), (0.46, 0.060, 3.0, 0.70),
        (0.74, 0.035, 2.0, 0.15), (0.22, 0.040, 2.4, 0.55), (0.55, 0.045, 2.8, 0.85),
        (0.38, 0.035, 1.9, 0.25), (0.68, 0.055, 2.5, 0.60), (0.28, 0.030, 2.1, 0.45),
        (0.58, 0.032, 1.8, 0.05),
    ]

    static func draw(in context: inout GraphicsContext, t: Double, width w: CGFloat, bottom: CGFloat,
                     level: CGFloat, eager: Bool) {
        guard level > w * 0.3 else { return }
        let count = eager ? bubbles.count : 6
        let speed = eager ? 1.6 : 1.0
        for (k, b) in bubbles.prefix(count).enumerated() {
            let cycle = (t * speed / b.climb + b.offset).truncatingRemainder(dividingBy: 1)
            let y = bottom - w * 0.12 - CGFloat(cycle) * (level - w * 0.2)
            let x = CGFloat(b.x) * w + CGFloat(sin(t * 2.3 + Double(k) * 1.7)) * w * 0.035
            let r = max(1.1, w * CGFloat(b.size) * CGFloat(0.65 + 0.45 * cycle))
            let fade = min(1, (1 - cycle) * 6) * min(1, cycle * 8)
            guard fade > 0.02 else { continue }
            let circle = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            context.fill(circle, with: .color(.white.opacity(0.14 * fade)))
            context.stroke(circle, with: .color(.white.opacity(0.62 * fade)), lineWidth: max(0.7, r * 0.32))
            let shine = Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.55, width: r * 0.45, height: r * 0.45))
            context.fill(shine, with: .color(.white.opacity(0.8 * fade)))
        }
    }
}

// MARK: Rise

/// One bubbling flask whose bottom layer just rose (`GameViewModel.rises`): animated once after
/// the pour lands, then removed. `layers` / `hidden` are the flask before the rise (bottom first).
struct RiseMark: Identifiable, Equatable {
    let id: Int
    let bottle: Int
    let layers: [Layer]
    let hidden: [Bool]
}

/// Timing of the rise animation.
nonisolated enum RisePose {
    /// The bottom layer gathers into a bubble (0–0.15 s), climbs while the stack settles
    /// (0.12–0.8 s), flattens on top (to 0.9 s) and the bands merge (to 1.0 s).
    static let duration = 1.0
    /// Reduce Motion: the stack cross-fades to its new order.
    static let reducedDuration = 0.45
    /// When the bubble reaches the top (the sound's "bloop").
    static let arrival = 0.78

    static func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(max((t - a) / (b - a), 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// The rise of a bubbling flask's bottom layer, drawn in place of its potion (`width` × `height`
/// = the flask's body): the bottom layer swells into a big bubble that climbs through the stack,
/// trailing small bubbles, while the layers above settle down one place; on top it flattens into
/// the new top layer. A murky bottom layer climbs as "?" and shows its color as it arrives (it is
/// in view on top). `hiddenAfter` is the flask's mask after the rise. With Reduce Motion the
/// stack cross-fades.
struct BubbleRise: View {
    let mark: RiseMark
    let hiddenAfter: [Bool]
    let width: CGFloat
    let height: CGFloat
    let runes: Bool
    let reduceMotion: Bool
    @State private var start = Date()

    private var duration: Double { reduceMotion ? RisePose.reducedDuration : RisePose.duration }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = min(timeline.date.timeIntervalSince(start) / DebugTiming.slow, duration)
            content(t: t)
        }
        .frame(width: width, height: height)
        .flaskClip(width: width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var layerHeight: CGFloat { BottleView.layerHeight(width: width) }
    private var after: [Layer] { Rules.bubbledUp(mark.layers) }

    @ViewBuilder
    private func content(t: Double) -> some View {
        if reduceMotion {
            let p = RisePose.ease(t, 0, RisePose.reducedDuration)
            ZStack(alignment: .bottom) {
                // The old order stays solid under the new one fading in, so the potion never
                // looks thin halfway.
                stack(mark.layers, hidden: mark.hidden)
                stack(after, hidden: hiddenAfter).opacity(p)
            }
        } else {
            let n = mark.layers.count
            let slide = RisePose.ease(t, 0.16, RisePose.arrival)
            let climb = RisePose.ease(t, 0.10, RisePose.arrival + 0.04)
            let merge = RisePose.ease(t, 0.86, 1.0)
            ZStack(alignment: .bottom) {
                // The layers above settle down one place.
                stack(Array(mark.layers.dropFirst()), hidden: Array(mark.hidden.dropFirst()))
                    .offset(y: -CGFloat(1 - slide) * layerHeight)
                trail(t: t, climb: climb, count: n)
                bubble(t: t, climb: climb, count: n)
                // The final bands (a risen layer joins a run of its color) take over at the end.
                stack(after, hidden: hiddenAfter).opacity(merge)
            }
        }
    }

    /// Bands of `layers` from the bottom, like `BottleView` (one gradient per run).
    private func stack(_ layers: [Layer], hidden: [Bool]) -> some View {
        VStack(spacing: 0) {
            ForEach(BottleView.runs(layers, hidden: hidden).reversed(), id: \.start) { run in
                LayerView(layer: run.layer, hidden: run.hidden, count: run.count, height: layerHeight,
                          width: width, runes: runes)
                    .frame(height: CGFloat(run.count) * layerHeight)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }

    /// The rising layer: a band at the bottom that swells into a round bubble, climbs, and
    /// flattens into the top band. Shows "?" while murky until it nears the top.
    @ViewBuilder
    private func bubble(t: Double, climb: Double, count n: Int) -> some View {
        if let layer = mark.layers.first {
            let round = sin(.pi * climb)                       // 0 = flat band … 1 = round bubble
            let gather = t < 0.12 ? sin(t / 0.12 * .pi) * 0.06 : 0   // a small swell before it lets go
            let w = width * CGFloat(1 - 0.36 * round + gather)
            let h = layerHeight * CGFloat(1 - 0.12 * round + gather)
            let y = height - layerHeight * (0.5 + CGFloat(climb) * CGFloat(max(n - 1, 0)))
            let murky = mark.hidden.first == true && climb < 0.85
            let fill = murky ? Palette.hiddenLayer : layer.liquidColor
            RoundedRectangle(cornerRadius: min(w, h) * 0.5 * CGFloat(round), style: .continuous)
                .fill(fill.gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: min(w, h) * 0.5 * CGFloat(round), style: .continuous)
                        .strokeBorder(.white.opacity(0.55 * round), lineWidth: max(1, width * 0.03))
                }
                .overlay(alignment: .topLeading) {
                    // The bubble's shine.
                    Ellipse().fill(.white.opacity(0.5 * round))
                        .frame(width: w * 0.22, height: h * 0.2)
                        .offset(x: w * 0.2, y: h * 0.16)
                }
                .overlay {
                    if murky {
                        Text(verbatim: "?")
                            .font(.system(size: layerHeight * 0.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    } else if case .key(let key) = layer {
                        Image(systemName: "key.fill")
                            .font(.system(size: layerHeight * 0.45, weight: .bold))
                            .rotationEffect(.degrees(-45))
                            .foregroundStyle(Palette.keyColor(key.rawValue))
                    }
                }
                .frame(width: w, height: h)
                .position(x: width / 2, y: y)
                .frame(width: width, height: height, alignment: .topLeading)
        }
    }

    /// Small bubbles left behind the climbing one, and a burst from the bottom as it lets go.
    private func trail(t: Double, climb: Double, count n: Int) -> some View {
        let color = mark.layers.first?.liquidColor ?? .white
        return Canvas { context, _ in
            let bottom = height - layerHeight * 0.5
            let headY = height - layerHeight * (0.5 + CGFloat(climb) * CGFloat(max(n - 1, 0)))
            for k in 0..<9 {
                let born = 0.08 + Double(k) * 0.07
                let age = t - born
                guard age > 0, age < 0.5 else { continue }
                let side = CGFloat(k % 2 == 0 ? -1 : 1) * CGFloat(0.12 + 0.05 * Double(k % 3))
                let x = width * (0.5 + side) + CGFloat(sin(age * 14 + Double(k))) * width * 0.03
                // Each starts at the bubble's tail and drifts up more slowly than it.
                let startY = min(bottom, headY + layerHeight * 0.45)
                let y = startY - CGFloat(age) * layerHeight * 1.4
                let r = max(1, width * CGFloat(0.035 + 0.012 * Double(k % 3)))
                let fade = 1 - age / 0.5
                let circle = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                context.fill(circle, with: .color(color.opacity(0.5 * fade)))
                context.stroke(circle, with: .color(.white.opacity(0.75 * fade)), lineWidth: max(0.7, r * 0.3))
            }
        }
        .frame(width: width, height: height)
    }
}
