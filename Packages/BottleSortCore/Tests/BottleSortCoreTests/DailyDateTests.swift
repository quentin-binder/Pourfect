import Foundation
import Testing
@testable import BottleSortCore

func day(_ y: Int, _ m: Int, _ d: Int) -> DailyDate { DailyDate(year: y, month: m, day: d)! }

/// A Date from wall-clock components in a fixed time zone (UTC offset in hours).
func instant(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, offsetHours: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: offsetHours * 3600)!
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("DailyDate")
struct DailyDateTests {
    @Test func validation() {
        #expect(DailyDate(year: 2026, month: 2, day: 29) == nil)
        #expect(DailyDate(year: 2028, month: 2, day: 29) != nil)
        #expect(DailyDate(year: 2000, month: 2, day: 29) != nil)
        #expect(DailyDate(year: 1900, month: 2, day: 29) == nil)
        #expect(DailyDate(year: 2026, month: 13, day: 1) == nil)
        #expect(DailyDate(year: 2026, month: 4, day: 31) == nil)
        #expect(DailyDate(year: 2026, month: 1, day: 0) == nil)
    }

    @Test func isoString() {
        #expect(day(2026, 11, 15).isoString == "2026-11-15")
        #expect(day(2027, 1, 5).isoString == "2027-01-05")
        #expect(DailyDate(isoString: "2026-11-15") == day(2026, 11, 15))
        #expect(DailyDate(isoString: "2026-02-30") == nil)
        #expect(DailyDate(isoString: "2026-1-05") == nil)
        #expect(DailyDate(isoString: "+026-11-15") == nil)
        #expect(DailyDate(isoString: "") == nil)
    }

    @Test func codableAsString() throws {
        let data = try JSONEncoder().encode([day(2026, 11, 15)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-11-15\"]")
        #expect(try JSONDecoder().decode([DailyDate].self, from: data) == [day(2026, 11, 15)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([DailyDate].self, from: Data("[\"2026-02-30\"]".utf8)) }
    }

    @Test func utcMidnightFromFarTimeZones() {
        // 2026-11-15 23:59 UTC is already the 16th in Kiribati (UTC+14) and still the 15th at UTC−12.
        #expect(DailyDate(instant(2026, 11, 16, 13, 59, offsetHours: 14)) == day(2026, 11, 15))
        #expect(DailyDate(instant(2026, 11, 16, 14, 0, offsetHours: 14)) == day(2026, 11, 16))
        #expect(DailyDate(instant(2026, 11, 15, 11, 59, offsetHours: -12)) == day(2026, 11, 15))
        #expect(DailyDate(instant(2026, 11, 15, 12, 0, offsetHours: -12)) == day(2026, 11, 16))
        // Same instant seen from both sides of the date line → same daily date.
        let a = instant(2026, 11, 16, 10, 0, offsetHours: 14)
        let b = instant(2026, 11, 15, 8, 0, offsetHours: -12)
        #expect(a == b)
        #expect(DailyDate(a) == DailyDate(b))
        #expect(DailyDate(a) == day(2026, 11, 15))
        // Exact boundaries.
        #expect(DailyDate(day(2026, 11, 15).startDate) == day(2026, 11, 15))
        #expect(DailyDate(day(2026, 11, 15).startDate.addingTimeInterval(-0.001)) == day(2026, 11, 14))
    }

    @Test func nextAndPrevious() {
        #expect(day(2026, 12, 31).next == day(2027, 1, 1))
        #expect(day(2027, 1, 1).previous == day(2026, 12, 31))
        #expect(day(2028, 2, 28).next == day(2028, 2, 29))
        #expect(day(2028, 2, 29).next == day(2028, 3, 1))
        #expect(day(2026, 2, 28).next == day(2026, 3, 1))
        #expect(day(2100, 2, 28).next == day(2100, 3, 1))
        #expect(day(2000, 3, 1).previous == day(2000, 2, 29))
        #expect(day(1970, 1, 1).dayNumber == 0)
        #expect(day(1969, 12, 31).dayNumber == -1)
        #expect(day(2026, 11, 15).adding(days: 365) == day(2027, 11, 15))
        #expect(day(2027, 1, 1).days(since: day(2026, 1, 1)) == 365)
        #expect(day(2029, 1, 1).days(since: day(2028, 1, 1)) == 366)
    }

    @Test func dayNumberRoundTripsAndMatchesUTCCalendar() {
        var d = day(1999, 12, 25)
        for n in d.dayNumber..<(d.dayNumber + 12_000) {
            #expect(DailyDate(dayNumber: n) == d)
            #expect(d.startDate.timeIntervalSince1970 == Double(n) * 86_400)
            #expect(DailyDate(d.startDate.addingTimeInterval(86_399)) == d)
            d = d.next
        }
    }

    @Test func weekdays() {
        #expect(day(2026, 11, 15).weekday == .sunday)
        #expect(day(2026, 11, 16).weekday == .monday)
        #expect(day(1970, 1, 1).weekday == .thursday)
        #expect(day(2000, 1, 1).weekday == .saturday)
        #expect(day(2028, 2, 29).weekday == .tuesday)
        #expect(day(1969, 12, 29).weekday == .monday)
    }

    @Test func comparableAndMonth() {
        #expect(day(2026, 12, 31) < day(2027, 1, 1))
        #expect(day(2026, 2, 1) < day(2026, 10, 1))
        #expect(day(2026, 11, 15).firstOfMonth == day(2026, 11, 1))
        #expect(day(2028, 2, 3).daysInMonth == 29)
        #expect(day(2026, 2, 3).daysInMonth == 28)
    }
}

