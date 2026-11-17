import BottleSortCore
import Match3Core
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
    /// An ingredient-gathering (match-3) level (R9).
    case match3(M3Level)
    /// A gathering episode's level list (episode number).
    case episode(Int)
    /// The Daily Gathering screen, and its level of a UTC day.
    case m3Daily
    case m3DailyPlay(M3Level, DailyDate)
    /// Secret Recipe (R10b): the daily screen, and a game (today's daily or a practice seed).
    case recipeDaily
    case recipe(RecipePlay)
}

struct RootView: View {
    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @Environment(DailyModel.self) private var daily
    @Environment(M3DailyModel.self) private var m3daily
    @Environment(RecipeDailyModel.self) private var recipeDaily
    @Environment(RushRecordModel.self) private var rushRecords
    @Environment(StoryPresenter.self) private var story
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @State private var path: [Route] = []
    /// Rewards just unlocked, shown in the "New reward!" toast (R7).
    @State private var toast: [Reward]?
    @State private var showsLabStyle = false
    #if DEBUG && os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        let stats = progress.playerStats(catalog: catalog, bestDailyStreak: daily.stats.bestStreak,
                                         rushBest: rushRecords.best)
        let unlocked = progress.unlockedRewards(stats)
        let cosmetics = settings.value.cosmetics.resolved(unlocked: unlocked)
        NavigationStack(path: $path) {
            ChapterMapView(onOpenChapter: { path.append(.pack($0)) },
                           onChallenges: { path.append(.challenges) },
                           onDaily: { path.append(.daily) },
                           onEpisode: { path.append(.episode($0)) },
                           onM3Daily: { path.append(.m3Daily) },
                           onLabStyle: { showsLabStyle = true })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .pack(let packID):
                        if let pack = catalog.pack(id: packID) {
                            PackView(pack: pack) { path.append(.level(pack: pack.id, index: $0)) }
                        }
                    case .challenges:
                        ChallengesView(onOpenPack: { path.append(.pack($0)) },
                                       onRandom: { path.append(.randomSettings) },
                                       onRush: { path.append(.rush) },
                                       onRecipeDaily: { path.append(.recipeDaily) },
                                       onRecipePractice: { path.append(.recipe(.practice(RecipeGameView.randomSeed()))) })
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
                        DailyView(onPlay: { level, date in path.append(.dailyPlay(level, date)) },
                                  onGathering: { path.append(.m3Daily) },
                                  onRecipe: { path.append(.recipeDaily) })
                    case .dailyPlay(let level, let date):
                        GameView(model: GameViewModel(dailyLevel: level, date: date, daily: daily))
                    case .rush:
                        RushView(makeRun: makeRushRun)
                    case .match3(let level):
                        MatchGameView(level: level) { path.removeAll() }
                    case .episode(let number):
                        if let file = Match3Library.shared.episodes.first(where: { $0.episode.number == number }) {
                            EpisodeView(file: file) { path.append(.match3($0)) }
                        }
                    case .m3Daily:
                        M3DailyView(onPlay: { level, date in path.append(.m3DailyPlay(level, date)) })
                    case .m3DailyPlay(let level, let date):
                        MatchGameView(level: level, daily: date) { if !path.isEmpty { path.removeLast() } }
                    case .recipeDaily:
                        RecipeDailyView { path.append(.recipe($0)) }
                    case .recipe(let play):
                        RecipeGameView(play: play)
                    }
                }
        }
        // A story scene is modal: the screen under it (the win card's Return default, Cmd-R,
        // Cmd-Z...) takes no keyboard shortcuts while it shows.
        .disabled(story.scene != nil)
        .cosmetics(cosmetics)
        .overlay {
            if let scene = story.scene {
                StoryOverlay(scene: scene, startLine: story.startLine) {
                    progress.markStorySeen(scene)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { story.finish() }
                }
                .id(scene)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            // Waits under a story scene (the ending can follow the win that unlocked a reward) and
            // gets its full time once the scene is gone; only a toast seen counts as announced.
            if let toast, story.scene == nil {
                RewardToast(rewards: toast) {
                    progress.markAnnounced(Set(toast.map(\.id)))
                    self.toast = nil
                    showsLabStyle = true
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: toast.map(\.id)) {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }   // covered by a scene
                    progress.markAnnounced(Set(toast.map(\.id)))
                    withAnimation { self.toast = nil }
                }
            }
        }
        .sheet(isPresented: $showsLabStyle) {
            NavigationStack { LabStyleView() }
                .cosmetics(cosmetics)
        }
        // New rewards: announce each once (never the starters; nothing with `-LPUnlockAll`).
        .onChange(of: unlocked, initial: true) { _, now in announce(now) }
        // A new UTC day may have started while the app was in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { daily.refresh(); m3daily.refresh(); recipeDaily.refresh() }
        }
        #if DEBUG
        .task { _ = SoundEngine.shared }   // starts synthesizing the sounds in the background
        .task { await openFromLaunchArguments() }
        #endif
    }

    private func announce(_ unlocked: Set<String>) {
        guard !ProgressModel.unlockAll else { return }
        let fresh = Rewards.newlyUnlocked(unlocked, announced: progress.announcedRewards)
        // Not yet in a toast (one waiting under a story scene keeps its rewards and adds these).
        let pending = toast ?? []
        let added = fresh.filter { reward in !pending.contains { $0.id == reward.id } }
        guard !added.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { toast = pending + added }
        let text = String(localized: "New reward: \(RewardToast.summary(added))", comment: "VoiceOver announcement when rewards unlock")
        AccessibilityNotification.Announcement(text).post()
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
        // `-LPShowStory N` plays chapter N's story scene (`-LPShowStory ending`: the ending) over
        // whatever else opens; `-LPStoryLine K` opens it on line K (1-based).
        if let raw = defaults.string(forKey: "LPShowStory") {
            // `-LPShowStory gathering.N`: gathering episode N's scene.
            let scene = raw == "ending" ? StoryScene.ending : StoryScene(id: raw) ?? Int(raw).map(StoryScene.chapter)
            if let scene { story.show(scene, line: max(0, defaults.integer(forKey: "LPStoryLine") - 1)) }
        }
        #if os(macOS)
        // `-LPWindowSize WxH` sets the main window's frame (points, title bar included) and centers
        // it, for App Store screenshots of a fixed aspect ratio.
        if let raw = defaults.string(forKey: "LPWindowSize") {
            let size = raw.split(separator: "x").compactMap { Double($0) }
            if size.count == 2, let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                window.setFrame(CGRect(origin: window.frame.origin, size: CGSize(width: size[0], height: size[1])),
                                display: true)
                window.center()
            }
        }
        #endif
        // `-LPOpenMatch3 ID` opens an ingredient-gathering level (`m3-03-2`, or `daily` for today's
        // daily match-3, `daily-YYYY-MM-DD` for another day's); `-LPM3Seed S` replaces its seed and
        // `-LPM3Demo K` (in `MatchGameView`) plays K bot moves.
        // `-LPOpenEpisode N` opens gathering episode N's level list; `-LPOpenM3Daily 1` the Daily
        // Gathering screen (`-LPPlayM3Daily 1` also starts today's level).
        // `-LPOpenRecipe daily|practice|stats` opens today's Secret Recipe, a practice one (seed
        // `-LPRecipeSeed N`, else random) or the daily screen; `-LPRecipeDemo K` (in `RecipeGameView`)
        // plays K guesses (nothing is saved).
        if let raw = defaults.string(forKey: "LPOpenRecipe") {
            switch raw {
            case "practice":
                let seed = defaults.integer(forKey: "LPRecipeSeed")
                path = [.challenges, .recipe(.practice(seed > 0 ? UInt64(seed) : RecipeGameView.randomSeed()))]
            case "stats": path = [.recipeDaily]
            default: path = [.recipeDaily, .recipe(.daily(recipeDaily.today))]
            }
            return
        }
        if defaults.integer(forKey: "LPOpenEpisode") > 0 {
            path = [.episode(defaults.integer(forKey: "LPOpenEpisode"))]
            return
        }
        if defaults.bool(forKey: "LPOpenM3Daily") || defaults.bool(forKey: "LPPlayM3Daily") {
            path = [.m3Daily]
            guard defaults.bool(forKey: "LPPlayM3Daily") else { return }
            while m3daily.level == nil { try? await Task.sleep(for: .milliseconds(100)) }
            if let level = m3daily.level { path.append(.m3DailyPlay(level, m3daily.today)) }
            return
        }
        if let id = defaults.string(forKey: "LPOpenMatch3") {
            var level: M3Level?
            if id.hasPrefix("daily") {
                let date = DailyDate(isoString: String(id.dropFirst("daily-".count))) ?? DailyDate.today()
                level = await Task.detached { M3Daily.level(for: date) }.value
            } else {
                level = Match3Library.shared.level(id: id)
            }
            if var level {
                let seed = defaults.integer(forKey: "LPM3Seed")
                if seed > 0 { level.seed = UInt64(seed) }
                // `-LPM3Moves N` replaces its move limit (to reach the win or out-of-moves card fast).
                let moves = defaults.integer(forKey: "LPM3Moves")
                if moves > 0 { level.moves = moves }
                path = [.match3(level)]
            }
            return
        }
        // `-LPOpenLabStyle 1` opens the Lab Style rewards screen.
        if defaults.bool(forKey: "LPOpenLabStyle") { showsLabStyle = true }
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
