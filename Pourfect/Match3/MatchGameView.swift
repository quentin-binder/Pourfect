import BottleSortCore
import Match3Core
import SwiftUI

/// An ingredient-gathering level (R9): the HUD (moves left, goals, score with star marks), the
/// board, and the win or "Out of moves" card. Retry is always free.
struct MatchGameView: View {
    /// The level being played (Next moves on to the episode's next level).
    @State private var level: M3Level
    @State private var model: MatchBoardModel?
    /// The open tip, if any (first time, or "?").
    @State private var tip: [TutorialTopic]?
    /// The UTC day of a Daily Gathering level (its first win counts for the streak); nil for episodes.
    var daily: DailyDate?
    /// Back to the chapter map.
    var onMap: () -> Void
    @Environment(Match3ProgressModel.self) private var m3progress
    @Environment(M3DailyModel.self) private var m3daily
    @Environment(TutorialModel.self) private var tutorials
    @Environment(StoryPresenter.self) private var story
    @Environment(AppSettings.self) private var settings
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @Environment(\.colorRunesEnabled) private var runes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(level: M3Level, daily: DailyDate? = nil, onMap: @escaping () -> Void) {
        _level = State(initialValue: level)
        self.daily = daily
        self.onMap = onMap
    }

    var body: some View {
        Group {
            if let model {
                VStack(spacing: 14) {
                    MatchHUD(model: model, runes: runes)
                    ZStack(alignment: .top) {
                        MatchBoardView(model: model)
                        banner(model)
                    }
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
                ContentUnavailableView("This level can't be played", systemImage: "exclamationmark.triangle",
                                       description: Text("Its board could not be set up."))
            }
        }
        .background { WorkbenchBackground(style: .game) }
        .environment(\.colorScheme, .dark)
        .navigationTitle(level.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.25), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(reduceMotion ? nil : .default) { tip = M3Tips.topics(for: level) } } label: {
                    Label("How to play", systemImage: "questionmark.circle")
                }
                .keyboardShortcut("/", modifiers: .command)
                .help(Text("How this level works", comment: "Tooltip of the match-3 help button"))
                .accessibilityLabel(Text("How to play this level", comment: "VoiceOver: the match-3 help button"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model?.restart() } label: { Label("Retry", systemImage: "arrow.counterclockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Start this level over")
            }
        }
        .task(id: level.id) { load() }
        // New things in this level: their tips, once the screen has settled (after a story scene).
        .task(id: "\(level.id)-\(story.scene == nil)") {
            let unseen = tutorials.unseen(M3Tips.topics(for: level))
            guard tip == nil, !unseen.isEmpty, story.scene == nil else { return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(reduceMotion ? nil : .default) { tip = unseen }
        }
        .onChange(of: settings.value, initial: true) { _, value in model?.settings = value }
        .onChange(of: reduceMotion, initial: true) { _, value in model?.reduceMotion = value }
        // The idle hint: after about 5 s without input, one valid swap glows (free).
        .task(id: model.map { "\($0.idleTick)-\($0.busy)" }) {
            guard let model, !model.busy, model.isPlaying, tip == nil else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            model.showHint()
        }
        .task { if settings.value.soundEnabled { SoundEngine.shared.warmUp() } }
        .onDisappear { model?.stop() }
    }

    private func load() {
        model?.stop()
        #if DEBUG
        let demo = UserDefaults.standard.integer(forKey: "LPM3Demo") > 0
        #else
        let demo = false
        #endif
        let fresh = MatchBoardModel(level: level, isDemo: demo)
        let played = level, date = daily
        fresh?.onWin = { [m3progress, m3daily] stars, score, movesLeft in
            if let date {
                _ = m3daily.record(date: date, level: played, stars: stars, score: score, movesLeft: movesLeft)
            }
            return m3progress.recordWin(played.id, stars: stars, score: score)
        }
        fresh?.settings = settings.value
        fresh?.reduceMotion = reduceMotion
        model = fresh
        fresh?.start()
        #if DEBUG
        let moves = UserDefaults.standard.integer(forKey: "LPM3Demo")
        if moves > 0, let fresh {
            Task { await fresh.debugAutoplay(moves: moves) }
        }
        #endif
    }

    // MARK: Banner and cards

    @ViewBuilder
    private func banner(_ model: MatchBoardModel) -> some View {
        Group {
            switch model.banner {
            case .finale:
                bannerText(Text("Bubbling Over!", comment: "Match-3 finale: the moves left become specials that fire"),
                           icon: "flame")
            case .shuffle:
                bannerText(Text("No swaps left: stirring the tray", comment: "Match-3: the board is reshuffled"),
                           icon: "arrow.triangle.2.circlepath")
            case .cascade(let n):
                bannerText(Text("Cascade ×\(n)", comment: "Match-3: several matches in a row after one swap"),
                           icon: "sparkles")
            case nil:
                EmptyView()
            }
        }
        .padding(.top, 6)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.4), value: model.banner)
    }

    private func bannerText(_ text: Text, icon: String) -> some View {
        Label { text } icon: { Image(systemName: icon) }
            .font(.title3.weight(.bold))
            .foregroundStyle(M3Colors.gold)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(M3Colors.gold.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func card(_ model: MatchBoardModel) -> some View {
        switch model.outcome {
        case .won(let stars, let score, let newBest, _):
            resultCard {
                Text("Gathered!", comment: "Match-3 win card title").font(.largeTitle.bold())
                StarsView(count: stars, size: 32)
                Text("Score \(score)", comment: "Match-3 win card: the final score").font(.title3.monospacedDigit())
                if newBest {
                    Label("New best score", systemImage: "rosette").foregroundStyle(M3Colors.gold)
                }
                if daily != nil {
                    Label {
                        Text("Daily Gathering streak \(m3daily.stats.currentStreak)", comment: "Match-3 win card of the daily level")
                    } icon: {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                    }
                    .font(.headline)
                }
                HStack {
                    Button("Retry") { model.restart() }
                        .buttonStyle(.bordered)
                    Button(daily == nil ? LocalizedStringKey("Map") : LocalizedStringKey("Back")) { onMap() }
                        .buttonStyle(.bordered)
                    if let daily, let detail = m3daily.details[daily] {
                        ShareLink(item: M3DailyText.share(date: daily, detail: detail)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    if daily == nil, let next = Match3Library.shared.next(after: level.id) {
                        Button("Next Level") { level = next }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .controlSize(.large)
            }
        case .lost:
            resultCard {
                Text("Out of moves", comment: "Match-3 card when the moves run out").font(.largeTitle.bold())
                Text("Retrying is free, and the board starts the same way.",
                     comment: "Match-3 out-of-moves card: retry costs nothing; the seed gives the same start")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
                HStack(spacing: 14) {
                    ForEach(level.goals.indices, id: \.self) { i in
                        GoalChip(goal: level.goals[i], progress: model.progress(level.goals[i]), runes: runes)
                    }
                }
                HStack {
                    Button(daily == nil ? LocalizedStringKey("Map") : LocalizedStringKey("Back")) { onMap() }
                        .buttonStyle(.bordered)
                    Button("Retry") { model.restart() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        case nil:
            EmptyView()
        }
    }

    private func resultCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 14, content: content)
            .padding(24)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 12)
            .padding()
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
    }
}

// MARK: HUD

/// Moves left, the goals with their counters, and the score with its star marks.
struct MatchHUD: View {
    let model: MatchBoardModel
    let runes: Bool

    var body: some View {
        let hud = model.hud
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                moves(hud.moves)
                goals
                Spacer(minLength: 0)
                ScoreMeter(score: hud.score, stars: model.level.stars).frame(width: 170)
            }
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    moves(hud.moves)
                    ScoreMeter(score: hud.score, stars: model.level.stars)
                }
                goals
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 640)
    }

    private func moves(_ count: Int) -> some View {
        VStack(spacing: 0) {
            Text(count, format: .number)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(count <= 3 ? Color.orange : Color.primary)
                .animation(.snappy, value: count)
            Text("moves", comment: "Match-3 HUD caption under the moves left").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) moves left", comment: "VoiceOver: match-3 moves left"))
    }

    private var goals: some View {
        HStack(spacing: 14) {
            ForEach(model.level.goals.indices, id: \.self) { i in
                GoalChip(goal: model.level.goals[i], progress: model.progress(model.level.goals[i]), runes: runes)
            }
        }
    }
}

/// One goal: its icon and "12/20", or a check mark once it is met.
struct GoalChip: View {
    let goal: M3Goal
    let progress: (current: Int, target: Int)
    let runes: Bool

    var body: some View {
        let done = progress.current >= progress.target
        HStack(spacing: 5) {
            icon
                .frame(width: 26, height: 26)
                .overlay(alignment: .bottomTrailing) {
                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white, .green)
                            .offset(x: 4, y: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            if goal.type == .score {
                Text(progress.target, format: .number).font(.subheadline.weight(.semibold).monospacedDigit())
            } else {
                Text(verbatim: "\(max(0, progress.target - progress.current))")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: progress.current)
            }
        }
        .opacity(done ? 0.75 : 1)
        .animation(.spring(duration: 0.3), value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Match3Goals.name(goal)): \(progress.current) of \(progress.target)",
                                 comment: "VoiceOver: a match-3 goal and its progress"))
    }

    @ViewBuilder private var icon: some View {
        switch goal.type {
        case .collect:
            if let kind = goal.kind { M3KindIcon(kind: kind, size: 26, runes: runes) }
        case .frost:
            IceCrystal(size: 24, turns: nil)
        case .crates:
            M3CrateView(hits: 1, size: 26)
        case .drops:
            M3FlaskView(size: 28)
        case .score:
            Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(M3Colors.gold)
        }
    }
}

/// The score and a bar with marks at the two- and three-star thresholds.
struct ScoreMeter: View {
    let score: Int
    let stars: M3StarThresholds

    var body: some View {
        let top = Double(stars.three) * 1.08
        VStack(alignment: .leading, spacing: 4) {
            Text(score, format: .number)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy, value: score)
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(LinearGradient(colors: [M3Colors.flaskLiquid, M3Colors.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, w * min(1, Double(score) / top)))
                        .animation(.easeOut(duration: 0.4), value: score)
                    ForEach([stars.two, stars.three], id: \.self) { mark in
                        Image(systemName: score >= mark ? "star.fill" : "star")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(score >= mark ? Color.yellow : Color.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .position(x: w * Double(mark) / top, y: 4)
                    }
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Score \(score); two stars at \(stars.two), three stars at \(stars.three)",
                                 comment: "VoiceOver: match-3 score and star thresholds"))
    }
}
