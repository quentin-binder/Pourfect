import BottleSortCore
import SwiftUI

struct GameView: View {
    @State var model: GameViewModel
    @Environment(AppSettings.self) private var settings
    /// Reduce Motion after the in-app override.
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @Environment(TutorialModel.self) private var tutorials
    @Environment(DailyModel.self) private var daily
    @Environment(\.dismiss) private var dismiss
    /// The tip on screen, if any (first time a mechanic appears, or the "?" button).
    @State private var tip: [TutorialTopic]?

    private let maxPerRow = 7

    var body: some View {
        VStack(spacing: 16) {
            hud
            GeometryReader { geo in
                board(in: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlayPreferenceValue(BottleFramesKey.self) { pourLayer($0) }
            }
            controls
        }
        .padding()
        .overlay { overlay }
        .overlay(alignment: .top) { message }
        .overlay {
            if let tip {
                TutorialOverlay(topics: tip) {
                    tutorials.markSeen(tip)
                    withAnimation { self.tip = nil }
                }
                .id(tip)
                .transition(.opacity)
            }
        }
        .task(id: model.level.id) {
            // First time a mechanic appears: show its tip once the screen has settled.
            let unseen = tutorials.unseen(model.tutorialTopics)
            guard tip == nil, !unseen.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation { tip = unseen }
        }
        // The workbench is a dark scene: glass outlines, text and materials use the dark look.
        .background { WorkbenchBackground(style: .game) }
        .environment(\.colorScheme, .dark)
        .onChange(of: model.feedback.last?.id) { previous, _ in
            for item in model.feedback(after: previous) {
                FeedbackPlayer.play(item.event, settings: settings.value, reduceMotion: reduceMotion)
            }
        }
        .onChange(of: model.cancelledPours) { FeedbackPlayer.cancelPending() }
        .task { if settings.value.soundEnabled { SoundEngine.shared.warmUp() } }
        .navigationTitle(model.title)
        .onDisappear {
            model.randomMaker.cancel()   // left the screen: stop generating
            FeedbackPlayer.cancelPending()
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Light bar content over the dark workbench, on a faint dark wash.
        .toolbarBackground(Color.black.opacity(0.25), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        #if DEBUG
        // Dev aid: `-LPDemoMoves K` plays the first K optimal moves via taps (0 = off).
        .task {
            let k = UserDefaults.standard.integer(forKey: "LPDemoMoves")
            if k > 0 { await model.debugPlayOptimal(moves: k) }
            // `-LPDemoUndo N`: then undoes N moves, one per second (to check corks popping off).
            for _ in 0..<UserDefaults.standard.integer(forKey: "LPDemoUndo") {
                while model.pour != nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.easeInOut(duration: 0.3)) { model.undo() }
            }
        }
        #endif
    }

    private var isWon: Bool { if case .won = model.status { return true } else { return false } }
    /// Win / stuck cards wait until the pour that caused them has finished animating.
    private var showsResult: Bool { model.pour == nil }

    // MARK: HUD

    private var hud: some View {
        HStack {
            Text(model.title).font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text("Moves \(model.moveCount)").font(.headline.monospacedDigit())
            if let best = model.minMoves {
                Text("· Best \(best)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { withAnimation { tip = model.tutorialTopics } } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .keyboardShortcut("/", modifiers: .command)
            .help("How this recipe works")
            .accessibilityLabel(Text("How to play this recipe"))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.3)) { model.undo() } } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!model.canUndo || isWon)

            Button { withAnimation(.easeInOut(duration: 0.3)) { model.restart() } } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.moveCount == 0)

            Button { model.requestHint() } label: {
                Label(model.isThinking ? "Thinking…" : "Hint", systemImage: "lightbulb")
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(isWon || model.isThinking)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: Board

    private func board(in size: CGSize) -> some View {
        let bottles = model.state.bottles
        let rowCount = max(1, Int((Double(bottles.count) / Double(maxPerRow)).rounded(.up)))
        let perRow = Int((Double(bottles.count) / Double(rowCount)).rounded(.up))
        let capacity = CGFloat(bottles.first?.capacity ?? 4)
        let spacing: CGFloat = 14
        // Fit width: perRow bottles + spacing. Fit height: rows × (capacity × 0.78w + 0.45w) + lift room.
        let byWidth = (size.width - spacing * CGFloat(perRow - 1)) / CGFloat(perRow)
        let byHeight = (size.height - 40 * CGFloat(rowCount)) / (CGFloat(rowCount) * (capacity * 0.78 + 0.45 + 0.3))
        let width = max(24, min(byWidth, byHeight, 72))
        let rows = stride(from: 0, to: bottles.count, by: perRow).map { Array($0..<min($0 + perRow, bottles.count)) }

        return VStack(spacing: 40) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(row, id: \.self) { index in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { model.tap(bottle: index) }
                        } label: {
                            BottleView(bottle: bottles[index], width: width,
                                       hiddenLayers: model.hiddenLayerCount(index),
                                       isSelected: model.selected == index,
                                       hintRole: hintRole(for: index),
                                       shakes: model.shakes.indices.contains(index) ? model.shakes[index] : 0,
                                       completions: model.completions.indices.contains(index)
                                           ? model.completions[index] : 0)
                        }
                        .buttonStyle(.plain)
                        .anchorPreference(key: BottleFramesKey.self, value: .bounds) { [index: $0] }
                        // The pour animation draws these two bottles itself; swap without fading.
                        .animation(nil) { $0.opacity(isPouring(index) ? 0 : 1) }
                        .accessibilityLabel(Text("Flask \(index + 1)"))
                        .accessibilityValue(bottles[index].spokenContents(hiddenLayers: model.hiddenLayerCount(index)))
                    }
                }
            }
        }
    }

    private func isPouring(_ index: Int) -> Bool {
        guard let pour = model.pour else { return false }
        return pour.from == index || pour.to == index
    }

    @ViewBuilder
    private func pourLayer(_ frames: [Int: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let pour = model.pour, let from = frames[pour.from], let to = frames[pour.to] {
                PourAnimationView(event: pour, sourceFrame: proxy[from], targetFrame: proxy[to],
                                  boardSize: proxy.size, reduceMotion: reduceMotion) {
                    withAnimation(.easeInOut(duration: 0.3)) { model.finishPour(pour.id) }
                }
                .id(pour.id)
                .transition(.identity)   // the board's own bottles take over in the same frame
            }
        }
        .allowsHitTesting(false)
    }

    private func hintRole(for index: Int) -> BottleView.HintRole? {
        guard let hint = model.hint else { return nil }
        if hint.from == index { return .source }
        if hint.to == index { return .target }
        return nil
    }

    // MARK: Overlays

    @ViewBuilder private var overlay: some View {
        switch showsResult ? model.status : .playing {
        case .won where model.isDaily:
            dailyWinCard
        case .won(let stars):
            card {
                Text("Brewed!").font(.largeTitle.bold())
                StarsView(count: stars, size: 32)
                Text("\(model.moveCount) moves · best possible \(model.minMoves ?? model.moveCount)")
                    .foregroundStyle(.secondary)
                if model.isRandom {
                    randomStatus
                }
                HStack {
                    Button("Replay") { withAnimation { model.restart() } }
                        .buttonStyle(.bordered)
                    if model.isRandom {
                        Button {
                            withAnimation { model.newRandomLevel() }
                        } label: {
                            Label(model.randomMaker.phase == .failed ? "Try Again" : "New Random Brew",
                                  systemImage: "dice")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.randomMaker.isGenerating)
                    } else if model.hasNextLevel {
                        Button("Next Recipe") { withAnimation { model.nextLevel() } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .controlSize(.large)
            }
        case .stuck:
            VStack {
                Spacer()
                card {
                    Text("Stuck — undo or restart?").font(.headline)
                    HStack {
                        Button("Undo") { withAnimation { model.undo() } }.disabled(!model.canUndo)
                        Button("Restart") { withAnimation { model.restart() } }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 70)
            }
        case .playing:
            EmptyView()
        }
    }

    // MARK: Daily win

    /// The daily's win card: solved / perfect, streak, share. Never shows chapter stars.
    private var dailyWinCard: some View {
        card {
            switch model.dailyOutcome {
            case .recorded(let result):
                Label("Daily solved!", systemImage: "sparkles")
                    .font(.largeTitle.bold())
                dailyBadge(result)
                streakLine
                ShareLink(item: DailyText.share(result, streak: daily.stats.currentStreak)) {
                    Label("Share Result", systemImage: "square.and.arrow.up")
                }
            case .alreadySolved(let first):
                Text("Brewed again!").font(.largeTitle.bold())
                Text("\(model.moveCount) moves this time. Your first solve of the day is the one that counts.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 340)
                dailyBadge(first)
                streakLine
                ShareLink(item: DailyText.share(first, streak: daily.stats.currentStreak)) {
                    Label("Share Result", systemImage: "square.and.arrow.up")
                }
            case .clockBehind:
                Text("Brewed!").font(.largeTitle.bold())
                Text("Your device's clock is earlier than a brew you already solved, so this one doesn't count.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 340)
            case .dayEnded, nil:
                Text("Brewed!").font(.largeTitle.bold())
                Text("This brew's day ended at midnight UTC, so it no longer counts. Today's new brew is waiting.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 340)
            }
            HStack {
                Button("Replay") { withAnimation { model.restart() } }
                    .buttonStyle(.bordered)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }

    /// Perfect badge, or the moves against the minimum (and why a hint cost the badge).
    @ViewBuilder private func dailyBadge(_ result: DailyResult) -> some View {
        if result.isPerfect {
            PerfectBadge(large: true)
            Text("\(result.moves) moves, the fewest possible")
                .foregroundStyle(.secondary)
        } else {
            Text("\(result.moves) moves · perfect is \(result.minMoves)")
                .font(.headline.monospacedDigit())
            if result.usedHint {
                Label("A hint was used, so this brew can't be perfect", systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var streakLine: some View {
        let stats = daily.stats
        return HStack(spacing: 14) {
            StreakFlame(count: stats.currentStreak)
            Text("Best \(stats.bestStreak)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Progress / failure of "New Random Brew" on the win card.
    @ViewBuilder private var randomStatus: some View {
        switch model.randomMaker.phase {
        case .generating(let attempt, let total):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Attempt \(attempt) of \(total)").monospacedDigit()
            }
            .foregroundStyle(.secondary)
        case .failed:
            Text(RandomLevelMaker.failureMessage)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.orange)
                .frame(maxWidth: 320)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var message: some View {
        if let text = model.hintMessage {
            Text(text)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 40)
                .transition(.opacity)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 14, content: content)
            .padding(24)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 12)
            .transition(.scale.combined(with: .opacity))
    }
}
