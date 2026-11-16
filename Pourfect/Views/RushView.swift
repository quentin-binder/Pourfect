import BottleSortCore
import SwiftUI

/// Rush (R6): the game board with Rush's clock, a "+5 s" after each solve, a quiet "brewing"
/// note while the next recipe is generated, and the end card when time is up.
struct RushView: View {
    @State private var run: RushRun
    let makeRun: () -> RushRun

    @Environment(AppSettings.self) private var settings
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(makeRun: @escaping () -> RushRun) {
        self.makeRun = makeRun
        _run = State(initialValue: makeRun())
    }

    var body: some View {
        ZStack {
            if let game = run.game {
                GameView(model: game, rush: run)
                    .id(ObjectIdentifier(run))
                    // While the next recipe brews (or after time is up) the board takes no taps.
                    .allowsHitTesting(run.phase == .playing)
            } else {
                brewing(first: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { WorkbenchBackground(style: .game) }
                    .environment(\.colorScheme, .dark)
                    .navigationTitle("Rush")
            }
            if run.phase == .solved {
                solvedToast
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            if run.phase == .loading, run.game != nil {
                brewing(first: false)
                    .transition(.opacity)
            }
            if case .over(let newBest) = run.phase {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .transition(.opacity)
                endCard(newBest: newBest)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: run.phase)
        .task(id: ObjectIdentifier(run)) { run.start() }
        .onDisappear { run.stop() }
        .onChange(of: scenePhase, initial: true) { _, phase in run.isPaused = phase != .active }
        .onChange(of: run.phase) { _, phase in
            guard case .over(let newBest) = phase, settings.value.soundEnabled else { return }
            SoundEngine.shared.play(.success)
            if newBest { SoundEngine.shared.play(.goldSeal, after: 0.85) }
        }
    }

    private func brewing(first: Bool) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            if first {
                Text("Brewing the first recipe…", comment: "Rush: the first recipe is being generated")
            } else {
                Text("Brewing the next recipe… the clock waits", comment: "Rush: the next recipe is being generated; the timer is paused meanwhile")
            }
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var solvedToast: some View {
        VStack(spacing: 4) {
            Text("Brewed!").font(.title.bold())
            Text("+\(Int(RushClock.solveBonus)) s", comment: "Rush: time bonus for a solved recipe")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 26).padding(.vertical, 14)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 10)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    private func endCard(newBest: Bool) -> some View {
        VStack(spacing: 14) {
            Label("Time's up!", systemImage: "hourglass.bottomhalf.filled")
                .font(.largeTitle.bold())
            if newBest {
                GoldSealFlourish()
            }
            VStack(spacing: 2) {
                Text(run.solved, format: .number)
                    .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(newBest ? AnyShapeStyle(PerfectBadge.gold) : AnyShapeStyle(.primary))
                Group {
                    if run.solved == 1 {
                        Text("recipe brewed", comment: "Rush end card, under the number of solved recipes (one)")
                    } else {
                        Text("recipes brewed", comment: "Rush end card, under the number of solved recipes")
                    }
                }
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(run.solved) recipes brewed", comment: "VoiceOver: Rush score"))
            if newBest {
                Text("New best!", comment: "Rush end card: the run beat the saved best")
                    .font(.title2.bold())
                    .foregroundStyle(PerfectBadge.gold)
                if run.previousBest > 0 {
                    Text("Your best was \(run.previousBest).", comment: "Rush end card: the best before this run")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Best \(max(run.previousBest, run.solved))", comment: "Rush end card: the saved best score")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if run.clock.skipped > 0 {
                Text("Skipped \(run.clock.skipped)", comment: "Rush end card: recipes skipped in this run")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    run.stop()
                    run = makeRun()
                } label: {
                    Label("Rush Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: 380)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(radius: 14)
        .environment(\.colorScheme, .dark)
    }
}

/// Rush's clock in the game HUD: minutes and seconds, warm when under 10 s. Its own view, so
/// the tick only redraws this text, not the board.
struct RushTimerView: View {
    let run: RushRun
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    var body: some View {
        let seconds = run.clock.displaySeconds
        let low = seconds <= 10
        HStack(spacing: 4) {
            Image(systemName: run.phase == .playing ? "timer" : "pause.circle")
            Text(Self.format(seconds))
                .monospacedDigit()
        }
        .font(.headline)
        .foregroundStyle(low ? Color.orange : Color.primary)
        .scaleEffect(low && !reduceMotion && seconds > 0 && seconds % 2 == 0 ? 1.1 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: seconds)
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(Capsule().fill(low ? Color.orange.opacity(0.2) : Color.white.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time left", comment: "VoiceOver: Rush timer"))
        .accessibilityValue(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// "2:41".
    static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
