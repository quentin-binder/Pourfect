import BottleSortCore
import SwiftUI

/// One bottle: rounded outline with stacked colored layers (bottom → top).
struct BottleView: View {
    let bottle: Bottle
    let width: CGFloat
    var isSelected = false
    var hintRole: HintRole?
    var shakes = 0

    enum HintRole { case source, target }

    private var layerHeight: CGFloat { width * 0.78 }
    private var neck: CGFloat { width * 0.45 }
    private var height: CGFloat { CGFloat(bottle.capacity) * layerHeight + neck }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: width * 0.12, bottomLeadingRadius: width * 0.45,
                               bottomTrailingRadius: width * 0.45, topTrailingRadius: width * 0.12)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            shape.fill(Color.primary.opacity(0.05))
            VStack(spacing: 0) {
                ForEach(Array(bottle.layers.enumerated().reversed()), id: \.offset) { _, layer in
                    LayerView(layer: layer)
                        .frame(height: layerHeight)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
            .clipShape(shape)
            shape.strokeBorder(outline, lineWidth: isSelected || hintRole != nil ? 3 : 2)
        }
        .frame(width: width, height: height)
        .offset(y: isSelected ? -width * 0.3 : 0)
        .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
        .animation(.easeInOut(duration: 0.35), value: shakes)
        .shadow(color: hintRole != nil ? .yellow.opacity(0.8) : .clear, radius: 8)
        .contentShape(Rectangle())
    }

    private var outline: Color {
        switch hintRole {
        case .source: return .yellow
        case .target: return .orange
        case nil: return isSelected ? .accentColor : .primary.opacity(0.45)
        }
    }
}

private struct LayerView: View {
    let layer: Layer

    var body: some View {
        switch layer {
        case .color(let id):
            Rectangle().fill(Palette.color(id.rawValue).gradient)
        }
    }
}

/// Horizontal wiggle; animate by changing `animatableData` by 1.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}
