import BottleSortCore
import SwiftUI

/// The gold seal (R6 "perfect brewer"): the daily's "Perfect" seal, gold on its own. Used on
/// recipe tiles, the chapter header, the chapter map and the win card.
struct GoldSealMark: View {
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(PerfectBadge.gold)
            .background(Circle().fill(.black.opacity(0.55)).padding(size * 0.12))
            .shadow(color: .yellow.opacity(0.45), radius: size * 0.25)
            .accessibilityHidden(true)
    }
}

/// "Gold seals 4 / 30" for a chapter or challenge book.
struct GoldSealCount: View {
    let progress: GoldSealProgress
    var font: Font = .headline

    var body: some View {
        Label {
            Text("Gold seals \(progress.earned) / \(progress.total)", comment: "Gold seals earned in a chapter out of its recipes")
                .monospacedDigit()
        } icon: {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(PerfectBadge.gold)
        }
        .font(font)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(progress.earned) of \(progress.total) recipes with a gold seal",
                                 comment: "VoiceOver: gold seals earned in a chapter"))
    }
}

/// The win card's flourish for a perfect brew: the seal stamps in over a burst of gold rays
/// (a still seal with Reduce Motion).
struct GoldSealFlourish: View {
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @State private var stamped = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(PerfectBadge.gold)
                        .frame(width: 4, height: 14)
                        .offset(y: stamped ? -46 : -22)
                        .rotationEffect(.degrees(Double(i) * 30))
                        .opacity(stamped ? 0 : 0.9)
                }
            }
            Circle()
                .fill(RadialGradient(colors: [.yellow.opacity(0.45), .clear], center: .center, startRadius: 4, endRadius: 46))
                .frame(width: 92, height: 92)
                .opacity(stamped ? 1 : 0)
            GoldSealMark(size: 52)
                .scaleEffect(stamped ? 1 : 1.8)
                .opacity(stamped ? 1 : 0)
                .rotationEffect(.degrees(stamped ? 0 : -25))
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Gold seal", comment: "VoiceOver: the win card's gold seal for a perfect brew"))
        .task {
            if reduceMotion { stamped = true; return }
            // Lands as the win arpeggio ends (the seal's chime plays then, `FeedbackPlayer`).
            try? await Task.sleep(for: .seconds(0.75))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { stamped = true }
        }
    }
}
