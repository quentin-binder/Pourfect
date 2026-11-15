import BottleSortCore
import SwiftUI

struct GameView: View {
    @State var model: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .sensoryFeedback(.impact(weight: .light), trigger: model.invalidMoveCount)
        .sensoryFeedback(.success, trigger: showsResult && isWon) { _, won in won }
        .navigationTitle("Level \(model.levelIndex + 1)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if DEBUG
        // Dev aid: `-LPDemoMoves K` plays the first K optimal moves via taps (0 = off).
        .task {
            let k = UserDefaults.standard.integer(forKey: "LPDemoMoves")
            if k > 0 { await model.debugPlayOptimal(moves: k) }
        }
        #endif
    }

    private var isWon: Bool { if case .won = model.status { return true } else { return false } }
    /// Win / stuck cards wait until the pour that caused them has finished animating.
    private var showsResult: Bool { model.pour == nil }

    // MARK: HUD

    private var hud: some View {
        HStack {
            Text("Level \(model.levelIndex + 1)").font(.headline)
            Spacer()
            Text("Moves \(model.moveCount)").font(.headline.monospacedDigit())
            if let best = model.minMoves {
                Text("· Best \(best)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
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
                                       isSelected: model.selected == index,
                                       hintRole: hintRole(for: index),
                                       shakes: model.shakes.indices.contains(index) ? model.shakes[index] : 0)
                        }
                        .buttonStyle(.plain)
                        .anchorPreference(key: BottleFramesKey.self, value: .bounds) { [index: $0] }
                        // The pour animation draws these two bottles itself; swap without fading.
                        .animation(nil) { $0.opacity(isPouring(index) ? 0 : 1) }
                        .accessibilityLabel("Bottle \(index + 1)")
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
        case .won(let stars):
            card {
                Text("Solved!").font(.largeTitle.bold())
                StarsView(count: stars, size: 32)
                Text("\(model.moveCount) moves · best possible \(model.minMoves ?? model.moveCount)")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Replay") { withAnimation { model.restart() } }
                        .buttonStyle(.bordered)
                    if model.hasNextLevel {
                        Button("Next") { withAnimation { model.nextLevel() } }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 12)
            .transition(.scale.combined(with: .opacity))
    }
}
