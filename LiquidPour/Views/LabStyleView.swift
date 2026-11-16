import BottleSortCore
import SwiftUI

extension ProgressModel {
    /// The milestone stats from saved progress: main-path stars and finished chapters, gold seals
    /// on every shipped recipe, best Rush and best daily streak.
    func playerStats(catalog: LevelCatalog, bestDailyStreak: Int, rushBest: Int) -> PlayerStats {
        PlayerStats.gather(chapters: catalog.chapters.compactMap { pack in
                               pack.chapter.map { (number: $0, recipeIDs: pack.levels.map(\.id)) }
                           },
                           stars: bestStars, goldSeals: goldSeals,
                           sealable: catalog.packs.flatMap { $0.levels.map(\.id) },
                           rushBest: rushBest, bestDailyStreak: bestDailyStreak)
    }

    /// Unlocked reward ids (every reward with `-LPUnlockAll`).
    func unlockedRewards(_ stats: PlayerStats) -> Set<String> {
        Self.unlockAll ? Set(Rewards.all.map(\.id)) : Rewards.unlocked(stats)
    }
}

/// "Lab Style" (R7): every cosmetic reward by category. Unlocked ones can be chosen (one per
/// category); locked ones say how to earn them, with the player's progress. Opened from the
/// map's toolbar and from the "New reward!" toast.
struct LabStyleView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @Environment(DailyModel.self) private var daily
    @Environment(RushRecordModel.self) private var rushRecords
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        let stats = progress.playerStats(catalog: catalog, bestDailyStreak: daily.stats.bestStreak,
                                         rushBest: rushRecords.best)
        let unlocked = progress.unlockedRewards(stats)
        let chosen = settings.value.cosmetics.resolved(unlocked: unlocked)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Earn new looks for your lab by playing: finish chapters, collect stars and gold seals, keep a Daily Brew streak or set a Rush record.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(CosmeticCategory.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.title)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(category.footnote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Rewards.rewards(in: category)) { reward in
                                RewardCard(reward: reward, progress: reward.milestone.progress(in: stats),
                                           isUnlocked: unlocked.contains(reward.id),
                                           isSelected: chosen.contains(reward.item),
                                           howToEarn: reward.milestone.howToEarn(catalog: catalog)) {
                                    select(reward.item)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { WorkbenchBackground(style: .menu) }
        .navigationTitle(Text("Lab Style", comment: "Title of the cosmetic rewards screen"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 720, minHeight: 640, idealHeight: 760)
        #endif
    }

    private func select(_ item: Reward.Item) {
        switch item {
        case .theme(let t): settings.value.cosmetics.theme = t
        case .flask(let f): settings.value.cosmetics.flask = f
        case .effect(let e): settings.value.cosmetics.effect = e
        }
    }
}

private extension CosmeticSelection {
    func contains(_ item: Reward.Item) -> Bool {
        switch item {
        case .theme(let t): theme == t
        case .flask(let f): flask == f
        case .effect(let e): effect == e
        }
    }
}

/// One reward: a preview, its name, and "selected", or how to earn it with a progress bar.
private struct RewardCard: View {
    let reward: Reward
    let progress: MilestoneProgress
    let isUnlocked: Bool
    let isSelected: Bool
    let howToEarn: String
    let onSelect: () -> Void

    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @State private var burst: Date?

    var body: some View {
        Button {
            guard isUnlocked else { return }
            onSelect()
            if case .effect = reward.item, !reduceMotion { burst = Date() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // A fixed-size slot: a filled painting must not widen the card.
                Color.clear
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .overlay { preview }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        if !isUnlocked {
                            RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.45))
                            Image(systemName: "lock.fill").font(.title2).foregroundStyle(.white)
                        }
                    }
                HStack(alignment: .firstTextBaseline) {
                    Text(reward.item.title).font(.headline).lineLimit(2)
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
                if isUnlocked {
                    Text(isSelected ? String(localized: "In use", comment: "Lab Style: the chosen reward")
                                    : String(localized: "Ready to use", comment: "Lab Style: an unlocked reward"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(howToEarn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if progress.target > 1 {
                        HStack(spacing: 6) {
                            ProgressView(value: progress.fraction).tint(.orange)
                            Text("\(min(progress.current, progress.target)) / \(progress.target)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: Text {
        if isSelected { return Text("\(reward.item.title), in use", comment: "VoiceOver: the chosen Lab Style reward") }
        if isUnlocked { return Text("\(reward.item.title), unlocked", comment: "VoiceOver: an unlocked Lab Style reward") }
        if progress.target > 1 {
            return Text("\(reward.item.title), locked. \(howToEarn). \(min(progress.current, progress.target)) of \(progress.target).",
                        comment: "VoiceOver: a locked Lab Style reward, how to earn it and the progress")
        }
        return Text("\(reward.item.title), locked. \(howToEarn).", comment: "VoiceOver: a locked Lab Style reward and how to earn it")
    }

    @ViewBuilder private var preview: some View {
        switch reward.item {
        case .theme(let theme):
            Image(theme.image(landscape: true))
                .resizable()
                .aspectRatio(contentMode: .fill)
        case .flask(let style):
            FlaskPreview(style: style)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.55))
        case .effect(let effect):
            ZStack {
                Color.black.opacity(0.55)
                FlaskPreview(style: .classic, corked: true)
                    .overlay(alignment: .top) {
                        if let burst {
                            CompletionBurst(effect: effect, start: burst, color: Palette.color(4), width: 22)
                                .offset(y: -CompletionBurst.size(width: 22).height / 2 + 18)
                                .task(id: burst) {
                                    try? await Task.sleep(for: .seconds(CompletionBurst.duration(effect) + 0.1))
                                    if self.burst == burst { self.burst = nil }
                                }
                        }
                    }
                Image(systemName: effect.symbol)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            }
        }
    }
}

extension PotionEffect {
    var symbol: String {
        switch self {
        case .sparkle: "sparkles"
        case .bubbles: "bubbles.and.sparkles"
        case .fireflies: "moon.stars"
        case .starburst: "sun.max"
        }
    }
}

/// A small flask in `style` with three potions, drawn with the board's glass look.
struct FlaskPreview: View {
    let style: FlaskShapeStyle
    var corked = false

    var body: some View {
        let w: CGFloat = 22
        let h = BottleView.height(width: w, capacity: 3)
        let shape = FlaskShape(style: style)
        ZStack(alignment: .bottom) {
            shape.fill(BottleView.glassBacking)
            VStack(spacing: 0) {
                ForEach([4, 1, 7], id: \.self) { color in
                    Rectangle().fill(Palette.color(color).gradient)
                        .frame(height: BottleView.layerHeight(width: w))
                }
            }
            .frame(width: w, height: h, alignment: .bottom)
            .clipShape(shape)
            shape.strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
        }
        .frame(width: w, height: h)
        .overlay(alignment: .top) {
            if corked {
                Cork(width: style.corkWidth(w)).offset(y: Cork.offsetY(width: style.corkWidth(w)))
            }
        }
        .scaleEffect(1.25)
        .accessibilityHidden(true)
    }
}

/// "New reward!" (R7): a small banner at the top when a milestone unlocks rewards. Tap it to
/// open Lab Style; it goes away on its own after a few seconds. VoiceOver announces it.
struct RewardToast: View {
    let rewards: [Reward]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New reward!", comment: "Toast title when a cosmetic reward unlocks")
                        .font(.headline)
                    Text(Self.summary(rewards))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.yellow.opacity(0.6), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens Lab Style"))
    }

    /// "Forest Hut", "Forest Hut and Fireflies", "Forest Hut and 2 more".
    static func summary(_ rewards: [Reward]) -> String {
        guard let first = rewards.first?.item.title else { return "" }
        switch rewards.count {
        case 1: return first
        case 2: return String(localized: "\(first) and \(rewards[1].item.title)", comment: "Toast: two new rewards")
        default: return String(localized: "\(first) and \(rewards.count - 1) more", comment: "Toast: several new rewards")
        }
    }
}
