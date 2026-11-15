import SwiftUI

@main
struct LiquidPourApp: App {
    @State private var catalog = LevelCatalog.loadBundled()
    @State private var progress = ProgressModel(store: UserDefaultsProgressStore())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(catalog)
                .environment(progress)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 760)
        #endif
    }
}
