import BottleSortCore
import SwiftUI

struct GameView: View {
    @State var model: GameViewModel
    /// The Rush run this board belongs to (R6): the HUD shows its clock, Skip replaces Hint and
    /// a win hands over to the run instead of showing the win card.
    var rush: RushRun?
    @Environment(AppSettings.self) private var settings
    /// Reduce Motion after the in-app override.
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @Environment(TutorialModel.self) private var tutorials
    @Environment(DailyModel.self) private var daily
    @Environment(\.dismiss) private var dismiss
    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @Environment(StoryPresenter.self) private var story
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
                    // Links between flasks, at the flasks' actual places: pressure pipes run
                    // behind the flasks (along the floor, behind the glass across rows), twin
                    // chains hang in front of them.
                    .backgroundPreferenceValue(BottleFramesKey.self) { linkLayer($0, pipes: true) }
                    .overlayPreferenceValue(BottleFramesKey.self) { linkLayer($0, pipes: false) }
                    .overlayPreferenceValue(BottleFramesKey.self) { pushPreviewLayer($0) }
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
            // Rush never opens a tip by itself: its clock is running (its mechanics come from
            // chapters already played; "?" still explains them, with the clock stopped).
            guard tip == nil, !unseen.isEmpty, rush == nil else { return }
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
        // The ending (R7) plays once after the last recipe of the final chapter is solved,
        // a moment after the win card appears.
        .task(id: showsResult && isWon) {
            guard showsResult, isWon, !model.isDemo, !model.isRush, !model.isDaily, !model.isRandom,
                  let scene = Story.sceneAfterWin(recipeID: model.level.id,
                                                  finalRecipeID: catalog.chapter(Story.finalChapter)?.levels.last?.id,
                                                  seen: progress.storySeen) else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            story.show(scene)
        }
        .onChange(of: tip == nil) { _, closed in rush?.isShowingTip = !closed }
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
            // `-LPDemoLinkPour S`: then, after S seconds, plays a pour that pushes through a
            // pressure pipe (else one split between twins).
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
            // `-LPDemoSelect N`: then picks up flask N (1-based, the shuffled level's numbering);
            // `-LPDemoSelect push` picks up the first flask whose pour into a pressure-pipe flask
            // would push (to see the push preview).
            var select = UserDefaults.standard.integer(forKey: "LPDemoSelect")
            if UserDefaults.standard.string(forKey: "LPDemoSelect") == "push" {
                let s = model.state
                let pipes = s.links.compactMap { if case let .overflow(a, _) = $0 { a } else { nil } }
                select = 1 + (s.bottles.indices.first { from in
                    pipes.contains { Rules.push(of: Move(from: from, to: $0), in: s) != nil }
                } ?? -1)
            }
            if select > 0, select <= model.state.bottles.count {
                while model.pour != nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeInOut(duration: 0.3)) { model.tap(bottle: select - 1) }
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
            if let rush {
                RushTimerView(run: rush)
                    .padding(.trailing, 4)
            }
            Text("Moves \(model.moveCount)").font(.headline.monospacedDigit())
            if let best = model.minMoves, rush == nil {
                Text("· Best \(best)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { withAnimation { tip = model.tutorialTopics } } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .keyboardShortcut("/", modifiers: .command)
            .disabled(rushLocked)
            .help("How this recipe works")
            .accessibilityLabel(Text("How to play this recipe"))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// In Rush, the board is locked (no Undo, Restart, Skip or tip, by click or shortcut) while
    /// the next recipe brews, during the "Brewed!" pause and behind the end card.
    private var rushLocked: Bool { rush.map { $0.phase != .playing } ?? false }

    /// The full labels when they fit on one line each; on a narrow screen (an iPhone in Rush,
    /// where Skip's label is longer than Hint's) Undo and Restart show only their icons.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            controlButtons(compact: false)
            controlButtons(compact: true)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func controlButtons(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.3)) { model.undo() } } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(CompactLabelStyle(iconOnly: compact))
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!model.canUndo || isWon || rushLocked)
            .help("Undo")

            Button { withAnimation(.easeInOut(duration: 0.3)) { model.restart() } } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
                    .labelStyle(CompactLabelStyle(iconOnly: compact))
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.moveCount == 0 || rushLocked)
            .help("Restart")

            if let rush {
                // Hints are off in Rush; a skip costs time instead.
                Button { withAnimation(.easeInOut(duration: 0.3)) { rush.skip() } } label: {
                    Label("Skip −\(Int(RushClock.skipPenalty)) s", systemImage: "forward.fill")
                        .lineLimit(1)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(isWon || rushLocked)
                .accessibilityLabel(Text("Skip this recipe"))
                .accessibilityHint(Text("Costs \(Int(RushClock.skipPenalty)) seconds",
                                        comment: "VoiceOver hint on Rush's Skip button; the argument is the time penalty"))
            } else {
                Button { model.requestHint() } label: {
                    Label(model.isThinking ? "Thinking…" : "Hint", systemImage: "lightbulb")
                        .lineLimit(1)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(isWon || model.isThinking)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fixedSize()
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
        let glass = bottles.map { GlassParts($0).riseInWidths }.max() ?? 0
        // A switch's lever arches above the rims of its flasks (about half a width, over a gate's
        // housing).
        let lever: CGFloat = model.state.links.contains { if case .switchGate = $0 { return true } else { return false } }
            ? 0.6 : 0
        let parts = max(glass, lever)
        // A pressure pipe runs along the floor under its flasks (about 0.4 widths).
        let hasPipe = model.state.links.contains(where: \.isPipe)
        // Fit width: perRow bottles + spacing. Fit height: rows × (capacity × 0.78w + 0.45w) + lift room.
        // Linked flasks side by side get a wider gap for their chain or pipe (`linkGap`, in widths).
        let pairsPerRow = rows.map { row in row.filter { linkedRight(of: $0, in: row) }.count }.max() ?? 0
        let byWidth = (size.width - spacing * CGFloat(perRow - 1)) / (CGFloat(perRow) + Self.linkGap * CGFloat(pairsPerRow))
        // A bubbling flask's dial hangs under its base (about 0.52w): room for it under every row.
        // A cauldron's legs and recipe card hang under it: room for them under every row.
        let recipeRows = bottles.map(\.recipes.count).max() ?? 0
        let card = RecipeCard.roomInWidths(rows: recipeRows)
        let dial: CGFloat = bottles.contains { $0.bubbling != nil } ? 0.52 : 0
        let floorPipe: CGFloat = hasPipe ? 0.45 : 0
        let byHeight = (size.height - 40 * CGFloat(rowCount))
            / (CGFloat(rowCount) * (capacity * 0.78 + 0.45 + 0.3 + parts + max(dial, card, floorPipe)))
        let width = max(24, min(byWidth, byHeight, 72))
        let dialRoom = max(dial > 0 ? BubbleGauge.room(width) : 0, RecipeCard.room(width, rows: recipeRows),
                           hasPipe ? PipeGeometry.room(width) : 0)

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
        // The top row's switch lever arches above its rims.
        .padding(.top, lever * width)
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

    /// The flask's contents for VoiceOver, plus its link (twin chain, pressure pipe, switch or gate).
    private func spokenValue(_ index: Int) -> String {
        let contents = model.state.bottles[index].spokenContents(hidden: model.hiddenMask(index))
        switch LinkRole(model.state, bottle: index) {
        case .twin(let other):
            return contents + ", " + String(localized: "twin of flask \(other + 1), every pour into either is split evenly between both",
                                            comment: "VoiceOver: a twin flask; the argument is the other twin's number")
        case .pipeOut(let to):
            let pipe = contents + ", " + String(localized: "pressure pipe, pushes its bottom layer into the bottom of flask \(to + 1)",
                                                comment: "VoiceOver: the flask a pressure pipe starts from (a pour into it that doesn't fit pushes its bottom layers through the pipe); the argument is the flask the pipe runs into")
            // The held flask would push through this pipe if poured here (the push preview).
            guard let push = model.pushPreviews[index] else { return pipe }
            return pipe + ", " + (push.amount == 1
                ? String(localized: "pouring here pushes 1 layer into flask \(push.bottle + 1)",
                         comment: "VoiceOver: while a flask is held, pouring it into this pressure-pipe flask would push one layer through the pipe; the argument is the flask at the pipe's far end")
                : String(localized: "pouring here pushes \(push.amount) layers into flask \(push.bottle + 1)",
                         comment: "VoiceOver: while a flask is held, pouring it into this pressure-pipe flask would push several layers through the pipe; the arguments are the number of layers (2 or more) and the flask at the pipe's far end"))
        case .pipeIn(let from):
            return contents + ", " + String(localized: "the pressure pipe of flask \(from + 1) pushes layers into its bottom",
                                            comment: "VoiceOver: the flask at the far end of a pressure pipe; the argument is the flask the pipe starts from")
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

    /// The chains and switch levers (`pipes` false) or the pipes (true), drawn between the flasks'
    /// frames on the board (after the shuffle and any resize). A link follows a flask that is
    /// picked up. A chain fades while one of its flasks is in the air pouring (the pour animation
    /// draws that flask); a switch link fades only the parts on the flask in the air; a pipe
    /// stays: it runs along the floor, so it keeps the source's resting frame while it flies.
    @ViewBuilder
    private func linkLayer(_ frames: [Int: Anchor<CGRect>], pipes: Bool) -> some View {
        let links = model.state.links.filter { $0.isPipe == pipes }
        let previews = pipes ? model.pushPreviews : [:]
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(links.indices, id: \.self) { i in
                    let link = links[i]
                    let (a, b) = link.endpoints
                    if let fa = frames[a], let fb = frames[b] {
                        let ra = proxy[fa], rb = proxy[fb]
                        let lifted = { (bottle: Int, w: CGFloat) -> CGFloat in model.selected == bottle ? w * 0.3 : 0 }
                        // A switch in the air takes its rod and gem along; the gate keeps its
                        // housing and portcullis on the board. A gate in the air takes its housing
                        // and portcullis; the switch keeps its gem, rod and lever.
                        let isSwitch: Bool = { if case .switchGate = link { return true } else { return false } }()
                        let switchAway = isSwitch && model.pour?.from == a
                        let gateAway = isSwitch && model.pour?.from == b
                        let flying = !isSwitch && !link.isPipe && (model.pour?.from == a || model.pour?.from == b)
                        // `links` holds this layer's links only: the link's index in the state.
                        let index = model.state.links.firstIndex(of: link) ?? 0
                        let refusals = model.linkRefusals.indices.contains(index) ? model.linkRefusals[index] : 0
                        // A switch link: the gate shown open or shut (as before the move while a
                        // pour is in the air), and how far the gate's neck or funnel stands up.
                        let open: Double = model.gateOpen(link: index) ? 1 : 0
                        let rise = GlassParts(model.state.bottles[b]).rise(rb.width)
                        let slides = !reduceMotion
                        let gateAnimation = GatePose.animation(reduceMotion: reduceMotion)
                        // The ends follow their flasks' shake (same count and timing as `BottleView`).
                        let shake = { (bottle: Int) -> CGFloat in
                            model.shakes.indices.contains(bottle) ? CGFloat(model.shakes[bottle]) : 0
                        }
                        // A pipe whose flask would push on a pour from the held flask glows.
                        let preview = link.isPipe && previews[a] != nil
                        let flows = !reduceMotion
                        LinkView(link: link, a: ra, b: rb, liftA: lifted(a, ra.width), liftB: lifted(b, rb.width),
                                 shakeA: shake(a), shakeB: shake(b), open: open, gateRise: rise, slides: slides,
                                 switchAway: switchAway, gateAway: gateAway, pushPreview: preview,
                                 previewFlows: flows)
                            .keyframeAnimator(initialValue: 0.0, trigger: refusals) { _, flare in
                                LinkView(link: link, a: ra, b: rb, liftA: lifted(a, ra.width), liftB: lifted(b, rb.width),
                                         shakeA: shake(a), shakeB: shake(b), flare: flare, open: open, gateRise: rise,
                                         slides: slides, switchAway: switchAway, gateAway: gateAway,
                                         pushPreview: preview, previewFlows: flows)
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

    /// The push preview's tags (F2): while a flask is held, "+N" under the far flask of every
    /// pressure pipe whose flask would push on a pour from it (`GameViewModel.pushPreviews`).
    private func pushPreviewLayer(_ frames: [Int: Anchor<CGRect>]) -> some View {
        let previews = model.pushPreviews.sorted { $0.key < $1.key }
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(previews, id: \.key) { entry in
                    let push = entry.value
                    if let fb = frames[push.bottle] {
                        let rb = proxy[fb]
                        PushBadge(amount: push.amount, width: rb.width)
                            .position(PushBadge.center(under: rb))
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
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
                // Chains, pipes and levers of the flasks drawn by the pour, redrawn above those
                // flasks; not the flying source's (its chain fades, its pipe stays on the board at
                // rest, its switch link keeps the other end's parts on the board).
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
        case .won where model.isRush:
            EmptyView()   // the run moves on (`RushView` shows "+5 s")
        case .won where model.isDaily:
            dailyWinCard
        case .won(let stars):
            card {
                if model.earnedGoldSeal {
                    GoldSealFlourish()
                    Text("Perfect brew!", comment: "Win card title: solved in the fewest moves without a hint")
                        .font(.largeTitle.bold())
                        .foregroundStyle(PerfectBadge.gold)
                } else {
                    Text("Brewed!").font(.largeTitle.bold())
                }
                StarsView(count: stars, size: 32)
                Text("\(model.moveCount) moves · best possible \(model.minMoves ?? model.moveCount)")
                    .foregroundStyle(.secondary)
                if model.earnedGoldSeal {
                    Group {
                        if model.isRandom {
                            Text("The fewest moves, without a hint.", comment: "Win card line under a perfect random brew")
                        } else {
                            Text("The fewest moves, without a hint: a gold seal for this recipe.",
                                 comment: "Win card line under a perfect brew")
                        }
                    }
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 320)
                } else if stars == 3, model.usedHint {
                    Label("A hint was used, so no gold seal this time", systemImage: "lightbulb")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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

/// A label that shows its title and icon, or only the icon (its title stays the VoiceOver label).
private struct CompactLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon).lineLimit(1)
        }
    }
}
