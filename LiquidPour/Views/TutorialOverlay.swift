import BottleSortCore
import SwiftUI

/// One page of a tip: a small scene drawn with the game's own flasks, a title and a sentence.
struct TutorialStep: Identifiable {
    enum Scene { case pickAndPour, pourRules, goal, sealed, keyOpensSeal, murky, reveal }

    let id: String
    let topic: TutorialTopic
    let title: String
    let text: String
    let scene: Scene

    static func steps(for topic: TutorialTopic) -> [TutorialStep] {
        switch topic {
        case .basic:
            return [
                TutorialStep(id: "basic.pour", topic: topic, title: String(localized: "Pour"),
                             text: String(localized: "Tap a flask to pick it up, then tap another flask to pour into it."),
                             scene: .pickAndPour),
                TutorialStep(id: "basic.rules", topic: topic, title: String(localized: "Matching potions"),
                             text: String(localized: "A potion pours only onto the same potion or into an empty flask, and only as much as fits."),
                             scene: .pourRules),
                TutorialStep(id: "basic.goal", topic: topic, title: String(localized: "Brew the recipe"),
                             text: String(localized: "Fill every flask with a single potion. Undo, Restart and Hint are always there to help."),
                             scene: .goal),
            ]
        case .sealed:
            return [
                TutorialStep(id: "sealed.lock", topic: topic, title: String(localized: "Rune seals"),
                             text: String(localized: "A sealed flask is locked: nothing can be poured into it or out of it."),
                             scene: .sealed),
                TutorialStep(id: "sealed.key", topic: topic, title: String(localized: "Rune-stone keys"),
                             text: String(localized: "Pour the rune-stone key of the same color onto the sealed flask to break the seal."),
                             scene: .keyOpensSeal),
            ]
        case .murky:
            return [
                TutorialStep(id: "murky.hidden", topic: topic, title: String(localized: "Murky potions"),
                             text: String(localized: "Murky flasks hide what lies beneath. Only the top potion is visible."),
                             scene: .murky),
                TutorialStep(id: "murky.reveal", topic: topic, title: String(localized: "Clear the mist"),
                             text: String(localized: "Pour off the top potion to reveal the layer below it. Hints still work."),
                             scene: .reveal),
            ]
        }
    }
}

/// The first-time tip shown over the game: 1–3 illustrated steps, then "Got it".
struct TutorialOverlay: View {
    let topics: [TutorialTopic]
    let onDone: () -> Void

    @State private var page = Self.firstPage

    /// Dev aid: `-LPTutorialPage N` (1-based) opens a tip on step N.
    private static var firstPage: Int {
        #if DEBUG
        return max(0, UserDefaults.standard.integer(forKey: "LPTutorialPage") - 1)
        #else
        return 0
        #endif
    }

    private var steps: [TutorialStep] { topics.flatMap { TutorialStep.steps(for: $0) } }

    var body: some View {
        let steps = self.steps
        let step = steps[min(page, steps.count - 1)]
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {}   // swallow taps meant for the board
            VStack(spacing: 16) {
                Text(step.topic.headline)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                TutorialScene(scene: step.scene)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.35)))
                    .accessibilityHidden(true)
                Text(step.title).font(.title2.bold())
                Text(step.text)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if steps.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(steps.indices, id: \.self) { i in
                            Circle().fill(i == page ? Color.primary : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(Text("Step \(page + 1) of \(steps.count)"))
                }
                HStack {
                    if page > 0 {
                        Button("Back") { withAnimation { page -= 1 } }
                            .buttonStyle(.bordered)
                    }
                    if page + 1 < steps.count {
                        Button("Next") { withAnimation { page += 1 } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Got it", action: onDone)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(radius: 16)
            .padding()
            .id(step.id)
            .transition(.opacity)
        }
        .accessibilityAddTraits(.isModal)
    }
}

extension TutorialTopic {
    /// Small heading above a tip.
    var headline: String {
        switch self {
        case .basic: return String(localized: "How to play")
        case .sealed: return String(localized: "New: sealed flasks")
        case .murky: return String(localized: "New: murky potions")
        }
    }
}

/// A tiny still life of flasks for one tutorial step, drawn with `BottleView`.
private struct TutorialScene: View {
    let scene: TutorialStep.Scene
    private let w: CGFloat = 34

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            switch scene {
            case .pickAndPour:
                BottleView(bottle: Bottle([0, 1, 1], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([1], capacity: 4), width: w)
            case .pourRules:
                VStack(spacing: 6) {
                    BottleView(bottle: Bottle([2, 2], capacity: 4), width: w)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                BottleView(bottle: Bottle([0, 2], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                VStack(spacing: 6) {
                    BottleView(bottle: Bottle([1, 0], capacity: 4), width: w)
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            case .goal:
                BottleView(bottle: Bottle([0, 0, 0, 0], capacity: 4), width: w)
                BottleView(bottle: Bottle([1, 1, 1, 1], capacity: 4), width: w)
                BottleView(bottle: Bottle([3, 3, 3, 3], capacity: 4), width: w)
            case .sealed:
                BottleView(bottle: Bottle([4, 4, 1], capacity: 4, lockedBy: 1), width: w)
                Image(systemName: "nosign").font(.title).foregroundStyle(.secondary)
                BottleView(bottle: Bottle([1], capacity: 4), width: w)
            case .keyOpensSeal:
                BottleView(bottle: Bottle(layers: [.color(3), .key(1)], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([4, 4, 1], capacity: 4, lockedBy: 1), width: w)
                Image(systemName: "equal").font(.title3).foregroundStyle(.secondary)
                BottleView(bottle: Bottle([4, 4, 1], capacity: 4), width: w)
            case .murky:
                BottleView(bottle: Bottle([5, 0, 6, 2], capacity: 4), width: w, hiddenLayers: 3)
                BottleView(bottle: Bottle([3, 7, 7], capacity: 4), width: w, hiddenLayers: 1)
            case .reveal:
                BottleView(bottle: Bottle([5, 0, 6, 6], capacity: 4), width: w, hiddenLayers: 2, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([5, 0], capacity: 4), width: w, hiddenLayers: 1)
            }
        }
        .padding(.top, 18)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, w)
    }
}
