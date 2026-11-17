import BottleSortCore
import DistilleryCore
import HiddenCore
import SwiftUI

/// Art and names for the ten chapters of the main path.
enum ChapterArt {
    /// Square vignette of chapter `number` (asset catalog `chapter_01` … `chapter_10`).
    static func vignette(_ number: Int) -> ImageResource? {
        let all: [ImageResource] = [.chapter01, .chapter02, .chapter03, .chapter04, .chapter05,
                                    .chapter06, .chapter07, .chapter08, .chapter09, .chapter10]
        return all.indices.contains(number - 1) ? all[number - 1] : nil
    }

    /// Where chapter `number`'s button sits on `chapter_map` (1344 × 3136), as fractions of the
    /// image size: the clearings along the painted path, chapter 1 at the cellar at the bottom,
    /// chapter 10 at the dragon at the top.
    static let mapSpots: [CGPoint] = [
        CGPoint(x: 0.55, y: 0.915),   //  1 cellar steps
        CGPoint(x: 0.34, y: 0.848),   //  2 vault door
        CGPoint(x: 0.64, y: 0.772),   //  3 marsh pool
        CGPoint(x: 0.36, y: 0.688),   //  4 library door
        CGPoint(x: 0.67, y: 0.617),   //  5 glass works ledge
        CGPoint(x: 0.33, y: 0.528),   //  6 pond terrace
        CGPoint(x: 0.69, y: 0.440),   //  7 bog stairs
        CGPoint(x: 0.34, y: 0.345),   //  8 twin towers bend
        CGPoint(x: 0.67, y: 0.192),   //  9 hall terrace
        CGPoint(x: 0.37, y: 0.120),   // 10 dragon's cave
    ]

    /// Aspect ratio (width / height) of `chapter_map`.
    static let mapAspect: CGFloat = 1344.0 / 3136.0

    /// Display name of chapter `number`: the shipped pack's name, else the planned location.
    static func name(of number: Int, in catalog: LevelCatalog) -> String? {
        catalog.chapter(number)?.name ?? ChapterOutline.plan.first { $0.number == number }?.location
    }
}

/// One stop on the chapter map: shipped (open or locked) or planned ("coming soon").
struct MapChapter: Identifiable {
    enum State: Equatable {
        case open(ChapterProgress)
        /// `starsNeeded` = stars still missing in the previous chapter (nil while that one is locked too).
        case locked(previous: String, starsNeeded: Int?)
        case comingSoon
    }

    let number: Int
    let name: String
    let pack: LevelPackInfo?
    let state: State
    /// Every recipe of the (open) chapter has a gold seal (R6).
    var goldComplete = false

    var id: Int { number }
    var isOpen: Bool { if case .open = state { return true } else { return false } }

    /// The planned chapters plus any shipped chapter beyond the plan, in order.
    static func entries(catalog: LevelCatalog, progress: ProgressModel) -> [MapChapter] {
        let open = progress.unlockedChapters(catalog.chapters)
        let numbers = Set(ChapterOutline.plan.map(\.number)).union(catalog.chapters.compactMap(\.chapter)).sorted()
        return numbers.map { number in
            let name = ChapterArt.name(of: number, in: catalog) ?? ""
            guard let index = catalog.chapters.firstIndex(where: { $0.chapter == number }) else {
                return MapChapter(number: number, name: name, pack: nil, state: .comingSoon)
            }
            let pack = catalog.chapters[index]
            if open[index] {
                return MapChapter(number: number, name: name, pack: pack, state: .open(progress.progress(of: pack)),
                                  goldComplete: progress.goldSeals(of: pack).isComplete)
            }
            let previous = index > 0 ? catalog.chapters[index - 1] : nil
            let needed = (index > 0 && open[index - 1]) ? previous.map { progress.progress(of: $0).starsToOpenNext } : nil
            return MapChapter(number: number, name: name, pack: pack,
                              state: .locked(previous: previous?.name ?? "", starsNeeded: needed))
        }
    }
}

/// Home screen: the painted chapter map. The path climbs from chapter 1 (bottom) to chapter 10
/// (top); open chapters lead to their recipe list. On wide windows the map is a column beside a
/// panel with "Continue" and the Challenges; on narrow ones it fills the width with a bar below.
struct ChapterMapView: View {
    let onOpenChapter: (_ packID: String) -> Void
    let onChallenges: () -> Void
    /// Opens the daily hub (every daily game, R10).
    let onToday: () -> Void
    /// Opens ingredient-gathering episode N (R9).
    let onEpisode: (_ number: Int) -> Void
    /// Opens distillery workshop stage N (R10).
    let onDistillStage: (_ stage: Int) -> Void
    /// Opens a curiosity room (R11).
    let onHiddenRoom: (_ room: HiddenSceneID) -> Void
    let onLabStyle: () -> Void

    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @Environment(Match3ProgressModel.self) private var m3progress
    @Environment(DistillProgressModel.self) private var distill
    @Environment(HiddenProgressModel.self) private var hidden

    var body: some View {
        let entries = MapChapter.entries(catalog: catalog, progress: progress)
        let episodes = m3progress.entries(catalog: catalog, progress: progress)
        let stages = distill.stageEntries(catalog: catalog, progress: progress)
        let rooms = hidden.entries(catalog: catalog, progress: progress)
        let current = entries.last(where: \.isOpen)
        GeometryReader { geo in
            let wide = geo.size.width >= 760
            if wide {
                let panelWidth = min(340, geo.size.width * 0.38)
                let mapWidth = min(520, geo.size.width - panelWidth - 72)
                HStack(spacing: 28) {
                    map(entries, episodes: episodes, stages: stages, rooms: rooms, current: current, width: mapWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15)))
                        .shadow(color: .black.opacity(0.5), radius: 18)
                        .padding(.vertical, 16)
                    panel(current: current, entries: entries)
                        .frame(width: panelWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The bar is a safe-area inset of the scroll view, so chapter 1 can scroll above it.
                map(entries, episodes: episodes, stages: stages, rooms: rooms, current: current, width: geo.size.width)
                    .safeAreaInset(edge: .bottom) { compactBar(current: current) }
            }
        }
        .background { PaintedBackdrop(image: .chapterMap, style: .game) }
        .environment(\.colorScheme, .dark)
        .navigationTitle("Pourfect")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.3), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onChallenges) { Label("Challenges", systemImage: "trophy") }
                    .help("Challenge recipes and Random Brew")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onLabStyle) { Label("Lab Style", systemImage: "paintpalette") }
                    .help(Text("Workbench themes, flask shapes and potion effects", comment: "Tooltip of the Lab Style button"))
            }
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
    }

    // MARK: Map

    private func map(_ entries: [MapChapter], episodes: [MapEpisode], stages: [MapDistillStage], rooms: [MapHiddenRoom],
                     current: MapChapter?, width: CGFloat) -> some View {
        let height = width / ChapterArt.mapAspect
        // Opens scrolled to the chapter the player is on.
        // (Nudged down a little so the marker's name plate is in view too.)
        var anchorY: CGFloat = min(1, (current.flatMap { ChapterArt.mapSpots.indices.contains($0.number - 1)
            ? ChapterArt.mapSpots[$0.number - 1].y : nil } ?? CGFloat(1)) + 0.05)
        #if DEBUG
        // Dev aid: `-LPMapAnchor 0.2` opens the map scrolled to that height (0 = top, 1 = bottom).
        if let raw = UserDefaults.standard.string(forKey: "LPMapAnchor"), let y = Double(raw) { anchorY = CGFloat(y) }
        #endif
        return ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Image(.chapterMap)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: width, height: height)
                    .accessibilityHidden(true)
                // The distillery wing up the left edge: its pipe, then a still per stage (R10).
                DistillWingPipe(stages: stages, size: CGSize(width: width, height: height),
                                scale: min(1.15, max(0.8, width / 440)))
                ForEach(stages) { stage in
                    if DistillWing.mapSpots.indices.contains(stage.stage - 1) {
                        let spot = DistillWing.mapSpots[stage.stage - 1]
                        DistillStageMarker(entry: stage, scale: min(1.15, max(0.8, width / 440))) {
                            onDistillStage(stage.stage)
                        }
                        .position(x: spot.x * width, y: spot.y * height)
                    }
                }
                // The curiosity rooms up the right edge: a dotted thread, then a magnifier per room (R11).
                HiddenWingThread(rooms: rooms, size: CGSize(width: width, height: height),
                                 scale: min(1.15, max(0.8, width / 440)))
                ForEach(rooms) { room in
                    let spot = HiddenArt.mapSpots[room.room.number - 1]
                    HiddenRoomMarker(entry: room, scale: min(1.15, max(0.8, width / 440))) {
                        onHiddenRoom(room.room)
                    }
                    .position(x: spot.x * width, y: spot.y * height)
                }
                // Gathering episodes sit on the path between the chapters (drawn first, under them).
                ForEach(episodes) { episode in
                    if EpisodeArt.mapSpots.indices.contains(episode.number - 1) {
                        let spot = EpisodeArt.mapSpots[episode.number - 1]
                        EpisodeMarker(entry: episode, scale: min(1.15, max(0.8, width / 440))) {
                            if episode.isOpen { onEpisode(episode.number) }
                        }
                        .position(x: spot.x * width, y: spot.y * height)
                    }
                }
                ForEach(entries) { entry in
                    if ChapterArt.mapSpots.indices.contains(entry.number - 1) {
                        let spot = ChapterArt.mapSpots[entry.number - 1]
                        ChapterMarker(entry: entry, isCurrent: entry.number == current?.number,
                                      scale: min(1.15, max(0.8, width / 440))) {
                            if let pack = entry.pack, entry.isOpen { onOpenChapter(pack.id) }
                        }
                        .id(entry.number)
                        .position(x: spot.x * width, y: spot.y * height)
                    }
                }
            }
            .frame(width: width, height: height)
        }
        .frame(width: width)
        .defaultScrollAnchor(UnitPoint(x: 0.5, y: anchorY))
    }

    // MARK: Side panel (wide) and bottom bar (narrow)

    private func panel(current: MapChapter?, entries: [MapChapter]) -> some View {
        let total = catalog.chapters.reduce(into: (0, 0)) { sum, pack in
            let p = progress.progress(of: pack)
            sum.0 += p.stars; sum.1 += p.maxStars
        }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pourfect").font(.system(size: 40, weight: .bold, design: .serif))
                Text("An alchemist's journey from the cellar to the dragon's hoard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label { Text("\(total.0) / \(total.1)").monospacedDigit() } icon: {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                .font(.headline)
                .padding(.top, 4)
                .accessibilityLabel(Text("\(total.0) of \(total.1) stars on the main path"))
            }
            ForEach(catalog.loadErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            TodayHomeCard(action: onToday)
            if let current, let pack = current.pack {
                continueCard(current, pack: pack)
            }
            challengesCard
        }
        .padding(.vertical)
    }

    private func continueCard(_ entry: MapChapter, pack: LevelPackInfo) -> some View {
        Button { onOpenChapter(pack.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let art = ChapterArt.vignette(entry.number) {
                    Image(art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue · Chapter \(entry.number)")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(entry.name).font(.title3.bold())
                    if case .open(let p) = entry.state {
                        HStack {
                            Label { Text("\(p.stars) / \(p.maxStars)").monospacedDigit() } icon: {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(14)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Continue chapter \(entry.number), \(entry.name)"))
    }

    private var challengesCard: some View {
        Button(action: onChallenges) {
            HStack(spacing: 14) {
                Image(systemName: "trophy.fill").font(.title).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Challenges").font(.headline)
                    Text("Rush, hard recipe books, Random Brew and the distillery, open any time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func compactBar(current: MapChapter?) -> some View {
        VStack(spacing: 8) {
            TodayBarRow(action: onToday)
            compactButtons(current: current)
        }
        .controlSize(.large)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func compactButtons(current: MapChapter?) -> some View {
        HStack(spacing: 10) {
            if let current, let pack = current.pack {
                Button { onOpenChapter(pack.id) } label: {
                    Label("Continue", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text("Continue chapter \(current.number), \(current.name)"))
            }
            Button(action: onChallenges) {
                Label("Challenges", systemImage: "trophy.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// A chapter's button on the map: its vignette in a round frame, number, name and stars.
private struct ChapterMarker: View {
    let entry: MapChapter
    let isCurrent: Bool
    let scale: CGFloat
    let action: () -> Void

    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @State private var glow = false

    private var size: CGFloat { 66 * scale }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                medallion
                plate
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that would fade the whole marker. Closed chapters simply do nothing.
        .allowsHitTesting(entry.isOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .onAppear { if isCurrent && !reduceMotion { glow = true } }
    }

    private var ringColor: Color {
        switch entry.state {
        case .open(let p): return p.stars >= p.maxStars && p.maxStars > 0 ? .yellow : (isCurrent ? .orange : .white)
        case .locked: return .gray
        case .comingSoon: return .gray.opacity(0.6)
        }
    }

    private var medallion: some View {
        ZStack {
            if isCurrent {
                Circle()
                    .fill(Color.orange.opacity(0.55))
                    .frame(width: size * 1.3, height: size * 1.3)
                    .blur(radius: 10)
                    .scaleEffect(glow ? 1.1 : 0.9)
                    .opacity(glow ? 1 : 0.6)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: glow)
            }
            Group {
                if let art = ChapterArt.vignette(entry.number) {
                    Image(art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray
                }
            }
            .frame(width: size, height: size)
            .saturation(entry.isOpen ? 1 : 0.15)
            .brightness(entry.isOpen ? 0 : -0.3)
            .clipShape(Circle())
            Circle().strokeBorder(ringColor, lineWidth: 3 * scale).frame(width: size, height: size)
            switch entry.state {
            case .locked:
                Image(systemName: "lock.fill").font(.system(size: 22 * scale, weight: .bold)).foregroundStyle(.white)
            case .comingSoon:
                Image(systemName: "hourglass").font(.system(size: 20 * scale, weight: .bold)).foregroundStyle(.white.opacity(0.85))
            case .open:
                EmptyView()
            }
            Text(entry.number, format: .number)
                .font(.system(size: 13 * scale, weight: .bold).monospacedDigit())
                .foregroundStyle(entry.isOpen ? Color.black : Color.white)
                .frame(width: 24 * scale, height: 24 * scale)
                .background(Circle().fill(entry.isOpen ? ringColor : Color.black.opacity(0.75)))
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .offset(x: -size * 0.38, y: -size * 0.38)
            if entry.isOpen && entry.goldComplete {
                GoldSealMark(size: 20 * scale)
                    .offset(x: size * 0.38, y: -size * 0.38)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }

    private var plate: some View {
        VStack(spacing: 1) {
            Text(entry.name)
                .font(.system(size: 13 * scale, weight: .semibold, design: .serif))
                .lineLimit(1)
                .foregroundStyle(entry.isOpen ? Color.white : Color.white.opacity(0.75))
            switch entry.state {
            case .open(let p):
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text("\(p.stars) / \(p.maxStars)").monospacedDigit()
                }
                .font(.system(size: 11 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            case .locked(_, let needed):
                Group {
                    if let needed {
                        Text("\(needed) more \(Image(systemName: "star.fill")) needed")
                    } else {
                        Text("Locked")
                    }
                }
                .font(.system(size: 11 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            case .comingSoon:
                Text("Coming soon")
                    .font(.system(size: 11 * scale, weight: .medium).italic())
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 10 * scale).padding(.vertical, 4 * scale)
        .background(Capsule().fill(Color.black.opacity(entry.isOpen ? 0.62 : 0.5)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .fixedSize()
    }

    private var accessibilityText: Text {
        switch entry.state {
        case .open(let p):
            if entry.goldComplete {
                return Text("Chapter \(entry.number), \(entry.name), \(p.stars) of \(p.maxStars) stars, every recipe gold-sealed",
                            comment: "VoiceOver: a chapter on the map whose recipes all have a gold seal")
            }
            return Text("Chapter \(entry.number), \(entry.name), \(p.stars) of \(p.maxStars) stars")
        case .locked(let previous, let needed):
            if let needed {
                return Text("Chapter \(entry.number), \(entry.name), locked. Earn \(needed) more stars in \(previous)")
            }
            return Text("Chapter \(entry.number), \(entry.name), locked")
        case .comingSoon:
            return Text("Chapter \(entry.number), \(entry.name), coming soon")
        }
    }
}
