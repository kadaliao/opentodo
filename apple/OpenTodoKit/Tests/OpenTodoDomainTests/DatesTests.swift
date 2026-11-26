// Ported from app/test/dates_test.dart, case for case.

import Testing
@testable import OpenTodoDomain

// Sunday.
private let today = Day(2026, 11, 15)

private func d(_ key: String) -> Day { Day(key)! }

@Suite("dates")
struct DatesTests {
    @Test("dateLabel") func dateLabels() {
        #expect(dateLabel(today, today: today) == "今天")
        #expect(dateLabel(Day(2026, 11, 16), today: today) == "明天")
        #expect(dateLabel(Day(2026, 11, 17), today: today) == "后天")
        #expect(dateLabel(Day(2026, 11, 14), today: today) == "昨天")
        // Monday-start weeks: from a Sunday, Wednesday is next week.
        #expect(dateLabel(Day(2026, 11, 18), today: today) == "下周三")
        #expect(dateLabel(Day(2026, 11, 25), today: today) == "11月25日")
        #expect(dateLabel(Day(2027, 1, 3), today: today) == "2027年1月3日")

        let wednesday = Day(2026, 11, 11)
        #expect(dateLabel(Day(2026, 11, 14), today: wednesday) == "周六")
        #expect(dateLabel(Day(2026, 11, 19), today: wednesday) == "下周四")
    }

    @Test("timeLabel") func timeLabels() {
        #expect(timeLabel(0) == "上午12:00")
        #expect(timeLabel(9 * 60) == "上午9:00")
        #expect(timeLabel(12 * 60 + 30) == "下午12:30")
        #expect(timeLabel(15 * 60 + 5) == "下午3:05")
    }

    @Test("dueLabel shows the time for today only") func dueLabelToday() {
        #expect(dueLabel(d("2026-11-15"), 9 * 60, today: today) == "上午9:00")
        #expect(dueLabel(d("2026-11-15"), nil, today: today) == "今天")
        #expect(dueLabel(d("2026-11-16"), 9 * 60, today: today) == "明天")
        #expect(fullDueLabel(d("2026-11-16"), 15 * 60, today: today) == "明天, 下午3:00")
    }

    @Test("daySectionTitle") func daySectionTitles() {
        #expect(daySectionTitle(today, today: today) == "今天, 周日")
        #expect(daySectionTitle(Day(2026, 11, 18), today: today) == "11月18日, 周三")
    }

    @Test("daysBetween across the end of DST") func daysBetweenDST() {
        #expect(Day(2026, 3, 28).days(to: Day(2026, 3, 30)) == 2)
        #expect(Day(2026, 11, 1).days(to: Day(2026, 10, 31)) == -1)
    }

    @Suite("spans")
    struct Spans {
        @Test("end, last day and days covered") func endLastDayDays() {
            // 上午11:30-下午12:30.
            #expect(spanEnd(d("2026-11-15"), 690, 60) == LocalDateTime(2026, 11, 15, 12, 30))
            #expect(spanLastDay(d("2026-11-15"), 690, 60) == today)
            #expect(spanDays(d("2026-11-15"), 690, 60) == 1)
            // 22:00 to 01:00 runs into Monday; to midnight it doesn't.
            #expect(spanLastDay(d("2026-11-15"), 22 * 60, 180) == Day(2026, 11, 16))
            #expect(spanLastDay(d("2026-11-15"), 22 * 60, 120) == today)
            // All day, Sunday to Tuesday.
            #expect(spanEnd(d("2026-11-15"), nil, 3 * 1440) == LocalDateTime(2026, 11, 18))
            #expect(spanLastDay(d("2026-11-15"), nil, 3 * 1440) == Day(2026, 11, 17))
            #expect(spanDays(d("2026-11-15"), nil, 3 * 1440) == 3)
            // No span.
            #expect(spanEnd(d("2026-11-15"), 690, nil) == nil)
            #expect(spanLastDay(d("2026-11-15"), nil, nil) == today)
            #expect(spanDays(d("2026-11-15"), nil, nil) == 1)
        }

        @Test("normalized for the kind of task") func normalized() {
            #expect(normalizeDuration(600, 45) == 45)
            #expect(normalizeDuration(600, 0) == nil)
            #expect(normalizeDuration(600, -30) == nil)
            #expect(normalizeDuration(600, nil) == nil)
            // All day: whole days, and one day is no span.
            #expect(normalizeDuration(nil, 1440) == nil)
            #expect(normalizeDuration(nil, 2880) == 2880)
            #expect(normalizeDuration(nil, 1500) == 2880)
        }

        @Test("moving between timed and all day") func timeChange() {
            // 10:00 for three hours, then all day: one day, no span.
            #expect(durationForTimeChange(d("2026-11-15"), 600, nil, 180) == nil)
            // Overnight into Monday: Sunday and Monday.
            #expect(durationForTimeChange(d("2026-11-15"), 22 * 60, nil, 180) == 2880)
            // All day to timed: starts over.
            #expect(durationForTimeChange(d("2026-11-15"), nil, 600, 2880) == nil)
            // Same kind keeps it.
            #expect(durationForTimeChange(d("2026-11-15"), 600, 720, 90) == 90)
            #expect(durationForTimeChange(d("2026-11-15"), nil, nil, 2880) == 2880)
        }

        @Test("labels") func labels() {
            #expect(timeRangeLabel(9 * 60, 11 * 60) == "上午9:00-11:00")
            #expect(timeRangeLabel(690, 750) == "上午11:30-下午12:30")
            #expect(timeRangeLabel(15 * 60, 17 * 60 + 30) == "下午3:00-5:30")

            // Task rows: the times today, the dates across days.
            #expect(dueLabel(d("2026-11-15"), 690, today: today, duration: 60) == "上午11:30-下午12:30")
            #expect(dueLabel(d("2026-11-16"), 690, today: today, duration: 60) == "明天")
            #expect(dueLabel(d("2026-11-15"), nil, today: today, duration: 3 * 1440) == "今天-后天")
            #expect(dueLabel(d("2026-11-14"), nil, today: today, duration: 2 * 1440) == "昨天-今天")

            // The detail view.
            #expect(fullDueLabel(d("2026-11-16"), 15 * 60, today: today, duration: 120) == "明天, 下午3:00-5:00")
            #expect(fullDueLabel(d("2026-11-15"), nil, today: today, duration: 3 * 1440) == "今天 - 后天")
            #expect(fullDueLabel(d("2026-11-15"), 22 * 60, today: today, duration: 180)
                == "今天 下午10:00 - 明天 上午1:00")
        }
    }
}
