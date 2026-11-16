import BottleSortCore
import SwiftUI

@main
struct LiquidPourApp: App {
    @State private var catalog = LevelCatalog.loadBundled()
    @State private var progress = ProgressModel(store: UserDefaultsProgressStore())
    @State private var settings = AppSettings(store: UserDefaultsSettingsStore())
    @State private var tutorials = TutorialModel(store: UserDefaultsTutorialStore())
    @State private var daily = DailyModel.makeDefault()
    @State private var rushRecords = RushRecordModel()

    var body: some Scene {
        WindowGroup("Pourfect") {
            RootView()
                .environment(catalog)
                .environment(progress)
                .environment(tutorials)
                .environment(daily)
                .environment(rushRecords)
                .settingsEnvironment(settings)
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 800)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .settingsEnvironment(settings)
        }
        #endif
    }
}
