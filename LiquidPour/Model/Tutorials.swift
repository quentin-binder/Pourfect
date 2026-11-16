import BottleSortCore
import Foundation
import Observation

/// A mechanic with a first-time tip. Raw values match `Mechanic` names in the level files.
enum TutorialTopic: String, CaseIterable, Hashable {
    case basic, sealed, murky, essence, narrowNeck, funnel, tap, frozen, bubbling, twins, overflow, cauldron
    case switches = "switch"

    init?(_ mechanic: Mechanic) { self.init(rawValue: mechanic.rawValue) }

    /// Mechanics a recipe actually uses, in teaching order. A recipe with no special mechanic
    /// teaches the basic pour. `introduces` (the pack's metadata) is added for the recipe that
    /// opens a chapter only when that recipe uses none of them itself: a chapter that brings
    /// several mechanics (Glass Works: narrow neck, funnel, tap) teaches each one on the first
    /// recipe that uses it, not all at once.
    static func topics(in level: LevelDefinition, introduces: [Mechanic] = []) -> [TutorialTopic] {
        var found = Set(level.mechanics.compactMap { TutorialTopic($0) })
        let introduced = Set(introduces.compactMap { TutorialTopic($0) })
        if found.isDisjoint(with: introduced) { found.formUnion(introduced) }
        if found.subtracting([.basic]).isEmpty { found.insert(.basic) }
        return allCases.filter(found.contains)
    }
}

/// Which tips the player has already seen. Swap the implementation to change storage.
protocol TutorialStore {
    func hasSeen(_ topic: TutorialTopic) -> Bool
    func markSeen(_ topic: TutorialTopic)
    func reset()
}

struct UserDefaultsTutorialStore: TutorialStore {
    var defaults: UserDefaults = .standard
    var prefix = "tutorial.seen."

    func hasSeen(_ topic: TutorialTopic) -> Bool { defaults.bool(forKey: prefix + topic.rawValue) }
    func markSeen(_ topic: TutorialTopic) { defaults.set(true, forKey: prefix + topic.rawValue) }
    func reset() { TutorialTopic.allCases.forEach { defaults.removeObject(forKey: prefix + $0.rawValue) } }
}

/// Observable seen-state of the tips, injected at the app root.
@Observable
final class TutorialModel {
    @ObservationIgnored private let store: TutorialStore
    private(set) var seen: Set<TutorialTopic>

    init(store: TutorialStore) {
        #if DEBUG
        // Dev aid: `-LPResetTutorials 1` forgets every seen tip at launch.
        if UserDefaults.standard.bool(forKey: "LPResetTutorials") { store.reset() }
        #endif
        self.store = store
        self.seen = Set(TutorialTopic.allCases.filter(store.hasSeen))
    }

    /// Topics of `topics` the player hasn't seen yet.
    func unseen(_ topics: [TutorialTopic]) -> [TutorialTopic] {
        #if DEBUG
        // Dev aid: `-LPSkipTutorials 1` never shows a tip on its own (nothing is saved).
        if UserDefaults.standard.bool(forKey: "LPSkipTutorials") { return [] }
        #endif
        return topics.filter { !seen.contains($0) }
    }

    func markSeen(_ topics: [TutorialTopic]) {
        for topic in topics where !seen.contains(topic) {
            seen.insert(topic)
            store.markSeen(topic)
        }
    }
}
