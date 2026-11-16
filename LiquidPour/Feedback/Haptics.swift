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

    /// Two soft, low taps: the overflow ran through the pipe and dropped into the far flask.
    static func overflow() {
        #if os(iOS)
        soft.impactOccurred(intensity: 0.45)
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            soft.impactOccurred(intensity: 0.3)
        }
        #endif
    }

    /// Light impact: the tap did nothing.
    static func illegal() {
        #if os(iOS)
        light.impactOccurred()
        #endif
    }
}
