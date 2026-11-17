import BottleSortCore
import DistilleryCore
import SwiftUI

/// A distillery pack's level list (R10): a workshop stage on the map wing or a challenge pack.
/// A painted header (stage, title, stars) above its twenty stills, which open in order. A stage's
/// story scene plays the first time it opens.
struct DistillPackView: View {
    let pack: DistillPack
    let onSelect: (_ level: DistillLevel) -> Void

    @Environment(ProgressModel.self) private var progress
    @Environment(DistillProgressModel.self) private var distill
    @Environment(StoryPresenter.self) private var story

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let file = DistillLibrary.shared.file(pack) {
                    header(file)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(file.levels.indices, id: \.self) { index in
                            let level = file.levels[index]
                            let unlocked = distill.isLevelUnlocked(index, in: file)
                            Button { if unlocked { onSelect(level) } } label: {
                                DistillLevelCell(number: index + 1, level: level, stars: distill.stars(level.id),
                                                 bestTaps: distill.bestTaps(level.id), unlocked: unlocked,
                                                 teaches: DistillContent.slot(pack, index).teaches)
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(unlocked)
                        }
                    }
                } else {
                    ContentUnavailableView("Missing", systemImage: "exclamationmark.triangle",
                                           description: Text(verbatim: DistillLibrary.shared.loadErrors.joined(separator: "\n")))
                }
                Label(pack.stage == nil
                      ? String(localized: "Stars from the challenge packs are kept apart and never lock a chapter.",
                               comment: "Footnote of a distillery challenge pack")
                      : String(localized: "The distillery is optional: its stars are kept apart and never lock a chapter.",
                               comment: "Footnote of a distillery stage"),
                      systemImage: "drop")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { PaintedBackdrop(image: backdrop, style: .menu) }
        .navigationTitle(DistillWing.title(pack))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let stage = pack.stage {
                ToolbarItem(placement: .primaryAction) {
                    Button { story.show(.distillery(stage)) } label: { Label("Story", systemImage: "text.bubble") }
                        .help(Text("Replay this stage's story", comment: "Tooltip of the Story button on a distillery stage"))
                }
            }
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
        .task(id: pack) {
            guard let stage = pack.stage, StoryPresenter.autoPlays,
                  let scene = Story.sceneOnOpening(distillery: stage, seen: progress.storySeen) else { return }
            try? await Task.sleep(for: .milliseconds(350))
            story.show(scene)
        }
    }

    private var backdrop: ImageResource { pack == .stage3 || pack == .master ? .chapter09 : .bgWorkbenchLandscape }

    private var kicker: String {
        if let stage = pack.stage {
            return String(localized: "Distillery · Stage \(stage)", comment: "Distillery stage screen kicker")
        }
        return String(localized: "Distillery challenge", comment: "Distillery challenge pack screen kicker")
    }

    private func header(_ file: DistillPackFile) -> some View {
        let s = distill.summary(file)
        return VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(kicker)
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(DistillWing.title(pack))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text(DistillWing.subtitle(pack))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                StillIcon(liquid: DistillWing.liquid(pack.stage ?? 2), size: 76)
            }
            HStack(spacing: 10) {
                Label { Text("\(s.stars) / \(s.maxStars)").monospacedDigit() } icon: {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                .font(.headline)
                .foregroundStyle(.white)
                ProgressView(value: Double(s.stars), total: Double(max(1, s.maxStars)))
                    .tint(.yellow)
                    .frame(maxWidth: 200)
                Spacer(minLength: 0)
                Text("\(s.won) of \(file.levels.count) distilled", comment: "Distillery pack header: levels won")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(s.stars) of \(s.maxStars) stars, \(s.won) of \(file.levels.count) stills distilled",
                                     comment: "VoiceOver: distillery pack progress"))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .bottomLeading)
        .background {
            Image(backdrop)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(DistillArt.brass.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
}

/// One still of a pack: number, stars, the best tap count, and a "new piece" mark on the level that
/// brings one in; a lock while closed.
private struct DistillLevelCell: View {
    let number: Int
    let level: DistillLevel
    let stars: Int
    let bestTaps: Int?
    let unlocked: Bool
    /// What this level introduces ("tee", "coil" …), from the pack preset.
    let teaches: String?

    var body: some View {
        VStack(spacing: 4) {
            if unlocked {
                HStack(spacing: 5) {
                    Text(number, format: .number).font(.title2.bold().monospacedDigit())
                    if let symbol = newSymbol {
                        Image(systemName: symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DistillArt.brassLight)
                            .padding(3)
                            .background(Circle().fill(DistillArt.brassDark))
                    }
                }
                StarsView(count: stars, size: 10)
                Text(verbatim: "\(level.board.width)×\(level.board.height)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "lock.fill").font(.title3)
                Text(number, format: .number).font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .foregroundStyle(unlocked ? Color.primary : Color.primary.opacity(0.6))
        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? DistillArt.brass.opacity(0.2) : Color.gray.opacity(0.18)))
        .background(unlocked ? .thinMaterial : .regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(unlocked && stars == 3 ? Color.yellow.opacity(0.6) : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(unlocked ? .isButton : [])
    }

    private var newSymbol: String? {
        switch teaches {
        case "tee": "arrow.triangle.branch"
        case "fixed": "pin.fill"
        case "colors": "drop.halffull"
        case "cross": "plus"
        case "coil": "flame.fill"
        case "valve": "spigot.fill"
        default: nil
        }
    }

    private var accessibilityText: Text {
        guard unlocked else { return Text("Still \(number), locked", comment: "VoiceOver: a locked distillery level") }
        if let bestTaps {
            return Text("Still \(number), \(stars) stars, best \(bestTaps) taps", comment: "VoiceOver: a won distillery level")
        }
        if newSymbol != nil {
            return Text("Still \(number), new piece, not distilled yet", comment: "VoiceOver: an open distillery level that brings a new piece")
        }
        return Text("Still \(number), not distilled yet", comment: "VoiceOver: an open distillery level")
    }
}
