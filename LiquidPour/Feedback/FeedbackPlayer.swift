import BottleSortCore
import Foundation

/// Turns game feedback events into sound and haptics, honoring the player's settings.
/// Timings line up with the pour animation (`PourPose`).
enum FeedbackPlayer {
    static func play(_ event: GameViewModel.FeedbackEvent, settings: GameSettings, reduceMotion: Bool) {
        let sound = settings.soundEnabled
        let haptics = settings.hapticsEnabled
        let engine = SoundEngine.shared
        switch event {
        case .select:
            if sound { engine.play(.clink) }
            if haptics { Haptics.select() }
        case .illegal:
            if sound { engine.play(.tap) }
            if haptics { Haptics.illegal() }
        case .refused(_, let modifier):
            if sound {
                switch modifier {
                case .essence: engine.play(.runeHum)
                case .frozen: engine.play(.frostTink)
                default: engine.play(.brassKnock)
                }
            }
            if haptics { Haptics.illegal() }
        case .refusedLink:
            if sound { engine.play(.chainRattle) }
            if haptics { Haptics.illegal() }
        case .refusedPipe:
            if sound { engine.play(.brassKnock) }
            if haptics { Haptics.illegal() }
        case .split:
            // The chain chimes softly as the stream forks between the twins.
            if sound { engine.play(.chainRattle, after: reduceMotion ? 0 : PourPose.flowStart, volume: 0.45) }
        case .push(_, let start):
            // The push starts once the flask is full: the pipe thumps, the layers glug through.
            let delay = reduceMotion ? 0.05 : PourPose.flowStart + start * (PourPose.flowEnd - PourPose.flowStart)
            if sound { engine.play(.pipePush, after: delay) }
            if haptics { delayed(delay) { Haptics.push() } }
        case .pour(_, _, let amount, let isKey, let fromBottom):
            // Liquid starts moving at `flowStart` (immediately with reduce motion).
            let flowStart = reduceMotion ? 0 : PourPose.flowStart
            if sound {
                if isKey {
                    // The key drops into the lock near the end of the flow.
                    engine.play(.keyClick, after: reduceMotion ? 0.1 : PourPose.flowEnd - 0.12)
                } else {
                    if fromBottom {
                        // A tap: the brass valve turns just before the potion runs.
                        engine.play(.valve, after: reduceMotion ? 0 : PourPose.flowStart - 0.1)
                    } else if !reduceMotion {
                        engine.play(.clinkLow, after: PourPose.flowStart - 0.1)
                    }
                    engine.playGurgle(amount: amount, after: flowStart)
                }
            }
            if haptics { delayed(flowStart) { Haptics.pour() } }
        case .thawed:
            // The ice cracks and melts as the pour lands (`ThawingIce`).
            if sound { engine.play(.thaw) }
            if haptics { Haptics.thaw() }
        case .bubbled:
            // The bottom layer gathers into a bubble and climbs as the pour lands (`BubbleRise`).
            if sound { engine.play(.bubbleUp) }
            if haptics { Haptics.bubble() }
        case .mixed:
            // The ingredients swirl into the new potion as the pour lands (`MixSwirl`).
            if sound { engine.play(.brew) }
            if haptics { Haptics.brew() }
        case .flaskCompleted:
            if sound { engine.play(.corkPop) }
            if haptics { Haptics.flaskCompleted() }
        case .levelWon:
            // Leaves room for the cork pop of the last flask.
            if sound { engine.play(.success, after: 0.35) }
            if haptics { delayed(0.35) { Haptics.levelWon() } }
        }
    }

    /// Drops delayed sounds and haptics that haven't fired yet: the pour they belonged to was
    /// cancelled (undo, restart, new level), the game was left, or sound was turned off.
    static func cancelPending() {
        SoundEngine.shared.cancelPending()
        for task in pendingHaptics { task.cancel() }
        pendingHaptics.removeAll()
    }

    private static var pendingHaptics: [Task<Void, Never>] = []

    private static func delayed(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        guard seconds > 0 else { action(); return }
        pendingHaptics.removeAll { $0.isCancelled }
        pendingHaptics.append(Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        })
    }
}
