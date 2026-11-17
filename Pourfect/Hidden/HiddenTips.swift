import SwiftUI

/// The pictures of the curiosity rooms' tip (R11).
enum HiddenTipScene: Equatable {
    case find, zoom, lantern
}

/// The first-time tip of the hidden-object rooms (also behind "?" in a round).
enum HiddenTips {
    static func steps() -> [TutorialStep] {
        func step(_ id: String, _ title: String, _ text: String, _ scene: HiddenTipScene) -> TutorialStep {
            TutorialStep(id: id, topic: .hiddenBasics, title: title, text: text, scene: .hidden(scene))
        }
        #if os(macOS)
        let zoom = String(localized: "Pinch on the trackpad or turn the mouse wheel to zoom, drag to look around. Double-click zooms in on a spot.",
                          comment: "Hidden-object tip (Mac): zoom and pan")
        let find = String(localized: "Click the things on the list when you spot them in the room. Other curios lie about too: clicking those, or nothing, counts as a miss.",
                          comment: "Hidden-object tip (Mac): find the objects on the list")
        #else
        let zoom = String(localized: "Pinch to zoom, drag to look around. Double-tap zooms in on a spot. Small things are much easier up close.",
                          comment: "Hidden-object tip (iPhone, iPad): zoom and pan")
        let find = String(localized: "Tap the things on the list when you spot them in the room. Other curios lie about too: tapping those, or nothing, counts as a miss.",
                          comment: "Hidden-object tip (iPhone, iPad): find the objects on the list")
        #endif
        return [
            step("hidden.find", String(localized: "Find what's on the list", comment: "Hidden-object tip title"), find, .find),
            step("hidden.zoom", String(localized: "Look closer", comment: "Hidden-object tip title"), zoom, .zoom),
            step("hidden.lantern", String(localized: "The lantern", comment: "Hidden-object tip title"),
                 String(localized: "Stuck? The lantern glows around one thing still to find, then recharges for 30 seconds. No clock is running: three stars need no hint and at most three misses.",
                        comment: "Hidden-object tip: the lantern hint and stars"), .lantern),
        ]
    }
}

/// A small picture for each tip page, drawn from symbols and the game's own lantern and magnifier.
struct HiddenTipSceneView: View {
    let scene: HiddenTipScene

    var body: some View {
        switch scene {
        case .find:
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    row("key.fill", done: true)
                    row("hourglass", done: false)
                    row("crown.fill", done: false)
                }
                Image(systemName: "hand.tap.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.85))
            }
        case .zoom:
            HStack(spacing: 18) {
                Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                HiddenMagnifierIcon().frame(width: 64, height: 64)
            }
        case .lantern:
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.45).opacity(0.5), .clear],
                                             center: .center, startRadius: 4, endRadius: 70))
                    .frame(width: 140, height: 140)
                Circle().strokeBorder(HiddenArt.gold, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                    .frame(width: 104, height: 104)
                HiddenLanternIcon().frame(width: 40, height: 48)
            }
        }
    }

    private func row(_ symbol: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(HiddenArt.gold.opacity(done ? 0.4 : 1))
            Capsule().fill(Color.white.opacity(done ? 0.25 : 0.6)).frame(width: 70, height: 6)
            if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
    }
}
