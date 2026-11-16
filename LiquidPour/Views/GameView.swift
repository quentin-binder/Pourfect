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

    var body: some View {
        VStack(spacing: 16) {
            hud
                // Messages hang just below the HUD (its height differs between Mac and iPhone),
                // above the board.
                .overlay(alignment: .bottom) {
                    message.alignmentGuide(.bottom) { $0[.top] - 8 }
                }
                .zIndex(1)
            GeometryReader { geo in
                board(in: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Chains and pipes between linked flasks, at the flasks' actual places.
                    .overlayPreferenceValue(BottleFramesKey.self) { linkLayer($0) }
                    .overlayPreferenceValue(BottleFramesKey.self) { pourLayer($0) }
            }
            controls
        }
        .padding()
        .overlay { overlay }
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
        // Dev aid: `-LPDemoMoves K` plays the first K optimal moves via taps (0 = off; a demo win
        // saves nothing).
        .task {
            let k = UserDefaults.standard.integer(forKey: "LPDemoMoves")
            if k > 0 { await model.debugPlayOptimal(moves: k) }
            // `-LPDemoUndo N`: then undoes N moves, one per second (to check corks popping off).
            // `-LPDemoRefuse S`: then, after S seconds, tries a pour an essence flask refuses
            // (rune flare + message).
            // `-LPDemoIcePour S`: then, after S seconds, pours from above a frozen layer.
            let iceDelay = UserDefaults.standard.double(forKey: "LPDemoIcePour")
            if iceDelay > 0 {
                while model.pour != nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .seconds(iceDelay))
                withAnimation(.easeInOut(duration: 0.3)) { model.debugIcePour() }
            }
            // `-LPDemoLinkPour S`: then, after S seconds, plays a pour that runs through an
            // overflow pipe (else one split between twins).
            let linkDelay = UserDefaults.standard.double(forKey: "LPDemoLinkPour")
            if linkDelay > 0 {
                while model.pour != nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .seconds(linkDelay))
                withAnimation(.easeInOut(duration: 0.3)) { model.debugLinkPour() }
            }
            let refuseDelay = UserDefaults.standard.double(forKey: "LPDemoRefuse")
            if refuseDelay > 0 {
                while model.pour != nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .seconds(refuseDelay))
                withAnimation(.easeInOut(duration: 0.3)) { model.debugRefusedPour() }
            }
            for _ in 0..<UserDefaults.standard.integer(forKey: "LPDemoUndo") {
                while model.pour != nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.easeInOut(duration: 0.3)) { model.undo() }
            }
        }
        #endif
    }

    private var isWon: Bool { if case .won = model.status { return true } else { return false } }
    /// Win / stuck cards wait until the pour that caused them has finished animating (and a
    /// mix it made has settled).
    private var showsResult: Bool { model.pour == nil && !model.isMixing }

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
        let rows = BoardLayout.rows(count: bottles.count)
        let rowCount = rows.count
        let perRow = BoardLayout.perRow(count: bottles.count)
        let capacity = CGFloat(bottles.first?.capacity ?? 4)
        // A tap's spigot sticks out on the right, a cauldron's pot bulges on both sides: a little
        // more room between flasks.
        let spacing: CGFloat = bottles.contains { $0.hasTap || $0.isCauldron } ? 22 : 14
        // A narrow neck or a funnel stands above its flask (in widths): room for it on every row.
        // An overflow pipe arches above the rims of its flasks (about half a width), and so does
        // a switch's lever (over a gate's housing).
        let pipe: CGFloat = model.state.links.contains { if case .twins = $0 { return false } else { return true } }
            ? 0.6 : 0
        let parts = max(bottles.map { GlassParts($0).riseInWidths }.max() ?? 0, pipe)
        // Fit width: perRow bottles + spacing. Fit height: rows × (capacity × 0.78w + 0.45w) + lift room.
        // Linked flasks side by side get a wider gap for their chain or pipe (`linkGap`, in widths).
        let pairsPerRow = rows.map { row in row.filter { linkedRight(of: $0, in: row) }.count }.max() ?? 0
        let byWidth = (size.width - spacing * CGFloat(perRow - 1)) / (CGFloat(perRow) + Self.linkGap * CGFloat(pairsPerRow))
        // A bubbling flask's dial hangs under its base (about 0.52w): room for it under every row.
        // A cauldron's legs and recipe card hang under it: room for them under every row.
        let recipeRows = bottles.map(\.recipes.count).max() ?? 0
        let card = RecipeCard.roomInWidths(rows: recipeRows)
        let dial: CGFloat = bottles.contains { $0.bubbling != nil } ? 0.52 : 0
        let byHeight = (size.height - 40 * CGFloat(rowCount))
            / (CGFloat(rowCount) * (capacity * 0.78 + 0.45 + 0.3 + parts + max(dial, card)))
        let width = max(24, min(byWidth, byHeight, 72))
        let dialRoom = max(dial > 0 ? BubbleGauge.room(width) : 0, RecipeCard.room(width, rows: recipeRows))

        return VStack(spacing: 40 + parts * width + dialRoom) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(row, id: \.self) { index in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { model.tap(bottle: index) }
                        } label: {
                            BottleView(bottle: model.bottle(index), width: width,
                                       hidden: model.hiddenMask(index),
                                       isSelected: model.selected == index,
                                       hintRole: hintRole(for: index),
                                       shakes: model.shakes.indices.contains(index) ? model.shakes[index] : 0,
                                       completions: model.completions.indices.contains(index)
                                           ? model.completions[index] : 0,
                                       refusals: model.refusals.indices.contains(index) ? model.refusals[index] : 0,
                                       ice: model.ice(index),
                                       thaws: model.thaws(index),
                                       bubbling: model.bubbling(index),
                                       rise: model.rise(index),
                                       twin: model.state.twin(of: index) != nil,
                                       chainRefusals: chainRefusals(index),
                                       mix: model.mix(index))
                        }
                        .buttonStyle(.plain)
                        .anchorPreference(key: BottleFramesKey.self, value: .bounds) { [index: $0] }
                        // The pour animation draws these two bottles itself; swap without fading.
                        .animation(nil) { $0.opacity(isPouring(index) ? 0 : 1) }
                        .accessibilityLabel(Text("Flask \(index + 1)"))
                        .accessibilityValue(spokenValue(index))
                        .padding(.trailing, linkedRight(of: index, in: row) ? Self.linkGap * width : 0)
                    }
                }
            }
        }
        .padding(.bottom, dialRoom)
        // The top row's pipe arches above its rims.
        .padding(.top, pipe * width)
    }

    /// Extra room (in flask widths) between two linked flasks standing side by side.
    private static let linkGap: CGFloat = 0.4

    /// Whether the flask right of `index` in its row is its link partner.
    private func linkedRight(of index: Int, in row: [Int]) -> Bool {
        guard let link = model.state.link(at: index), row.contains(index + 1) else { return false }
        return link.endpoints.0 == index + 1 || link.endpoints.1 == index + 1
    }

    private func isPouring(_ index: Int) -> Bool {
        model.pour?.bottles.contains(index) ?? false
    }

    /// The flask's contents for VoiceOver, plus its link (twin chain, overflow pipe, switch or gate).
    private func spokenValue(_ index: Int) -> String {
        let contents = model.state.bottles[index].spokenContents(hidden: model.hiddenMask(index))
        switch LinkRole(model.state, bottle: index) {
        case .twin(let other):
            return contents + ", " + String(localized: "twin of flask \(other + 1), every pour into either is split evenly between both",
                                            comment: "VoiceOver: a twin flask; the argument is the other twin's number")
        case .pipeOut(let to):
            return contents + ", " + String(localized: "overflow pipe into flask \(to + 1), what doesn't fit runs on",
                                            comment: "VoiceOver: the flask an overflow pipe starts from; the argument is the flask it runs into")
        case .pipeIn(let from):
            return contents + ", " + String(localized: "the overflow pipe of flask \(from + 1) runs into it",
                                            comment: "VoiceOver: the flask an overflow pipe ends over; the argument is the flask it starts from")
        case .switchOf(let gate):
            if Rules.isSwitchOn(model.state.bottles[index]) {
                return contents + ", " + String(localized: "switch flask, full of one potion: the gate of flask \(gate + 1) is open",
                                                comment: "VoiceOver: a switch flask that is complete; the argument is its gate's flask number")
            }
            return contents + ", " + String(localized: "switch flask, fill it with one potion to open the gate of flask \(gate + 1)",
                                            comment: "VoiceOver: a switch flask that is not complete; the argument is its gate's flask number")
        case .gateOf(let s):
            if model.state.isGateClosed(index) {
                return contents + ", " + String(localized: "gate shut, nothing pours in or out until flask \(s + 1) is full of one potion",
                                                comment: "VoiceOver: a closed gate flask; the argument is its switch's flask number")
            }
            return contents + ", " + String(localized: "gate open while flask \(s + 1) stays full of one potion",
                                            comment: "VoiceOver: an open gate flask; the argument is its switch's flask number")
        case nil:
            return contents
        }
    }

    /// How often the chain of twin `index` has refused a pour (its band glints each time).
    private func chainRefusals(_ index: Int) -> Int {
        guard let link = model.state.link(at: index), let i = model.state.links.firstIndex(of: link),
              model.linkRefusals.indices.contains(i) else { return 0 }
        return model.linkRefusals[i]
    }

    /// The chains, pipes and switch levers, drawn between the flasks' frames on the board (after the shuffle and
    /// any resize). A link follows a flask that is picked up, and fades while one of its flasks
    /// is in the air pouring (the pour animation draws that flask).
    @ViewBuilder
    private func linkLayer(_ frames: [Int: Anchor<CGRect>]) -> some View {
        let links = model.state.links
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(links.indices, id: \.self) { i in
                    let link = links[i]
                    let (a, b) = link.endpoints
                    if let fa = frames[a], let fb = frames[b] {
                        let ra = proxy[fa], rb = proxy[fb]
                        let lifted = { (bottle: Int, w: CGFloat) -> CGFloat in model.selected == bottle ? w * 0.3 : 0 }
                        // A switch in the air takes its rod and gem along; the gate keeps its
                        // housing and portcullis on the board.
                        let isSwitch: Bool = { if case .switchGate = link { return true } else { return false } }()
                        let switchAway = isSwitch && model.pour?.from == a
                        let flying = model.pour?.from == b || (!isSwitch && model.pour?.from == a)
                        let refusals = model.linkRefusals.indices.contains(i) ? model.linkRefusals[i] : 0
                        // A switch link: the gate shown open or shut (as before the move while a
                        // pour is in the air), and how far the gate's neck or funnel stands up.
                        let open: Double = model.gateOpen(link: i) ? 1 : 0
                        let rise = GlassParts(model.state.bottles[b]).rise(rb.width)
                        let slides = !reduceMotion
                        let gateAnimation = GatePose.animation(reduceMotion: reduceMotion)
                        // The ends follow their flasks' shake (same count and timing as `BottleView`).
                        let shake = { (bottle: Int) -> CGFloat in
                            model.shakes.indices.contains(bottle) ? CGFloat(model.shakes[bottle]) : 0
                        }
                        LinkView(link: link, a: ra, b: rb, liftA: lifted(a, ra.width), liftB: lifted(b, rb.width),
                                 shakeA: shake(a), shakeB: shake(b), open: open, gateRise: rise, slides: slides,
                                 switchAway: switchAway)
                            .keyframeAnimator(initialValue: 0.0, trigger: refusals) { _, flare in
                                LinkView(link: link, a: ra, b: rb, liftA: lifted(a, ra.width), liftB: lifted(b, rb.width),
                                         shakeA: shake(a), shakeB: shake(b), flare: flare, open: open, gateRise: rise,
                                         slides: slides, switchAway: switchAway)
                                    // The portcullis slides up (or drops) and the gem lights (or
                                    // dims); set here, inside the animator's content, so it applies.
                                    .animation(gateAnimation, value: open)
                            } keyframes: { _ in
                                KeyframeTrack {
                                    LinearKeyframe(1, duration: 0.12, timingCurve: .easeOut)
                                    LinearKeyframe(1, duration: 0.25)
                                    LinearKeyframe(0, duration: 0.45, timingCurve: .easeIn)
                                }
                            }
                            .animation(.easeInOut(duration: 0.35), value: model.shakes)
                            .opacity(flying ? 0 : 1)
                            .animation(.easeInOut(duration: 0.25), value: flying)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pourLayer(_ frames: [Int: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let pour = model.pour, let from = frames[pour.from], let to = frames[pour.to] {
                let shareFrames = Dictionary(uniqueKeysWithValues: pour.shares.compactMap { share in
                    frames[share.bottle].map { (share.bottle, proxy[$0]) }
                })
                // Chains and pipes of the flasks drawn by the pour (not the flying source's: they
                // fade on the board meanwhile), redrawn above those flasks.
                let links = model.state.links.indices.compactMap { i -> PourLink? in
                    let link = model.state.links[i]
                    let (a, b) = link.endpoints
                    guard a != pour.from, b != pour.from, pour.bottles.contains(a) || pour.bottles.contains(b),
                          let fa = frames[a], let fb = frames[b] else { return nil }
                    let gate = proxy[fb]
                    return PourLink(link: link, a: proxy[fa], b: gate, open: model.gateOpen(link: i) ? 1 : 0,
                                    gateRise: GlassParts(model.state.bottles[b]).rise(gate.width))
                }
                PourAnimationView(event: pour, sourceFrame: proxy[from], targetFrame: proxy[to],
                                  shareFrames: shareFrames, links: links,
                                  boardSize: proxy.size, reduceMotion: reduceMotion) {
                    withAnimation(.easeInOut(duration: 0.3)) { model.finishPour(pour.id, reduceMotion: reduceMotion) }
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
        // A hinted pour into a twin fills both twins.
        if model.state.twin(of: hint.to) == index { return .target }
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
                .multilineTextAlignment(.center)
                .lineLimit(1...2)
                .minimumScaleFactor(0.85)
                // A capsule on one line, a rounded card if a long potion name wraps (iPhone).
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
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
