import BottleSortCore
import Foundation

/// Sound and haptics of the distillery board (R10), honoring the player's settings. The board model
/// passes the delay at which its animation reaches each moment.
enum DistillFeedback {
    enum Event {
        /// A piece clicks a quarter turn.
        case turn
        /// A tap on something that doesn't turn (riveted piece, crossing, empty cell, cauldron, flask).
        case refused
        /// Liquid starts running along `count` newly connected channels.
        case flow(count: Int)
        /// A flask received its own color.
        case flaskFilled
        case valveOpened
        /// Two colors met.
        case murky
        case won
        case restart
    }

    static func play(_ event: Event, settings: GameSettings, after delay: TimeInterval = 0) {
        let sound = settings.soundEnabled
        let haptics = settings.hapticsEnabled
        let engine = SoundEngine.shared
        let delay = max(0, delay)
        switch event {
        case .turn:
            if sound { engine.play(.keyClick, volume: 0.75) }
            if haptics { Haptics.select() }
        case .refused:
            if sound { engine.play(.brassKnock, volume: 0.7) }
            if haptics { Haptics.illegal() }
        case .flow(let count):
            if sound { engine.playGurgle(amount: min(4, 1 + count / 6), after: delay) }
            if haptics { later(delay) { Haptics.pour() } }
        case .flaskFilled:
            if sound { engine.play(.clinkLow, after: delay) }
            if haptics { later(delay) { Haptics.pour() } }
        case .valveOpened:
            if sound { engine.play(.gateOpen, after: delay, volume: 0.8) }
            if haptics { later(delay) { Haptics.gate(opened: true) } }
        case .murky:
            if sound { engine.play(.brassKnock, after: delay, volume: 0.5) }
        case .won:
            if sound {
                engine.play(.corkPop)
                engine.play(.success, after: 0.3)
            }
            if haptics { Haptics.levelWon() }
        case .restart:
            if sound { engine.play(.clink, volume: 0.5) }
        }
    }

    private static func later(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        guard seconds > 0 else { action(); return }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            action()
        }
    }
}
