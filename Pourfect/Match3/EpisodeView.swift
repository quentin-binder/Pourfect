import BottleSortCore
import Match3Core
import SwiftUI

/// An ingredient-gathering episode (R9): a painted header (where the ingredients are going, stars)
/// above its eight levels, which open in order. Its story scene plays the first time it opens.
struct EpisodeView: View {
    let file: M3EpisodeFile
    let onSelect: (_ level: M3Level) -> Void

    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @Environment(Match3ProgressModel.self) private var m3
    @Environment(StoryPresenter.self) private var story
    @Environment(\.colorRunesEnabled) private var runes

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 14)]
    private var number: Int { file.episode.number }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(file.levels.indices, id: \.self) { index in
                        let level = file.levels[index]
                        let unlocked = m3.isLevelUnlocked(index, in: file)
                        Button { if unlocked { onSelect(level) } } label: {
                            EpisodeLevelCell(number: index + 1, level: level, stars: m3.stars(level.id),
                                             unlocked: unlocked, runes: runes)
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(unlocked)
                    }
                }
                Label("Gathering is optional: its stars are kept apart and never lock a chapter.",
                      systemImage: "leaf")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { PaintedBackdrop(image: backdrop, style: .menu) }
        .navigationTitle(file.episode.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { story.show(.gathering(number)) } label: { Label("Story", systemImage: "text.bubble") }
                    .help(Text("Replay this episode's story", comment: "Tooltip of the Story button on a gathering episode"))
            }
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
        .task(id: number) {
            guard StoryPresenter.autoPlays,
                  let scene = Story.sceneOnOpening(gathering: number, seen: progress.storySeen) else { return }
            try? await Task.sleep(for: .milliseconds(350))
            story.show(scene)
        }
    }

    /// The place the ingredients are for: the next chapter (the larder belongs to the hoard).
    private var destination: Int { min(number + 1, Story.finalChapter) }
    private var backdrop: ImageResource { ChapterArt.vignette(destination) ?? .bgWorkbenchLandscape }

    private var header: some View {
        let stars = file.levels.reduce(0) { $0 + m3.stars($1.id) }
        let maxStars = file.levels.count * 3
        let kinds = Array(Set(file.levels.flatMap(\.kinds))).sorted()
        return VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ingredient gathering \(number)", comment: "Episode screen kicker")
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(file.episode.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text(file.episode.subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 8)
                IngredientBasket(kinds: [EpisodeArt.featured(file)] + kinds.filter { $0 != EpisodeArt.featured(file) },
                                 size: 72)
            }
            if let place = ChapterArt.name(of: destination, in: catalog) {
                Label(number == Story.finalChapter
                      ? String(localized: "For the grand brew at \(place)", comment: "Episode 10 header: what the ingredients are for")
                      : String(localized: "Supplies for \(place)", comment: "Episode header: the next chapter the ingredients are for"),
                      systemImage: "map")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: Capsule())
            }
            HStack(spacing: 10) {
                Label { Text("\(stars) / \(maxStars)").monospacedDigit() } icon: {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                .font(.headline)
                .foregroundStyle(.white)
                ProgressView(value: Double(stars), total: Double(max(1, maxStars)))
                    .tint(.yellow)
                    .frame(maxWidth: 200)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(stars) of \(maxStars) stars"))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .bottomLeading)
        .background {
            Image(backdrop)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
}

/// One level of an episode: number, stars and its main goal's icon; a lock while closed.
private struct EpisodeLevelCell: View {
    let number: Int
    let level: M3Level
    let stars: Int
    let unlocked: Bool
    let runes: Bool

    var body: some View {
        VStack(spacing: 4) {
            if unlocked {
                HStack(spacing: 6) {
                    Text(number, format: .number).font(.title2.bold().monospacedDigit())
                    goalIcon.frame(width: 22, height: 22)
                }
                StarsView(count: stars, size: 10)
            } else {
                Image(systemName: "lock.fill").font(.title3)
                Text(number, format: .number).font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .foregroundStyle(unlocked ? Color.primary : Color.primary.opacity(0.6))
        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? Color.green.opacity(0.16) : Color.gray.opacity(0.18)))
        .background(unlocked ? .thinMaterial : .regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// What the level asks for first: an obstacle when it has one, else the first ingredient.
    @ViewBuilder private var goalIcon: some View {
        let goals = level.goals
        if goals.contains(where: { $0.type == .drops }) {
            M3FlaskView(size: 22)
        } else if goals.contains(where: { $0.type == .crates }) {
            M3CrateView(hits: 1, size: 22)
        } else if goals.contains(where: { $0.type == .frost }) {
            IceCrystal(size: 20, turns: nil)
        } else if let kind = goals.first(where: { $0.type == .collect })?.kind {
            M3KindIcon(kind: kind, size: 22, runes: runes)
        } else {
            Image(systemName: "sparkles").foregroundStyle(M3Colors.gold)
        }
    }

    private var accessibilityText: Text {
        let goals = level.goals.map { Match3Goals.name($0) }.joined(separator: ", ")
        guard unlocked else { return Text("Level \(number), locked", comment: "VoiceOver: a locked gathering level") }
        return Text("Level \(number), \(stars) stars. Goals: \(goals)", comment: "VoiceOver: a gathering level tile")
    }
}
