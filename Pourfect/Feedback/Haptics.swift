#if os(iOS)
import UIKit
#endif

/// Game haptics. iOS only; every call is a no-op on the Mac.
enum Haptics {
    #if os(iOS)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()
    #endif

    /// Light tap: a bottle was picked up.
    static func select() {
        #if os(iOS)
        light.impactOccurred(intensity: 0.7)
        #endif
    }

    /// Soft thud: liquid reaches the target.
    static func pour() {
        #if os(iOS)
        soft.impactOccurred(intensity: 0.8)
        #endif
    }

    /// Success pattern: a flask was completed.
    static func flaskCompleted() {
        #if os(iOS)
        notification.notificationOccurred(.success)
        #endif
    }

    /// Success pattern plus a closing knock: the level was solved.
    static func levelWon() {
        #if os(iOS)
        notification.notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            medium.impactOccurred()
        }
        #endif
    }

    /// Two soft taps: ice cracked and melted.
    static func thaw() {
        #if os(iOS)
        soft.impactOccurred(intensity: 0.5)
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            soft.impactOccurred(intensity: 0.35)
        }
        #endif
    }

    /// Three light, quickening taps: a bubbling flask's bottom layer rose to the top.
    static func bubble() {
        #if os(iOS)
        Task {
            for (k, delay) in [0, 260, 180].enumerated() {
                try? await Task.sleep(for: .milliseconds(delay))
                light.impactOccurred(intensity: 0.35 + 0.15 * Double(k))
            }
        }
        #endif
    }

    /// A rolling swirl of soft taps, then a fuller one as the new potion blooms (E1 mixing).
    static func brew() {
        #if os(iOS)
        Task {
            for (k, delay) in [0, 110, 110, 110].enumerated() {
                try? await Task.sleep(for: .milliseconds(delay))
                soft.impactOccurred(intensity: 0.3 + 0.08 * Double(k))
            }
            try? await Task.sleep(for: .milliseconds(Int(MixPose.bloom * 1000) - 330))
            medium.impactOccurred(intensity: 0.6)
        }
        #endif
    }

    /// A firm thump, then a soft tap: the pressure pipe pushed, and the layer entered the far
    /// flask from below.
    static func push() {
        #if os(iOS)
        medium.impactOccurred(intensity: 0.6)
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            soft.impactOccurred(intensity: 0.35)
        }
        #endif
    }

    /// A gate's portcullis (A3): a quick ratchet of light taps and a firm knock as it locks
    /// open, or one heavy knock as it drops shut.
    static func gate(opened: Bool) {
        #if os(iOS)
        if opened {
            Task {
                for _ in 0..<3 {
                    light.impactOccurred(intensity: 0.35)
                    try? await Task.sleep(for: .milliseconds(90))
                }
                try? await Task.sleep(for: .milliseconds(80))
                medium.impactOccurred(intensity: 0.7)
            }
        } else {
            medium.impactOccurred(intensity: 0.9)
        }
        #endif
    }

    /// Ingredient gathering (R9): a light tap per match, firmer with each cascade step.
    static func matchPop(cascade: Int) {
        #if os(iOS)
        light.impactOccurred(intensity: min(1, 0.45 + 0.12 * Double(max(0, cascade - 1))))
        #endif
    }

    /// A special fires (R9): one firm knock.
    static func specialFired() {
        #if os(iOS)
        medium.impactOccurred(intensity: 0.75)
        #endif
    }

    /// Frost cracks or a crate is hit (R9): a soft tap.
    static func obstacleHit() {
        #if os(iOS)
        soft.impactOccurred(intensity: 0.55)
        #endif
    }

    /// Light impact: the tap did nothing.
    static func illegal() {
        #if os(iOS)
        light.impactOccurred()
        #endif
    }
}
