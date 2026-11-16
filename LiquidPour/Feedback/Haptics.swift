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

    /// Light impact: the tap did nothing.
    static func illegal() {
        #if os(iOS)
        light.impactOccurred()
        #endif
    }
}
