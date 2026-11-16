import BottleSortCore
import SwiftUI

/// One chapter or challenge pack: a painted header (chapter vignette, name, stars, what the
/// stars open) above the recipe grid. Recipes open in order.
struct PackView: View {
    let pack: LevelPackInfo
    let onSelect: (_ index: Int) -> Void

    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @Environment(StoryPresenter.self) private var story

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 14)]

    var body: some View {
        let ids = pack.levels.map(\.id)
        ScrollView {
            VStack(spacing: 20) {
                header
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(pack.levels.indices, id: \.self) { index in
                        let unlocked = progress.isUnlocked(index: index, ids: ids)
                        // Not `.disabled`: on the Mac that greys the label out a second time and the
                        // locked cells became unreadable in light mode. The cell draws its own locked look.
                        Button { if unlocked { onSelect(index) } } label: {
                            LevelCell(number: index + 1, stars: progress.stars(for: ids[index]), unlocked: unlocked,
                                      goldSeal: progress.hasGoldSeal(ids[index]))
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(unlocked)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { PaintedBackdrop(image: backdrop, style: .menu) }
        .navigationTitle(pack.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let number = pack.chapter, !Story.replayable(chapter: number, seen: progress.storySeen).isEmpty {
                ToolbarItem(placement: .primaryAction) { storyButton(number) }
            }
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
        // The chapter's story scene plays the first time its recipe list opens (R7).
        .task(id: pack.id) {
            guard StoryPresenter.autoPlays, let number = pack.chapter,
                  let scene = Story.sceneOnOpening(chapter: number, seen: progress.storySeen) else { return }
            try? await Task.sleep(for: .milliseconds(350))
            story.show(scene)
        }
    }

    /// Replays the chapter's story scene; the last chapter also offers the ending once seen.
    @ViewBuilder private func storyButton(_ number: Int) -> some View {
        let scenes = Story.replayable(chapter: number, seen: progress.storySeen)
        if scenes.count > 1 {
            Menu {
                ForEach(scenes, id: \.self) { scene in
                    Button(scene == .ending ? String(localized: "Ending", comment: "Story menu: the ending scene")
                                            : String(localized: "Chapter Story", comment: "Story menu: the chapter's scene")) {
                        story.show(scene)
                    }
                }
            } label: {
                Label("Story", systemImage: "text.bubble")
            }
            .help(Text("Replay this chapter's story", comment: "Tooltip of the Story button"))
        } else if let scene = scenes.first {
            Button { story.show(scene) } label: { Label("Story", systemImage: "text.bubble") }
                .help(Text("Replay this chapter's story", comment: "Tooltip of the Story button"))
        }
    }

    private var backdrop: ImageResource { pack.chapter.flatMap { ChapterArt.vignette($0) } ?? .bgWorkbenchLandscape }

    private var header: some View {
        let earned = progress.progress(of: pack)
        return VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            if let number = pack.chapter {
                Text("Chapter \(number)")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text("Challenge")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(pack.name)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            if let subtitle = pack.subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
            }
            HStack(spacing: 10) {
                Label { Text("\(earned.stars) / \(earned.maxStars)").monospacedDigit() } icon: {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                .font(.headline)
                .foregroundStyle(.white)
                ProgressView(value: Double(earned.stars), total: Double(max(1, earned.maxStars)))
                    .tint(.yellow)
                    .frame(maxWidth: 200)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(earned.stars) of \(earned.maxStars) stars"))
            GoldSealCount(progress: progress.goldSeals(of: pack), font: .subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            if let note = gateNote(earned) {
                Label(note, systemImage: earned.opensNextChapter ? "lock.open.fill" : "lock.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .bottomLeading)
        .background {
            Image(backdrop)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    /// What this chapter's stars do for the next chapter (nil for challenges and the last chapter).
    private func gateNote(_ earned: ChapterProgress) -> String? {
        guard let number = pack.chapter, let next = ChapterArt.name(of: number + 1, in: catalog) else { return nil }
        guard catalog.chapter(number + 1) != nil else {
            return String(localized: "\(next) is coming soon")
        }
        if earned.opensNextChapter { return String(localized: "\(next) is open") }
        return String(localized: "Earn \(earned.starsToOpenNext) more stars to open \(next)")
    }
}

struct LevelCell: View {
    let number: Int
    let stars: Int
    let unlocked: Bool
    /// Solved in the minimum without a hint (R6).
    var goldSeal = false

    var body: some View {
        VStack(spacing: 4) {
            if unlocked {
                Text(number, format: .number).font(.title2.bold().monospacedDigit())
                StarsView(count: stars, size: 10)
            } else {
                Image(systemName: "lock.fill").font(.title3)
                Text(number, format: .number).font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        // Locked cells use a dimmed primary (not .secondary) on a denser material, so the lock and
        // number stay legible over the washed-out light-mode backdrop.
        .foregroundStyle(unlocked ? Color.primary : Color.primary.opacity(0.6))
        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.18)))
        .background(unlocked ? .thinMaterial : .regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            if unlocked && goldSeal { GoldSealMark(size: 15).padding(5) }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        guard unlocked else { return Text("Recipe \(number), locked") }
        if goldSeal {
            return Text("Recipe \(number), \(stars) stars, gold seal", comment: "VoiceOver: a recipe tile solved perfectly")
        }
        return Text("Recipe \(number), \(stars) stars")
    }
}

struct StarsView: View {
    let count: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i < count ? Color.yellow : Color.secondary)
            }
        }
    }
}

/// Opens Settings: the Settings window on the Mac (same as ⌘,), a sheet on iOS.
struct SettingsButton: View {
    #if os(iOS)
    @State private var showsSettings = false
    #endif

    var body: some View {
        #if os(macOS)
        SettingsLink { Label("Settings", systemImage: "gearshape") }
            .help("Sound, color runes and motion")
        #else
        Button { showsSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            .sheet(isPresented: $showsSettings) {
                NavigationStack { SettingsView(showsDone: true) }
            }
        #endif
    }
}
