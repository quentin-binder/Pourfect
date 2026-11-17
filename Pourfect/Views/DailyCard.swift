import BottleSortCore
import SwiftUI

/// VoiceOver summary of the Daily Brew (the "Today" card and the daily hub, R10).
enum DailyAccessibility {
    static func summary(_ daily: DailyModel) -> Text {
        let spec = daily.spec
        let streak = daily.stats.currentStreak
        let state: String
        if let result = daily.todayResult {
            state = result.isPerfect ? String(localized: "solved perfectly") : String(localized: "solved")
        } else {
            state = spec.mode.localizedName
        }
        return Text("Daily Brew, \(spec.localizedLabel), \(state), streak \(streak)")
    }
}
