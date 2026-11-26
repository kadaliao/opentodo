// Countdowns (效率模块). New in the Swift version, no Dart counterpart.
// Lunar facts used: 春节 2026-02-17, 2027-02-06; 中秋 2025-10-06,
// 2026-09-25; 2024-02-09 was 腊月三十 and 2025–2029 have no 三十 in 腊月
// (除夕 2025-01-28 is 腊月二十九); 2025 has a 闰六月 from 07-25.

import Foundation
import Testing
@testable import OpenTodoDomain

private func cd(
    _ date: Day, kind: CountdownKind = .countdown, lunar: Bool = false, repeats: CountdownRepeat = .none,
    id: String = "c", pinned: Bool = false, today: Bool = false, reminders: [Int] = []
) -> Countdown {
    Countdown(id: id, kind: kind, date: date, lunar: lunar, repeats: repeats, showInToday: today,
              reminders: reminders, pinnedAt: pinned ? 1 : nil)
}

@Suite("Countdown model")
struct CountdownModelTests {
    @Test func jsonUsesSimpleTypes() throws {
        let c = Countdown(id: "c", title: "生日", kind: .birthday, date: Day(2000, 2, 5), lunar: true, repeats: .yearly,
                          emoji: "🎂", color: 0xFF14A38B, showInToday: true, reminders: [-900], pinnedAt: 5)
        let data = try JSONEncoder().encode(c)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["date"] as? String == "2000-02-05")
        #expect(obj["kind"] as? Int == 2 && obj["repeats"] as? Int == 1 && obj["lunar"] as? Bool == true)
        #expect(try JSONDecoder().decode(Countdown.self, from: data) == c)
    }

    @Test func unknownNumbersReadAsDefaults() throws {
        struct Box: Decodable { var k: CountdownKind; var r: CountdownRepeat }
        let b = try JSONDecoder().decode(Box.self, from: Data(#"{"k":8,"r":8}"#.utf8))
        #expect(b.k == .countdown && b.r == CountdownRepeat.none)
    }

    @Test func reminderOffsets() {
        #expect(countdownReminder(daysBefore: 1, minute: 540) == -900)
        #expect(countdownReminder(daysBefore: 0, minute: 540) == 540)
        #expect(countdownReminder(daysBefore: 7, minute: 0) == -7 * 1440)
        #expect(countdownReminderParts(-900) == (1, 540))
        #expect(countdownReminderParts(540) == (0, 540))
        #expect(countdownReminderParts(-7 * 1440) == (7, 0))
    }
}

@Suite("Countdown dates")
struct CountdownDateTests {
    let today = Day(2026, 11, 26)

    @Test func oneOffsStayOnTheirDate() {
        #expect(countdownTarget(cd(Day(2027, 1, 1)), today: today) == Day(2027, 1, 1))
        #expect(countdownTarget(cd(Day(2026, 1, 1)), today: today) == Day(2026, 1, 1))
        // A repeating one still ahead the first time is its own date.
        #expect(countdownTarget(cd(Day(2027, 5, 1), repeats: .yearly), today: today) == Day(2027, 5, 1))
    }

    @Test func yearly() {
        let c = cd(Day(2020, 3, 15), repeats: .yearly)
        #expect(countdownTarget(c, today: today) == Day(2027, 3, 15))
        #expect(countdownTarget(c, today: Day(2026, 3, 15)) == Day(2026, 3, 15))
        #expect(countdownTarget(c, today: Day(2026, 3, 14)) == Day(2026, 3, 15))
        // Across the new year.
        let eve = cd(Day(2000, 12, 31), repeats: .yearly)
        #expect(countdownTarget(eve, today: Day(2026, 12, 31)) == Day(2026, 12, 31))
        #expect(countdownTarget(eve, today: Day(2027, 1, 1)) == Day(2027, 12, 31))
    }

    @Test func aLeapDayFallsOnThe28thInOtherYears() {
        let c = cd(Day(2024, 2, 29), repeats: .yearly)
        #expect(countdownTarget(c, today: today) == Day(2027, 2, 28))
        #expect(countdownTarget(c, today: Day(2027, 3, 1)) == Day(2028, 2, 29))
        #expect(countdownOccurrences(c, from: Day(2024, 1, 1), limit: 5)
            == [Day(2024, 2, 29), Day(2025, 2, 28), Day(2026, 2, 28), Day(2027, 2, 28), Day(2028, 2, 29)])
    }

    @Test func monthlyTakesTheLastDayOfShortMonths() {
        let c = cd(Day(2026, 1, 31), repeats: .monthly)
        #expect(countdownTarget(c, today: Day(2026, 4, 5)) == Day(2026, 4, 30))
        #expect(countdownTarget(c, today: Day(2026, 2, 1)) == Day(2026, 2, 28))
        #expect(countdownTarget(c, today: Day(2026, 12, 31)) == Day(2026, 12, 31))
        #expect(countdownTarget(c, today: Day(2027, 1, 1)) == Day(2027, 1, 31))
        #expect(countdownTarget(c, today: Day(2028, 2, 1)) == Day(2028, 2, 29))
        #expect(countdownOccurrences(c, from: Day(2026, 1, 1), limit: 4)
            == [Day(2026, 1, 31), Day(2026, 2, 28), Day(2026, 3, 31), Day(2026, 4, 30)])
    }

    @Test func lunarYearly() {
        let spring = cd(Day(2026, 2, 17), kind: .holiday, lunar: true, repeats: .yearly)
        #expect(countdownTarget(spring, today: today) == Day(2027, 2, 6))
        #expect(countdownTarget(spring, today: Day(2027, 2, 6)) == Day(2027, 2, 6))
        let moon = cd(Day(2025, 10, 6), kind: .holiday, lunar: true, repeats: .yearly)
        #expect(countdownTarget(moon, today: Day(2026, 1, 1)) == Day(2026, 9, 25))
        // Today in the lunar year before (腊月), the festival in the next.
        #expect(countdownTarget(moon, today: Day(2026, 2, 1)) == Day(2026, 9, 25))
    }

    @Test func aMissingThirtiethFallsOnThe29th() {
        let eve = cd(Day(2024, 2, 9), kind: .holiday, lunar: true, repeats: .yearly)
        #expect(countdownTarget(eve, today: Day(2024, 3, 1)) == Day(2025, 1, 28))
        #expect(toLunar(Day(2025, 1, 28)) == LunarDate(2024, 12, 29))
    }

    @Test func aLeapMonthDateRepeatsInTheOrdinaryMonth() {
        let c = cd(Day(2025, 7, 25), kind: .birthday, lunar: true, repeats: .yearly) // 闰六月初一
        #expect(toLunar(Day(2025, 7, 25)) == LunarDate(2025, 6, 1, leap: true))
        let next = countdownTarget(c, today: Day(2025, 8, 1))
        #expect(next == fromLunar(2026, 6, 1))
        #expect(next.flatMap(toLunar) == LunarDate(2026, 6, 1))
    }

    @Test func lunarMonthlyCountsLeapMonths() {
        let c = cd(Day(2025, 6, 25), lunar: true, repeats: .monthly) // 六月初一
        #expect(toLunar(Day(2025, 6, 25)) == LunarDate(2025, 6, 1))
        #expect(countdownTarget(c, today: Day(2025, 7, 1)) == Day(2025, 7, 25)) // 闰六月初一
        // 三十 each month, or the 29th where there's none.
        let eve = cd(Day(2024, 2, 9), lunar: true, repeats: .monthly)
        let ds = countdownOccurrences(eve, from: Day(2025, 1, 1), limit: 12)
        #expect(ds.count == 12)
        for d in ds {
            let l = toLunar(d)!
            #expect(l.day == 30 || (l.day == 29 && toLunar(d + 1)!.day == 1), "\(d)")
        }
        #expect(Set(ds.map { toLunar($0)!.month }).count < 12) // a leap month among them
    }

    @Test func outsideTheLunarTable() {
        #expect(countdownTarget(cd(Day(2020, 1, 1), lunar: true, repeats: .yearly), today: Day(2101, 6, 1)) == nil)
        #expect(countdownTarget(cd(Day(1800, 1, 1), lunar: true), today: today) == nil)
        #expect(countdownStatus(cd(Day(1800, 1, 1), lunar: true), today: today) == nil)
    }
}

@Suite("Countdown display")
struct CountdownDisplayTests {
    let today = Day(2026, 11, 26)

    @Test func countingDownAndUp() {
        #expect(countdownStatus(cd(Day(2026, 12, 1)), today: today) == CountdownStatus(target: Day(2026, 12, 1), days: 5, past: false))
        #expect(countdownStatus(cd(Day(2026, 11, 20)), today: today) == CountdownStatus(target: Day(2026, 11, 20), days: 6, past: true))
        #expect(countdownStatus(cd(today), today: today) == CountdownStatus(target: today, days: 0, past: false))
        // An anniversary counts up from its date, even when it repeats.
        let met = cd(Day(2020, 11, 27), kind: .anniversary, repeats: .yearly)
        #expect(countdownStatus(met, today: today) == CountdownStatus(target: Day(2020, 11, 27), days: 2190, past: true))
        // Not come yet: it counts down.
        #expect(countdownStatus(cd(Day(2027, 1, 1), kind: .anniversary), today: today)?.past == false)
        // A birthday counts down to the next one.
        #expect(countdownStatus(cd(Day(2000, 11, 27), kind: .birthday, repeats: .yearly), today: today)
            == CountdownStatus(target: Day(2026, 11, 27), days: 1, past: false))
        #expect(countdownDays(cd(Day(2026, 11, 20)), today: today) == -6)
        #expect(countdownDays(cd(Day(2026, 12, 1)), today: today) == 5)
    }

    @Test func calendarSpans() {
        #expect(calendarSpan(Day(2026, 1, 31), Day(2026, 2, 28)) == (0, 1, 0))
        #expect(calendarSpan(Day(2026, 11, 26), Day(2029, 2, 13)) == (2, 2, 18))
        #expect(calendarSpan(Day(2029, 2, 13), Day(2026, 11, 26)) == (2, 2, 18))
        #expect(calendarSpan(Day(2024, 2, 29), Day(2025, 2, 28)) == (1, 0, 0))
        #expect(calendarSpan(Day(2024, 2, 29), Day(2025, 3, 1)) == (1, 0, 1))
        #expect(calendarSpan(Day(2026, 12, 31), Day(2027, 1, 30)) == (0, 0, 30))
        #expect(calendarSpan(today, today) == (0, 0, 0))
    }

    @Test func formats() {
        let target = today + 83 // 2027-02-17
        #expect(countdownText(from: today, to: target, format: .days) == "83天")
        #expect(countdownText(from: today, to: target, format: .weeksDays) == "11周6天")
        #expect(countdownText(from: today, to: target, format: .yearsMonthsDays) == "2个月22天")
        #expect(countdownText(from: today, to: today + 21, format: .weeksDays) == "3周")
        #expect(countdownText(from: today, to: today + 5, format: .weeksDays) == "5天")
        #expect(countdownText(from: today, to: Day(2027, 11, 29), format: .yearsMonthsDays) == "1年3天")
        #expect(countdownText(from: today, to: Day(2026, 12, 26), format: .yearsMonthsDays) == "1个月")
        #expect(countdownText(from: today, to: today - 10, format: .days) == "10天")
        #expect(countdownText(from: today, to: today, format: .weeksDays) == "今天")
        #expect(countdownText(cd(Day(2025, 11, 26), kind: .anniversary), today: today, format: .yearsMonthsDays) == "1年")
    }

    @Test func ages() {
        let b = cd(Day(2000, 11, 27), kind: .birthday, repeats: .yearly)
        #expect(countdownAge(b, on: today) == 25)
        #expect(countdownAge(b, on: today + 1) == 26)
        #expect(countdownAge(b, on: Day(2000, 11, 27)) == 0)
        #expect(countdownAge(b, on: Day(2000, 11, 26)) == nil)
        let leap = cd(Day(2004, 2, 29), kind: .birthday, repeats: .yearly)
        #expect(countdownAge(leap, on: Day(2027, 2, 27)) == 22)
        #expect(countdownAge(leap, on: Day(2027, 2, 28)) == 23)
        #expect(countdownAge(leap, on: Day(2028, 2, 28)) == 23)
        #expect(countdownAge(leap, on: Day(2028, 2, 29)) == 24)
    }

    @Test func lunarAges() {
        // Born on 正月初一 2000 (02-05): a year older each 春节.
        let b = cd(Day(2000, 2, 5), kind: .birthday, lunar: true, repeats: .yearly)
        #expect(countdownAge(b, on: Day(2026, 2, 16)) == 25)
        #expect(countdownAge(b, on: Day(2026, 2, 17)) == 26)
        #expect(countdownAge(cd(Day(2000, 2, 5), kind: .birthday), on: Day(2026, 2, 16)) == 26) // by the Gregorian date
        #expect(countdownAge(b, on: Day(2000, 2, 5)) == 0)
        #expect(countdownAge(b, on: Day(2001, 1, 23)) == 0) // 腊月 of the same lunar year
        #expect(countdownAge(b, on: Day(2001, 1, 24)) == 1) // 春节 2001
    }
}

@Suite("Countdown lists")
struct CountdownListTests {
    let today = Day(2026, 11, 26)

    @Test func pinnedThenAheadThenGoneBy() {
        let cs = [
            cd(Day(2026, 12, 20), id: "far"),
            cd(Day(2026, 11, 20), id: "past6"),
            cd(Day(2026, 11, 25), id: "past1"),
            cd(Day(2026, 11, 28), id: "soon"),
            cd(Day(2027, 6, 1), id: "pinned", pinned: true),
            cd(Day(2026, 11, 26), id: "today"),
            Countdown(id: "deleted", date: Day(2026, 11, 27), deletedAt: 1),
            cd(Day(1800, 1, 1), lunar: true, repeats: .yearly, id: "unknown"),
        ]
        #expect(sortCountdowns(cs, today: today).map(\.id) == ["pinned", "today", "soon", "far", "past1", "past6", "unknown"])
    }

    @Test func todayShowsTheMarkedOnesOnTheirDay() {
        let cs = [
            cd(Day(1990, 11, 26), kind: .birthday, repeats: .yearly, id: "birthday", today: true),
            cd(Day(2026, 11, 26), id: "unmarked"),
            cd(Day(2026, 11, 27), id: "tomorrow", today: true),
            cd(Day(2026, 10, 26), repeats: .monthly, id: "monthly", today: true),
        ]
        #expect(todayCountdowns(cs, today: today).map(\.id) == ["birthday", "monthly"])
    }

    @Test func reminderTimes() {
        let r = [countdownReminder(daysBefore: 1, minute: 540), 540]
        let one = cd(Day(2026, 12, 1), reminders: r)
        #expect(countdownReminderTimes(one, now: LocalDateTime(2026, 11, 29, 8, 0))
            == [LocalDateTime(2026, 11, 30, 9, 0), LocalDateTime(2026, 12, 1, 9, 0)])
        #expect(countdownReminderTimes(one, now: LocalDateTime(2026, 11, 30, 10, 0)) == [LocalDateTime(2026, 12, 1, 9, 0)])
        #expect(countdownReminderTimes(one, now: LocalDateTime(2026, 12, 1, 10, 0)).isEmpty)
        // A yearly one moves on to next year's.
        let yearly = cd(Day(2025, 12, 1), repeats: .yearly, reminders: r)
        #expect(countdownReminderTimes(yearly, now: LocalDateTime(2026, 12, 1, 10, 0))
            == [LocalDateTime(2027, 11, 30, 9, 0), LocalDateTime(2027, 12, 1, 9, 0)])
        #expect(countdownReminderTimes(cd(Day(2026, 12, 1)), now: LocalDateTime(2026, 11, 1, 0, 0)).isEmpty)
    }
}
