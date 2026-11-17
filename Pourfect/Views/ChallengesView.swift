import BottleSortCore
import SwiftUI

/// The Challenges hub (R6), off the calm main path: Rush, the hard recipe books (never gated)
/// and Random Brew. Nothing here counts toward the chapter map's star gates.
struct ChallengesView: View {
    let onOpenPack: (_ packID: String) -> Void
    let onRandom: () -> Void
    let onRush: () -> Void
    /// Secret Recipe (R10b): the daily screen and a practice game.
    var onRecipeDaily: (() -> Void)?
    var onRecipePractice: (() -> Void)?

    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @Environment(RushRecordModel.self) private var rushRecords

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                sectionTitle("Rush", symbol: "timer")
                rushCard
                if let onRecipeDaily {
                    sectionTitle("Secret Recipe", symbol: "lock.fill")
                    RecipeEntryCard(onDaily: onRecipeDaily, onPractice: onRecipePractice)
                }
                sectionTitle("Recipe books", symbol: "book.closed.fill")
                ForEach(catalog.challenges) { pack in
                    packCard(pack)
                }
                sectionTitle("Random Brew", symbol: "dice.fill")
                randomCard
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
            Text("A race against the clock, hard recipe books and random brews. Always open; nothing here counts toward the chapter map.",
                 comment: "Challenges hub header")
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

    /// On the `.menu` backdrop (washed with the system background: light in light mode, dark
    /// in dark mode), so primary text, not white.
    private func sectionTitle(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private var rushCard: some View {
        let record = rushRecords.record
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hourglass")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rush").font(.headline)
                    Text("Brew as many recipes as you can in 3 minutes. Each brew adds \(Int(RushClock.solveBonus)) s, a skip costs \(Int(RushClock.skipPenalty)) s. No hints; recipes grow harder and bring in the mechanics you have met on the map.",
                         comment: "Rush description in the Challenges hub; the arguments are the time bonus and the skip penalty in seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 14) {
                Label { Text("Best \(record.best)", comment: "Rush best score").monospacedDigit() } icon: {
                    Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Best Rush: \(record.best) recipes", comment: "VoiceOver: Rush best score"))
                if record.runs > 0 {
                    Text("\(record.runs) runs", comment: "Rush runs played").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onRush) {
                    Label("Start Rush", systemImage: "play.fill").font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .accessibilityHint(Text("Starts a 3 minute run", comment: "VoiceOver hint on Start Rush"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.16)))
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func packCard(_ pack: LevelPackInfo) -> some View {
        let earned = progress.progress(of: pack)
        let seals = progress.goldSeals(of: pack)
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
                        Label { Text("\(seals.earned) / \(seals.total)").monospacedDigit() } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(PerfectBadge.gold)
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
        .accessibilityLabel(Text("\(pack.name), \(earned.stars) of \(earned.maxStars) stars, \(seals.earned) gold seals",
                                 comment: "VoiceOver: a challenge book in the hub"))
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
