// `Day` and `LocalDateTime` themselves (no Dart counterpart: Dart had
// `DateTime`).

import Foundation
import Testing
@testable import OpenTodoDomain

@Suite("Day")
struct DayTests {
    @Test func partsAndWeekday() {
        let d = Day(2026, 11, 15)
        #expect(d.year == 2026 && d.month == 11 && d.day == 15)
        #expect(d.weekday == 7) // Sunday
        #expect(Day(2026, 11, 16).weekday == 1) // Monday
        #expect(Day(2000, 1, 1).weekday == 6) // Saturday
        #expect(Day(1970, 1, 1).weekday == 4) // Thursday
    }

    @Test func julianDayMatchesKnownValues() {
        #expect(Day(2000, 1, 1).julianDay == 2_451_545)
        #expect(Day(1970, 1, 1).julianDay == 2_440_588)
        #expect(Day(julianDay: 2_451_545) == Day(2000, 1, 1))
    }

    @Test func roundTripsEveryDayFor400Years() {
        var d = Day(1900, 1, 1)
        var (y, m, dd) = (1900, 1, 1)
        while d.year < 2300 {
            #expect(d.parts == (y, m, dd), "\(d)")
            d += 1
            dd += 1
            if dd > Day.daysIn(year: y, month: m) { dd = 1; m += 1 }
            if m > 12 { m = 1; y += 1 }
        }
    }

    @Test func rollsOverLikeDartDateTime() {
        #expect(Day(2026, 13, 1) == Day(2027, 1, 1))
        #expect(Day(2026, 12, 32) == Day(2027, 1, 1))
        #expect(Day(2026, 3, 0) == Day(2026, 2, 28))
        #expect(Day(2024, 3, 0) == Day(2024, 2, 29))
        #expect(Day(2026, 0, 1) == Day(2025, 12, 1))
        #expect(Day(2026, -1, 1) == Day(2025, 11, 1))
        #expect(Day(2026, 1, -1) == Day(2025, 12, 30))
        #expect(Day(2026, 11 + 1, 0).day == 30)
    }

    @Test func strictConstruction() {
        #expect(Day.valid(2026, 2, 28) == Day(2026, 2, 28))
        #expect(Day.valid(2026, 2, 29) == nil)
        #expect(Day.valid(2024, 2, 29) != nil)
        #expect(Day.valid(2026, 13, 1) == nil)
        #expect(Day.valid(2026, 4, 31) == nil)
        #expect(Day.valid(2026, 1, 0) == nil)
    }

    @Test func parsesAndPrintsKeys() {
        #expect(Day("2026-11-05") == Day(2026, 11, 5))
        #expect(Day("2026-1-5") == Day(2026, 1, 5))
        #expect(Day(2026, 1, 5).key == "2026-01-05")
        #expect(Day(987, 1, 5).key == "0987-01-05")
        #expect("\(Day(2026, 1, 5))" == "2026-01-05")
        for bad in ["", "2026", "2026-11", "2026-11-31", "2026-13-01", "2026-11-1x", "+2026-11-01",
                    "2026-11-01T00:00", "20261-11-01", "2026--1-01", "2026-011-01"] {
            #expect(Day(bad) == nil, "\(bad)")
        }
        #expect(Day("2026-11-15"[...]) == Day(2026, 11, 15)) // Substring
    }

    @Test func arithmeticAndComparison() {
        let d = Day(2026, 11, 15)
        #expect(d + 17 == Day(2026, 12, 2))
        #expect(d - 15 == Day(2026, 10, 31))
        #expect(Day(2027, 1, 1) - d == 47)
        #expect(d.days(to: Day(2026, 11, 1)) == -14)
        #expect(Day(2026, 2, 28) + 1 == Day(2026, 3, 1))
        #expect(Day(2024, 2, 28) + 1 == Day(2024, 2, 29))
        #expect(d < d + 1 && !(d < d))
        #expect(Array(d..<(d + 3)) == [d, d + 1, d + 2])
        #expect((d...(d + 6)).count == 7)
        #expect(max(d, d - 1) == d)
    }

    @Test func weeksAndMonths() {
        #expect(Day(2026, 11, 15).startOfWeek == Day(2026, 11, 9))
        #expect(Day(2026, 11, 16).startOfWeek == Day(2026, 11, 16))
        #expect(Day(2026, 11, 15).startOfMonth == Day(2026, 11, 1))
        #expect(Day(2026, 11, 15).endOfMonth == Day(2026, 11, 30))
        #expect(Day(2024, 2, 3).daysInMonth == 29)
        #expect(Day(1900, 2, 3).daysInMonth == 28)
        #expect(Day(2000, 2, 3).daysInMonth == 29)
        #expect(Day.daysIn(year: 2026, month: 12) == 31)
        #expect(Day(2026, 1, 31).addingMonths(1) == Day(2026, 2, 28))
        #expect(Day(2026, 1, 31).addingMonths(-2) == Day(2025, 11, 30))
        #expect(Day(2026, 11, 15).addingMonths(14) == Day(2028, 1, 15))
    }

    @Test func codableAsText() throws {
        let data = try JSONEncoder().encode([Day(2026, 11, 15)])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-11-15"]"#)
        #expect(try JSONDecoder().decode([Day].self, from: data) == [Day(2026, 11, 15)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Day].self, from: Data(#"["2026-02-30"]"#.utf8)) }
    }

    @Test func fromAndToDateInAGivenZone() throws {
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        // 2026-11-15T02:00:00Z: 10:00 in Shanghai, still the 14th in New York.
        let instant = Date(timeIntervalSince1970: 1_794_708_000)
        #expect(Day(instant, in: shanghai) == Day(2026, 11, 15))
        #expect(Day(instant, in: newYork) == Day(2026, 11, 14))
        #expect(Day.today(in: shanghai, now: instant) == Day(2026, 11, 15))
        #expect(Day(2026, 11, 15).start(in: shanghai) == Date(timeIntervalSince1970: 1_794_672_000))
    }
}

@Suite("LocalDateTime")
struct LocalDateTimeTests {
    @Test func rollsOverLikeDartDateTime() {
        let t = LocalDateTime(Day(2026, 11, 15), minute: 22 * 60 + 180)
        #expect(t.day == Day(2026, 11, 16) && t.hour == 1 && t.minute == 0)
        let u = LocalDateTime(Day(2026, 11, 15), minute: -1)
        #expect(u.day == Day(2026, 11, 14) && u.minuteOfDay == 1439)
        #expect(LocalDateTime(2026, 12, 31, 24, 0) == LocalDateTime(2027, 1, 1))
        #expect(LocalDateTime(2026, 11, 15, 0, 9 * 60 - 1440 * 3) == LocalDateTime(2026, 11, 12, 9, 0))
    }

    @Test func arithmeticAndComparison() {
        let a = LocalDateTime(2026, 11, 15, 22, 30)
        #expect(a + 90 == LocalDateTime(2026, 11, 16, 0, 0))
        #expect(a - 22 * 60 - 31 == LocalDateTime(2026, 11, 14, 23, 59))
        #expect(LocalDateTime(2026, 11, 16, 1, 0) - a == 150)
        #expect(a < a + 1 && !(a < a))
    }

    @Test func text() throws {
        let a = LocalDateTime(2026, 11, 5, 9, 5)
        #expect(a.key == "2026-11-05T09:05")
        #expect(LocalDateTime("2026-11-05T09:05") == a)
        for bad in ["2026-11-05", "2026-11-05T24:00", "2026-11-05T9:60", "2026-11-05T09", "x"] {
            #expect(LocalDateTime(bad) == nil, "\(bad)")
        }
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(LocalDateTime.self, from: data) == a)
    }

    @Test func fromAndToDate() throws {
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let instant = Date(timeIntervalSince1970: 1_794_708_059) // 10:00:59 in Shanghai
        #expect(LocalDateTime(instant, in: shanghai) == LocalDateTime(2026, 11, 15, 10, 0))
        #expect(LocalDateTime.now(in: shanghai, now: instant).minuteOfDay == 600)
        #expect(LocalDateTime(2026, 11, 15, 10, 0).date(in: shanghai) == Date(timeIntervalSince1970: 1_794_708_000))
    }

    @Test func wallClockArithmeticIgnoresDST() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        // DST ended at 02:00 on 2026-11-01: a day later at the same clock time
        // is 25 hours later in real time.
        let before = LocalDateTime(2026, 10, 31, 9, 0)
        let after = before + minutesPerDay
        #expect(after == LocalDateTime(2026, 11, 1, 9, 0))
        #expect(after.date(in: newYork).timeIntervalSince(before.date(in: newYork)) == 25 * 3600)
        // 02:30 on 2026-03-08 doesn't exist there; it moves on.
        let skipped = LocalDateTime(2026, 3, 8, 2, 30).date(in: newYork)
        #expect(LocalDateTime(skipped, in: newYork) == LocalDateTime(2026, 3, 8, 3, 30))
    }
}
