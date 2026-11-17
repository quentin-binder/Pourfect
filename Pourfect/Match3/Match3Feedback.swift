import BottleSortCore
import Foundation

/// Sound and haptics of the ingredient-gathering board (R9), honoring the player's settings.
/// The board model calls these at the moments its animation reaches them.
enum Match3Feedback {
    enum Event {
        case select
        case swap
        /// A swap that makes no match: the pieces bounce back.
        case refused
        /// Pieces cleared by matches in wave `cascade` (1 = the swap's own wave).
        case pop(cascade: Int)
        case special
        case created
        case frost
        case crate
        case flask
        case reshuffle
        case won
        case outOfMoves
    }

    static func play(_ event: Event, settings: GameSettings) {
        let sound = settings.soundEnabled
        let haptics = settings.hapticsEnabled
        let engine = SoundEngine.shared
        switch event {
        case .select:
            if sound { engine.play(.clink, volume: 0.5) }
            if haptics { Haptics.select() }
        case .swap:
            if sound { engine.play(.m3Swap) }
        case .refused:
            if sound { engine.play(.tap, volume: 0.8) }
            if haptics { Haptics.illegal() }
        case .pop(let cascade):
            if sound { engine.playPop(step: cascade - 1) }
            if haptics { Haptics.matchPop(cascade: cascade) }
        case .special:
            if sound { engine.play(.m3Whoosh) }
            if haptics { Haptics.specialFired() }
        case .created:
            if sound { engine.play(.m3Spark) }
        case .frost:
            if sound { engine.play(.m3Crack) }
            if haptics { Haptics.obstacleHit() }
        case .crate:
            if sound { engine.play(.m3Crate) }
            if haptics { Haptics.obstacleHit() }
        case .flask:
            if sound { engine.play(.m3Collect) }
            if haptics { Haptics.flaskCompleted() }
        case .reshuffle:
            if sound { engine.play(.brew, volume: 0.7) }
            if haptics { Haptics.brew() }
        case .won:
            if sound { engine.play(.success) }
            if haptics { Haptics.levelWon() }
        case .outOfMoves:
            if sound { engine.play(.runeHum, volume: 0.7) }
            if haptics { Haptics.illegal() }
        }
    }
}
