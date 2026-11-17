import BottleSortCore
import CoreGraphics
import HiddenCore
import ImageIO
import SwiftUI

/// Colours, names and map places of the Curiosity Rooms (R11, hidden-object search scenes). The wing climbs the
/// map's right edge: one magnifier token per room, level with the chapter that opens it (2, 5, 8), joined by a
/// dotted thread. DECISIONS 303.
enum HiddenArt {
    static let brass = Color(red: 0.80, green: 0.62, blue: 0.30)
    static let brassDark = Color(red: 0.36, green: 0.24, blue: 0.10)
    static let gold = Color(red: 1.00, green: 0.82, blue: 0.35)
    static let panel = Color(red: 0.09, green: 0.075, blue: 0.06).opacity(0.94)
    /// The rooms' accent colours: dusty violet, market green, dragon red.
    static func accent(_ room: HiddenSceneID) -> Color {
        switch room {
        case .attic: Color(red: 0.62, green: 0.48, blue: 0.85)
        case .market: Color(red: 0.45, green: 0.75, blue: 0.4)
        case .hoard: Color(red: 0.9, green: 0.35, blue: 0.25)
        }
    }

    /// Fractions of the map image size, like `ChapterArt.mapSpots`.
    static let mapSpots: [CGPoint] = [
        CGPoint(x: 0.875, y: 0.835),   // attic, across from chapter 2 (vault door)
        CGPoint(x: 0.875, y: 0.565),   // market, between the glass works and the pond terrace
        CGPoint(x: 0.875, y: 0.285),   // hoard, under the hall terrace, across from chapter 8
    ]

    static func wingName() -> String {
        String(localized: "Curiosity Rooms", comment: "Name of the hidden-object wing")
    }

    static func subtitle(_ room: HiddenSceneID) -> String {
        switch room {
        case .attic: String(localized: "Forty curios under the rafters. Some are on your list, the rest only look like they should be.",
                            comment: "Hidden-object room 1 subtitle")
        case .market: String(localized: "Fruit, pots and trinkets piled high. Find what the alchemist asks for.",
                             comment: "Hidden-object room 2 subtitle")
        case .hoard: String(localized: "Gold on gold. From round six, golden treasures join the list.",
                            comment: "Hidden-object room 3 subtitle")
        }
    }

    private static var backdrops: [HiddenSceneID: CGImage] = [:]

    /// The room's half-size painting (headers, the story scene behind it).
    static func backdrop(_ room: HiddenSceneID) -> CGImage? {
        if let hit = backdrops[room] { return hit }
        guard let dir = HiddenRoomAssets.folder(room),
              let src = CGImageSourceCreateWithURL(dir.appending(path: "background_1376.jpg") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        backdrops[room] = image
        return image
    }

    static func backdropImage(_ room: HiddenSceneID) -> Image {
        backdrop(room).map { Image(decorative: $0, scale: 1) } ?? Image(.bgWorkbenchLandscape)
    }
}

// MARK: - Map

/// A room's button on the chapter map: a brass magnifier over the room's colour with its stars, or a lock and
/// the chapter that opens it. Rooms never block the chapter path.
struct HiddenRoomMarker: View {
    let entry: MapHiddenRoom
    let scale: CGFloat
    let action: () -> Void
    @State private var showsLockNote = false

    private var size: CGFloat { 44 * scale }

    var body: some View {
        Button {
            if entry.isOpen { action() } else { showsLockNote = true }
        } label: {
            VStack(spacing: 2) {
                token
                plate
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .help(tooltip)
        .popover(isPresented: $showsLockNote) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(HiddenArt.wingName()): \(HiddenNames.title(entry.room))", comment: "Tooltip of a hidden-object room on the map")
                    .font(.headline)
                Label { opensText } icon: { Image(systemName: "lock.fill") }
                    .foregroundStyle(.secondary)
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private var opensText: Text {
        Text("Opens with chapter \(entry.opensWith)", comment: "Map: when a locked hidden-object room opens")
    }

    private var tooltip: Text {
        let name = Text("\(HiddenArt.wingName()): \(HiddenNames.title(entry.room))", comment: "Tooltip of a hidden-object room on the map")
        guard !entry.isOpen else { return name }
        return Text("\(name). \(opensText)", comment: "Tooltip of a locked hidden-object room: its name, then when it opens")
    }

    private var ring: Color {
        guard entry.isOpen else { return .gray }
        if entry.stars >= entry.maxStars { return .yellow }
        return entry.isComplete ? Color(red: 0.55, green: 0.85, blue: 0.45) : HiddenArt.brass
    }

    private var token: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [HiddenArt.accent(entry.room).opacity(entry.isOpen ? 0.9 : 0.35),
                                                  Color(red: 0.1, green: 0.08, blue: 0.1)],
                                         center: .center, startRadius: 1, endRadius: size * 0.6))
            Circle().strokeBorder(ring, lineWidth: 2.5 * scale)
            HiddenMagnifierIcon(dimmed: !entry.isOpen)
                .frame(width: size * 0.62, height: size * 0.62)
            if !entry.isOpen {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            } else if entry.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(.white, .green)
                    .offset(x: size * 0.38, y: -size * 0.36)
            }
            Text(verbatim: ["I", "II", "III"][entry.room.number - 1])
                .font(.system(size: 9 * scale, weight: .heavy, design: .serif))
                .foregroundStyle(.black)
                .frame(width: 17 * scale, height: 17 * scale)
                .background(Circle().fill(entry.isOpen ? HiddenArt.gold : Color.gray))
                .overlay(Circle().strokeBorder(HiddenArt.brassDark, lineWidth: 1))
                .offset(x: -size * 0.38, y: -size * 0.36)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
    }

    private var plate: some View {
        VStack(spacing: 0) {
            Text("Curiosities", comment: "Map plate over a hidden-object room marker")
                .font(.system(size: 9 * scale, weight: .bold, design: .serif))
                .foregroundStyle(HiddenArt.gold.opacity(entry.isOpen ? 1 : 0.6))
            Group {
                if entry.isOpen {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text("\(entry.stars) / \(entry.maxStars)").monospacedDigit()
                    }
                } else {
                    Text("Chapter \(entry.opensWith)", comment: "Map plate of a locked hidden-object room: the chapter that opens it")
                }
            }
            .font(.system(size: 9.5 * scale, weight: .semibold))
            .foregroundStyle(.white.opacity(entry.isOpen ? 0.95 : 0.7))
        }
        .padding(.horizontal, 6 * scale).padding(.vertical, 2 * scale)
        .background(Capsule().fill(Color(red: 0.12, green: 0.1, blue: 0.08).opacity(0.88)))
        .overlay(Capsule().strokeBorder(ring.opacity(0.55)))
        .fixedSize()
    }

    private var accessibilityText: Text {
        let title = HiddenNames.title(entry.room)
        if entry.isOpen {
            return Text("Curiosity room \(entry.room.number), \(title), \(entry.stars) of \(entry.maxStars) stars",
                        comment: "VoiceOver: an open hidden-object room on the map")
        }
        return Text("Curiosity room \(entry.room.number), \(title), locked. Opens with chapter \(entry.opensWith)",
                    comment: "VoiceOver: a locked hidden-object room on the map")
    }
}

/// A brass magnifying glass, drawn in Canvas.
struct HiddenMagnifierIcon: View {
    var dimmed = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let lens = CGRect(x: w * 0.08, y: h * 0.08, width: w * 0.6, height: h * 0.6)
            var handle = Path()
            handle.move(to: CGPoint(x: w * 0.6, y: h * 0.6))
            handle.addLine(to: CGPoint(x: w * 0.92, y: h * 0.92))
            ctx.stroke(handle, with: .color(HiddenArt.brassDark), style: StrokeStyle(lineWidth: w * 0.17, lineCap: .round))
            ctx.stroke(handle, with: .color(Color(red: 0.45, green: 0.25, blue: 0.12)), style: StrokeStyle(lineWidth: w * 0.11, lineCap: .round))
            ctx.fill(Path(ellipseIn: lens), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.55), Color(red: 0.7, green: 0.85, blue: 0.95).opacity(0.3)]),
                center: CGPoint(x: lens.minX + lens.width * 0.35, y: lens.minY + lens.height * 0.3), startRadius: 0, endRadius: lens.width * 0.6))
            ctx.stroke(Path(ellipseIn: lens), with: .color(HiddenArt.brass), lineWidth: w * 0.09)
            ctx.stroke(Path(ellipseIn: lens.insetBy(dx: w * 0.045, dy: h * 0.045)), with: .color(HiddenArt.gold.opacity(0.6)), lineWidth: w * 0.025)
            // A glint.
            var glint = Path()
            glint.addArc(center: CGPoint(x: lens.midX, y: lens.midY), radius: lens.width * 0.32,
                         startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
            ctx.stroke(glint, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: w * 0.05, lineCap: .round))
        }
        .saturation(dimmed ? 0.1 : 1)
        .brightness(dimmed ? -0.25 : 0)
        .accessibilityHidden(true)
    }
}

/// The dotted gold thread joining the rooms up the map's right edge; the stretch to an open room is bright.
struct HiddenWingThread: View {
    let rooms: [MapHiddenRoom]
    let size: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let points = HiddenArt.mapSpots.prefix(rooms.count).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            guard points.count > 1 else { return }
            for i in 1..<points.count {
                let a = points[i - 1], b = points[i]
                var path = Path()
                path.move(to: a)
                path.addCurve(to: b, control1: CGPoint(x: a.x + 18 * scale, y: a.y - (a.y - b.y) * 0.35),
                              control2: CGPoint(x: b.x - 18 * scale, y: b.y + (a.y - b.y) * 0.35))
                ctx.stroke(path.offsetBy(dx: 1.5, dy: 1.5), with: .color(.black.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round, dash: [1, 9 * scale]))
                ctx.stroke(path, with: .color(rooms[i].isOpen ? HiddenArt.gold : Color.gray.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round, dash: [1, 9 * scale]))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Room screen

/// A room's ten rounds (R11): a painted header (the room itself, its stars), then the rounds, which open in order
/// and can be replayed (each round is one fixed, curated layout, the same for every player). The room's story scene
/// plays the first time it opens.
struct HiddenRoomView: View {
    let room: HiddenSceneID
    let onPlay: (_ round: Int) -> Void

    @Environment(ProgressModel.self) private var progress
    @Environment(HiddenProgressModel.self) private var hidden
    @Environment(StoryPresenter.self) private var story

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(HiddenProgression.rounds), id: \.self) { round in
                        let unlocked = hidden.isRoundUnlocked(round, in: room)
                        Button { if unlocked { onPlay(round) } } label: {
                            HiddenRoundCell(room: room, round: round, stars: hidden.stars(room, round: round),
                                            unlocked: unlocked)
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(unlocked)
                    }
                }
                Label(String(localized: "The curiosity rooms are optional: their stars are kept apart and never lock a chapter.",
                             comment: "Footnote of a hidden-object room"),
                      systemImage: "magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background {
            HiddenArt.backdropImage(room)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 30, opaque: true)
                .overlay(Color.black.opacity(0.45))
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle(HiddenNames.title(room))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { story.show(.hidden(room.number)) } label: { Label("Story", systemImage: "text.bubble") }
                    .help(Text("Replay this room's story", comment: "Tooltip of the Story button in a hidden-object room"))
            }
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
        .task(id: room) {
            // Decode the room's pictures while the player picks a round.
            let room = room
            Task.detached(priority: .utility) { _ = try? HiddenRoomAssets.load(room) }
            guard StoryPresenter.autoPlays,
                  let scene = Story.sceneOnOpening(hiddenRoom: room.number, seen: progress.storySeen) else { return }
            try? await Task.sleep(for: .milliseconds(350))
            story.show(scene)
        }
    }

    private var header: some View {
        let stars = hidden.progress.stars(room), finished = hidden.progress.roundsFinished(room)
        let total = HiddenProgression.rounds.count
        return VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Text("\(HiddenArt.wingName()) · Room \(room.number)", comment: "Hidden-object room screen kicker")
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
            Text(HiddenNames.title(room))
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text(HiddenArt.subtitle(room))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Label { Text("\(stars) / \(total * 3)").monospacedDigit() } icon: {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                .font(.headline)
                .foregroundStyle(.white)
                ProgressView(value: Double(stars), total: Double(total * 3))
                    .tint(.yellow)
                    .frame(maxWidth: 200)
                Spacer(minLength: 0)
                Text("\(finished) of \(total) rounds", comment: "Hidden-object room header: rounds finished")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(stars) of \(total * 3) stars, \(finished) of \(total) rounds finished",
                                     comment: "VoiceOver: hidden-object room progress"))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .bottomLeading)
        .background {
            HiddenArt.backdropImage(room)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(HiddenArt.brass.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
}

/// One round of a room: number, stars, how many objects it asks for (the curve's count, which every fixed round
/// keeps: `HiddenFixedTests`); a lock while closed.
private struct HiddenRoundCell: View {
    let room: HiddenSceneID
    let round: Int
    let stars: Int
    let unlocked: Bool

    var body: some View {
        let spec = HiddenCurve.spec(room, round: round)
        VStack(spacing: 4) {
            if unlocked {
                Text(round, format: .number).font(.title2.bold().monospacedDigit())
                StarsView(count: stars, size: 10)
                Label { Text("\(spec.targets) to find", comment: "Hidden-object round cell: objects on the list") } icon: {
                    Image(systemName: "magnifyingglass")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Image(systemName: "lock.fill").font(.title3)
                Text(round, format: .number).font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .foregroundStyle(unlocked ? Color.primary : Color.primary.opacity(0.6))
        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? HiddenArt.accent(room).opacity(0.2) : Color.gray.opacity(0.18)))
        .background(unlocked ? .thinMaterial : .regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(unlocked && stars == 3 ? Color.yellow.opacity(0.6) : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(spec))
        .accessibilityAddTraits(unlocked ? .isButton : [])
    }

    private func accessibilityText(_ spec: HiddenRoundSpec) -> Text {
        guard unlocked else { return Text("Round \(round), locked", comment: "VoiceOver: a locked hidden-object round") }
        if stars > 0 {
            return Text("Round \(round), \(stars) stars, \(spec.targets) objects to find",
                        comment: "VoiceOver: a finished hidden-object round")
        }
        return Text("Round \(round), not played yet, \(spec.targets) objects to find",
                    comment: "VoiceOver: an open hidden-object round")
    }
}
