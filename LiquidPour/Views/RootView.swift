import BottleSortCore
import SwiftUI

/// Screens reachable from the chapter map.
enum Route: Hashable {
    /// A chapter's or challenge book's recipe list.
    case pack(String)
    case challenges
    case level(pack: String, index: Int)
    case randomSettings
    case random(LevelDefinition, RandomLevelOptions)
    case daily
    case dailyPlay(LevelDefinition, DailyDate)
    /// A new Rush run (R6).
    case rush
}

struct RootView: View {
    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @Environment(DailyModel.self) private var daily
    @Environment(RushRecordModel.self) private var rushRecords
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    #if DEBUG && os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            ChapterMapView(onOpenChapter: { path.append(.pack($0)) },
                           onChallenges: { path.append(.challenges) },
                           onDaily: { path.append(.daily) })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .pack(let packID):
                        if let pack = catalog.pack(id: packID) {
                            PackView(pack: pack) { path.append(.level(pack: pack.id, index: $0)) }
                        }
                    case .challenges:
                        ChallengesView(onOpenPack: { path.append(.pack($0)) },
                                       onRandom: { path.append(.randomSettings) },
                                       onRush: { path.append(.rush) })
                    case .level(let packID, let index):
                        if let pack = catalog.pack(id: packID) {
                            GameView(model: GameViewModel(levels: pack.levels, index: index, progress: progress,
                                                          introduces: pack.introduces))
                        }
                    case .randomSettings:
                        RandomLevelView { level, options in path.append(.random(level, options)) }
                    case .random(let level, let options):
                        GameView(model: GameViewModel(randomLevel: level, options: options))
                    case .daily:
                        DailyView { level, date in path.append(.dailyPlay(level, date)) }
                    case .dailyPlay(let level, let date):
                        GameView(model: GameViewModel(dailyLevel: level, date: date, daily: daily))
                    case .rush:
                        RushView(makeRun: makeRushRun)
                    }
                }
        }
        // A new UTC day may have started while the app was in the background.
        .onChange(of: scenePhase) { _, phase in if phase == .active { daily.refresh() } }
        #if DEBUG
        .task { _ = SoundEngine.shared }   // starts synthesizing the sounds in the background
        .task { await openFromLaunchArguments() }
        #endif
    }

    /// A new Rush run with a fresh seed, using the mechanics the player has met on the main path.
    private func makeRushRun() -> RushRun {
        let seed = Self.debugNumber("LPRushSeed").map { UInt64($0) } ?? UInt64.random(in: 1...999_999_999)
        let duration = Self.debugNumber("LPRushDuration") ?? RushClock.duration
        let autoplay = Self.debugNumber("LPRushAutoplay") != nil
        let mechanics = RushMechanic.unlocked(by: progress.learnedMechanics(catalog.chapters))
        return RushRun(seed: seed, mechanics: mechanics, duration: duration, records: rushRecords, autoplay: autoplay)
    }

    /// A positive launch-argument number in DEBUG builds (`-LPRushSeed 42`); always nil in release.
    private static func debugNumber(_ key: String) -> Double? {
        #if DEBUG
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : nil
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// Dev aids for automated screenshots (DEBUG builds only):
    /// - `-LPOpenChapter N` opens chapter N's recipe list, `-LPOpenChallenge NAME` a challenge book
    ///   (`challenger`, `expert`, `master`; file name or display name), `-LPOpenChallenges 1` the Challenges area.
    /// - `-LPOpenLevel N` (1-based) then opens recipe N of that chapter / book directly. Without
    ///   either, `-LPOpenPack P` picks the pack by position: chapters first, then Challenger,
    ///   Expert, Master (with 4 chapters: 1–4, then 5–7; default 1).
    /// - `-LPRandomSettings 1` opens the Random Brew screen; `-LPRandomMode classic|locks|hidden`
    ///   (+ optional `-LPRandomSeed S`) generates a random recipe with the saved settings and opens it.
    /// - `-LPOpenRush 1` starts a Rush run (`-LPRushSeed N`, `-LPRushDuration S`, `-LPRushAutoplay 1`:
    ///   each recipe plays itself and nothing is saved).
    /// - `-LPOpenDaily 1` opens the Daily Brew screen; `-LPPlayDaily 1` also starts today's puzzle
    ///   (pretend date and fake results: `-LPDailyDate`, `-LPDailySeedResults`, see `DailyModel`).
    private func openFromLaunchArguments() async {
        guard path.isEmpty else { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "LPOpenDaily") || defaults.bool(forKey: "LPPlayDaily") {
            path = [.daily]
            guard defaults.bool(forKey: "LPPlayDaily") else { return }
            while daily.level == nil { try? await Task.sleep(for: .milliseconds(100)) }
            if let level = daily.level { path.append(.dailyPlay(level, daily.today)) }
            return
        }
        #if os(macOS)
        if defaults.bool(forKey: "LPOpenSettings") { openSettings() }
        #endif
        if let dir = defaults.string(forKey: "LPExportSounds") {
            SoundEngine.shared.debugExport(to: URL(fileURLWithPath: dir))
        }
        let n = defaults.integer(forKey: "LPOpenLevel")
        var pack: LevelPackInfo?
        var showsList = false
        if defaults.integer(forKey: "LPOpenChapter") > 0 {
            pack = catalog.chapter(defaults.integer(forKey: "LPOpenChapter"))
            showsList = true
        } else if let name = defaults.string(forKey: "LPOpenChallenge")?.lowercased() {
            pack = catalog.challenges.first { $0.id.lowercased() == name || $0.id.lowercased() == "challenge_" + name
                || $0.name.lowercased() == name }
            showsList = true
        } else if n > 0 {
            let p = max(1, defaults.integer(forKey: "LPOpenPack"))
            if p <= catalog.packs.count { pack = catalog.packs[p - 1] }
        }
        if let pack {
            var route: [Route] = pack.isChapter ? [] : [.challenges]
            if showsList || n == 0 { route.append(.pack(pack.id)) }
            if n > 0, n <= pack.levels.count { route.append(.level(pack: pack.id, index: n - 1)) }
            path = route
            return
        }
        if defaults.bool(forKey: "LPOpenChallenges") { path = [.challenges]; return }
        if defaults.bool(forKey: "LPOpenRush") { path = [.challenges, .rush]; return }
        if defaults.bool(forKey: "LPRandomSettings") { path = [.challenges, .randomSettings]; return }
        guard let raw = defaults.string(forKey: "LPRandomMode") else { return }
        var options = RandomSettings.load()
        switch raw {
        case "locks", "locksAndKeys": options.mode = .locksAndKeys
        case "hidden": options.mode = .hidden
        default: options.mode = .classic
        }
        let seed = UInt64(max(1, defaults.integer(forKey: "LPRandomSeed")))
        let chosen = options
        let result = await Task.detached { RandomLevel.generate(chosen, seed: seed) }.value
        if let level = result.level { path = [.challenges, .random(level, result.options)] }
    }
    #endif
}
