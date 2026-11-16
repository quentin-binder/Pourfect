import BottleSortCore
import SwiftUI

/// One page of a tip: a small scene drawn with the game's own flasks, a title and a sentence.
struct TutorialStep: Identifiable {
    enum Scene {
        case pickAndPour, pourRules, goal, sealed, keyOpensSeal, murky, reveal, essence, essenceOut
        case neckOut, neckIn, funnelIn, funnelCare, tapBottom, tapNoIn
        case iceHolds, iceSeals, iceThaws
        case bubbleRises, bubbleDial, bubbleUse
        case twinSplit, twinEven, twinOut, pipeOverflow, pipePassOn
    }

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
                             text: String(localized: "A sealed flask is locked: only its rune-stone key can be poured in, and nothing can be poured out."),
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
        case .essence:
            return [
                TutorialStep(id: "essence.gate", topic: topic, title: String(localized: "Essence flasks"),
                             text: String(localized: "A flask etched with a glowing rune takes only the potion of that rune. Anything else is refused, even when the flask is empty."),
                             scene: .essence),
                TutorialStep(id: "essence.out", topic: topic, title: String(localized: "Pour out freely"),
                             text: String(localized: "You can always pour out of an essence flask. Clear the other potions out, then fill it with its own."),
                             scene: .essenceOut),
            ]
        case .narrowNeck:
            return [
                TutorialStep(id: "neck.out", topic: topic, title: String(localized: "Narrow necks"),
                             text: String(localized: "A flask with a narrow neck and a brass collar lets one layer through per pour, even when more would fit."),
                             scene: .neckOut),
                TutorialStep(id: "neck.in", topic: topic, title: String(localized: "One at a time"),
                             text: String(localized: "Pouring into a narrow neck works the same way: one layer per pour. Plan for the extra pours."),
                             scene: .neckIn),
            ]
        case .funnel:
            return [
                TutorialStep(id: "funnel.in", topic: topic, title: String(localized: "Funnel flasks"),
                             text: String(localized: "A flask with a brass funnel takes potions in like any flask, but nothing ever pours out of it."),
                             scene: .funnelIn),
                TutorialStep(id: "funnel.care", topic: topic, title: String(localized: "Fill it with care"),
                             text: String(localized: "A potion poured into a funnel stays there for good. Only pour in what can fill it with one potion."),
                             scene: .funnelCare),
            ]
        case .tap:
            return [
                TutorialStep(id: "tap.bottom", topic: topic, title: String(localized: "Tap flasks"),
                             text: String(localized: "A flask with a brass tap pours from the bottom: the bottom potion runs out of the tap and the rest slides down."),
                             scene: .tapBottom),
                TutorialStep(id: "tap.in", topic: topic, title: String(localized: "Nothing goes in"),
                             text: String(localized: "Nothing can be poured into a tap flask, not even a key. Drain it, or leave it full of one potion."),
                             scene: .tapNoIn),
            ]
        case .frozen:
            return [
                TutorialStep(id: "ice.holds", topic: topic, title: String(localized: "Frozen layers"),
                             text: String(localized: "Ice holds a layer in place: it can't move, and neither can anything below it. The potion above the ice pours as usual."),
                             scene: .iceHolds),
                TutorialStep(id: "ice.seals", topic: topic, title: String(localized: "Frozen over"),
                             text: String(localized: "When the top layer is frozen, the flask is shut: nothing pours in or out until the ice thaws."),
                             scene: .iceSeals),
                TutorialStep(id: "ice.thaws", topic: topic, title: String(localized: "Wait for the thaw"),
                             text: String(localized: "The number on the ice counts down after every pour, wherever you pour. At zero the ice cracks and melts."),
                             scene: .iceThaws),
            ]
        case .bubbling:
            return [
                TutorialStep(id: "bubbling.rises", topic: topic, title: String(localized: "Bubbling flasks"),
                             text: String(localized: "Every few moves a bubbling flask bubbles up: its bottom potion rises to the top, and the potions above it sink one place."),
                             scene: .bubbleRises),
                TutorialStep(id: "bubbling.dial", topic: topic, title: String(localized: "Watch the dial"),
                             text: String(localized: "The dial under the flask lights up after every pour, wherever you pour. Its number is the moves left until it bubbles up."),
                             scene: .bubbleDial),
                TutorialStep(id: "bubbling.use", topic: topic, title: String(localized: "Use the rise"),
                             text: String(localized: "A potion buried at the bottom comes up on its own. Time your pours so it has somewhere to go when it rises."),
                             scene: .bubbleUse),
            ]
        case .twins:
            return [
                TutorialStep(id: "twins.split", topic: topic, title: String(localized: "Twin flasks"),
                             text: String(localized: "Two flasks on a silver chain are twins. Pour into either one and the pour is split evenly: half lands in each."),
                             scene: .twinSplit),
                TutorialStep(id: "twins.even", topic: topic, title: String(localized: "Fair shares"),
                             text: String(localized: "Both twins must take the potion, and each gets the same amount. A single layer can't be split, so it can't go in."),
                             scene: .twinEven),
                TutorialStep(id: "twins.out", topic: topic, title: String(localized: "Pour out freely"),
                             text: String(localized: "Pouring out of a twin works as usual: only the flask you pick up pours. One twin can't pour into the other."),
                             scene: .twinOut),
            ]
        case .overflow:
            return [
                TutorialStep(id: "overflow.pipe", topic: topic, title: String(localized: "Overflow pipes"),
                             text: String(localized: "A glass pipe runs from one flask's rim to another flask. When a pour doesn't fit, the rest runs on through the pipe."),
                             scene: .pipeOverflow),
                TutorialStep(id: "overflow.spill", topic: topic, title: String(localized: "Mind the spill"),
                             text: String(localized: "A full flask with the same potion on top lets the whole pour through. The far flask takes it like any pour, or the rest stays where it was."),
                             scene: .pipePassOn),
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
        case .essence: return String(localized: "New: essence flasks")
        case .narrowNeck: return String(localized: "New: narrow necks")
        case .funnel: return String(localized: "New: funnel flasks")
        case .tap: return String(localized: "New: tap flasks")
        case .frozen: return String(localized: "New: frozen layers")
        case .bubbling: return String(localized: "New: bubbling flasks")
        case .twins: return String(localized: "New: twin flasks")
        case .overflow: return String(localized: "New: overflow pipes")
        }
    }
}

/// A tiny still life of flasks for one tutorial step, drawn with `BottleView`.
private struct TutorialScene: View {
    let scene: TutorialStep.Scene
    private let w: CGFloat = 34

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
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
                BottleView(bottle: Bottle([5, 0, 6, 2], capacity: 4), width: w, hidden: BottleView.bottomHidden(3, of: 4))
                BottleView(bottle: Bottle([3, 7, 7], capacity: 4), width: w, hidden: BottleView.bottomHidden(1, of: 3))
            case .essence:
                VStack(spacing: 6) {
                    BottleView(bottle: essence(0, [0, 0]), width: w)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                BottleView(bottle: Bottle([1, 0], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                VStack(spacing: 6) {
                    BottleView(bottle: essence(2, []), width: w)
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            case .essenceOut:
                BottleView(bottle: essence(0, [0, 0, 6]), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([6, 6], capacity: 4), width: w)
                Image(systemName: "arrow.right").font(.title3).foregroundStyle(.secondary).padding(.bottom, w)
                BottleView(bottle: essence(0, [0, 0, 0, 0]), width: w)
            case .reveal:
                BottleView(bottle: Bottle([5, 0, 6, 6], capacity: 4), width: w, hidden: BottleView.bottomHidden(2, of: 4),
                           isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([5, 0], capacity: 4), width: w, hidden: BottleView.bottomHidden(1, of: 2))
            case .neckOut:
                BottleView(bottle: glass(.narrowNeck, [0, 1, 1]), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([1], capacity: 4), width: w)
                equals
                BottleView(bottle: glass(.narrowNeck, [0, 1]), width: w)
                BottleView(bottle: Bottle([1, 1], capacity: 4), width: w)
            case .neckIn:
                BottleView(bottle: Bottle([2, 2, 2], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: glass(.narrowNeck, [2]), width: w)
                equals
                BottleView(bottle: Bottle([2, 2], capacity: 4), width: w)
                BottleView(bottle: glass(.narrowNeck, [2, 2]), width: w)
            case .funnelIn:
                BottleView(bottle: Bottle([3, 1], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                // Start state, like the essence scene: the empty funnel may take the blue.
                VStack(spacing: 6) {
                    BottleView(bottle: glass(.funnel, []), width: w)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Image(systemName: "nosign").font(.title).foregroundStyle(.secondary).padding(.bottom, w)
                VStack(spacing: 6) {
                    BottleView(bottle: glass(.funnel, [4, 4]), width: w)
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            case .funnelCare:
                VStack(spacing: 6) {
                    BottleView(bottle: glass(.funnel, [5, 5, 5]), width: w)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                VStack(spacing: 6) {
                    BottleView(bottle: glass(.funnel, [5, 2]), width: w)
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            case .tapBottom:
                BottleView(bottle: glass(.tap, [0, 0, 2, 3]), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([0], capacity: 4), width: w)
                equals
                BottleView(bottle: glass(.tap, [2, 3]), width: w)
                BottleView(bottle: Bottle([0, 0, 0], capacity: 4), width: w)
            case .iceHolds:
                BottleView(bottle: iced([2, 5, 3, 3], layer: 1, turns: 3), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([3], capacity: 4), width: w)
                equals
                BottleView(bottle: iced([2, 5], layer: 1, turns: 2), width: w)
                BottleView(bottle: Bottle([3, 3, 3], capacity: 4), width: w)
            case .iceSeals:
                BottleView(bottle: Bottle([0, 6], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                Image(systemName: "nosign").font(.title).foregroundStyle(.secondary).padding(.bottom, w)
                VStack(spacing: 6) {
                    BottleView(bottle: iced([1, 4, 6], layer: 2, turns: 2), width: w)
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            case .iceThaws:
                BottleView(bottle: iced([1, 4, 4], layer: 2, turns: 2), width: w)
                arrow
                BottleView(bottle: iced([1, 4, 4], layer: 2, turns: 1), width: w)
                arrow
                BottleView(bottle: Bottle([1, 4, 4], capacity: 4), width: w)
            case .bubbleRises:
                BottleView(bottle: bubbling([0, 4, 4], every: 3, phase: 2), width: w)
                arrow
                BottleView(bottle: bubbling([4, 4, 0], every: 3, phase: 0), width: w)
            case .bubbleDial:
                BottleView(bottle: bubbling([1, 2, 2], every: 3, phase: 1), width: w)
                arrow
                BottleView(bottle: bubbling([1, 2, 2], every: 3, phase: 2), width: w)
                arrow
                BottleView(bottle: bubbling([2, 2, 1], every: 3, phase: 0), width: w)
            case .bubbleUse:
                BottleView(bottle: bubbling([0, 6, 6], every: 2, phase: 1), width: w)
                arrow
                BottleView(bottle: bubbling([6, 6, 0], every: 2, phase: 0), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                BottleView(bottle: Bottle([0, 0], capacity: 4), width: w)
            case .twinSplit:
                BottleView(bottle: Bottle([0, 3, 3], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                LinkedPair(kind: .twins, first: Bottle([], capacity: 4), second: Bottle([], capacity: 4), width: w)
                equals
                LinkedPair(kind: .twins, first: Bottle([3], capacity: 4), second: Bottle([3], capacity: 4), width: w)
            case .twinEven:
                VStack(spacing: 6) {
                    LinkedPair(kind: .twins, first: Bottle([4], capacity: 4), second: Bottle([4], capacity: 4), width: w)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                BottleView(bottle: Bottle([2, 4, 4], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                    .padding(.bottom, 22)
                VStack(spacing: 6) {
                    LinkedPair(kind: .twins, first: Bottle([4], capacity: 4), second: Bottle([2], capacity: 4), width: w)
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            case .twinOut:
                LinkedPair(kind: .twins, first: Bottle([6, 6, 1], capacity: 4), second: Bottle([6, 6, 1], capacity: 4),
                           width: w, firstSelected: true)
                arrow
                BottleView(bottle: Bottle([5, 1], capacity: 4), width: w)
                equals
                LinkedPair(kind: .twins, first: Bottle([6, 6], capacity: 4), second: Bottle([6, 6, 1], capacity: 4), width: w)
            case .pipeOverflow:
                BottleView(bottle: Bottle([2, 2, 2], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                LinkedPair(kind: .pipe, first: Bottle([5, 5, 2], capacity: 4), second: Bottle([], capacity: 4), width: w)
                equals
                LinkedPair(kind: .pipe, first: Bottle([5, 5, 2, 2], capacity: 4), second: Bottle([2, 2], capacity: 4), width: w)
            case .pipePassOn:
                BottleView(bottle: Bottle([1, 6], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                arrow
                LinkedPair(kind: .pipe, first: Bottle([3, 3, 6, 6], capacity: 4), second: Bottle([6], capacity: 4), width: w)
                equals
                LinkedPair(kind: .pipe, first: Bottle([3, 3, 6, 6], capacity: 4), second: Bottle([6, 6], capacity: 4), width: w)
            case .tapNoIn:
                BottleView(bottle: Bottle([6, 1], capacity: 4), width: w, isSelected: true)
                    .offset(y: -14)
                Image(systemName: "nosign").font(.title).foregroundStyle(.secondary).padding(.bottom, w)
                VStack(spacing: 6) {
                    BottleView(bottle: glass(.tap, [1, 6]), width: w)
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
        }
        .padding(.top, 18)
        // A bubbling flask's dial hangs under its base.
        .padding(.bottom, hangsDial ? BubbleGauge.room(w) : 0)
    }

    private var hangsDial: Bool {
        switch scene {
        case .bubbleRises, .bubbleDial, .bubbleUse: return true
        default: return false
        }
    }

    /// An essence flask with the rune of `color` holding `colors`.
    private func essence(_ color: Int, _ colors: [Int]) -> Bottle {
        Bottle(layers: colors.map { .color(ColorID($0)) }, capacity: 4, modifiers: [.essence(ColorID(color))])
    }

    /// A flask with one glass works modifier holding `colors`.
    private func glass(_ modifier: BottleModifier, _ colors: [Int]) -> Bottle {
        Bottle(layers: colors.map { .color(ColorID($0)) }, capacity: 4, modifiers: [modifier])
    }

    /// A flask holding `colors` whose layer `layer` is frozen for `turns` more moves.
    private func iced(_ colors: [Int], layer: Int, turns: Int) -> Bottle {
        Bottle(layers: colors.map { .color(ColorID($0)) }, capacity: 4,
               modifiers: [.frozen(layer: layer, turns: turns)])
    }

    /// A bubbling flask holding `colors` (bottom first), `phase` moves into a period of `every`.
    private func bubbling(_ colors: [Int], every: Int, phase: Int) -> Bottle {
        Bottle(layers: colors.map { .color(ColorID($0)) }, capacity: 4,
               modifiers: [.bubbling(every: every, phase: phase)])
    }

    private var equals: some View {
        Image(systemName: "equal")
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.bottom, w)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, w)
    }
}
