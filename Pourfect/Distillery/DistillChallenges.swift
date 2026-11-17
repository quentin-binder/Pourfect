import BottleSortCore
import DistilleryCore
import SwiftUI

/// The Distillery section of the Challenges hub (R10): the Expert and Master packs and Random
/// Distillery. Always open, like the other challenges; nothing here counts toward the map.
struct DistillChallengeSection: View {
    let onOpenPack: (_ pack: DistillPack) -> Void
    let onRandom: () -> Void

    @Environment(DistillProgressModel.self) private var progress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([DistillPack.expert, .master], id: \.self) { pack in
                if let file = DistillLibrary.shared.file(pack) { packCard(pack, file: file) }
            }
            randomCard
        }
    }

    private func packCard(_ pack: DistillPack, file: DistillPackFile) -> some View {
        let s = progress.summary(file)
        return Button { onOpenPack(pack) } label: {
            HStack(spacing: 14) {
                StillIcon(liquid: Palette.color(pack == .expert ? 4 : 5), size: 40)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(DistillWing.title(pack)).font(.headline)
                    Text(DistillWing.subtitle(pack)).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Label { Text("\(s.stars) / \(s.maxStars)").monospacedDigit() } icon: {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                        }
                        Text("\(s.won) / \(file.levels.count) distilled", comment: "Distillery challenge pack card: levels won")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(DistillArt.brass.opacity(0.14)))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(DistillWing.title(pack)), \(s.stars) of \(s.maxStars) stars, \(s.won) of \(file.levels.count) stills distilled",
                                 comment: "VoiceOver: a distillery challenge pack in the hub"))
    }

    private var randomCard: some View {
        Button(action: onRandom) {
            HStack(spacing: 14) {
                Image(systemName: "dice.fill").font(.title).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Random Distillery", comment: "Title of a random distillery level").font(.headline)
                    Text("Gentle · Tricky · Fiendish", comment: "Random Distillery card: the three tiers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(DistillArt.copper.opacity(0.22)))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Choose a tier, then distill a random still", comment: "VoiceOver hint of the Random Distillery card"))
    }
}

/// Random Distillery: pick a tier and get a fresh seeded still (same seed, same level). Nothing is saved.
struct RandomDistillView: View {
    let onPlay: (_ level: DistillLevel) -> Void

    @State private var busy: DistillRandomTier?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Every still is new: a fresh board from a random seed. Random stills save no stars.",
                     comment: "Random Distillery screen header")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(DistillRandomTier.allCases, id: \.self) { tier in
                    tierCard(tier)
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background { WorkbenchBackground(style: .menu) }
        .navigationTitle(Text("Random Distillery", comment: "Title of a random distillery level"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
    }

    private func tierCard(_ tier: DistillRandomTier) -> some View {
        Button { generate(tier) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol(tier))
                    .font(.title)
                    .foregroundStyle(DistillArt.copper)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name(tier)).font(.headline)
                    Text(details(tier)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if busy == tier {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill").foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy != nil)
        .accessibilityLabel(Text("\(name(tier)): \(details(tier))", comment: "VoiceOver: a Random Distillery tier"))
        .accessibilityHint(Text("Builds a random still and opens it", comment: "VoiceOver hint of a Random Distillery tier"))
    }

    private func generate(_ tier: DistillRandomTier) {
        busy = tier
        let seed = UInt64.random(in: 1...999_999_999)
        Task {
            let level = await Task.detached(priority: .userInitiated) { DistillRandom.level(tier: tier, seed: seed) }.value
            busy = nil
            onPlay(level)
        }
    }

    private func name(_ tier: DistillRandomTier) -> String {
        switch tier {
        case .gentle: String(localized: "Gentle", comment: "Random Distillery tier")
        case .tricky: String(localized: "Tricky", comment: "Random Distillery tier")
        case .fiendish: String(localized: "Fiendish", comment: "Random Distillery tier")
        }
    }

    private func details(_ tier: DistillRandomTier) -> String {
        switch tier {
        case .gentle: String(localized: "5×5, one potion, straights and elbows", comment: "Random Distillery tier details")
        case .tricky: String(localized: "6×6, two potions, splitters and crossings", comment: "Random Distillery tier details")
        case .fiendish: String(localized: "7×7, two potions, riveted pieces, a heat coil and a valve", comment: "Random Distillery tier details")
        }
    }

    private func symbol(_ tier: DistillRandomTier) -> String {
        switch tier {
        case .gentle: "leaf.fill"
        case .tricky: "arrow.triangle.branch"
        case .fiendish: "flame.fill"
        }
    }
}
