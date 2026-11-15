import BottleSortCore
import SwiftUI

/// One bottle: rounded outline with stacked layers (bottom → top). Draws key layers,
/// a lock badge on locked bottles, and "?" for layers the session reports as hidden.
struct BottleView: View {
    let bottle: Bottle
    let width: CGFloat
    /// Number of bottom layers shown as "?" (from `GameSession.hiddenDepths`).
    var hiddenLayers = 0
    var isSelected = false
    var hintRole: HintRole?
    var shakes = 0

    enum HintRole { case source, target }

    // Bottle geometry, shared with the pour animation so both draw identical bottles.
    static func layerHeight(width: CGFloat) -> CGFloat { width * 0.78 }
    static func height(width: CGFloat, capacity: Int) -> CGFloat {
        CGFloat(capacity) * layerHeight(width: width) + width * 0.45
    }
    static func shape(width: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: width * 0.12, bottomLeadingRadius: width * 0.45,
                               bottomTrailingRadius: width * 0.45, topTrailingRadius: width * 0.12)
    }
    static let outlineColor = Color.primary.opacity(0.45)
    static let glassColor = Color.primary.opacity(0.05)
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
    private var shape: UnevenRoundedRectangle { Self.shape(width: width) }

    var body: some View {
        ZStack(alignment: .bottom) {
            shape.fill(Self.glassColor)
            VStack(spacing: 0) {
                // One view per run of identical visible layers, so a run shares one gradient.
                ForEach(runs.reversed(), id: \.start) { run in
                    LayerView(layer: run.layer, hidden: run.hidden, height: layerHeight)
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
            if let key = bottle.lockedBy {
                shape.fill(Self.lockedDim)
                Self.lockBadge(key, width: width)
                    .frame(maxHeight: .infinity)   // centered on the bottle
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            }
            shape.strokeBorder(outline, lineWidth: isSelected || hintRole != nil ? 3 : 2)
        }
        .frame(width: width, height: height)
        .offset(y: isSelected ? -width * 0.3 : 0)
        .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
        .animation(.easeInOut(duration: 0.35), value: shakes)
        .shadow(color: hintRole != nil ? .yellow.opacity(0.8) : .clear, radius: 8)
        .contentShape(Rectangle())
    }

    /// Consecutive layers drawn as one band: same color and both visible. Hidden ("?") and
    /// key layers are always bands of their own (each shows its own glyph / flips on its own).
    struct Run { let start: Int; var count: Int; let layer: Layer; let hidden: Bool }

    static func runs(_ layers: [Layer], hiddenLayers: Int) -> [Run] {
        var runs: [Run] = []
        for (index, layer) in layers.enumerated() {
            let hidden = index < hiddenLayers
            if !hidden, !layer.isKey, let last = runs.last, !last.hidden, last.layer == layer {
                runs[runs.count - 1].count += 1
            } else {
                runs.append(Run(start: index, count: 1, layer: layer, hidden: hidden))
            }
        }
        return runs
    }

    private var runs: [Run] { Self.runs(bottle.layers, hiddenLayers: hiddenLayers) }

    private var outline: Color {
        switch hintRole {
        case .source: return .yellow
        case .target: return .orange
        case nil:
            if isSelected { return .accentColor }
            if let key = bottle.lockedBy { return Palette.keyColor(key.rawValue).opacity(0.8) }
            return Self.outlineColor
        }
    }
}

/// One layer. A hidden layer is a grey "?" card that flips over to its real face when revealed.
private struct LayerView: View {
    let layer: Layer
    let hidden: Bool
    let height: CGFloat

    var body: some View {
        face
            .modifier(FlipReveal(angle: hidden ? 180 : 0, hiddenFace: hiddenFace))
            .animation(.easeInOut(duration: 0.45), value: hidden)
    }

    @ViewBuilder private var face: some View {
        switch layer {
        case .color(let id):
            Rectangle().fill(Palette.color(id.rawValue).gradient)
        case .key(let key):
            Rectangle().fill(Palette.keyLayer)
                .overlay {
                    Image(systemName: "key.fill")
                        .font(.system(size: height * 0.5, weight: .bold))
                        .rotationEffect(.degrees(-45))
                        .foregroundStyle(Palette.keyColor(key.rawValue))
                }
                .accessibilityLabel("Key")
        }
    }

    private var hiddenFace: some View {
        Rectangle().fill(Palette.hiddenLayer.gradient)
            .overlay {
                Text("?")
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
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}
