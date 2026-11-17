import BottleSortCore
import DistilleryCore
import SwiftUI

/// A distillery level (R10): the HUD (taps, best, and the minimum once won), the board, Undo /
/// Restart / Hint, first-time tips, and the win card with stars by taps.
struct DistillGameView: View {
    enum Kind: Hashable {
        /// A workshop stage or challenge pack level: saved, with Next.
        case pack
        /// A Random Distillery level: nothing is saved.
        case random
        /// A Daily Distillery level of a UTC day (its result goes to `onWin`).
        case daily(DailyDate)
    }

    @State private var level: DistillLevel
    @State private var model: DistillBoardModel?
    /// The open tip, if any (first time, or "?").
    @State private var tip: [TutorialTopic]?
    let kind: Kind
    /// Called on each win (not for a demo), after the level's best is saved: the daily screen records its streak here.
    var onWin: ((_ level: DistillLevel, _ stars: Int, _ taps: Int, _ usedHint: Bool) -> Void)?
    /// Back to where the level was opened from.
    var onBack: () -> Void

    @Environment(DistillProgressModel.self) private var progress
    @Environment(DistillDailyModel.self) private var distillDaily
    @Environment(TutorialModel.self) private var tutorials
    @Environment(StoryPresenter.self) private var story
    @Environment(AppSettings.self) private var settings
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    init(level: DistillLevel, kind: Kind = .pack,
         onWin: ((DistillLevel, Int, Int, Bool) -> Void)? = nil, onBack: @escaping () -> Void) {
        _level = State(initialValue: level)
        self.kind = kind
        self.onWin = onWin
        self.onBack = onBack
    }

    var body: some View {
        Group {
            if let model {
                VStack(spacing: 12) {
                    DistillHUD(model: model, best: kind == .random ? nil : progress.bestTaps(level.id),
                               everWon: kind != .random && progress.isWon(level.id))
                    DistillBoardView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    controls(model)
                }
                .padding()
                .overlay { card(model) }
                .overlay {
                    if let tip, story.scene == nil {
                        TutorialOverlay(topics: tip) {
                            tutorials.markSeen(tip)
                            withAnimation(reduceMotion ? nil : .default) { self.tip = nil }
                        }
                        .id(tip)
                        .transition(.opacity)
                    }
                }
            } else {
                Color.clear
            }
        }
        .background { WorkbenchBackground(style: .game) }
        .environment(\.colorScheme, .dark)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.25), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(reduceMotion ? nil : .default) { tip = DistillTips.topics(for: level) } } label: {
                    Label("How to play", systemImage: "questionmark.circle")
                }
                .keyboardShortcut("/", modifiers: .command)
                .help(Text("How the distillery works", comment: "Tooltip of the distillery help button"))
            }
        }
        .task(id: level.id) { load() }
        // New piece types in this level: their tips, once the screen has settled (after a story scene).
        .task(id: "\(level.id)-\(story.scene == nil)") {
            let unseen = tutorials.unseen(DistillTips.topics(for: level))
            guard tip == nil, !unseen.isEmpty, story.scene == nil else { return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(reduceMotion ? nil : .default) { tip = unseen }
        }
        .onChange(of: settings.value, initial: true) { _, value in model?.settings = value }
        .onChange(of: reduceMotion, initial: true) { _, value in model?.reduceMotion = value }
        .task { if settings.value.soundEnabled { SoundEngine.shared.warmUp() } }
        .onDisappear { model?.stop() }
    }

    private var title: String {
        switch kind {
        case .daily:
            return String(localized: "Daily Distillery", comment: "Title of the daily distillery level")
        case .random:
            return String(localized: "Random Distillery", comment: "Title of a random distillery level")
        case .pack:
            if let title = level.title { return title }
            let number = DistillLibrary.shared.number(of: level.id) ?? 1
            return String(localized: "Still \(number)", comment: "Title of a distillery level; the argument is its number in the stage")
        }
    }

    private func load() {
        model?.stop()
        #if DEBUG
        let demo = UserDefaults.standard.integer(forKey: "LPDistillDemo")
        #else
        let demo = 0
        #endif
        let fresh = DistillBoardModel(level: level, isDemo: demo > 0)
        let played = level, kind = kind, onWin = onWin
        fresh.onWin = { [progress, distillDaily] stars, taps, usedHint in
            var newBest = false
            if kind != .random { newBest = progress.recordWin(played.id, stars: stars, taps: taps) }
            // The day's first win counts for the Daily Distillery streak (replays change nothing).
            if case .daily(let date) = kind {
                distillDaily.record(date: date, level: played, stars: stars, taps: taps, usedHint: usedHint)
            }
            onWin?(played, stars, taps, usedHint)
            return newBest
        }
        fresh.settings = settings.value
        fresh.reduceMotion = reduceMotion
        model = fresh
        #if DEBUG
        if demo > 0 { Task { await fresh.debugAutoplay(taps: demo) } }
        #endif
    }

    // MARK: Controls

    private func controls(_ model: DistillBoardModel) -> some View {
        HStack(spacing: 12) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
                .help("Undo")
            Button { model.restart() } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.taps == 0 && !model.usedHint || model.outcome != nil)
                .help("Restart")
            Button { model.hint() } label: {
                Label(model.hintBusy ? "Thinking…" : "Hint", systemImage: "lightbulb").lineLimit(1)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(model.isWon || model.hintBusy)
            .help(Text("Turns one piece towards the solution. A hint costs the third star.",
                       comment: "Tooltip of the distillery Hint button"))
            .accessibilityHint(Text("Turns one piece towards the solution. A hint costs the third star.",
                                    comment: "Tooltip of the distillery Hint button"))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: Win card

    @ViewBuilder
    private func card(_ model: DistillBoardModel) -> some View {
        if case .won(let stars, let taps, let newBest) = model.outcome {
            VStack(spacing: 14) {
                Text(stars == 3 ? LocalizedStringKey("Perfect distillation!") : LocalizedStringKey("Distilled!"))
                    .font(.largeTitle.bold())
                StarsView(count: stars, size: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(stars) stars"))
                Text("\(taps) taps · fewest possible \(model.level.minTaps)",
                     comment: "Distillery win card: taps used and the minimum")
                    .font(.title3.monospacedDigit())
                if model.usedHint {
                    Label("A hint was used, so two stars at most", systemImage: "lightbulb")
                        .foregroundStyle(.secondary)
                } else if stars < 3 {
                    Text("Three stars at \(model.level.minTaps) taps, two up to \(model.level.minTaps + DistillStars.margin(minTaps: model.level.minTaps)).",
                         comment: "Distillery win card: the tap counts for three and two stars")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if newBest {
                    Label("New best", systemImage: "rosette").foregroundStyle(DistillArt.gold)
                }
                if case .daily = kind {
                    Label {
                        Text("Daily Distillery streak \(distillDaily.stats.currentStreak)", comment: "Distillery win card of the daily level")
                    } icon: {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                    }
                    .font(.headline)
                }
                HStack {
                    Button("Retry") { model.restart() }
                        .buttonStyle(.bordered)
                    Button("Back") { onBack() }
                        .buttonStyle(.bordered)
                    if case .daily(let date) = kind, let detail = distillDaily.details[date] {
                        ShareLink(item: DistillDailyText.share(date: date, detail: detail)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    if kind == .pack, let next = DistillLibrary.shared.next(after: level.id) {
                        Button("Next Level") { level = next }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .controlSize(.large)
            }
            .padding(24)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 12)
            .padding()
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }
}

// MARK: HUD

/// Taps so far, the best win's taps, the minimum (once the level has been won), and the flasks filled.
struct DistillHUD: View {
    let model: DistillBoardModel
    let best: Int?
    let everWon: Bool

    var body: some View {
        let flow = model.flow
        HStack(spacing: 18) {
            counter(Text(model.taps, format: .number), caption: Text("taps", comment: "Distillery HUD caption under the tap count"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(model.taps) taps", comment: "VoiceOver: distillery tap count"))
            counter(Text(verbatim: best.map { "\($0)" } ?? "–"), caption: Text("best", comment: "Distillery HUD caption: fewest taps of a win"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(best.map { Text("Best \($0) taps", comment: "VoiceOver: distillery best tap count") }
                                    ?? Text("No best yet", comment: "VoiceOver: distillery level not yet won"))
            if everWon || model.isWon {
                counter(Text(model.level.minTaps, format: .number),
                        caption: Text("fewest", comment: "Distillery HUD caption: the minimum taps, shown once won"))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Fewest possible \(model.level.minTaps) taps", comment: "VoiceOver: distillery minimum taps"))
            }
            Spacer(minLength: 0)
            flasks(flow)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 640)
    }

    private func counter(_ value: Text, caption: Text) -> some View {
        VStack(spacing: 0) {
            value
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: model.taps)
            caption.font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
    }

    /// One dot per flask in its wanted color, filled once it holds it; drips and murk warnings.
    private func flasks(_ flow: DistillFlow) -> some View {
        let targets = model.board.targets
        return HStack(spacing: 8) {
            if !flow.leaks.isEmpty {
                Image(systemName: "drop.fill").foregroundStyle(.orange)
                    .help(Text("An open pipe end is dripping", comment: "Tooltip: distillery leak warning"))
            }
            if flow.murkyCount > 0 {
                Image(systemName: "smoke.fill").foregroundStyle(Color(red: 0.75, green: 0.7, blue: 0.5))
                    .help(Text("Two potions are mixing", comment: "Tooltip: distillery murk warning"))
            }
            ForEach(targets.indices, id: \.self) { i in
                let filled = flow.received[i].color == targets[i].color
                Circle()
                    .fill(filled ? Palette.color(targets[i].color.rawValue) : Color.clear)
                    .overlay(Circle().strokeBorder(Palette.color(targets[i].color.rawValue), lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .animation(.easeOut(duration: 0.3), value: filled)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: DistillSpeech.status(flow, targets: targets.count)))
    }
}
