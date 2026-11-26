// The calendar additions of the Swift version (CalendarExtras.swift and the
// year / multi-week modes): no Flutter test to port.

import Foundation
import Testing
@testable import OpenTodoDomain

private let sunday = Day(2026, 11, 15)

@Suite("calendar extras")
struct CalendarExtrasTests {
    // MARK: year and multi-week

    @Test("the year view covers the year, pages by years, and is titled by it") func yearRange() {
        #expect(visibleRange(.year, sunday).description == "2026-01-01..2027-01-01")
        #expect(visibleRange(.year, sunday).length == 365)
        #expect(shiftAnchor(.year, sunday, 1) == Day(2027, 11, 15))
        #expect(shiftAnchor(.year, Day(2028, 2, 29), -1) == Day(2027, 2, 28))
        #expect(calendarTitle(.year, sunday) == "2026年")
        #expect(!CalendarMode.year.isTimeGrid && CalendarMode.year.label == "年")
    }

    @Test("twelve small months, each in whole weeks") func smallMonths() {
        let months = yearMonths(2026)
        #expect(months.count == 12)
        #expect(months[10] == monthGrid(2026, 11))
        #expect(months.allSatisfy { $0.start.weekday == 1 && $0.length % 7 == 0 })
        // February 2027's grid is exactly four weeks.
        #expect(yearMonths(2027)[1].length == 28)
    }

    @Test("how busy each day is: distinct tasks, spans on every day, repeats ahead") func density() {
        let year = visibleRange(.year, sunday)
        let entries = calendarEntries([
            calendarTask("出差", due: "2026-11-16", duration: 3 * 1440),
            calendarTask("晨会", due: "2026-11-16", time: 9 * 60),
            calendarTask("周报", due: "2026-11-20", repeat: "FREQ=WEEKLY;COUNT=3"),
        ], year, today: sunday)
        let d = dayDensity(entries)
        #expect(d[Day(2026, 11, 16)] == 2)
        #expect(d[Day(2026, 11, 17)] == 1)
        #expect(d[Day(2026, 11, 18)] == 1)
        #expect(d[Day(2026, 11, 19)] == nil)
        #expect([Day(2026, 11, 20), Day(2026, 11, 27), Day(2026, 12, 4)].map { d[$0] } == [1, 1, 1])
        #expect(d.count == 6)
        #expect([0, 1, 2, 3, 4, 5, 6, 40].map(densityLevel) == [0, 1, 2, 2, 3, 3, 4, 4])
    }

    @Test("multi-week: 2 to 6 weeks from the anchor's week, paging by as many") func multiWeek() {
        #expect(visibleRange(.multiWeek, sunday).description == "2026-11-09..2026-12-07") // 4 by default
        #expect(visibleRange(.multiWeek, sunday, weeks: 2).description == "2026-11-09..2026-11-23")
        #expect(visibleRange(.multiWeek, sunday, weeks: 6).length == 42)
        // Out of range is clamped.
        #expect(visibleRange(.multiWeek, sunday, weeks: 1).length == 14)
        #expect(visibleRange(.multiWeek, sunday, weeks: 9).length == 42)
        #expect(shiftAnchor(.multiWeek, sunday, 1, weeks: 3) == sunday + 21)
        #expect(shiftAnchor(.multiWeek, sunday, -1) == sunday - 28)
        #expect(calendarTitle(.multiWeek, sunday) == "2026年11月–12月")
        #expect(calendarTitle(.multiWeek, sunday, weeks: 2) == "2026年11月")
        #expect(calendarTitle(.multiWeek, Day(2026, 12, 20)) == "2026年12月–2027年1月")
        #expect(weekRows(visibleRange(.multiWeek, sunday, weeks: 3)).map(\.description)
            == ["2026-11-09..2026-11-16", "2026-11-16..2026-11-23", "2026-11-23..2026-11-30"])
    }

    @Test("the new modes and the weeks are kept in the prefs; the Flutter version opens the month instead")
    func prefs() throws {
        let p = CalendarPrefs(mode: .multiWeek, weeks: 3)
        let back = try JSONDecoder().decode(CalendarPrefs.self, from: JSONEncoder().encode(p))
        #expect(back.mode == .multiWeek && back.weeks == 3)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        #expect(json["mode"] as? String == "multiWeek") // CalendarMode.byName: null in Dart, so 月
        // Written by the Flutter version: no weeks.
        #expect(try JSONDecoder().decode(CalendarPrefs.self, from: Data(#"{"mode":"month"}"#.utf8)).weeks == 4)
        #expect(try JSONDecoder().decode(CalendarPrefs.self, from: Data(#"{"weeks":12}"#.utf8)).weeks == 6)
        #expect(CalendarPrefs(weeks: 0).weeks == 2)
    }

    // MARK: bars

    private func layout(_ tasks: [TodoTask], week: DayRange, today: Day = sunday) -> [String] {
        weekLayout(calendarEntries(tasks, week, today: today), week: week).map(\.description)
    }

    private let nextWeek = visibleRange(.week, sunday + 1) // Mon 16 - Sun 22

    @Test("a task over several days is one bar; single days go below it") func bars() {
        #expect(layout([
            calendarTask("晨会", due: "2026-11-17", time: 9 * 60),
            calendarTask("出差", due: "2026-11-16", duration: 3 * 1440), // Mon-Wed
            calendarTask("交房租", due: "2026-11-20"),
        ], week: nextWeek) == [
            "出差 0+3 @0",
            "晨会 1+1 @1",
            "交房租 4+1 @0", // Friday is free on the top line
        ])
    }

    @Test("bars stack: earlier start first, then the longer, each on the first free line") func stacking() {
        #expect(layout([
            calendarTask("短", due: "2026-11-17", duration: 2 * 1440), // Tue-Wed
            calendarTask("长", due: "2026-11-17", duration: 4 * 1440), // Tue-Fri
            calendarTask("早", due: "2026-11-16", duration: 2 * 1440), // Mon-Tue
            calendarTask("周末", due: "2026-11-21", duration: 2 * 1440), // Sat-Sun
        ], week: nextWeek) == [
            "早 0+2 @0",
            "长 1+4 @1",
            "短 1+2 @2",
            "周末 5+2 @0",
        ])
    }

    @Test("a bar cut by the row's edges says so; overnight timed spans are bars too") func edges() {
        let grid = monthGrid(2026, 11)
        let rows = weekRows(grid)
        #expect(rows.count == 6)
        let trip = calendarTask("出差", due: "2026-11-14", duration: 4 * 1440) // Sat 14 - Tue 17
        let entries = calendarEntries([trip], grid, today: sunday)
        #expect(weekLayout(entries, week: rows[2]).map(\.description) == ["出差 5+2 @0 >"])
        #expect(weekLayout(entries, week: rows[3]).map(\.description) == ["出差 0+2 @0 <"])
        let last = weekLayout(entries, week: rows[3]).first!
        #expect(last.isBar && last.entry.dayIndex == 2)

        let night = calendarTask("夜班", due: "2026-11-18", time: 22 * 60, duration: 10 * 60)
        let item = weekLayout(calendarEntries([night], nextWeek, today: sunday), week: nextWeek).first!
        #expect(item.description == "夜班 2+2 @0")
        #expect(item.isBar && item.entry.time == 22 * 60)
    }

    @Test("each occurrence of a repeating span is its own bar") func repeatingBars() {
        let shift = calendarTask("值班", due: "2026-11-16", duration: 2 * 1440, repeat: "FREQ=WEEKLY;BYDAY=MO,TH")
        #expect(layout([shift], week: nextWeek, today: Day(2026, 11, 16)) == [
            "值班 0+2 @0",
            "值班 3+2 @0",
        ])
        let projected = weekLayout(calendarEntries([shift], nextWeek, today: Day(2026, 11, 16)), week: nextWeek)
        #expect(projected.map(\.entry.projected) == [false, true])
    }

    @Test("what doesn't fit in a cell is counted per day") func overflow() {
        let items = weekLayout(calendarEntries([
            calendarTask("出差", due: "2026-11-16", duration: 3 * 1440), // Mon-Wed, line 0
            calendarTask("a", due: "2026-11-17"),
            calendarTask("b", due: "2026-11-17"),
            calendarTask("c", due: "2026-11-17"),
        ], nextWeek, today: sunday), week: nextWeek)
        #expect(items.map(\.line) == [0, 1, 2, 3])
        #expect(hiddenCounts(items, lines: 2) == [0, 2, 0, 0, 0, 0, 0])
        #expect(hiddenCounts(items, lines: 0) == [1, 4, 1, 0, 0, 0, 0])
        #expect(hiddenCounts(items, lines: 9) == [0, 0, 0, 0, 0, 0, 0])
    }

    // MARK: 安排任务

    @Test("the panel lists open tasks without a date, by list if asked") func unscheduled() {
        let tasks = [
            calendarTask("读书"),
            calendarTask("有日期", due: "2026-11-16"),
            calendarTask("做完了", status: .done),
            calendarTask("删了", trashedAt: 1),
            calendarTask("写方案", listId: "work", priority: .high),
            calendarTask("整理桌面"),
        ]
        #expect(unscheduledTasks(tasks).map(\.id) == ["写方案", "整理桌面", "读书"])
        #expect(unscheduledTasks(tasks, listId: "work").map(\.id) == ["写方案"])
        #expect(unscheduledTasks(tasks, listId: inboxListId).map(\.id) == ["整理桌面", "读书"])
    }

    @Test("dropped from the panel: at the hour on a grid, else all day") func scheduling() {
        let t = calendarTask("读书")
        #expect(scheduleTarget(t, Day(2026, 11, 18), minute: 20 * 60).description == "读书 2026-11-18 20:00")
        #expect(scheduleTarget(t, Day(2026, 11, 18)).description == "读书 2026-11-18")
    }
}
