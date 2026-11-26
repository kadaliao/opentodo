// Ported from app/test/recurrence_test.dart, case for case.

import Testing
@testable import OpenTodoDomain

// 2026-11-15 is a Sunday.
private func d(_ m: Int, _ day: Int, _ y: Int = 2026) -> Day { Day(y, m, day) }
private func rule(_ s: String) -> RepeatRule { RepeatRule.tryParse(s)! }
private let today = d(11, 15)

/// The next `n` dates after `from`.
private func series(_ r: RepeatRule, _ from: Day, _ n: Int) -> [Day] {
    var out: [Day] = []
    var at = from
    for _ in 0..<n {
        guard let next = nextOccurrence(r, at) else { break }
        out.append(next)
        at = next
    }
    return out
}

@Suite("recurrence")
struct RecurrenceTests {
    // MARK: parse and format

    @Test("parse and format: round trip in a fixed order") func roundTrip() {
        for s in [
            "FREQ=DAILY",
            "FREQ=DAILY;INTERVAL=3",
            "FREQ=WEEKLY;BYDAY=MO,WE,FR",
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU",
            "FREQ=MONTHLY;BYMONTHDAY=15",
            "FREQ=MONTHLY;BYMONTHDAY=-1",
            "FREQ=MONTHLY;BYDAY=2TU",
            "FREQ=MONTHLY;BYDAY=-1FR",
            "FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=15",
            "FREQ=DAILY;UNTIL=20261231",
            "FREQ=WEEKLY;COUNT=5",
        ] {
            #expect(rule(s).description == s)
        }
    }

    @Test("parse and format: lenient about case, order, prefixes and extras") func lenient() {
        #expect(rule("RRULE:byday=we,mo;freq=weekly;INTERVAL=1;WKST=MO").description == "FREQ=WEEKLY;BYDAY=MO,WE")
        #expect(rule("FREQ=DAILY;UNTIL=20261231T235959Z").until == d(12, 31))
        #expect(rule("FREQ=DAILY;INTERVAL=0").interval == 1)
    }

    @Test("parse and format: unusable rules are null") func unusable() {
        #expect(RepeatRule.tryParse(nil) == nil)
        #expect(RepeatRule.tryParse("") == nil)
        #expect(RepeatRule.tryParse("FREQ=HOURLY") == nil)
        #expect(RepeatRule.tryParse("nonsense") == nil)
    }

    @Test("parse and format: equality is by text") func equality() {
        #expect(rule("FREQ=WEEKLY;BYDAY=WE,MO") == rule("FREQ=WEEKLY;BYDAY=MO,WE"))
        #expect(RepeatRule.workdays == rule("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"))
        #expect(Set([rule("FREQ=WEEKLY;BYDAY=WE,MO"), rule("FREQ=WEEKLY;BYDAY=MO,WE")]).count == 1)
    }

    // MARK: next occurrence

    @Test("next occurrence: daily") func daily() {
        #expect(series(.daily, d(11, 15), 2) == [d(11, 16), d(11, 17)])
        #expect(series(rule("FREQ=DAILY;INTERVAL=3"), d(11, 15), 2) == [d(11, 18), d(11, 21)])
        // Across the end of the year.
        #expect(nextOccurrence(.daily, d(12, 31)) == d(1, 1, 2027))
    }

    @Test("next occurrence: weekly keeps the task weekday unless days are given") func weekly() {
        #expect(series(.weekly, d(11, 15), 2) == [d(11, 22), d(11, 29)])
        #expect(series(rule("FREQ=WEEKLY;BYDAY=MO,WE"), d(11, 15), 3) == [d(11, 16), d(11, 18), d(11, 23)])
    }

    @Test("next occurrence: every other week stays in step") func everyOtherWeek() {
        #expect(series(rule("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE"), d(11, 16), 4)
            == [d(11, 18), d(11, 30), d(12, 2), d(12, 14)])
    }

    @Test("next occurrence: workdays skip the weekend") func workdays() {
        #expect(series(.workdays, d(11, 19), 3) == [d(11, 20), d(11, 23), d(11, 24)])
        #expect(series(.weekends, d(11, 15), 2) == [d(11, 21), d(11, 22)])
    }

    @Test("next occurrence: monthly on a day skips months without it") func monthlyOnADay() {
        #expect(series(.monthly, d(1, 31), 3) == [d(3, 31), d(5, 31), d(7, 31)])
        #expect(series(rule("FREQ=MONTHLY;BYMONTHDAY=15"), d(11, 20), 2) == [d(12, 15), d(1, 15, 2027)])
        #expect(series(rule("FREQ=MONTHLY;INTERVAL=3"), d(11, 15), 2) == [d(2, 15, 2027), d(5, 15, 2027)])
    }

    @Test("next occurrence: monthly on the last day") func monthlyLastDay() {
        #expect(series(rule("FREQ=MONTHLY;BYMONTHDAY=-1"), d(11, 30), 4)
            == [d(12, 31), d(1, 31, 2027), d(2, 28, 2027), d(3, 31, 2027)])
    }

    @Test("next occurrence: monthly on the nth weekday") func monthlyNthWeekday() {
        #expect(series(rule("FREQ=MONTHLY;BYDAY=2TU"), d(11, 10), 2) == [d(12, 8), d(1, 12, 2027)])
        #expect(series(rule("FREQ=MONTHLY;BYDAY=-1FR"), d(11, 27), 2) == [d(12, 25), d(1, 29, 2027)])
        // Months without a fifth Monday are skipped.
        #expect(series(rule("FREQ=MONTHLY;BYDAY=5MO"), d(11, 30), 2) == [d(3, 29, 2027), d(5, 31, 2027)])
    }

    @Test("next occurrence: yearly, and Feb 29 waits for a leap year") func yearly() {
        #expect(nextOccurrence(.yearly, d(11, 15)) == d(11, 15, 2027))
        #expect(nextOccurrence(.yearly, d(2, 29, 2028)) == d(2, 29, 2032))
        #expect(nextOccurrence(rule("FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=8"), d(11, 15)) == d(3, 8, 2027))
        #expect(nextOccurrence(rule("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH"), d(1, 1)) == d(11, 26))
    }

    @Test("next occurrence: until and count end the series") func untilAndCount() {
        #expect(series(rule("FREQ=DAILY;UNTIL=20261117"), d(11, 15), 5) == [d(11, 16), d(11, 17)])
        #expect(nextOccurrence(rule("FREQ=DAILY;COUNT=1"), d(11, 15)) == nil)
        #expect(nextOccurrence(rule("FREQ=DAILY;COUNT=2"), d(11, 15)) == d(11, 16))
    }

    // MARK: advancing a repeating task

    @Test("advancing: on time, the next occurrence") func advanceOnTime() throws {
        let a = try #require(advanceRepeat(.daily, today, today: today))
        #expect(a.date == d(11, 16))
        #expect(a.rule == .daily)
    }

    @Test("advancing: overdue, past occurrences are passed over") func advanceOverdue() {
        #expect(advanceRepeat(.daily, d(11, 12), today: today)?.date == d(11, 16))
        // A Monday task done on Sunday goes to the coming Monday.
        #expect(advanceRepeat(rule("FREQ=WEEKLY;BYDAY=MO"), d(11, 9), today: today)?.date == d(11, 16))
    }

    @Test("advancing: done early, the occurrence after its date") func advanceEarly() {
        #expect(advanceRepeat(.daily, d(11, 20), today: today)?.date == d(11, 21))
    }

    @Test("advancing: from completion, the rule restarts today") func advanceFromCompletion() {
        #expect(advanceRepeat(rule("FREQ=DAILY;INTERVAL=3"), d(11, 10), today: today, repeatFrom: .completion)?.date
            == d(11, 18))
    }

    @Test("advancing: count goes down, and passed-over occurrences use it up") func advanceCount() throws {
        let a = try #require(advanceRepeat(rule("FREQ=DAILY;COUNT=3"), today, today: today))
        #expect(a.date == d(11, 16))
        #expect(a.rule.count == 2)
        #expect(advanceRepeat(rule("FREQ=DAILY;COUNT=1"), today, today: today) == nil)
        // 12th, 13th and 14th were the three; nothing is left.
        #expect(advanceRepeat(rule("FREQ=DAILY;COUNT=3"), d(11, 12), today: today) == nil)
    }

    @Test("advancing: until") func advanceUntil() {
        #expect(advanceRepeat(rule("FREQ=DAILY;UNTIL=20261115"), today, today: today) == nil)
        #expect(advanceRepeat(rule("FREQ=DAILY;UNTIL=20261116"), today, today: today)?.date == d(11, 16))
    }

    // MARK: -

    @Test("occurrences after a date, as far as the series runs") func occurrences() {
        #expect(Array(occurrencesAfter(.daily, d(11, 15)).prefix(3)) == [d(11, 16), d(11, 17), d(11, 18)])
        // COUNT counts the date itself.
        #expect(Array(occurrencesAfter(rule("FREQ=WEEKLY;COUNT=3"), d(11, 15))) == [d(11, 22), d(11, 29)])
        #expect(Array(occurrencesAfter(rule("FREQ=DAILY;COUNT=1"), d(11, 15))).isEmpty)
        #expect(Array(occurrencesAfter(rule("FREQ=DAILY;UNTIL=20261117"), d(11, 15))) == [d(11, 16), d(11, 17)])
        #expect(Array(occurrencesAfter(rule("FREQ=MONTHLY;BYMONTHDAY=31"), d(10, 31)).prefix(3))
            == [d(12, 31), d(1, 31, 2027), d(3, 31, 2027)])
        // Each iteration starts over.
        let s = occurrencesAfter(rule("FREQ=WEEKLY;COUNT=3"), d(11, 15))
        #expect(Array(s) == Array(s))
    }

    @Test("first occurrence for a new task") func first() {
        #expect(firstOccurrence(.daily, today) == today)
        #expect(firstOccurrence(.weekly, today) == today)
        #expect(firstOccurrence(rule("FREQ=WEEKLY;BYDAY=MO"), d(11, 15)) == d(11, 16))
        #expect(firstOccurrence(rule("FREQ=WEEKLY;BYDAY=MO"), d(11, 16)) == d(11, 16))
        #expect(firstOccurrence(rule("FREQ=MONTHLY;BYMONTHDAY=15"), d(11, 15)) == d(11, 15))
        #expect(firstOccurrence(rule("FREQ=MONTHLY;BYMONTHDAY=15"), d(11, 16)) == d(12, 15))
        #expect(firstOccurrence(rule("FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=1"), d(11, 16)) == d(1, 1, 2027))
        #expect(firstOccurrence(.workdays, d(11, 15)) == d(11, 16))
    }

    @Test("nth weekday of a month") func nthWeekday() {
        #expect(nthWeekdayOfMonth(2026, 11, 1, 7) == d(11, 1))
        #expect(nthWeekdayOfMonth(2026, 11, 2, 2) == d(11, 10))
        #expect(nthWeekdayOfMonth(2026, 11, -1, 1) == d(11, 30))
        #expect(nthWeekdayOfMonth(2026, 11, -1, 2) == d(11, 24))
        #expect(nthWeekdayOfMonth(2026, 11, 5, 1) == d(11, 30))
        #expect(nthWeekdayOfMonth(2026, 11, 5, 2) == nil)
    }

    @Test("described in words") func words() {
        let sun = d(11, 15)
        func say(_ s: String, from: RepeatFrom = .dueDate) -> String { describeRepeat(rule(s), sun, repeatFrom: from) }
        #expect(say("FREQ=DAILY") == "每天")
        #expect(say("FREQ=DAILY;INTERVAL=3") == "每3天")
        #expect(say("FREQ=WEEKLY") == "每周日")
        #expect(say("FREQ=WEEKLY;BYDAY=MO,WE,FR") == "每周一、三、五")
        #expect(say("FREQ=WEEKLY;INTERVAL=2;BYDAY=TU") == "每2周的周二")
        #expect(say("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR") == "工作日")
        #expect(say("FREQ=WEEKLY;BYDAY=SA,SU") == "周末")
        #expect(say("FREQ=MONTHLY") == "每月15日")
        #expect(say("FREQ=MONTHLY;BYMONTHDAY=-1") == "每月最后一天")
        #expect(say("FREQ=MONTHLY;BYDAY=2TU") == "每月第2个周二")
        #expect(say("FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR") == "每2个月的最后一个周五")
        #expect(say("FREQ=YEARLY") == "每年11月15日")
        #expect(say("FREQ=YEARLY;INTERVAL=2;BYMONTH=3;BYMONTHDAY=8") == "每2年的3月8日")
        #expect(say("FREQ=DAILY;INTERVAL=3", from: .completion) == "每3天（按完成日期）")
        #expect(say("FREQ=DAILY;UNTIL=20261231") == "每天，至2026年12月31日")
        #expect(say("FREQ=DAILY;COUNT=5") == "每天，还剩5次")
    }

    // MARK: China

    private func next(_ r: RepeatRule, _ from: String, _ n: Int) -> [String] {
        occurrencesAfter(r, Day(from)!).prefix(n).map(\.key)
    }

    @Test("China: text") func chinaText() {
        for text in [
            "RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=15;SKIP=BACKWARD",
            "RSCALE=CHINESE;FREQ=MONTHLY;BYMONTHDAY=1;SKIP=BACKWARD",
            "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;X-HOLIDAYS=CN",
        ] {
            #expect(RepeatRule.tryParse(text)?.description == text)
        }
        #expect(RepeatRule.tryParse("FREQ=YEARLY;RSCALE=HEBREW;BYMONTH=5") == nil)
        #expect(RepeatRule.tryParse("RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=6L;BYMONTHDAY=1")?.month == 6)
        #expect(RepeatRule.lunarYearlyOn(Day(2026, 9, 25))?.description
            == "RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=15;SKIP=BACKWARD")
        #expect(RepeatRule.statutoryWorkdays.description == "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;X-HOLIDAYS=CN")
    }

    @Test("China: 法定工作日 skips the holidays and works the weekend days in exchange") func statutoryWorkdays() {
        let r = RepeatRule.statutoryWorkdays
        #expect(next(r, "2026-09-18", 2) == ["2026-09-20", "2026-09-21"]) // Sunday 9/20 is worked
        #expect(next(r, "2026-09-30", 4) == ["2026-10-08", "2026-10-09", "2026-10-10", "2026-10-12"])
        #expect(firstOccurrence(r, Day(2026, 10, 3)) == Day(2026, 10, 8))
        let done = advanceRepeat(r, Day(2027, 2, 4), today: Day(2027, 2, 4))
        #expect(done?.date == Day(2027, 2, 14)) // 春节 off, Sunday 2/14 worked
        #expect(describeRepeat(r, Day(2026, 11, 16)) == "法定工作日")
    }

    @Test("China: 农历每年 and 农历每月, leap months and 除夕") func lunar() throws {
        let midAutumn = try #require(RepeatRule.lunarYearlyOn(Day(2026, 9, 25)))
        #expect(next(midAutumn, "2026-09-25", 2) == ["2027-09-15", "2028-10-03"])
        #expect(describeRepeat(midAutumn, Day(2026, 9, 25)) == "农历每年八月十五")

        // 腊月三十: 除夕 even when the month has 29 days.
        let eve = RepeatRule(.yearly, monthDays: [30], month: 12, lunar: true)
        #expect(next(eve, "2026-02-16", 2) == ["2027-02-05", "2028-01-25"])
        #expect(describeRepeat(eve, Day(2026, 2, 16)) == "农历每年腊月三十")

        // Every 初一, through 2025's leap sixth month.
        let first = try #require(RepeatRule.lunarMonthlyOn(Day(2025, 6, 25)))
        #expect(next(first, "2025-06-25", 3) == ["2025-07-25", "2025-08-23", "2025-09-22"])
        #expect(describeRepeat(first, Day(2025, 6, 25)) == "农历每月初一")
        #expect(firstOccurrence(first, Day(2025, 7, 1)) == Day(2025, 7, 25))

        let every2 = RepeatRule(.yearly, interval: 2, monthDays: [1], month: 1, lunar: true)
        #expect(next(every2, "2026-02-17", 1) == ["2028-01-26"])
        #expect(describeRepeat(every2, Day(2026, 2, 17)) == "每2年的农历正月初一")
    }
}
