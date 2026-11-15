import SwiftUI

struct RootView: View {
    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            LevelSelectView { path.append($0) }
                .navigationDestination(for: Int.self) { index in
                    GameView(model: GameViewModel(levels: catalog.levels, index: index, progress: progress))
                }
        }
        #if DEBUG
        // Dev aid: launch with `-LPOpenLevel N` (1-based) to jump straight into a level.
        .onAppear {
            let n = UserDefaults.standard.integer(forKey: "LPOpenLevel")
            if n > 0, n <= catalog.levels.count, path.isEmpty { path = [n - 1] }
        }
        #endif
    }
}
