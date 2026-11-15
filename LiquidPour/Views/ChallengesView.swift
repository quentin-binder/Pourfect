import BottleSortCore
import SwiftUI

/// The optional Challenges area: hard recipe books (never gated) and Random Brew.
struct ChallengesView: View {
    let onOpenPack: (_ packID: String) -> Void
    let onRandom: () -> Void

    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                randomCard
                ForEach(catalog.challenges) { pack in
                    packCard(pack)
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background { WorkbenchBackground(style: .menu) }
        .navigationTitle("Challenges")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Challenges", systemImage: "trophy.fill")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Hard recipe books for practiced alchemists. Always open; they don't count toward the chapter map.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .bottomLeading)
        .background {
            Image(.bgWorkbenchLandscape)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(.bottom, 6)
    }

    private func packCard(_ pack: LevelPackInfo) -> some View {
        let earned = progress.progress(of: pack)
        return Button { onOpenPack(pack.id) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon(for: pack))
                    .font(.title)
                    .foregroundStyle(.orange)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.name).font(.headline)
                    if let subtitle = pack.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Label { Text("\(earned.stars) / \(earned.maxStars)").monospacedDigit() } icon: {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                        }
                        Text("\(pack.levels.count) recipes").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(pack.name), \(earned.stars) of \(earned.maxStars) stars"))
    }

    /// Flame for the first book, then hotter symbols for the harder ones.
    private func icon(for pack: LevelPackInfo) -> String {
        let symbols = ["flame", "flame.fill", "crown.fill"]
        let index = catalog.challenges.firstIndex(of: pack) ?? 0
        return symbols[min(index, symbols.count - 1)]
    }

    private var randomCard: some View {
        Button(action: onRandom) {
            HStack(spacing: 14) {
                Image(systemName: "dice.fill").font(.title).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Random Brew").font(.headline)
                    Text("Classic · Rune Seals · Murky Layers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.22)))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Choose a mode and workbench size, then brew a recipe"))
    }
}
