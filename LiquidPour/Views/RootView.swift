import BottleSortCore
import SwiftUI

/// Screens reachable from the level select.
enum Route: Hashable {
    case level(Int)
    case randomSettings
    case random(LevelDefinition, RandomLevelOptions)
}

struct RootView: View {
    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            LevelSelectView(onSelect: { path.append(.level($0)) },
                            onRandom: { path.append(.randomSettings) })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .level(let index):
                        GameView(model: GameViewModel(levels: catalog.levels, index: index, progress: progress))
                    case .randomSettings:
                        RandomLevelView { level, options in path.append(.random(level, options)) }
                    case .random(let level, let options):
                        GameView(model: GameViewModel(randomLevel: level, options: options))
                    }
                }
        }
        #if DEBUG
        .task { await openFromLaunchArguments() }
        #endif
    }

    #if DEBUG
    /// Dev aids for automated screenshots (DEBUG builds only):
    /// `-LPOpenLevel N` (1-based) opens a pack level; `-LPRandomSettings 1` opens the Random Level
    /// screen; `-LPRandomMode classic|locks|hidden` (+ optional `-LPRandomSeed S`) generates a
    /// random level with the saved settings and opens it.
    private func openFromLaunchArguments() async {
        guard path.isEmpty else { return }
        let defaults = UserDefaults.standard
        let n = defaults.integer(forKey: "LPOpenLevel")
        if n > 0, n <= catalog.levels.count { path = [.level(n - 1)]; return }
        if defaults.bool(forKey: "LPRandomSettings") { path = [.randomSettings]; return }
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
        if let level = result.level { path = [.random(level, result.options)] }
    }
    #endif
}
