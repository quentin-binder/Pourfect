import BottleSortCore
import Foundation

// Localized names for the daily puzzle. The core's `name` / `label` are English only.

extension Weekday {
    var localizedName: String {
        switch self {
        case .monday: return String(localized: "Monday", comment: "Weekday of the daily puzzle")
        case .tuesday: return String(localized: "Tuesday", comment: "Weekday of the daily puzzle")
        case .wednesday: return String(localized: "Wednesday", comment: "Weekday of the daily puzzle")
        case .thursday: return String(localized: "Thursday", comment: "Weekday of the daily puzzle")
        case .friday: return String(localized: "Friday", comment: "Weekday of the daily puzzle")
        case .saturday: return String(localized: "Saturday", comment: "Weekday of the daily puzzle")
        case .sunday: return String(localized: "Sunday", comment: "Weekday of the daily puzzle")
        }
    }

    /// One or two letters for the calendar header.
    var shortSymbol: String {
        switch self {
        case .monday: return String(localized: "Mo", comment: "Calendar column: Monday")
        case .tuesday: return String(localized: "Tu", comment: "Calendar column: Tuesday")
        case .wednesday: return String(localized: "We", comment: "Calendar column: Wednesday")
        case .thursday: return String(localized: "Th", comment: "Calendar column: Thursday")
        case .friday: return String(localized: "Fr", comment: "Calendar column: Friday")
        case .saturday: return String(localized: "Sa", comment: "Calendar column: Saturday")
        case .sunday: return String(localized: "Su", comment: "Calendar column: Sunday")
        }
    }
}

extension DailyTier {
    var localizedName: String {
        switch self {
        case .gentle: return String(localized: "Gentle", comment: "Daily puzzle difficulty (Monday)")
        case .steady: return String(localized: "Steady", comment: "Daily puzzle difficulty (Tuesday)")
        case .sealed: return String(localized: "Sealed", comment: "Daily puzzle difficulty (Wednesday)")
        case .murky: return String(localized: "Murky", comment: "Daily puzzle difficulty (Thursday)")
        case .tricky: return String(localized: "Tricky", comment: "Daily puzzle difficulty (Friday)")
        case .deepSeal: return String(localized: "Deep Seal", comment: "Daily puzzle difficulty (Saturday)")
        case .grand: return String(localized: "Grand Brew", comment: "Daily puzzle difficulty (Sunday)")
        }
    }
}

extension DailyMode {
    var localizedName: String {
        switch self {
        case .classic: return String(localized: "Classic", comment: "Random recipe mode")
        case .sealed: return String(localized: "Rune Seal", comment: "Daily puzzle mode: one sealed flask")
        case .murky: return String(localized: "Murky Layers", comment: "Random recipe mode with hidden layers")
        case .murkySealed: return String(localized: "Murky Layers + Rune Seal", comment: "Daily puzzle mode")
        }
    }

    var symbol: String {
        switch self {
        case .classic: return "flask.fill"
        case .sealed: return "lock.fill"
        case .murky: return "cloud.fog.fill"
        case .murkySealed: return "smoke.fill"
        }
    }
}

extension DailySpec {
    /// "Sunday · Grand Brew"
    var localizedLabel: String { String(localized: "\(weekday.localizedName) · \(tier.localizedName)") }
    /// 1 (Monday, easiest) … 7 (Sunday, hardest).
    var difficulty: Int { weekday.rawValue }
}

enum DailyText {
    /// "New brew in 3 h 12 m" (the next puzzle comes at UTC midnight).
    static func countdown(seconds: TimeInterval, gathering: Bool = false) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        if gathering {
            if h == 0 { return String(localized: "New gathering in \(m) m", comment: "Countdown to the next daily gathering, minutes") }
            return String(localized: "New gathering in \(h) h \(m) m", comment: "Countdown to the next daily gathering, hours and minutes")
        }
        if h == 0 { return String(localized: "New brew in \(m) m", comment: "Countdown to the next daily puzzle, minutes") }
        return String(localized: "New brew in \(h) h \(m) m", comment: "Countdown to the next daily puzzle, hours and minutes")
    }

    /// Spoiler-free text to share a result: "Pourfect Daily 2026-11-15 · 12 moves (perfect) · 🔥 5".
    static func share(_ result: DailyResult, streak: Int) -> String {
        let moves = result.isPerfect
            ? String(localized: "\(result.moves) moves (perfect)", comment: "Shared daily result")
            : String(localized: "\(result.moves) moves", comment: "Shared daily result")
        return String(localized: "Pourfect Daily \(result.date.isoString) · \(moves) · 🔥 \(streak)",
                      comment: "Shared daily result: date, moves, streak")
    }

    /// Month title of the calendar ("November 2026"), for a UTC month.
    static func monthTitle(_ date: DailyDate) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).month(.wide).year()
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        // The grid is a Gregorian month: name it in the same calendar, whatever the device uses.
        style.calendar = Calendar(identifier: .gregorian)
        return date.startDate.formatted(style)
    }

    /// A full date for VoiceOver ("15 November 2026"), for a UTC day (Gregorian, like the calendar grid).
    static func longDate(_ date: DailyDate) -> String {
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        style.calendar = Calendar(identifier: .gregorian)
        return date.startDate.formatted(style)
    }
}
