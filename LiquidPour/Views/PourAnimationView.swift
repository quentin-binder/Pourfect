import BottleSortCore
import SwiftUI

/// Collects each bottle's layout frame so the pour animation knows where bottles sit.
struct BottleFramesKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Where every moving part of a pour is at one instant. All values are 0…1 unless noted.
struct PourPose {
    var travel: Double = 0        // source, horizontal: 0 = in its slot, 1 = mouth above the target
    var rise: Double = 0          // source, vertical (leads on the way out, lags on the way back,
                                  // so the bottle crosses the board high above the others)
    var returning = false         // second half: travel back to the resting (unlifted) slot
    var tilt: Double = 0          // 0 = upright, 1 = fully tilted
    var flow: Double = 0          // share of the poured layers already moved
    var streamHead: Double = 0    // stream drawn along its path from `streamTail` to `streamHead`
    var streamTail: Double = 0
    var sourceSlosh: Double = 0   // surface rock, radians
    var targetSlosh: Double = 0
    var corkOff: Double = 0       // a completed source's cork pops off before it tilts
    var time: Double = 0          // seconds since the pour started (timing of an overflow)

    static let duration = 1.1
    static let reducedDuration = 0.4
    /// When liquid moves from source to target (seconds after the pour starts); sound and
    /// haptics time themselves on this. With reduce motion the flow is 0…`reducedDuration`.
    static let flowStart = 0.34
    static let flowEnd = 0.74

    /// The choreography. Lift & fly (0–0.32 s), tilt, stream + flow (0.32–0.74 s),
    /// straighten & return (0.72–1.0 s), surfaces settle (to 1.1 s).
    static func at(_ t: Double, reduceMotion: Bool) -> PourPose {
        var p = PourPose()
        p.time = t
        if reduceMotion {
            p.returning = true   // source stays in its resting slot
            p.flow = ease(t, 0, reducedDuration)
            p.corkOff = ease(t, 0, reducedDuration / 3)
            return p
        }
        p.returning = t > 0.6
        p.travel = p.returning ? 1 - ease(t, 0.76, 0.96) : ease(t, 0.06, 0.32)
        p.rise = p.returning ? 1 - ease(t, 0.84, 1.0) : ease(t, 0, 0.24)
        p.tilt = t < 0.6 ? ease(t, 0.12, 0.36) : 1 - ease(t, 0.72, 0.95)
        p.flow = ease(t, flowStart, flowEnd)
        p.corkOff = ease(t, 0.02, 0.22)
        p.streamHead = ease(t, 0.30, 0.42)
        p.streamTail = ease(t, 0.64, 0.78)   // leaves the lip before the bottle moves away
        let settle = 1 - ease(t, 1.0, duration)   // guarantees a flat surface at the end
        p.targetSlosh = (0.03 * sin(t * 45) * (p.flow > 0 && p.flow < 1 ? 1 : 0)
                         + damped(t, from: 0.74, amplitude: 0.12)) * settle
        p.sourceSlosh = damped(t, from: 0.9, amplitude: 0.12) * settle
        return p
    }

    static func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(max((t - a) / (b - a), 0), 1)
        return x * x * (3 - 2 * x)
    }

    private static func damped(_ t: Double, from start: Double, amplitude: Double) -> Double {
        guard t > start else { return 0 }
        let dt = t - start
        return amplitude * exp(-dt * 10) * sin(dt * 30)
    }
}

/// Animates one `PourEvent`: the source bottle flies over the target, tilts, a stream falls
/// while both levels change continuously, and the source flies back. Draws on top of the board
/// (the board hides the two real bottles meanwhile). Purely visual: the move is already applied.
///
/// A tap flask (C4, `event.fromBottom`) doesn't tilt: it flies so its spigot hangs over the
/// target's mouth, the valve turns, a stream runs from the nozzle, and its bottom layers drain
/// while the stack above slides down. A narrow neck (C2) pours from its neck's lip in a thin
/// stream; a funnel target catches the stream in its cone.
///
/// Ice (D1) stays put: a frozen layer and everything under it don't tilt or slosh
/// (`TiltedLiquid.rigidLayers`), only the potion above it pours; both flasks keep their ice,
/// counters and frost rim from before the move. The counters tick and thawed ice melts on the
/// board once the pour has landed (`ThawingIce`).
///
/// A bubbling flask (D2) flies with its dial (the phase from before the move) and its bubbles,
/// which fade while it tilts. A rise caused by the move plays on the board after the pour has
/// landed (`BubbleRise`).
///
/// A cauldron (E1) keeps its iron pot and rim in flight; its recipe card stays on the board
/// (under the source's resting place, under the target where it stands). When the pour mixes,
/// the target's card lights the recipe while it flows; the swirl into the new potion plays on
/// the board after the pour has landed (`MixSwirl`): in flight the poured potion simply lands
/// on the other ingredient.
///
/// Twins (F1): the source hovers between the two twins and its stream forks, half into each;
/// both fill together. An overflow pipe (F2): the target fills to the rim, then the rest runs
/// visibly through the pipe and drips into the flask at its far end, which fills after it.
/// Chains and pipes touching a flask drawn here are drawn here too, above those flasks.
/// A link drawn by the pour animation, between two flasks' frames.
struct PourLink {
    let link: BottleSortCore.Link
    let a: CGRect
    let b: CGRect
    /// A switch link: its gate is shown open (1) or shut (0), as it was before the move.
    var open: Double = 0
    var gateRise: CGFloat = 0
}

struct PourAnimationView: View {
    let event: GameViewModel.PourEvent
    let sourceFrame: CGRect
    let targetFrame: CGRect
    /// Frames of the other flasks the pour fills (`event.shares`), by bottle index.
    var shareFrames: [Int: CGRect] = [:]
    /// Links whose flasks this view draws (but not the source), with both flasks' frames (a
    /// switch link with its gate shown open or shut as before the move, and its gate's rise).
    var links: [PourLink] = []
    let boardSize: CGSize
    let reduceMotion: Bool
    let onFinish: () -> Void

    @Environment(\.colorRunesEnabled) private var runesEnabled
    @State private var start = Date()

    private var duration: Double { reduceMotion ? PourPose.reducedDuration : PourPose.duration }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = min(timeline.date.timeIntervalSince(start) / DebugTiming.slow, duration)
            let pose = PourPose.at(t, reduceMotion: reduceMotion)
            if event.fromBottom { tapFrame(pose) } else { frame(pose) }
        }
        .allowsHitTesting(false)
        .task(id: event.id) {
            try? await Task.sleep(for: .seconds(duration * DebugTiming.slow))
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    // MARK: One frame

    private var width: CGFloat { sourceFrame.width }
    private var height: CGFloat { sourceFrame.height }
    private var layerHeight: CGFloat { BottleView.layerHeight(width: targetFrame.width) }
    private var color: Color { event.layer.liquidColor }
    private var sourceParts: GlassParts { GlassParts(event.sourceBefore) }
    private var targetParts: GlassParts { GlassParts(event.targetBefore) }

    /// Width of the falling stream: thin through a narrow neck (one layer trickles), a little
    /// thinner from a spigot than from a lip.
    private var streamWidth: CGFloat {
        if sourceParts.neck || targetParts.neck { return width * 0.07 }
        return event.fromBottom ? width * 0.11 : width * 0.14
    }

    private func surfaceY(_ target: CGRect, flow: Double) -> CGFloat {
        target.maxY - layerHeight * (CGFloat(event.targetBefore.layers.count) + CGFloat(event.targetAmount) * targetFill(flow))
    }

    // MARK: Twins and overflow

    /// The twin that shares a split pour, with its frame.
    private var twinShare: (landing: GameViewModel.Landing, frame: CGRect)? {
        guard let share = event.shares.first(where: { $0.route == .twin }), let frame = shareFrames[share.bottle] else { return nil }
        return (share, frame)
    }

    /// The far end of the target's overflow pipe, when part of the pour runs on into it.
    private var overflowShare: (landing: GameViewModel.Landing, frame: CGRect)? {
        guard let share = event.overflow, let frame = shareFrames[share.bottle] else { return nil }
        return (share, frame)
    }

    /// Where the source pours: over the target, or over the middle of a split between twins.
    private var aimFrame: CGRect {
        guard let twin = twinShare?.frame else { return targetFrame }
        return CGRect(x: (targetFrame.midX + twin.midX) / 2 - targetFrame.width / 2, y: min(targetFrame.minY, twin.minY),
                      width: targetFrame.width, height: targetFrame.height)
    }

    /// How far the target has filled (0…1 of `targetAmount`): with an overflow it fills first,
    /// up to the rim, and the rest of the flow runs on through the pipe.
    private func targetFill(_ flow: Double) -> Double {
        guard event.overflow != nil else { return flow }
        let share = Double(event.targetAmount) / Double(max(1, event.amount))
        return share > 0 ? min(1, flow / share) : 1
    }

    /// 0…1 while the overflow runs through the pipe and into the far flask: it starts when the
    /// target is full and ends a little after the stream (the pipe still drains).
    private func overflowProgress(_ pose: PourPose) -> Double {
        if reduceMotion { return pose.flow }
        let share = Double(event.targetAmount) / Double(max(1, event.amount))
        let start = PourPose.flowStart + share * (PourPose.flowEnd - PourPose.flowStart)
        return PourPose.ease(pose.time, start, PourPose.flowEnd + 0.22)
    }

    /// A flask the pour fills besides the target, filling with `fill` (0…1 of its share).
    private func shareSegments(_ share: GameViewModel.Landing, fill: Double) -> [LiquidSegment] {
        let kept = share.before.layers.enumerated().map { i, layer in
            segment(layer, index: i, hidden: share.hiddenBefore, fraction: 1)
        }
        return kept + Array(repeating: LiquidSegment(color: color, fraction: fill, rune: rune(for: event.layer)),
                            count: share.amount)
    }

    private func shareSurfaceY(_ share: GameViewModel.Landing, frame: CGRect, fill: Double) -> CGFloat {
        frame.maxY - layerHeight * (CGFloat(share.before.layers.count) + CGFloat(share.amount) * fill)
    }

    /// The flasks the pour fills besides the target (the twin, the pipe's far end), and the
    /// links between the flasks drawn here, above them.
    @ViewBuilder
    private func receivers(_ pose: PourPose) -> some View {
        ForEach(event.shares, id: \.bottle) { share in
            if let frame = shareFrames[share.bottle] {
                let fill = share.route == .twin ? pose.flow : PourPose.ease(overflowProgress(pose), 0.3, 0.95)
                bottle(share.before, segments: shareSegments(share, fill: fill), frame: frame,
                       gravity: share.route == .twin ? pose.targetSlosh : 0, hidden: share.hiddenBefore,
                       twin: share.route == .twin)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        ForEach(links.indices, id: \.self) { i in
            LinkView(link: links[i].link, a: links[i].a, b: links[i].b, open: links[i].open,
                     gateRise: links[i].gateRise)
        }
    }

    /// The overflow running through the pipe: a band of potion travels along the tube from the
    /// target's rim, then drips from the nozzle onto the far flask's rising surface. With Reduce
    /// Motion the filled tube fades in and out instead.
    @ViewBuilder
    private func pipeFlow(_ pose: PourPose) -> some View {
        if let overflow = overflowShare {
            let pipe = PipeGeometry(from: targetFrame, to: overflow.frame)
            let q = overflowProgress(pose)
            let fill = PourPose.ease(q, 0.3, 0.95)
            let liquid = StrokeStyle(lineWidth: pipe.tube * 0.55, lineCap: .round)
            let drip = Path { p in
                p.move(to: pipe.end)
                p.addLine(to: CGPoint(x: pipe.end.x, y: max(pipe.end.y + 2,
                                                            shareSurfaceY(overflow.landing, frame: overflow.frame, fill: fill))))
            }
            if reduceMotion {
                let glow = sin(.pi * q)
                pipe.path.stroke(color, style: liquid).opacity(glow)
                drip.stroke(color, style: StrokeStyle(lineWidth: pipe.tube * 0.4, lineCap: .round)).opacity(glow)
            } else {
                let head = PourPose.ease(q, 0, 0.38), tail = PourPose.ease(q, 0.62, 1)
                if head > tail + 0.001 {
                    pipe.path.trimmedPath(from: tail, to: head).stroke(color.gradient, style: liquid)
                }
                let dripHead = PourPose.ease(q, 0.3, 0.42), dripTail = PourPose.ease(q, 0.88, 1)
                if dripHead > dripTail + 0.001 {
                    drip.trimmedPath(from: dripTail, to: dripHead)
                        .stroke(color.gradient, style: StrokeStyle(lineWidth: pipe.tube * 0.4, lineCap: .round))
                }
            }
        }
    }

    /// A split pour's stream: it leaves the lip, falls to a point between the twins and forks,
    /// one branch into each twin's mouth onto its rising surface.
    @ViewBuilder
    private func splitStream(from lip: CGPoint, right: Bool, pose: PourPose) -> some View {
        if let twin = twinShare, pose.streamHead > pose.streamTail + 0.001 {
            let dir: CGFloat = right ? 1 : -1
            let start = CGPoint(x: lip.x + dir * width * 0.04, y: lip.y)
            let fork = CGPoint(x: lip.x + dir * width * 0.14, y: max(lip.y + width * 0.3, aimFrame.minY - width * 0.4))
            let ends = [
                CGPoint(x: targetFrame.midX, y: surfaceY(targetFrame, flow: pose.flow)),
                CGPoint(x: twin.frame.midX, y: shareSurfaceY(twin.landing, frame: twin.frame, fill: pose.flow)),
            ]
            ForEach(ends.indices, id: \.self) { i in
                let end = ends[i]
                Path { p in
                    p.move(to: start)
                    p.addQuadCurve(to: fork, control: CGPoint(x: lip.x + dir * width * 0.16, y: lip.y + width * 0.08))
                    p.addQuadCurve(to: CGPoint(x: end.x, y: max(end.y, fork.y + width * 0.2)),
                                   control: CGPoint(x: fork.x + (end.x - fork.x) * 0.9, y: fork.y + width * 0.1))
                }
                .trimmedPath(from: pose.streamTail, to: pose.streamHead)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: streamWidth * 0.8, lineCap: .round))
            }
        }
    }

    private func frame(_ pose: PourPose) -> some View {
        let right = pourToRight
        let sign: Double = right ? 1 : -1
        let angle = sign * pose.tilt * pourAngle(flow: pose.flow)      // degrees
        let lip = lipPosition(pose, right: right)
        // A narrow neck pours from its neck's lip, not the body's corner: the flask is shifted
        // (more as it tilts) so the neck's lip ends where the corner would have been.
        let neck = sourceParts.neck ? Self.rotated(NarrowNeck.lipOffset(width, right: right), degrees: angle) : .zero
        let corner = CGPoint(x: lip.x - neck.x * pose.tilt, y: lip.y - neck.y * pose.tilt)
        let spout = CGPoint(x: corner.x + neck.x, y: corner.y + neck.y)

        return ZStack(alignment: .topLeading) {
            bottle(event.targetBefore, segments: targetSegments(pose.flow), frame: targetFrame,
                   gravity: pose.targetSlosh, hidden: event.targetHiddenBefore, drawsMarks: false, unlock: unlockProgress(pose),
                   twin: event.twins.contains(event.to), card: mixGlow(pose))
                .position(x: targetFrame.midX, y: targetFrame.midY)
            sourceCard
            receivers(pose)
            pipeFlow(pose)

            if event.isKey {
                fallingKey(from: spout, pose: pose)
            }

            bottle(event.sourceBefore, segments: sourceSegments(pose.flow), frame: sourceFrame,
                   gravity: angle * .pi / 180 + pose.sourceSlosh, hidden: event.sourceHiddenBefore,
                   corkOff: Rules.isCompleted(event.sourceBefore) ? pose.corkOff : nil,
                   opaque: min(1, pose.rise * 1.6),   // opaque before it crosses another flask
                   bubbles: 1 - min(1, pose.tilt * 2), twin: event.twins.contains(event.from))
                .shadow(color: .black.opacity(0.2 * pose.rise), radius: 6, y: 3)   // lifts it off the board
                .rotationEffect(.degrees(angle), anchor: right ? .topTrailing : .topLeading)
                // The rotation anchor is the pouring corner, so place the frame by that corner.
                .position(x: corner.x + (right ? -width / 2 : width / 2), y: corner.y + height / 2)

            // On top of both bottles: the stream leaves the lip in front of the tilted source and
            // falls through the target's glass onto its rising surface.
            if event.isKey {
            } else if twinShare != nil {
                splitStream(from: spout, right: right, pose: pose)
            } else {
                stream(from: spout, toY: surfaceY(targetFrame, flow: pose.flow), right: right, pose: pose)
            }

            targetMarks(pose, frame: targetFrame)
        }
        .frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading)
    }

    /// The target's marks on the front of its glass, drawn above the stream: the rune (it glows
    /// while its color flows in) and the funnel (the stream runs into its cone).
    @ViewBuilder
    private func targetMarks(_ pose: PourPose, frame: CGRect) -> some View {
        if let essence = event.targetBefore.essenceColor {
            EssenceMark(color: essence, width: frame.width, glow: essenceGlow(pose))
                .frame(width: frame.width, height: frame.height, alignment: .top)
                .position(x: frame.midX, y: frame.midY)
        }
        if targetParts.funnel, !Rules.isCompleted(event.targetBefore) {
            FunnelMark(width: frame.width)
                .frame(width: frame.width, height: frame.height, alignment: .top)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    /// One flask as drawn in flight, from its state before the move (`model` gives the glass
    /// parts, the rune and the seal).
    /// `unlock`: a sealed flask shows its lock (and dimmed contents) until the key lands; then
    /// the lock pops away (0 → 1).
    /// `corkOff`: a cork on a completed source, 0 = seated … 1 = popped off and gone.
    /// `opaque`: 0 = see-through glass like at rest … 1 = frosted backing (a lifted source).
    /// `drawsMarks`: false when the caller draws the rune and funnel itself, above the stream.
    /// `valve`: a tap's handle, 0 = closed … 1 = open.
    private func bottle(_ model: Bottle, segments: [LiquidSegment], frame: CGRect, gravity: Double,
                        hidden: [Bool] = [], drawsMarks: Bool = true, unlock: Double = 0, corkOff: Double? = nil,
                        opaque: Double = 0, valve: Double = 0, bubbles: Double = 1, twin: Bool = false,
                        card: Double? = nil) -> some View {
        let w = frame.width
        let shape = BottleView.shape(width: w)
        let parts = GlassParts(model)
        let essence = model.essenceColor
        let lock = model.lockedBy
        let ice = model.frozenLayers
        // Same outline as at rest (`BottleView`): the seal's metal, else frosted or plain glass.
        let plainOutline = !ice.isEmpty ? Ice.outline : model.isCauldron ? Iron.outline : BottleView.outlineColor
        let sealOutline = lock.map { Palette.keyColor($0.rawValue).opacity(0.8) }
        let cork = Cork.placement(for: model, width: w)
        return ZStack {
            // Same smoky backing as at rest; a lifted flask turns to frosted glass so bottles it
            // passes in front of don't show through.
            FlaskGlass(style: BottleView.glassBacking, width: w, necked: parts.neck)
            FlaskGlass(style: BottleView.flightBacking, width: w, necked: parts.neck).opacity(opaque)
            FlaskGlass(style: BottleView.glassColor, width: w, necked: parts.neck)
            if let essence { shape.fill(EssenceMark.tint(essence)) }
            TiltedLiquid(segments: segments, layerHeight: BottleView.layerHeight(width: w),
                         gravity: gravity, rigidLayers: Self.rigidLayers(model))
                .clipShape(shape)
                .potionGlow(width: w)
            if let gauge = model.bubbling, bubbles > 0.01 {
                let level = segments.reduce(CGFloat(0)) { $0 + $1.fraction } * BottleView.layerHeight(width: w)
                BubbleStream(width: w, height: frame.height, level: level, eager: gauge.movesUntilRise == 1,
                             paused: reduceMotion)
                    .opacity(bubbles)
            }
            if !ice.isEmpty {
                FrostGlass(width: w)
                IceLayers(ice: ice, width: w, height: frame.height, runes: runesEnabled, hidden: hidden)
            }
            GlassSheen(width: w)
            if let lock {
                shape.fill(BottleView.lockedDim.opacity(1 - unlock))
                BottleView.lockBadge(lock, width: w)
                    .scaleEffect(1 + 0.6 * unlock)
                    .opacity(1 - unlock)
            }
            FlaskOutline(style: plainOutline, width: w, necked: parts.neck, lineWidth: 2)
                .opacity(sealOutline == nil ? 1 : unlock)
            if let sealOutline {
                // The seal's metal outline fades into the flask's own as the lock pops away.
                FlaskOutline(style: sealOutline, width: w, necked: parts.neck, lineWidth: 2).opacity(1 - unlock)
            }
        }
        .frame(width: w, height: frame.height)
        .cauldronDress(model, width: w, height: frame.height, heat: card ?? 0, embers: card != nil)
        .bubbleGauge(model.bubbling, width: w)
        .recipeCard(card == nil ? [] : model.recipes, width: w, lit: event.mix?.recipe, glow: card ?? 0)
        .overlay(alignment: .topLeading) {
            if parts.tap { SpigotMark(width: w, height: frame.height, valve: valve) }
        }
        .overlay(alignment: .top) {
            if let essence, drawsMarks { EssenceMark(color: essence, width: w) }
        }
        .overlay(alignment: .top) {
            let outline = unlock < 0.5 ? sealOutline ?? plainOutline : plainOutline
            if parts.neck {
                NeckCollar(width: w, color: outline)
            } else if !model.isCauldron {
                FlaskRim(width: w, color: outline)
            }
        }
        .overlay(alignment: .top) {
            if !ice.isEmpty { FrostRim(width: w, necked: parts.neck) }
        }
        .overlay(alignment: .top) {
            if parts.funnel, drawsMarks, !Rules.isCompleted(model) { FunnelMark(width: w) }
        }
        .overlay(alignment: .top) {
            if twin { TwinBand(width: w) }
        }
        .overlay(alignment: .top) {
            // Same place as `BottleView`'s cork; pops up and fades like its removal transition.
            if let corkOff, corkOff < 1 {
                Cork(width: cork.width)
                    .scaleEffect(1 - 0.2 * corkOff)
                    .offset(y: cork.offsetY - w * 0.7 * corkOff)
                    .opacity(1 - corkOff)
            }
        }
    }

    /// Bottom layers of `bottle` that can't move: its highest frozen layer and everything under it.
    private static func rigidLayers(_ bottle: Bottle) -> Int {
        (bottle.frozenLayers.map(\.layer).max() ?? -1) + 1
    }

    /// Layer `index` of a bottle whose layers flagged in `hidden` show as "?", drawn like
    /// `BottleView` (grey "?" card, or a key slot with its icon).
    private func segment(_ layer: Layer, index: Int, hidden: [Bool], fraction: CGFloat) -> LiquidSegment {
        if hidden.indices.contains(index), hidden[index] {
            return LiquidSegment(color: Palette.hiddenLayer, fraction: fraction, glyph: .hidden)
        }
        if case .key(let key) = layer {
            return LiquidSegment(color: layer.liquidColor, fraction: fraction, glyph: .key(Palette.keyColor(key.rawValue)))
        }
        return LiquidSegment(color: layer.liquidColor, fraction: fraction, rune: rune(for: layer))
    }

    /// The layer's colorblind rune, when runes are on (never on key layers).
    private func rune(for layer: Layer) -> Rune? {
        guard runesEnabled, case .color(let id) = layer else { return nil }
        return Rune(colorIndex: id.rawValue)
    }

    /// Source keeps its layers; the poured ones (the top run, or a tap's bottom run) shrink as
    /// `flow` grows, so a tap's stack slides down as its bottom drains.
    /// A key leaves in one piece as soon as it starts to fall.
    private func sourceSegments(_ flow: Double) -> [LiquidSegment] {
        let layers = event.sourceBefore.layers
        let leaving = event.isKey ? (flow > 0.001 ? 0 : 1) : 1 - flow
        let moved = event.fromBottom ? 0..<event.amount : (layers.count - event.amount)..<layers.count
        return layers.enumerated().map { i, layer in
            segment(layer, index: i, hidden: event.sourceHiddenBefore, fraction: moved.contains(i) ? leaving : 1)
        }
    }

    /// Target keeps its layers and gains `amount` layers that grow with `flow`
    /// (none for a key: it is consumed by the lock).
    private func targetSegments(_ flow: Double) -> [LiquidSegment] {
        let kept = event.targetBefore.layers.enumerated().map { i, layer in
            segment(layer, index: i, hidden: event.targetHiddenBefore, fraction: 1)
        }
        if event.isKey { return kept }
        return kept + Array(repeating: LiquidSegment(color: color, fraction: targetFill(flow), rune: rune(for: event.layer)),
                            count: event.targetAmount)
    }

    // MARK: Tap pour

    /// A bottom pour: the tap flask flies upright until its nozzle hangs over the target's mouth,
    /// the valve turns open, the stream runs while the bottom run drains (the stack slides
    /// down), the valve closes and the flask flies back.
    private func tapFrame(_ pose: PourPose) -> some View {
        let place = tapPlacement
        let home = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY - (pose.returning ? 0 : width * 0.3))
        let over = place.center
        let up = over.y <= home.y
        let center = CGPoint(x: home.x + (over.x - home.x) * (up ? pose.travel : pose.rise),
                             y: home.y + (over.y - home.y) * (up ? pose.rise : pose.travel))
        // Without room above the target, it slides down under the tap and back.
        let target = targetFrame.offsetBy(dx: 0, dy: place.targetDrop * pose.travel)
        let nozzle = Spigot.nozzle(width: width, height: height)
        let tip = CGPoint(x: center.x - width / 2 + nozzle.x, y: center.y - height / 2 + nozzle.y)
        let mouth = CGPoint(x: target.midX, y: target.minY - targetParts.rise(target.width))

        return ZStack(alignment: .topLeading) {
            bottle(event.targetBefore, segments: targetSegments(pose.flow), frame: target,
                   gravity: pose.targetSlosh, hidden: event.targetHiddenBefore, drawsMarks: false, unlock: unlockProgress(pose),
                   twin: event.twins.contains(event.to), card: mixGlow(pose))
                .position(x: target.midX, y: target.midY)
            sourceCard
            receivers(pose)
            pipeFlow(pose)

            bottle(event.sourceBefore, segments: sourceSegments(pose.flow), frame: sourceFrame,
                   gravity: pose.sourceSlosh * 0.5, hidden: event.sourceHiddenBefore,
                   corkOff: Rules.isCompleted(event.sourceBefore) ? pose.corkOff : nil,
                   opaque: min(1, pose.rise * 1.6), valve: pose.tilt)
                .shadow(color: .black.opacity(0.2 * pose.rise), radius: 6, y: 3)
                .position(center)

            if event.isKey {
                fallingKey(from: tip, to: CGPoint(x: target.midX, y: target.midY), pose: pose)
            } else {
                tapStream(from: tip, mouth: mouth, toY: surfaceY(target, flow: pose.flow), pose: pose)
            }

            targetMarks(pose, frame: target)
        }
        .frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading)
    }

    /// Where the tap flask's center hangs while it pours, and how far the target slides down to
    /// get under it when the board has no room above the target (a top-row target).
    private var tapPlacement: (center: CGPoint, targetDrop: CGFloat) {
        let nozzle = Spigot.nozzle(width: width, height: height)
        let tipY = targetFrame.minY - targetParts.rise(targetFrame.width) - width * 0.22
        // The nozzle over the target's mouth, unless the flask would leave the board: then the
        // stream bends a little to reach the mouth.
        let ideal = targetFrame.midX - nozzle.x + width / 2
        let minX = width / 2 - 12
        let maxX = boardSize.width + 12 - (nozzle.x + Spigot.protrusion(width) - width / 2)
        let x = min(max(ideal, minX), max(minX, maxX))
        var y = tipY - nozzle.y + height / 2
        let topLimit: CGFloat = -24   // just into the space under the HUD
        var drop: CGFloat = 0
        if y - height / 2 < topLimit {
            drop = topLimit - (y - height / 2)
            y += drop
        }
        return (CGPoint(x: x, y: y), drop)
    }

    /// The stream from the spigot's nozzle: straight down into the target's mouth (bending a
    /// little when the nozzle couldn't hang right above it), then onto the rising surface.
    @ViewBuilder
    private func tapStream(from tip: CGPoint, mouth: CGPoint, toY surfaceY: CGFloat, pose: PourPose) -> some View {
        if pose.streamHead > pose.streamTail + 0.001 {
            let end = CGPoint(x: mouth.x, y: max(surfaceY, mouth.y + width * 0.2))
            let path = Path { p in
                p.move(to: tip)
                if abs(mouth.x - tip.x) > 1 {
                    p.addQuadCurve(to: mouth, control: CGPoint(x: tip.x, y: (tip.y + mouth.y) / 2))
                }
                p.addLine(to: end)
            }
            .trimmedPath(from: pose.streamTail, to: pose.streamHead)
            path.stroke(color.gradient, style: StrokeStyle(lineWidth: streamWidth, lineCap: .round))
        }
    }

    // MARK: Cauldron

    /// How brightly the target cauldron's card lights the mixing recipe (0 → 1 while the potion
    /// flows in, held until the board's swirl takes over). nil: the card isn't lit, 0 for a
    /// cauldron that doesn't mix.
    private func mixGlow(_ pose: PourPose) -> Double {
        guard event.mix != nil else { return 0 }
        return PourPose.ease(pose.flow, 0, 0.4)
    }

    /// A cauldron source's recipe card and ember glow stay at their resting place while the
    /// flask flies (the flying source is drawn without embers).
    @ViewBuilder
    private var sourceCard: some View {
        let recipes = event.sourceBefore.recipes
        if !recipes.isEmpty {
            Color.clear
                .frame(width: sourceFrame.width, height: sourceFrame.height)
                .cauldronEmbers(width: sourceFrame.width, height: sourceFrame.height)
                .recipeCard(recipes, width: sourceFrame.width)
                .position(x: sourceFrame.midX, y: sourceFrame.midY)
        }
    }

    // MARK: Essence

    /// The target's rune glows up while its own color flows in (0 → 1 → 0 over the flow).
    private func essenceGlow(_ pose: PourPose) -> Double {
        guard event.targetBefore.essenceColor != nil, !event.isKey else { return 0 }
        return sin(.pi * pose.flow)
    }

    // MARK: Key pour

    /// 0 → 1 while the lock pops off, after the key has dropped in.
    private func unlockProgress(_ pose: PourPose) -> Double {
        guard event.isKey else { return 0 }
        let x = min(max((pose.flow - 0.75) / 0.25, 0), 1)
        return x * x
    }

    /// The key falls from the lip (or the nozzle) into the lock at the target's center,
    /// shrinking as it enters.
    @ViewBuilder
    private func fallingKey(from lip: CGPoint, to end: CGPoint? = nil, pose: PourPose) -> some View {
        if case .key(let key) = event.layer, pose.flow > 0.001, pose.flow < 0.8 {
            let p = min(pose.flow / 0.75, 1)
            let end = end ?? CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            Image(systemName: "key.fill")
                .font(.system(size: width * 0.42, weight: .bold))
                .foregroundStyle(Palette.keyColor(key.rawValue))
                .rotationEffect(.degrees(-45 + 135 * p))
                .scaleEffect(1 - 0.5 * p)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .position(x: lip.x + (end.x - lip.x) * p, y: lip.y + (end.y - lip.y) * p * p)
        }
    }

    // MARK: Positions

    /// `v` turned by `degrees` clockwise on screen (like `rotationEffect`).
    private static func rotated(_ v: CGPoint, degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: v.x * cos(a) - v.y * sin(a), y: v.x * sin(a) + v.y * cos(a))
    }

    /// Mouth corner the liquid leaves from, in board coordinates.
    private func lipPosition(_ pose: PourPose, right: Bool) -> CGPoint {
        let corner = { (r: CGRect, lift: CGFloat) in
            CGPoint(x: right ? r.maxX : r.minX, y: r.minY - lift)
        }
        // Starts from the selection lift (see BottleView), lands back at rest.
        let home = pose.returning ? corner(sourceFrame, 0) : corner(sourceFrame, width * 0.3)
        let over = pourPoint(right: right)
        // Going up: rise first, then across. Going down (top row → bottom row): across first.
        let up = over.y <= home.y
        return CGPoint(x: home.x + (over.x - home.x) * (up ? pose.travel : pose.rise),
                       y: home.y + (over.y - home.y) * (up ? pose.rise : pose.travel))
    }

    /// Tilt (degrees from upright) at which the liquid left in the source just reaches the lip,
    /// so the stream always leaves from the liquid surface. Steeper as the bottle empties.
    /// Uses the bottle's bounding rectangle tilted about its top corner.
    /// Frozen layers (D1) stay at the bottom: only the free potion above them counts, in the
    /// part of the flask above the ice.
    private func pourAngle(flow: Double) -> Double {
        let rigid = CGFloat(Self.rigidLayers(event.sourceBefore))
        let layers = CGFloat(event.sourceBefore.layers.count) - rigid - CGFloat(event.amount) * flow
        let liquid = max(0, layers) * BottleView.layerHeight(width: width) * width
        let w = width, h = height - rigid * BottleView.layerHeight(width: width)
        let belowLip = { (radians: Double) -> CGFloat in
            let t = tan(radians)
            return w * t <= h ? w * h - w * w * t / 2 : h * h / (2 * t)
        }
        var low = 0.0, high = Double.pi / 2 - 0.01
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if belowLip(mid) > liquid { low = mid } else { high = mid }
        }
        return min(max(low * 180 / .pi + 4, 55), 86)
    }

    /// Where the lip hovers while pouring: just off-center over the target's mouth, high enough
    /// that the tilted body clears the bottles below (and the target's neck or funnel).
    private func pourPoint(right: Bool) -> CGPoint {
        let gap = height * cos(pourAngle(flow: 0) * .pi / 180) + width * 0.15 + targetParts.rise(targetFrame.width)
        let aim = aimFrame
        return CGPoint(x: aim.midX + (right ? -1 : 1) * width * 0.12, y: aim.minY - gap)
    }

    /// Pour toward the target from the side the source comes from, unless the tilted body would
    /// leave the board on that side.
    private var pourToRight: Bool {
        let preferred: Bool
        let aim = aimFrame
        if abs(sourceFrame.midX - aim.midX) > 1 {
            preferred = sourceFrame.midX < aim.midX
        } else {
            preferred = aim.midX > boardSize.width / 2
        }
        let reach = height + width * 0.25                               // body extent from the lip
        let fits = { (right: Bool) -> Bool in
            let x = pourPoint(right: right).x
            return right ? x - reach >= -16 : x + reach <= boardSize.width + 16
        }
        return fits(preferred) || !fits(!preferred) ? preferred : !preferred
    }

    // MARK: Stream

    @ViewBuilder
    private func stream(from lip: CGPoint, toY surfaceY: CGFloat, right: Bool, pose: PourPose) -> some View {
        if pose.streamHead > pose.streamTail + 0.001 {
            let dir: CGFloat = right ? 1 : -1
            let start = CGPoint(x: lip.x + dir * width * 0.04, y: lip.y)
            let end = CGPoint(x: lip.x + dir * width * 0.16, y: max(surfaceY, lip.y + width * 0.3))
            let path = Path { p in
                p.move(to: start)
                p.addQuadCurve(to: end, control: CGPoint(x: lip.x + dir * width * 0.16, y: lip.y + width * 0.08))
            }
            .trimmedPath(from: pose.streamTail, to: pose.streamHead)
            path.stroke(color.gradient, style: StrokeStyle(lineWidth: streamWidth, lineCap: .round))
        }
    }
}
