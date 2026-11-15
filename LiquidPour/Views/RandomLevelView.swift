import BottleSortCore
import SwiftUI

/// Random Level settings: mode and board size, then "Generate" (runs in the background).
struct RandomLevelView: View {
    let onPlay: (LevelDefinition, RandomLevelOptions) -> Void

    @State private var options = RandomSettings.load()
    @State private var maker = RandomLevelMaker()

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $options.mode) {
                    ForEach(GameMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(options.mode.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Mode")
            }

            Section {
                Stepper(value: $options.colors, in: RandomLevelOptions.colorRange) {
                    row("Colors", options.colors)
                }
                Stepper(value: $options.capacity, in: RandomLevelOptions.capacityRange) {
                    row("Bottle size", options.capacity)
                }
                Stepper(value: $options.emptyBottles, in: RandomLevelOptions.emptyRange) {
                    row("Empty bottles", options.emptyBottles)
                }
                if options.mode == .locksAndKeys {
                    Stepper(value: $options.locks, in: lockRange) {
                        row("Locks", options.locks)
                    }
                }
            } header: {
                Text("Board")
            } footer: {
                Text("\(RandomSettings.bottleCount(options)) bottles in total.")
            }

            Section {
                Button(action: generate) {
                    HStack {
                        Spacer()
                        Label(maker.phase == .failed ? "Try Again" : "Generate", systemImage: "dice")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(maker.isGenerating)
                status
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Random Level")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: options) { _, new in
            let fixed = new.clamped
            if fixed != new { options = fixed }   // e.g. locks must stay below colors
            RandomSettings.save(fixed)
            if maker.phase == .failed { maker.cancel() }
        }
        .onDisappear { maker.cancel() }
        #if DEBUG
        // Dev aid: `-LPRandomGenerate 1` presses Generate once when the screen opens.
        .task {
            if UserDefaults.standard.bool(forKey: "LPRandomGenerate"), maker.phase == .idle { generate() }
        }
        #endif
    }

    private var lockRange: ClosedRange<Int> {
        RandomLevelOptions.lockRange.lowerBound...max(RandomLevelOptions.lockRange.lowerBound,
                                                       min(RandomLevelOptions.lockRange.upperBound, options.colors - 1))
    }

    private func row(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)").monospacedDigit().foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var status: some View {
        switch maker.phase {
        case .generating(let attempt, let total):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Attempt \(attempt) of \(total)").monospacedDigit()
            }
            .foregroundStyle(.secondary)
        case .failed:
            Label(RandomLevelMaker.failureMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    private func generate() {
        let chosen = options.clamped
        maker.generate(chosen) { level in onPlay(level, chosen) }
    }
}
