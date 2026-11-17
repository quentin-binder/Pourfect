import BottleSortCore
import HiddenCore
import SwiftUI

/// A hidden-object round (R11): the room fills the screen (zoom and pan), the find list in a tray (bottom on
/// iPhone, a side column on the Mac and iPad), the lantern hint with its recharge ring, and the round card.
/// Calm: no timer; stars count hints and wrong taps.
struct HiddenGameView: View {
    let room: HiddenSceneID
    /// Back to the room's round list.
    var onBack: () -> Void

    @State private var model: HiddenGameModel
    @State private var viewport = HiddenViewport()
    @State private var trayOpen = true
    @State private var tip: [TutorialTopic]?

    @Environment(HiddenProgressModel.self) private var progress
    @Environment(TutorialModel.self) private var tutorials
    @Environment(StoryPresenter.self) private var story
    @Environment(AppSettings.self) private var settings
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    init(room: HiddenSceneID, round: Int, onBack: @escaping () -> Void) {
        self.room = room
        self.onBack = onBack
        _model = State(initialValue: HiddenGameModel(room: room, round: round))
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700 && geo.size.width > geo.size.height * 1.1
            Group {
                if wide {
                    HStack(spacing: 0) {
                        stage
                        HiddenFindColumn(model: model, open: $trayOpen)
                    }
                } else {
                    stage
                        .safeAreaInset(edge: .bottom, spacing: 0) { HiddenFindTray(model: model, open: $trayOpen) }
                }
            }
        }
        .overlay { card }
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
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.35), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(reduceMotion ? nil : .default) { tip = [.hiddenBasics] } } label: {
                    Label("How to play", systemImage: "questionmark.circle")
                }
                .keyboardShortcut("/", modifiers: .command)
                .help(Text("How the curiosity rooms work", comment: "Tooltip of the hidden-object help button"))
            }
        }
        .task { await start() }
        .task(id: story.scene == nil) {
            let unseen = tutorials.unseen([.hiddenBasics])
            guard tip == nil, !unseen.isEmpty, story.scene == nil else { return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(reduceMotion ? nil : .default) { tip = unseen }
        }
        .onChange(of: settings.value, initial: true) { _, value in model.settings = value }
        .onChange(of: reduceMotion, initial: true) { _, value in model.reduceMotion = value }
        .onChange(of: model.lastFound) { _, id in
            guard let id, model.phase == .playing else { return }
            let left = model.targets.count - model.found.count
            // One announcement per find; a reveal says so (its action posts nothing itself).
            let text = model.lastFoundRevealed
                ? String(localized: "Revealed \(model.name(id)). \(left) left.",
                         comment: "VoiceOver: reveal next found an object; the count still to find")
                : String(localized: "Found \(model.name(id)). \(left) left.", comment: "VoiceOver: an object was found; the count still to find")
            AccessibilityNotification.Announcement(text).post()
        }
        .task { if settings.value.soundEnabled { SoundEngine.shared.warmUp() } }
    }

    private var title: String {
        String(localized: "Round \(model.round)", comment: "Title of a hidden-object round; the argument is its number (1-10)")
    }

    // MARK: Scene

    private var stage: some View {
        ZStack {
            HiddenSceneView(model: model, viewport: viewport, outlineTargets: Self.debugOutlines)
                .accessibilityElement()
                .accessibilityLabel(Text("Picture of \(HiddenNames.title(room)). Objects are found by touch.",
                                         comment: "VoiceOver: the hidden-object picture"))
                .accessibilityHint(Text("Use the Reveal Next action to find the next object; it counts as a hint.",
                                        comment: "VoiceOver hint of the hidden-object picture"))
                .accessibilityAction(named: Text("Reveal next", comment: "VoiceOver action: find the next hidden object (counts as a hint)")) {
                    reveal()
                }
            HiddenEffectsOverlay(model: model, viewport: viewport)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if model.phase == .loading {
                ProgressView().controlSize(.large).tint(.white)
            }
            if case .failed(let message) = model.phase {
                ContentUnavailableView("Missing", systemImage: "exclamationmark.triangle", description: Text(verbatim: message))
            }
        }
        .overlay(alignment: .topLeading) { counter.padding(12) }
        .overlay(alignment: .bottomTrailing) { controls.padding(12) }
        .clipped()
    }

    private var counter: some View {
        let found = model.found.count, total = model.targets.count
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
            Text("\(found) / \(total)").monospacedDigit().contentTransition(.numericText())
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(HiddenArt.brass.opacity(0.5)))
        .modifier(HiddenShake(trigger: model.wrongPulse, enabled: !reduceMotion))
        .animation(reduceMotion ? nil : .snappy, value: found)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(found) of \(total) found", comment: "VoiceOver: hidden-object round progress"))
        .opacity(model.phase == .playing ? 1 : 0)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            #if os(macOS)
            Button { viewport.zoom(by: 1 / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
                .help(Text("Zoom out", comment: "Hidden-object zoom button"))
                .accessibilityLabel(Text("Zoom out", comment: "Hidden-object zoom button"))
            Button { viewport.zoom(by: 1.4) } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("=", modifiers: .command)
                .help(Text("Zoom in", comment: "Hidden-object zoom button"))
                .accessibilityLabel(Text("Zoom in", comment: "Hidden-object zoom button"))
            #endif
            HiddenLanternButton(model: model)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(HiddenArt.brass.opacity(0.5)))
        .opacity(model.phase == .playing ? 1 : 0)
    }

    /// Announced by the `lastFound` change like any find ("Revealed …").
    private func reveal() {
        model.revealNext()
    }

    // MARK: Loading

    private func start() async {
        model.onComplete = { [progress, room] round, stars in progress.record(room, round: round, stars: stars) }
        let round = model.round
        let seed = Self.debugNumber("LPHiddenSeed").map { UInt64($0) }
        await model.load(round: round, seed: seed)
        #if DEBUG
        let defaults = UserDefaults.standard
        if let zoom = Self.debugNumber("LPHiddenZoom") {
            try? await Task.sleep(for: .milliseconds(300))   // after the first layout
            viewport.zoom(by: zoom)
        }
        if defaults.object(forKey: "LPHiddenTray") != nil { trayOpen = defaults.bool(forKey: "LPHiddenTray") }
        let finds = defaults.integer(forKey: "LPHiddenDemo")
        let wrong = defaults.bool(forKey: "LPHiddenWrong"), lantern = defaults.bool(forKey: "LPHiddenHint")
        if finds > 0 || wrong || lantern {
            try? await Task.sleep(for: .milliseconds(600))
            model.debugDemo(finds: finds, wrong: wrong, hint: lantern)
        }
        #endif
    }

    /// Replay (the same fixed round) or the next round, in place.
    private func play(round: Int) {
        Task { await model.load(round: round) }
    }

    private static var debugOutlines: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "LPHiddenShow")
        #else
        return false
        #endif
    }

    private static func debugNumber(_ key: String) -> Double? {
        #if DEBUG
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : nil
        #else
        return nil
        #endif
    }

    // MARK: Round card

    @ViewBuilder
    private var card: some View {
        if case .complete(let stars, let newBest) = model.phase, let s = model.state {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(stars == 3 ? LocalizedStringKey("Sharp eyes!") : LocalizedStringKey("All found!"))
                        .font(.largeTitle.bold())
                    StarsView(count: stars, size: 32)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(stars) stars"))
                    HStack(spacing: 18) {
                        Label { Text("\(s.wrongTaps) wrong taps", comment: "Hidden-object round card: wrong taps") } icon: {
                            Image(systemName: "hand.tap")
                        }
                        Label { Text("\(s.hintsUsed) hints", comment: "Hidden-object round card: hints used") } icon: {
                            Image(systemName: "flame")
                        }
                    }
                    .font(.headline.monospacedDigit())
                    if stars < 3 {
                        Text("Three stars with no hint and at most \(HiddenStars.perfectWrongTaps) wrong taps; two with up to \(HiddenStars.goodHints) hints and \(HiddenStars.goodWrongTaps) wrong taps.",
                             comment: "Hidden-object round card: the star rules")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                    }
                    if newBest, progress.plays(room, round: s.round) > 1 {
                        Label("New best", systemImage: "rosette").foregroundStyle(HiddenArt.gold)
                    }
                    HStack {
                        Button { onBack() } label: { Text("Rooms", comment: "Hidden-object round card: back to the room's round list") }
                            .buttonStyle(.bordered)
                        Button { play(round: s.round) } label: { Text("Replay", comment: "Hidden-object round card: play the round again") }
                            .buttonStyle(.bordered)
                        if s.round < HiddenProgression.rounds.upperBound {
                            Button { play(round: s.round + 1) } label: { Text("Next Round", comment: "Hidden-object round card: next round") }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    .controlSize(.large)
                }
                .padding(24)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(HiddenArt.brass.opacity(0.5)))
                .shadow(radius: 12)
                .padding()
            }
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
        }
    }
}

// MARK: - Find list

/// One entry of the find list: thumbnail and name; ticked off with a flourish once found.
struct HiddenFindItem: View {
    let model: HiddenGameModel
    let id: String
    var compact = false
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    var body: some View {
        let isFound = model.found.contains(id)
        let flourish = model.lastFound == id
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.white.opacity(isFound ? 0.06 : 0.12))
                if let cg = model.assets?.images[id] {
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(4)
                        .opacity(isFound ? 0.35 : 1)
                }
                if isFound {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white, Color(red: 0.35, green: 0.75, blue: 0.4))
                        .offset(x: 13, y: 12)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .frame(width: compact ? 34 : 40, height: compact ? 34 : 40)
            Text(model.name(id))
                .font(compact ? .footnote.weight(.semibold) : .callout.weight(.semibold))
                .strikethrough(isFound, color: HiddenArt.gold)
                .foregroundStyle(isFound ? Color.white.opacity(0.45) : Color.white)
                .lineLimit(compact ? 1 : 2)
                .fixedSize(horizontal: compact, vertical: false)
            if !compact { Spacer(minLength: 0) }
        }
        .padding(.horizontal, compact ? 8 : 6).padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(flourish && isFound ? HiddenArt.gold.opacity(0.25) : Color.clear)
        }
        .scaleEffect(flourish && isFound && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.5), value: isFound)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: flourish)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFound
            ? Text("\(model.name(id)), found", comment: "VoiceOver: a found object on the find list")
            : Text("\(model.name(id)), not found yet", comment: "VoiceOver: an object still to find"))
    }
}

/// iPhone: the find list as a tray under the picture; collapsed it shows just the count.
struct HiddenFindTray: View {
    let model: HiddenGameModel
    @Binding var open: Bool
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { open.toggle() }
            } label: {
                HStack {
                    Text("Find", comment: "Heading of the hidden-object find list").font(.headline)
                    Text("\(model.found.count) of \(model.targets.count)", comment: "Find list: found of total")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: open ? "chevron.down" : "chevron.up").font(.subheadline.weight(.bold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? Text("Hide the find list", comment: "VoiceOver: collapse the find list")
                                     : Text("Show the find list", comment: "VoiceOver: expand the find list"))
            if open {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(model.targets, id: \.self) { id in
                                HiddenFindItem(model: model, id: id, compact: true).id(id)
                            }
                        }
                    }
                    .onChange(of: model.lastFound) { _, id in
                        // Keep the next object to find in view.
                        if let next = model.state?.remaining.first ?? id {
                            withAnimation(reduceMotion ? nil : .easeInOut) { proxy.scrollTo(next, anchor: .center) }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        .background(HiddenArt.panel)
        .overlay(alignment: .top) { Rectangle().fill(HiddenArt.brass.opacity(0.5)).frame(height: 1) }
        .foregroundStyle(.white)
    }
}

/// Mac and iPad: the find list in a column beside the picture; it folds to a narrow strip.
struct HiddenFindColumn: View {
    let model: HiddenGameModel
    @Binding var open: Bool
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if open {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Find", comment: "Heading of the hidden-object find list").font(.title3.bold())
                        Text("\(model.found.count) of \(model.targets.count)", comment: "Find list: found of total")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { open.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
                .help(open ? Text("Hide the find list", comment: "VoiceOver: collapse the find list")
                           : Text("Show the find list", comment: "VoiceOver: expand the find list"))
                .accessibilityLabel(open ? Text("Hide the find list", comment: "VoiceOver: collapse the find list")
                                         : Text("Show the find list", comment: "VoiceOver: expand the find list"))
            }
            if open {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.targets, id: \.self) { id in HiddenFindItem(model: model, id: id) }
                    }
                }
            } else {
                Text("\(model.found.count)/\(model.targets.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: open ? 230 : 52)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HiddenArt.panel)
        .overlay(alignment: .leading) { Rectangle().fill(HiddenArt.brass.opacity(0.5)).frame(width: 1) }
        .foregroundStyle(.white)
    }
}

// MARK: - Lantern

/// The lantern hint: lights a glow around one remaining object; a ring shows it recharging (30 s).
struct HiddenLanternButton: View {
    let model: HiddenGameModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let wait = model.hintCooldown(now: context.date)
            let ready = wait <= 0
            Button { model.useHint() } label: {
                ZStack {
                    Circle()
                        .trim(from: 0, to: ready ? 1 : 1 - wait / HiddenHintGlow.cooldown)
                        .stroke(ready ? HiddenArt.gold : HiddenArt.brass.opacity(0.8),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 34, height: 34)
                    HiddenLanternIcon(lit: ready)
                        .frame(width: 22, height: 26)
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(!ready || model.isComplete)
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .help(Text("Lantern: glows around one object still to find. Recharges after 30 seconds; a hint costs the third star.",
                       comment: "Tooltip of the hidden-object lantern hint"))
            .accessibilityLabel(Text("Lantern hint", comment: "VoiceOver: the hidden-object hint button"))
            .accessibilityValue(ready ? Text("Ready", comment: "VoiceOver: lantern ready")
                                      : Text("Recharging, \(Int(wait.rounded(.up))) seconds", comment: "VoiceOver: lantern recharging"))
        }
    }
}

/// A small brass lantern drawn in Canvas.
struct HiddenLanternIcon: View {
    var lit = true

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // Handle ring.
            ctx.stroke(Path(ellipseIn: CGRect(x: w * 0.32, y: 0, width: w * 0.36, height: h * 0.2)),
                       with: .color(HiddenArt.brass), lineWidth: max(1, w * 0.07))
            // Cap.
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.2, y: h * 0.16, width: w * 0.6, height: h * 0.12), cornerRadius: 2),
                     with: .color(HiddenArt.brass))
            // Glass with the flame.
            let glass = CGRect(x: w * 0.26, y: h * 0.28, width: w * 0.48, height: h * 0.5)
            ctx.fill(Path(roundedRect: glass, cornerRadius: w * 0.12),
                     with: lit ? .radialGradient(Gradient(colors: [Color(red: 1, green: 0.93, blue: 0.6), Color(red: 1, green: 0.62, blue: 0.2),
                                                                   Color(red: 0.6, green: 0.3, blue: 0.1)]),
                                                 center: CGPoint(x: glass.midX, y: glass.midY + h * 0.06), startRadius: 0, endRadius: glass.width * 0.7)
                              : .color(Color.white.opacity(0.15)))
            ctx.stroke(Path(roundedRect: glass, cornerRadius: w * 0.12), with: .color(HiddenArt.brass), lineWidth: max(1, w * 0.06))
            // Bars and base.
            ctx.stroke(Path { $0.move(to: CGPoint(x: glass.midX, y: glass.minY)); $0.addLine(to: CGPoint(x: glass.midX, y: glass.maxY)) },
                       with: .color(HiddenArt.brass.opacity(0.7)), lineWidth: max(0.8, w * 0.04))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.18, y: h * 0.78, width: w * 0.64, height: h * 0.14), cornerRadius: 2),
                     with: .color(HiddenArt.brass))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Effects

/// Sparkles of finds, puffs of wrong taps and the lantern's glow, drawn over the scene in view coordinates so they
/// follow zoom and pan. Reduce Motion: no flying particles, no shake, no circling light; short fades instead.
struct HiddenEffectsOverlay: View {
    let model: HiddenGameModel
    let viewport: HiddenViewport
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    var body: some View {
        let paused = model.effects.isEmpty && model.hint == nil
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: paused)) { context in
            Canvas { ctx, _ in
                let now = context.date
                if let hint = model.hint { drawLantern(&ctx, glow: hint.glow, t: now.timeIntervalSince(hint.lit)) }
                for e in model.effects {
                    let t = now.timeIntervalSince(e.start) / HiddenEffect.duration
                    guard t >= 0, t <= 1 else { continue }
                    switch e.kind {
                    case .sparkle: drawSparkle(&ctx, e, t: t)
                    case .puff: drawPuff(&ctx, e, t: t)
                    }
                }
            }
        }
    }

    private func drawSparkle(_ ctx: inout GraphicsContext, _ e: HiddenEffect, t: Double) {
        let c = viewport.toView(e.point)
        let r = max(14, e.size * viewport.scale * 0.6)
        let fade = 1 - t
        let ring = r * (0.6 + 0.9 * t)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)),
                   with: .color(HiddenArt.gold.opacity(0.85 * fade)), lineWidth: 2.5 * fade + 0.5)
        guard !reduceMotion else { return }
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * .pi + 0.3
            let d = r * (0.4 + 1.3 * t) * (k.isMultiple(of: 2) ? 1 : 0.75)
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            let s = (k.isMultiple(of: 2) ? 7.0 : 5.0) * (1 - t * 0.6)
            ctx.fill(star(at: p, size: s), with: .color(Color(red: 1, green: 0.95, blue: 0.7).opacity(fade)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.5, width: r, height: r)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(0.7 * fade), .clear]), center: c, startRadius: 0, endRadius: r * 0.5))
    }

    private func drawPuff(_ ctx: inout GraphicsContext, _ e: HiddenEffect, t: Double) {
        var c = viewport.toView(e.point)
        let fade = 1 - t
        if !reduceMotion { c.x += sin(t * 38) * 4 * fade }
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi
            let d = reduceMotion ? 6.0 : 6 + 16 * t
            let r = (reduceMotion ? 9.0 : 6 + 8 * t) * (k.isMultiple(of: 2) ? 1 : 0.8)
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d * 0.7)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 0.82, green: 0.76, blue: 0.66).opacity(0.55 * fade)))
        }
        ctx.stroke(Path { $0.move(to: CGPoint(x: c.x - 5, y: c.y - 5)); $0.addLine(to: CGPoint(x: c.x + 5, y: c.y + 5))
                          $0.move(to: CGPoint(x: c.x + 5, y: c.y - 5)); $0.addLine(to: CGPoint(x: c.x - 5, y: c.y + 5)) },
                   with: .color(Color.white.opacity(0.8 * fade)), lineWidth: 2)
    }

    private func drawLantern(_ ctx: inout GraphicsContext, glow: HiddenHintGlow, t: Double) {
        let c = viewport.toView(CGPoint(x: glow.center.x, y: glow.center.y))
        let r = max(28, glow.radius * viewport.scale)
        let total = HiddenGameModel.hintDuration
        let fade = min(1, t / 0.5) * min(1, max(0, (total - t) / 1.2))
        let pulse = reduceMotion ? 1 : 0.9 + 0.1 * sin(t * 3)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.2, y: c.y - r * 1.2, width: r * 2.4, height: r * 2.4)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.45).opacity(0.32 * fade * pulse),
                                                         Color(red: 1, green: 0.6, blue: 0.2).opacity(0.12 * fade), .clear]),
                                       center: c, startRadius: r * 0.2, endRadius: r * 1.2))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(HiddenArt.gold.opacity(0.8 * fade)),
                   style: StrokeStyle(lineWidth: 2.5, dash: [8, 6], dashPhase: reduceMotion ? 0 : CGFloat(t * 18)))
        guard !reduceMotion else { return }
        // The lantern's light circling the area.
        for k in 0..<3 {
            let a = t * 1.6 + Double(k) * 2 * .pi / 3
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.7).opacity(fade), .clear]),
                                           center: p, startRadius: 0, endRadius: 10))
            ctx.fill(star(at: p, size: 5), with: .color(Color.white.opacity(fade)))
        }
    }

    private func star(at p: CGPoint, size s: Double) -> Path {
        Path { path in
            path.move(to: CGPoint(x: p.x, y: p.y - s))
            path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: p)
            path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: p)
            path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: p)
            path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: p)
        }
    }
}

/// A short horizontal shake each time `trigger` changes.
struct HiddenShake: ViewModifier {
    let trigger: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
            view.offset(x: enabled ? x : 0)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-6, duration: 0.06)
                LinearKeyframe(5, duration: 0.08)
                LinearKeyframe(-3, duration: 0.07)
                LinearKeyframe(0, duration: 0.06)
            }
        }
    }
}
