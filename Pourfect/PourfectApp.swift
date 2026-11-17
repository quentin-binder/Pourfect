import BottleSortCore
import SwiftUI

@main
struct PourfectApp: App {
    @State private var catalog = LevelCatalog.loadBundled()
    @State private var progress = ProgressModel(store: UserDefaultsProgressStore())
    @State private var settings = AppSettings(store: UserDefaultsSettingsStore())
    @State private var tutorials = TutorialModel(store: UserDefaultsTutorialStore())
    @State private var daily = DailyModel.makeDefault()
    @State private var rushRecords = RushRecordModel()
    @State private var story = StoryPresenter()
    @State private var m3progress = Match3ProgressModel()
    @State private var m3daily = M3DailyModel.makeDefault()
    @State private var distillProgress = DistillProgressModel()
    @State private var distillDaily = DistillDailyModel.makeDefault()
    @State private var recipeDaily = RecipeDailyModel.makeDefault()

    var body: some Scene {
        WindowGroup("Pourfect") {
            RootView()
                .environment(catalog)
                .environment(progress)
                .environment(tutorials)
                .environment(daily)
                .environment(rushRecords)
                .environment(story)
                .environment(m3progress)
                .environment(m3daily)
                .environment(distillProgress)
                .environment(distillDaily)
                .environment(recipeDaily)
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
