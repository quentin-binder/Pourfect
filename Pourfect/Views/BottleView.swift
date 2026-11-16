import BottleSortCore
import SwiftUI

/// One bottle: rounded outline with stacked layers (bottom → top). Draws key layers,
/// a lock badge on locked bottles, "?" for layers the session reports as hidden, and the mark of
/// each flask modifier (essence rune, narrow neck, funnel, spigot, ice with its frost rim,
/// bubbles and the bubbling dial, the cauldron's iron pot and recipe card).
struct BottleView: View {
    let bottle: Bottle
    let width: CGFloat
    /// Per layer (0 = bottom): shown as "?" (from `GameSession.hiddenMasks`; missing = visible).
    var hidden: [Bool] = []
    var isSelected = false
    var hintRole: HintRole?
    var shakes = 0
    /// Goes up each time this bottle becomes complete (`GameViewModel.completions`): the cork
    /// drops in and sparkles burst out of the mouth.
    var completions = 0
    /// Goes up each time this flask's modifier refuses a pour (`GameViewModel.refusals`): its
    /// rune, funnel or spigot flares.
    var refusals = 0
    /// The frozen layers to draw (D1). nil = the bottle's own; the board passes the counters from
    /// before the move while a pour is in the air, so they tick when it lands.
    var ice: [FrozenLayer]? = nil
    /// Layers that just thawed: their ice cracks and melts (`ThawingIce`).
    var thaws: [ThawMark] = []
    /// The bubbling period and phase to show on the dial (D2). nil = the bottle's own; the board
    /// passes the phase from before the move while a pour is in the air, so the dial ticks when
    /// it lands.
    var bubbling: Bubbling? = nil
    /// The bottom layer that just rose (D2): drawn climbing through the stack (`BubbleRise`)
    /// in place of the potion until the mark is removed.
    var rise: RiseMark? = nil
    /// A twin flask (F1): it wears a silver band with rings for the chain (`TwinBand`).
    var twin = false
    /// Goes up each time this twin's chain refuses a pour: the band glints.
    var chainRefusals = 0
    /// The mix that just happened in this cauldron (E1): drawn swirling from the unmixed stack
    /// to the brewed potion (`MixSwirl`) in place of the potion until the mark is removed.
    var mix: MixMark? = nil

    /// A mask with the bottom `count` of `total` layers hidden (tips and previews).
    static func bottomHidden(_ count: Int, of total: Int) -> [Bool] {
        (0..<total).map { $0 < count }
    }

    @Environment(\.colorRunesEnabled) private var runesEnabled
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @Environment(\.flaskStyle) private var flaskStyle
    @Environment(\.potionEffect) private var potionEffect
    @State private var burst: Date?
    /// Replays the cork drop. Follows `completions` only with motion on, so toggling Reduce
    /// Motion never replays a drop.
    @State private var corkDrops = 0

    enum HintRole { case source, target }

    // Bottle geometry, shared with the pour animation so both draw identical bottles.
    static func layerHeight(width: CGFloat) -> CGFloat { width * 0.78 }
    static func height(width: CGFloat, capacity: Int) -> CGFloat {
        CGFloat(capacity) * layerHeight(width: width) + width * 0.45
    }
    /// The flask body in `style` (R7 cosmetics; `.classic` is the original rounded tube).
    static func shape(width: CGFloat, style: FlaskShapeStyle) -> FlaskShape {
        FlaskShape(style: style)
    }
    static let outlineColor = Color.primary.opacity(0.45)
    static let glassColor = Color.primary.opacity(0.05)
    /// Smoky tint behind the glass, so an empty flask still reads on the painted workbench.
    /// The pour animation blends a lifted flask from this to `flightBacking`.
    static let glassBacking = Color.black.opacity(0.3)
    /// Backing of a flask in flight: frosted glass, so flasks it passes in front of don't show
    /// through crisply.
    static let flightBacking = Material.regularMaterial
    /// Dims a locked bottle's contents.
    static let lockedDim = Color.black.opacity(0.4)

    /// The lock drawn over a locked bottle, in its key's color.
    static func lockBadge(_ key: KeyID, width: CGFloat) -> some View {
        Image(systemName: "lock.fill")
            .font(.system(size: width * 0.36, weight: .bold))
            .foregroundStyle(Palette.keyColor(key.rawValue))
            .frame(width: width * 0.72, height: width * 0.72)
            .background(Circle().fill(Color.black.opacity(0.7)))
            .overlay(Circle().strokeBorder(Palette.keyColor(key.rawValue), lineWidth: max(1.5, width * 0.04)))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    private var layerHeight: CGFloat { Self.layerHeight(width: width) }
    private var height: CGFloat { Self.height(width: width, capacity: bottle.capacity) }
    private var shape: FlaskShape { Self.shape(width: width, style: flaskStyle) }

    private var glass: GlassParts { GlassParts(bottle) }

    var body: some View {
        let necked = glass.neck
        ZStack(alignment: .bottom) {
            FlaskGlass(style: Self.glassBacking, width: width, necked: necked)
            FlaskGlass(style: Self.glassColor, width: width, necked: necked)
            if let essence = bottle.essenceColor { shape.fill(EssenceMark.tint(essence)) }
            VStack(spacing: 0) {
                // One view per run of identical visible layers, so a run shares one gradient.
                ForEach(runs.reversed(), id: \.start) { run in
                    LayerView(layer: run.layer, hidden: run.hidden, count: run.count, height: layerHeight,
                              width: width, runes: runesEnabled)
                        .frame(height: CGFloat(run.count) * layerHeight)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
            // Fill the whole bottle before clipping, so the shape's corners land on the glass and the
            // liquid surface stays flat (clipping the shorter stack would round the surface's corners).
            // This matches `TiltedLiquid` in the pour animation.
            .frame(width: width, height: height, alignment: .bottom)
            .clipShape(shape)
            // While the bottom layer rises, `BubbleRise` draws the potion; the bands keep their
            // identity underneath (no transitions when it hands back).
            // The same for a cauldron while it mixes (`MixSwirl`).
            .opacity(rise == nil && mix == nil ? 1 : 0)
            .animation(nil, value: rise == nil && mix == nil)   // swap in the same frame, never cross-fade
            .potionGlow(width: width)
            if let rise {
                BubbleRise(mark: rise, hiddenAfter: hidden, width: width, height: height, runes: runesEnabled,
                           reduceMotion: reduceMotion)
                    .id(rise.id)
                    .transition(.identity)
                    .potionGlow(width: width)
            }
            if let mix {
                MixSwirl(mark: mix, hidden: hidden, width: width, height: height, runes: runesEnabled,
                         reduceMotion: reduceMotion)
                    .id(mix.id)
                    .transition(.identity)
                    .potionGlow(width: width)
            }
            if let gauge = shownBubbling {
                BubbleStream(width: width, height: height, level: CGFloat(bottle.layers.count) * layerHeight,
                             eager: rise == nil && gauge.movesUntilRise == 1, paused: reduceMotion)
            }
            iceLayers
            if !thaws.isEmpty {
                ThawingIce(thaws: thaws, width: width, height: height, reduceMotion: reduceMotion)
            }
            GlassSheen(width: width)
            if let key = bottle.lockedBy {
                shape.fill(Self.lockedDim)
                Self.lockBadge(key, width: width)
                    .frame(maxHeight: .infinity)   // centered on the bottle
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            }
            FlaskOutline(style: outline, width: width, necked: necked,
                         lineWidth: isSelected || hintRole != nil ? 3 : 2)
        }
        .frame(width: width, height: height)
        .cauldronDress(bottle, width: width, height: height, heat: mix == nil ? 0 : 1)
        .overlay(alignment: .topLeading) { spigot }
        .overlay(alignment: .top) { essenceMark }
        .overlay(alignment: .top) {
            if necked {
                NeckCollar(width: width, color: outline)
            } else if !bottle.isCauldron {
                FlaskRim(width: flaskStyle.rimWidth(width), color: outline)
            }
        }
        .overlay(alignment: .top) {
            // The frost stays until the last thawing ice has melted.
            if holdsIce || !thaws.isEmpty { FrostRim(width: width, necked: necked).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.4), value: thaws.isEmpty)
        .overlay(alignment: .top) { funnel }
        .overlay(alignment: .top) { twinBand }
        .bubbleGauge(shownBubbling, width: width, rising: rise != nil)
        .recipeCard(bottle.recipes, width: width, lit: mix?.recipe, glow: mix == nil ? 0 : 1)
        // The card is already lit when the swirl takes over from the pour: light it at once,
        // fade it out when the mix settles.
        .animation(mix == nil ? .easeInOut(duration: 0.35) : nil, value: mix?.id)
        .overlay(alignment: .top) {
            // A cauldron that a mix completes is corked once the swirl has settled (the model
            // counts the completion then, so the cork drops in).
            cork.opacity(mix == nil ? 1 : 0)
        }
        .overlay(alignment: .top) { sparkles }
        .onChange(of: completions) {
            guard !reduceMotion else { return }
            // The completing pour lands inside `withAnimation`; start the drop outside it.
            var plain = Transaction()
            plain.disablesAnimations = true
            withTransaction(plain) { corkDrops += 1 }
            burst = Date().addingTimeInterval(0.12)   // sparkles start as the cork lands
        }
        .offset(y: isSelected ? -width * 0.3 : 0)
        .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
        .animation(.easeInOut(duration: 0.35), value: shakes)
        .shadow(color: hintRole != nil ? .yellow.opacity(0.8) : .clear, radius: 8)
        .contentShape(Rectangle())
    }

    // MARK: Essence flask

    /// The etched rune of an essence flask. Flares (and the flask shakes) when it refuses a pour;
    /// with reduce motion it only brightens, without swelling.
    @ViewBuilder private var essenceMark: some View {
        if let essence = bottle.essenceColor {
            let swells = !reduceMotion
            EssenceMark(color: essence, width: width)
                .keyframeAnimator(initialValue: 0.0, trigger: refusals) { _, flare in
                    EssenceMark(color: essence, width: width, flare: flare, swells: swells)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(1, duration: 0.12, timingCurve: .easeOut)
                        LinearKeyframe(1, duration: 0.25)
                        LinearKeyframe(0, duration: 0.45, timingCurve: .easeIn)
                    }
                }
        }
    }

    // MARK: Frozen layers

    private var frozen: [FrozenLayer] { ice ?? bottle.frozenLayers }
    private var holdsIce: Bool { !frozen.isEmpty }

    /// The ice over each frozen layer with its thaw counter, and frost on the glass. The ice
    /// brightens (and its crystal swells, with motion on) when it refuses a pour.
    @ViewBuilder private var iceLayers: some View {
        if holdsIce {
            let swells = !reduceMotion
            let frozen = self.frozen
            let runes = runesEnabled
            let width = self.width, height = self.height, hidden = self.hidden
            FrostGlass(width: width).transition(.opacity)
            IceLayers(ice: frozen, width: width, height: height, runes: runes, hidden: hidden)
                .keyframeAnimator(initialValue: 0.0, trigger: refusals) { _, flare in
                    IceLayers(ice: frozen, width: width, height: height, runes: runes, hidden: hidden,
                              flare: flare, swells: swells)
                } keyframes: { _ in Self.flareKeyframes }
        }
    }

    // MARK: Bubbling flask

    private var shownBubbling: Bubbling? {
        guard let own = bottle.bubbling else { return nil }
        return bubbling ?? own
    }

    // MARK: Twin flask

    /// The silver band of a twin; glints when the chain refuses a pour.
    @ViewBuilder private var twinBand: some View {
        if twin {
            TwinBand(width: width)
                .keyframeAnimator(initialValue: 0.0, trigger: chainRefusals) { _, flare in
                    TwinBand(width: width, flare: flare)
                } keyframes: { _ in Self.flareKeyframes }
        }
    }

    // MARK: Glass works

    /// The brass funnel in a funnel flask's mouth. It glints and lifts a little when it refuses
    /// to pour (brightens only with reduce motion), and gives way to the cork once the flask is
    /// complete (full of one potion: nothing more can go in or out).
    @ViewBuilder private var funnel: some View {
        if glass.funnel, !isCompleted {
            let swells = !reduceMotion
            FunnelMark(width: width)
                .keyframeAnimator(initialValue: 0.0, trigger: refusals) { _, flare in
                    FunnelMark(width: width, flare: flare, swells: swells)
                } keyframes: { _ in Self.flareKeyframes }
                .transition(reduceMotion ? .opacity : .offset(y: -width * 0.5).combined(with: .opacity))
        }
    }

    /// The brass spigot of a tap flask; glints when the flask refuses a pour.
    @ViewBuilder private var spigot: some View {
        if glass.tap {
            let height = self.height
            SpigotMark(width: width, height: height)
                .keyframeAnimator(initialValue: 0.0, trigger: refusals) { _, flare in
                    SpigotMark(width: width, height: height, flare: flare)
                } keyframes: { _ in Self.flareKeyframes }
        }
    }

    /// The refusal flare of a flask's mark: quick rise, hold, fade.
    private static var flareKeyframes: some Keyframes<Double> {
        KeyframeTrack {
            LinearKeyframe(1, duration: 0.12, timingCurve: .easeOut)
            LinearKeyframe(1, duration: 0.25)
            LinearKeyframe(0, duration: 0.45, timingCurve: .easeIn)
        }
    }

    // MARK: Completed flask

    /// Complete only once the ice shown is gone: a flask beside a pour keeps the ice it had
    /// before the move (`ice`) until the pour lands, and its cork waits for that too.
    private var isCompleted: Bool { frozen.isEmpty && Rules.isCompleted(bottle) }

    /// The cork sits in the mouth while the flask is complete. It drops in when the pour that
    /// completed it lands (`completions` changes) and pops off when the flask stops being complete.
    @ViewBuilder private var cork: some View {
        if isCompleted {
            let place = Cork.placement(for: bottle, width: width, style: flaskStyle)
            Cork(width: place.width)
                .corkDrop(width: width, trigger: corkDrops)
                .offset(y: place.offsetY)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity,
                    removal: .offset(y: -width * 0.7).combined(with: .scale(scale: 0.8)).combined(with: .opacity)))
        }
    }

    @ViewBuilder private var sparkles: some View {
        if let burst, case .color(let id)? = bottle.layers.last {
            let effect = potionEffect
            CompletionBurst(effect: effect, start: burst, color: Palette.color(id.rawValue), width: width)
                .offset(y: -CompletionBurst.size(width: width).height / 2)   // centered on the mouth
                .task(id: burst) {
                    try? await Task.sleep(for: .seconds(burst.timeIntervalSinceNow + CompletionBurst.duration(effect)))
                    if self.burst == burst { self.burst = nil }
                }
        }
    }

    /// Consecutive layers drawn as one band: same color and both visible. Hidden ("?") and
    /// key layers are always bands of their own (each shows its own glyph / flips on its own).
    struct Run { let start: Int; var count: Int; let layer: Layer; let hidden: Bool }

    static func runs(_ layers: [Layer], hidden mask: [Bool]) -> [Run] {
        var runs: [Run] = []
        for (index, layer) in layers.enumerated() {
            let hidden = mask.indices.contains(index) && mask[index]
            if !hidden, !layer.isKey, let last = runs.last, !last.hidden, last.layer == layer {
                runs[runs.count - 1].count += 1
            } else {
                runs.append(Run(start: index, count: 1, layer: layer, hidden: hidden))
            }
        }
        return runs
    }

    private var runs: [Run] { Self.runs(bottle.layers, hidden: hidden) }

    private var outline: Color {
        switch hintRole {
        case .source: return .yellow
        case .target: return .orange
        case nil:
            if isSelected { return .accentColor }
            if let key = bottle.lockedBy { return Palette.keyColor(key.rawValue).opacity(0.8) }
            if holdsIce { return Ice.outline }
            if bottle.isCauldron { return Iron.outline }
            return Self.outlineColor
        }
    }
}

/// One layer. A hidden layer is a grey "?" card that flips over to its real face when revealed.
/// Also drawn by `BubbleRise` while a bubbling flask's stack settles.
struct LayerView: View {
    let layer: Layer
    let hidden: Bool
    /// Layers in this run (one rune is drawn per layer).
    let count: Int
    let height: CGFloat
    let width: CGFloat
    let runes: Bool

    var body: some View {
        face
            .modifier(FlipReveal(angle: hidden ? 180 : 0, hiddenFace: hiddenFace))
            .animation(.easeInOut(duration: 0.45), value: hidden)
    }

    @ViewBuilder private var face: some View {
        switch layer {
        case .color(let id):
            Rectangle().fill(Palette.color(id.rawValue).gradient)
                .overlay {
                    if runes, let rune = Rune(colorIndex: id.rawValue) {
                        VStack(spacing: 0) {
                            ForEach(0..<count, id: \.self) { _ in
                                RuneView(rune: rune, scale: 0.5).frame(width: width, height: height)
                            }
                        }
                    }
                }
        case .key(let key):
            Rectangle().fill(Palette.keyLayer)
                .overlay {
                    Image(systemName: "key.fill")
                        .font(.system(size: height * 0.5, weight: .bold))
                        .rotationEffect(.degrees(-45))
                        .foregroundStyle(Palette.keyColor(key.rawValue))
                }
                .accessibilityLabel(Text("Rune key"))
        }
    }

    private var hiddenFace: some View {
        Rectangle().fill(Palette.hiddenLayer.gradient)
            .overlay {
                Text(verbatim: "?")
                    .font(.system(size: height * 0.55, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.12)).frame(height: 1) }
    }
}

/// Flips around the vertical axis: 0° shows the content, 180° shows `hiddenFace`
/// (swapped at 90°, when the card is edge-on).
private struct FlipReveal<Back: View>: ViewModifier, Animatable {
    var angle: Double
    let hiddenFace: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        ZStack {
            if angle < 90 { content } else { hiddenFace }
        }
        .rotation3DEffect(.degrees(angle < 90 ? angle : 180 - angle), axis: (x: 0, y: 1, z: 0),
                          perspective: 0.4)
    }
}

/// Horizontal wiggle; animate by changing `animatableData` by 1.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: Self.offset(animatableData), y: 0))
    }

    /// The sideways offset at `value` (0 at every whole number); also moves a link's ends.
    static func offset(_ value: CGFloat) -> CGFloat { 7 * sin(value * .pi * 4) }
}
