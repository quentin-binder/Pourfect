import BottleSortCore
import Foundation
import HiddenCore
import Observation

/// Best stars and finished plays of the hidden-object rounds (R11), saved as JSON under `hidden.progress.v1`.
/// Kept apart from the sorting chapters' stars: no chapter gate ever reads them. Older saves simply have no key
/// and start empty. Injected at the app root.
@Observable
final class HiddenProgressModel {
    @ObservationIgnored private let defaults: UserDefaults
    static let key = "hidden.progress.v1"

    private(set) var progress: HiddenProgress

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(HiddenProgress.self, from: $0) }
            ?? HiddenProgress()
    }

    func stars(_ room: HiddenSceneID, round: Int) -> Int { progress.bestStars(room, round: round) }

    /// How often a round has been finished.
    func plays(_ room: HiddenSceneID, round: Int) -> Int { progress.finishedPlays(room, round: round) }

    /// Records a finished round; returns true for new best stars.
    @discardableResult
    func record(_ room: HiddenSceneID, round: Int, stars: Int) -> Bool {
        let newBest = progress.record(room, round: round, stars: stars)
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: Self.key) }
        return newBest
    }

    /// Rounds open in order (`-LPUnlockAll`: all).
    func isRoundUnlocked(_ round: Int, in room: HiddenSceneID) -> Bool {
        if ProgressModel.unlockAll { return HiddenProgression.rounds.contains(round) }
        return HiddenProgression.isRoundUnlocked(round, in: room, progress: progress)
    }

    /// A room opens with sorting chapter 2, 5 or 8. Reads the sorting progress only.
    func isRoomUnlocked(_ room: HiddenSceneID, catalog: LevelCatalog, progress sorting: ProgressModel) -> Bool {
        if ProgressModel.unlockAll { return true }
        let open = sorting.unlockedChapters(catalog.chapters)
        var chapterOpen = Array(repeating: false, count: Story.chapters.upperBound)
        for (i, pack) in catalog.chapters.enumerated() {
            if let c = pack.chapter, chapterOpen.indices.contains(c - 1) { chapterOpen[c - 1] = open[i] }
        }
        return HiddenProgression.isSceneUnlocked(room, chapterUnlocked: chapterOpen)
    }

    func entries(catalog: LevelCatalog, progress sorting: ProgressModel) -> [MapHiddenRoom] {
        HiddenSceneID.allCases.map { room in
            MapHiddenRoom(room: room, isOpen: isRoomUnlocked(room, catalog: catalog, progress: sorting),
                          stars: progress.stars(room), roundsFinished: progress.roundsFinished(room))
        }
    }
}

/// One hidden-object room on the chapter map.
struct MapHiddenRoom: Identifiable {
    let room: HiddenSceneID
    let isOpen: Bool
    let stars: Int
    let roundsFinished: Int

    var id: String { room.rawValue }
    var maxStars: Int { HiddenProgression.rounds.count * 3 }
    var rounds: Int { HiddenProgression.rounds.count }
    var opensWith: Int { HiddenProgression.openingChapter(room) }
    var isComplete: Bool { roundsFinished >= rounds }
}
