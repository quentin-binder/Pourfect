import BottleSortCore
import DistilleryCore
import SwiftUI

/// One distillery workshop stage on the chapter map (R10).
struct MapDistillStage: Identifiable {
    let stage: Int
    let pack: DistillPack
    let isOpen: Bool
    let stars: Int
    let maxStars: Int
    /// Levels won at least once, of `count`.
    let won: Int
    let count: Int

    var id: Int { stage }
    /// The sorting chapter that opens it (3, 6, 9).
    var opensWith: Int { DistillProgression.openingChapter(stage: stage) }
    var isComplete: Bool { count > 0 && won >= count }
}

/// Names and map places of the distillery (R10). The wing climbs the left edge of `chapter_map`:
/// one still per stage, level with the chapter that opens it (3, 6, 9) on the far side from it,
/// joined by a brass pipe. DECISIONS 281.
enum DistillWing {
    /// Fractions of the map image size, like `ChapterArt.mapSpots`.
    static let mapSpots: [CGPoint] = [
        CGPoint(x: 0.125, y: 0.770),   // stage 1, across from chapter 3 (marsh pool)
        CGPoint(x: 0.125, y: 0.600),   // stage 2, between the glass works and the pond terrace
        CGPoint(x: 0.125, y: 0.225),   // stage 3, under the dragon's cave, across from chapter 9
    ]

    static func stageTitle(_ n: Int) -> String {
        DistillPack.stage(n).map { title($0) } ?? ""
    }

    /// Localized pack titles (the core's are English).
    static func title(_ pack: DistillPack) -> String {
        switch pack {
        case .stage1: String(localized: "The Cold Still", comment: "Distillery stage 1 title")
        case .stage2: String(localized: "Copper and Steam", comment: "Distillery stage 2 title")
        case .stage3: String(localized: "The Great Alembic", comment: "Distillery stage 3 title")
        case .expert: String(localized: "Distillery Expert", comment: "Distillery challenge pack title")
        case .master: String(localized: "Distillery Master", comment: "Distillery challenge pack title")
        }
    }

    static func subtitle(_ pack: DistillPack) -> String {
        switch pack {
        case .stage1: String(localized: "One cauldron, one flask: turn the brass pipes until the potion runs through.", comment: "Distillery stage 1 subtitle")
        case .stage2: String(localized: "Splitters, riveted pieces, two potions and crossings.", comment: "Distillery stage 2 subtitle")
        case .stage3: String(localized: "Heat coils that change a potion, and valves that wait for a flask.", comment: "Distillery stage 3 subtitle")
        case .expert: String(localized: "Two or three potions and every piece. Twenty hard stills.", comment: "Distillery Expert pack subtitle")
        case .master: String(localized: "Seven by seven, valves and coils everywhere.", comment: "Distillery Master pack subtitle")
        }
    }

    /// The board's liquid color shown on a stage's still (red, blue, then green).
    static func liquid(_ stage: Int) -> Color {
        Palette.color([0, 1, 3][max(0, min(2, stage - 1))])
    }
}

extension DistillProgressModel {
    /// Whether workshop stage `n` is open: with sorting chapter 3, 6 or 9. Reads the sorting progress
    /// only; nothing here feeds back into it.
    func isStageUnlocked(_ n: Int, catalog: LevelCatalog, progress: ProgressModel) -> Bool {
        if ProgressModel.unlockAll { return DistillProgression.stages.contains(n) }
        let open = progress.unlockedChapters(catalog.chapters)
        var chapterOpen = Array(repeating: false, count: Story.chapters.upperBound)
        for (i, pack) in catalog.chapters.enumerated() {
            if let c = pack.chapter, chapterOpen.indices.contains(c - 1) { chapterOpen[c - 1] = open[i] }
        }
        return DistillProgression.isStageUnlocked(n, chapterUnlocked: chapterOpen)
    }

    func summary(_ file: DistillPackFile) -> (stars: Int, maxStars: Int, won: Int) {
        (file.levels.reduce(0) { $0 + stars($1.id) }, file.levels.count * 3, file.levels.filter { isWon($0.id) }.count)
    }

    func stageEntries(catalog: LevelCatalog, progress: ProgressModel,
                      library: DistillLibrary.Library = DistillLibrary.shared) -> [MapDistillStage] {
        DistillProgression.stages.compactMap { n in
            guard let pack = DistillPack.stage(n), let file = library.file(pack) else { return nil }
            let s = summary(file)
            return MapDistillStage(stage: n, pack: pack, isOpen: isStageUnlocked(n, catalog: catalog, progress: progress),
                                   stars: s.stars, maxStars: s.maxStars, won: s.won, count: file.levels.count)
        }
    }
}

/// A small copper pot still, drawn in Canvas: the bulb over a fire, its neck, the swan pipe and the
/// receiving flask holding `liquid`.
struct StillIcon: View {
    var liquid: Color
    var size: CGFloat = 40
    var dimmed = false
    var lit = true

    var body: some View {
        Canvas { ctx, canvas in
            let w = canvas.width, h = canvas.height
            // Fire glow under the bulb.
            if lit {
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.14, y: h * 0.72, width: w * 0.48, height: h * 0.2)),
                         with: .radialGradient(Gradient(colors: [Color.orange.opacity(0.9), Color.orange.opacity(0)]),
                                               center: CGPoint(x: w * 0.38, y: h * 0.82), startRadius: 0, endRadius: w * 0.26))
            }
            // Swan pipe from the neck down to the flask.
            var swan = Path()
            swan.move(to: CGPoint(x: w * 0.42, y: h * 0.2))
            swan.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.56), control: CGPoint(x: w * 0.78, y: h * 0.14))
            ctx.stroke(swan, with: .color(DistillArt.brassDark), style: StrokeStyle(lineWidth: w * 0.085, lineCap: .round))
            ctx.stroke(swan, with: .color(DistillArt.brass), style: StrokeStyle(lineWidth: w * 0.05, lineCap: .round))
            // Receiving flask with the potion.
            let flask = CGRect(x: w * 0.66, y: h * 0.58, width: w * 0.26, height: h * 0.28)
            ctx.fill(Path(ellipseIn: flask), with: .color(.white.opacity(0.18)))
            ctx.fill(Path(ellipseIn: flask.insetBy(dx: w * 0.03, dy: h * 0.03).offsetBy(dx: 0, dy: h * 0.035)),
                     with: .color(liquid))
            ctx.stroke(Path(ellipseIn: flask), with: .color(.white.opacity(0.75)), lineWidth: max(0.8, w * 0.025))
            // Neck and cap.
            let neck = Path(roundedRect: CGRect(x: w * 0.32, y: h * 0.16, width: w * 0.12, height: h * 0.3), cornerRadius: w * 0.03)
            ctx.fill(neck, with: .color(DistillArt.copper))
            ctx.stroke(neck, with: .color(DistillArt.brassDark), lineWidth: max(0.6, w * 0.02))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.3, y: h * 0.1, width: w * 0.16, height: h * 0.1)), with: .color(DistillArt.brass))
            // Bulb.
            let bulb = CGRect(x: w * 0.1, y: h * 0.38, width: w * 0.56, height: h * 0.46)
            ctx.fill(Path(ellipseIn: bulb), with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.72, blue: 0.45), DistillArt.copper, Color(red: 0.45, green: 0.2, blue: 0.08)]),
                center: CGPoint(x: bulb.minX + bulb.width * 0.35, y: bulb.minY + bulb.height * 0.3),
                startRadius: 0, endRadius: bulb.width * 0.7))
            ctx.stroke(Path(ellipseIn: bulb), with: .color(DistillArt.brassDark), lineWidth: max(0.8, w * 0.025))
            // A riveted brass band round the bulb's middle.
            ctx.drawLayer { band in
                band.clip(to: Path(ellipseIn: bulb))
                band.fill(Path(CGRect(x: bulb.minX, y: h * 0.6, width: bulb.width, height: h * 0.06)),
                          with: .color(DistillArt.brassDark.opacity(0.85)))
                band.fill(Path(CGRect(x: bulb.minX, y: h * 0.6, width: bulb.width, height: h * 0.025)),
                          with: .color(DistillArt.brass.opacity(0.8)))
            }
        }
        .frame(width: size, height: size)
        .saturation(dimmed ? 0.1 : 1)
        .brightness(dimmed ? -0.25 : 0)
        .accessibilityHidden(true)
    }
}

/// A distillery stage's button on the chapter map: a still on a round iron-and-brass token with its
/// stars or a lock below. A locked stage says when it opens (tooltip, and a small note when tapped);
/// the distillery never blocks the chapter path.
struct DistillStageMarker: View {
    let entry: MapDistillStage
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
                Text("Distillery: \(DistillWing.title(entry.pack))", comment: "Tooltip of a distillery stage on the map")
                    .font(.headline)
                Label { opensText } icon: { Image(systemName: "lock.fill") }
                    .foregroundStyle(.secondary)
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private var opensText: Text {
        Text("Opens with chapter \(entry.opensWith)", comment: "Map: when a locked distillery stage opens")
    }

    private var tooltip: Text {
        let name = Text("Distillery: \(DistillWing.title(entry.pack))", comment: "Tooltip of a distillery stage on the map")
        guard !entry.isOpen else { return name }
        return Text("\(name). \(opensText)", comment: "Tooltip of a locked distillery stage: its name, then when it opens")
    }

    private var ring: Color {
        guard entry.isOpen else { return .gray }
        if entry.stars >= entry.maxStars, entry.maxStars > 0 { return .yellow }
        return entry.isComplete ? Color(red: 0.55, green: 0.85, blue: 0.45) : DistillArt.brass
    }

    private var token: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.24, green: 0.23, blue: 0.25), Color(red: 0.1, green: 0.1, blue: 0.11)],
                                         center: .center, startRadius: 1, endRadius: size * 0.6))
            Circle().strokeBorder(ring, lineWidth: 2.5 * scale)
            StillIcon(liquid: DistillWing.liquid(entry.stage), size: size * 0.8, dimmed: !entry.isOpen, lit: entry.isOpen)
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
            Text(verbatim: ["I", "II", "III"][max(0, min(2, entry.stage - 1))])
                .font(.system(size: 9 * scale, weight: .heavy, design: .serif))
                .foregroundStyle(.black)
                .frame(width: 17 * scale, height: 17 * scale)
                .background(Circle().fill(entry.isOpen ? DistillArt.brassLight : Color.gray))
                .overlay(Circle().strokeBorder(DistillArt.brassDark, lineWidth: 1))
                .offset(x: -size * 0.38, y: -size * 0.36)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
    }

    private var plate: some View {
        VStack(spacing: 0) {
            Text("Distillery", comment: "Map plate over a distillery stage marker")
                .font(.system(size: 9 * scale, weight: .bold, design: .serif))
                .foregroundStyle(DistillArt.brassLight.opacity(entry.isOpen ? 1 : 0.6))
            Group {
                if entry.isOpen {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text("\(entry.stars) / \(entry.maxStars)").monospacedDigit()
                    }
                } else {
                    Text("Chapter \(entry.opensWith)", comment: "Map plate of a locked distillery stage: the chapter that opens it")
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
        let title = DistillWing.title(entry.pack)
        if entry.isOpen {
            return Text("Distillery stage \(entry.stage), \(title), \(entry.stars) of \(entry.maxStars) stars",
                        comment: "VoiceOver: an open distillery stage on the map")
        }
        return Text("Distillery stage \(entry.stage), \(title), locked. Opens with chapter \(entry.opensWith)",
                    comment: "VoiceOver: a locked distillery stage on the map")
    }
}

/// The brass pipe of the distillery wing, up the map's left edge from stage to stage; the stretch
/// up to the highest open stage carries potion.
struct DistillWingPipe: View {
    let stages: [MapDistillStage]
    let size: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let points = DistillWing.mapSpots.prefix(stages.count).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            guard points.count > 1 else { return }
            let w = 9 * scale
            for i in 1..<points.count {
                let a = points[i - 1], b = points[i]
                let segment = Path { $0.move(to: a); $0.addLine(to: b) }
                ctx.stroke(segment.offsetBy(dx: 2, dy: 2), with: .color(.black.opacity(0.45)), lineWidth: w + 1)
                ctx.stroke(segment, with: .color(DistillArt.brassDark), lineWidth: w)
                ctx.stroke(segment, with: .color(DistillArt.brass), lineWidth: w * 0.75)
                ctx.stroke(segment.offsetBy(dx: -w * 0.18, dy: 0), with: .color(DistillArt.brassLight.opacity(0.4)), lineWidth: w * 0.15)
                let wet = stages[i].isOpen
                ctx.stroke(segment, with: .color(wet ? DistillWing.liquid(stages[i].stage).opacity(0.9) : DistillArt.bore),
                           lineWidth: w * 0.36)
                // Flanged joints every so often along the pipe.
                let length = hypot(b.x - a.x, b.y - a.y)
                let joints = max(1, Int(length / (70 * scale)))
                for k in 1..<joints {
                    let t = CGFloat(k) / CGFloat(joints)
                    let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    let flange = Path(roundedRect: CGRect(x: p.x - w * 0.8, y: p.y - w * 0.22, width: w * 1.6, height: w * 0.44),
                                      cornerRadius: w * 0.15)
                    ctx.fill(flange, with: .color(DistillArt.brassDark))
                    ctx.fill(flange.offsetBy(dx: 0, dy: -w * 0.05), with: .color(DistillArt.brass))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
