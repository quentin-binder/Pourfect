import BottleSortCore
import SwiftUI

@main
struct LiquidPourApp: App {
    @State private var catalog = LevelCatalog.loadBundled()
    @State private var progress = ProgressModel(store: UserDefaultsProgressStore())
    @State private var settings = AppSettings(store: UserDefaultsSettingsStore())

    var body: some Scene {
        WindowGroup("Pourfect") {
            RootView()
                .environment(catalog)
                .environment(progress)
                .settingsEnvironment(settings)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 760)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .settingsEnvironment(settings)
        }
        #endif
    }
}
