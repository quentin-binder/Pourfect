import Foundation

/// Day of the week, Monday first (ISO 8601 order).
public enum Weekday: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }

    /// English name ("Monday"); the app localizes its own labels.
    public var name: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }
}

/// One calendar day in UTC (proleptic Gregorian), e.g. 2026-11-15.
///
/// The daily puzzle changes at UTC midnight for every player worldwide, so a
/// `DailyDate` is always derived from a `Date` with a Gregorian calendar fixed to
/// UTC, never from the device calendar or time zone. Codable as its ISO string
/// ("2026-11-15").
public struct DailyDate: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    /// 1...12
    public let month: Int
    /// 1...daysInMonth
    public let day: Int

    /// nil if the components don't name a real day.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= DailyDate.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The UTC calendar day containing `date`.
    public init(_ date: Date) {
        let c = DailyDate.utcCalendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    /// Today in UTC.
    public static func today(now: Date = Date()) -> DailyDate { DailyDate(now) }

    /// Parses "YYYY-MM-DD" (exactly that shape, four-digit year).
    public init?(isoString s: String) {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// "2026-11-15"
    public var isoString: String {
        let y = String(year), m = String(month), d = String(day)
        return String(repeating: "0", count: max(0, 4 - y.count)) + y + "-"
            + (m.count < 2 ? "0" : "") + m + "-" + (d.count < 2 ? "0" : "") + d
    }

    public var description: String { isoString }

    // MARK: Arithmetic (pure integer maths, no Calendar involved)

    /// Days since 1970-01-01 (negative before it).
    public var dayNumber: Int {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The day `dayNumber` days after 1970-01-01.
    public init(dayNumber z0: Int) {
        // Howard Hinnant's civil_from_days.
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.month = m
        self.day = d
    }

    public func adding(days n: Int) -> DailyDate { DailyDate(dayNumber: dayNumber + n) }
    public var next: DailyDate { adding(days: 1) }
    public var previous: DailyDate { adding(days: -1) }

    /// Whole days from `other` to `self` (positive if `self` is later).
    public func days(since other: DailyDate) -> Int { dayNumber - other.dayNumber }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday (ISO 4).
        let mod = ((dayNumber % 7) + 7) % 7
        return Weekday(rawValue: (mod + 3) % 7 + 1)!
    }

    /// The first day of this date's month.
    public var firstOfMonth: DailyDate { DailyDate(year: year, month: month, day: 1)! }

    public var daysInMonth: Int { DailyDate.daysInMonth(year: year, month: month) }

    /// UTC midnight at the start of this day.
    public var startDate: Date { Date(timeIntervalSince1970: TimeInterval(dayNumber) * 86_400) }

    public static func isLeapYear(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        case 1...12: return 31
        default: return 0
        }
    }

    public static func < (a: DailyDate, b: DailyDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// Gregorian calendar fixed to UTC (never the device calendar or time zone).
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: Codable (ISO string)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let date = DailyDate(isoString: s) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a YYYY-MM-DD date: \(s)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
