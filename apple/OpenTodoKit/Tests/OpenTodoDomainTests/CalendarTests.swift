// Ported from app/test/calendar_test.dart, case for case, plus the pure
// logic of app/test/calendar_selection_test.dart (the rest of that file
// drives the UI and belongs to the calendar screens).

import Synchronization
import Testing
@testable import OpenTodoDomain

private let createdSeq = Mutex(0)

/// Like `task` in calendar_test.dart: the title doubles as the id, and each
/// one is created after the one before (newer first among equals).
func calendarTask(
    _ title: String,
    due: String? = nil,
    time: Int? = nil,
    duration: Int? = nil,
    listId: String = inboxListId,
    status: TaskStatus = .open,
    repeat: String? = nil,
    repeatFrom: RepeatFrom = .dueDate,
    trashedAt: Int? = nil,
    priority: Priority = .none
) -> TodoTask {
    let created = createdSeq.withLock { seq in
        seq += 1
        return 1000 + seq
    }
    return TodoTask(
        id: title, listId: listId, title: title, priority: priority,
        dueDate: due.map { Day($0)! }, dueTime: time, duration: duration,
        status: status, completedAt: status == .open ? nil : created,
        repeatRule: `repeat`, repeatFrom: repeatFrom, trashedAt: trashedAt,
        createdAt: created, updatedAt: created
    )
}

/// `title@YYYY-MM-DD`, with `*` for a projected date.
private func keys(_ entries: [CalendarEntry]) -> [String] { entries.map(\.description) }

private let sunday = Day(2026, 11, 15)

@Suite("calendar")
struct CalendarTests {
    // MARK: ranges

    @Test("ranges: a month grid is whole weeks, Monday first") func monthGrids() {
        // 1 Nov 2026 is a Sunday, 30 Nov a Monday: six rows.
        let r = monthGrid(2026, 11)
        #expect(r.description == "2026-10-26..2026-12-07")
        #expect(r.length == 42)
        // February 2027 starts on a Monday and ends on a Sunday: four rows.
        #expect(monthGrid(2027, 2).length == 28)
    }

    @Test("ranges: each mode covers its days around the anchor") func modeRanges() {
        #expect(visibleRange(.day, sunday).description == "2026-11-15..2026-11-16")
        #expect(visibleRange(.threeDays, sunday).description == "2026-11-15..2026-11-18")
        #expect(visibleRange(.week, sunday).description == "2026-11-09..2026-11-16")
        #expect(visibleRange(.agenda, sunday).description == "2026-11-01..2026-12-01")
        #expect(visibleRange(.month, sunday) == monthGrid(2026, 11))
    }

    @Test("ranges: pages move by the mode, months keeping the day where they can") func pages() {
        #expect(shiftAnchor(.day, sunday, -1) == Day(2026, 11, 14))
        #expect(shiftAnchor(.threeDays, sunday, 1) == Day(2026, 11, 18))
        #expect(shiftAnchor(.week, sunday, 2) == Day(2026, 11, 29))
        #expect(shiftAnchor(.month, Day(2027, 1, 31), 1) == Day(2027, 2, 28))
        #expect(shiftAnchor(.agenda, Day(2026, 12, 15), 1) == Day(2027, 1, 15))
    }

    @Test("ranges: titles name the month, or both months a week runs across") func titles() {
        #expect(calendarTitle(.month, sunday) == "2026年11月")
        #expect(calendarTitle(.week, sunday) == "2026年11月")
        #expect(calendarTitle(.week, Day(2026, 12, 1)) == "2026年11月–12月")
        #expect(calendarTitle(.threeDays, Day(2026, 12, 31)) == "2026年12月–2027年1月")
    }

    @Test("modes by name, as stored") func modeNames() {
        #expect(CalendarMode.byName("threeDays") == .threeDays)
        #expect(CalendarMode.byName("decade") == nil)
        #expect(CalendarMode.byName(nil) == nil)
        #expect(CalendarMode.allCases.map(\.label) == ["日", "3天", "周", "月", "日程", "年", "多周"])
    }

    // MARK: entries

    private let week = visibleRange(.week, sunday) // 9–15 Nov

    @Test("entries: dated tasks in the range, in day and time order") func datedTasks() {
        let entries = calendarEntries([
            calendarTask("下周", due: "2026-11-16"),
            calendarTask("下午", due: "2026-11-10", time: 15 * 60),
            calendarTask("全天", due: "2026-11-10"),
            calendarTask("上午", due: "2026-11-10", time: 9 * 60),
            calendarTask("没日期"),
            calendarTask("上周", due: "2026-11-08"),
        ], week, today: sunday)
        #expect(keys(entries) == ["全天@2026-11-10", "上午@2026-11-10", "下午@2026-11-10"])
    }

    @Test("entries: finished tasks come after open ones and can be hidden; trashed never show") func finished() {
        let tasks = [
            calendarTask("完成了", due: "2026-11-12", status: .done),
            calendarTask("没完成", due: "2026-11-12", time: 20 * 60),
            calendarTask("删了", due: "2026-11-12", trashedAt: 1),
        ]
        #expect(keys(calendarEntries(tasks, week, today: sunday)) == ["没完成@2026-11-12", "完成了@2026-11-12"])
        #expect(keys(calendarEntries(tasks, week, today: sunday, filter: CalendarFilter(showCompleted: false)))
            == ["没完成@2026-11-12"])
    }

    @Test("entries: hidden lists are left off") func hiddenLists() {
        let tasks = [
            calendarTask("收集箱的", due: "2026-11-12"),
            calendarTask("工作的", due: "2026-11-12", listId: "work"),
        ]
        #expect(keys(calendarEntries(tasks, week, today: sunday, filter: CalendarFilter(hiddenLists: [inboxListId])))
            == ["工作的@2026-11-12"])
    }

    @Test("entries: a repeating task shows on its later dates too, marked as projected") func projected() {
        let friday = Day(2026, 11, 13)
        let tasks = [calendarTask("晨跑", due: "2026-11-13", time: 7 * 60, repeat: "FREQ=DAILY")]
        #expect(keys(calendarEntries(tasks, week, today: friday)) == [
            "晨跑@2026-11-13",
            "晨跑@2026-11-14*",
            "晨跑@2026-11-15*",
        ])
        // Only the next one, when the person turns that off.
        #expect(keys(calendarEntries(tasks, week, today: friday, filter: CalendarFilter(showRepeats: false)))
            == ["晨跑@2026-11-13"])
        // A page further on shows only projected dates.
        let later = visibleRange(.week, Day(2026, 12, 1))
        let ahead = calendarEntries(tasks, later, today: friday)
        let allProjected = ahead.allSatisfy(\.projected)
        #expect(allProjected)
        #expect(ahead.count == 7)
    }

    @Test("entries: an overdue repeating task projects only dates after today") func overdueRepeating() {
        // Finishing it today moves it to the 16th, not the 13th.
        let tasks = [calendarTask("晨跑", due: "2026-11-12", repeat: "FREQ=DAILY")]
        #expect(keys(calendarEntries(tasks, week, today: sunday)) == ["晨跑@2026-11-12"])
        let next = visibleRange(.week, Day(2026, 11, 16))
        #expect(calendarEntries(tasks, next, today: sunday).first?.description == "晨跑@2026-11-16*")

        // Counted from completion, the series starts again from today.
        let relative = calendarTask("浇花", due: "2026-11-12", repeat: "FREQ=DAILY;INTERVAL=3", repeatFrom: .completion)
        #expect(keys(calendarEntries([relative], next, today: sunday)) == ["浇花@2026-11-18*", "浇花@2026-11-21*"])
    }

    @Test("entries: projections stop where the series ends") func projectionsEnd() {
        let month = visibleRange(.month, sunday)
        // COUNT=3 includes the current date: two more.
        #expect(keys(calendarEntries(
            [calendarTask("三次", due: "2026-11-02", repeat: "FREQ=WEEKLY;COUNT=3")], month, today: Day(2026, 11, 2)
        )) == ["三次@2026-11-02", "三次@2026-11-09*", "三次@2026-11-16*"])
        // Overdue, the dates passed over use the count up too: only the last is left.
        #expect(keys(calendarEntries(
            [calendarTask("三次", due: "2026-11-02", repeat: "FREQ=WEEKLY;COUNT=3")], month, today: sunday
        )) == ["三次@2026-11-02", "三次@2026-11-16*"])
        #expect(keys(calendarEntries(
            [calendarTask("到月中", due: "2026-11-10", repeat: "FREQ=DAILY;UNTIL=20261112")], month, today: Day(2026, 11, 10)
        )) == ["到月中@2026-11-10", "到月中@2026-11-11*", "到月中@2026-11-12*"])
    }

    @Test("entries: a finished repeating task projects nothing; its earlier dates are not shown") func finishedRepeating() {
        let month = visibleRange(.month, sunday)
        #expect(keys(calendarEntries(
            [calendarTask("结束了", due: "2026-11-10", status: .done, repeat: "FREQ=DAILY")], month, today: sunday
        )) == ["结束了@2026-11-10"])
        // A task due after the range has nothing in it.
        #expect(calendarEntries([calendarTask("以后", due: "2027-01-05", repeat: "FREQ=DAILY")], month, today: sunday).isEmpty)
    }

    @Test("entries: grouped by day") func groupedByDay() {
        let byDay = entriesByDay(calendarEntries([
            calendarTask("a", due: "2026-11-10"),
            calendarTask("b", due: "2026-11-10"),
            calendarTask("c", due: "2026-11-12"),
        ], week, today: sunday))
        #expect(byDay.keys.sorted() == [Day(2026, 11, 10), Day(2026, 11, 12)])
        #expect(byDay[Day(2026, 11, 10)]?.count == 2)
        // Newer first among equals, as the entries came.
        #expect(byDay[Day(2026, 11, 10)]?.map(\.task.id) == ["b", "a"])
    }

    // MARK: timed layout

    private func layout(_ tasks: [TodoTask]) -> [String] {
        layoutTimed(calendarEntries(tasks, DayRange(sunday, sunday + 1), today: sunday)).map(\.description)
    }

    @Test("timed layout: tasks that do not overlap get the full width") func noOverlap() {
        #expect(layout([
            calendarTask("a", due: "2026-11-15", time: 9 * 60),
            calendarTask("b", due: "2026-11-15", time: 9 * 60 + 30),
            calendarTask("全天", due: "2026-11-15"),
        ]) == ["a 540-570 0/1", "b 570-600 0/1"])
    }

    @Test("timed layout: overlapping tasks share the width, reusing free slots") func overlap() {
        #expect(layout([
            calendarTask("a", due: "2026-11-15", time: 9 * 60),
            calendarTask("b", due: "2026-11-15", time: 9 * 60 + 10),
            calendarTask("c", due: "2026-11-15", time: 9 * 60 + 20),
            calendarTask("d", due: "2026-11-15", time: 9 * 60 + 35),
            calendarTask("e", due: "2026-11-15", time: 11 * 60),
        ]) == [
            "a 540-570 0/3",
            "b 550-580 1/3",
            "c 560-590 2/3",
            "d 575-605 0/3", // a's slot is free again
            "e 660-690 0/1",
        ])
    }

    @Test("timed layout: a task late at night is cut at midnight") func lateAtNight() {
        #expect(layout([calendarTask("a", due: "2026-11-15", time: 23 * 60 + 50)]) == ["a 1430-1440 0/1"])
    }

    @Test("timed layout: minutes snap down to the step and stay in the day") func snapping() {
        #expect(snapMinutes(9 * 60 + 14.9) == 9 * 60)
        #expect(snapMinutes(9 * 60 + 15) == 9 * 60 + 15)
        #expect(snapMinutes(-20) == 0)
        #expect(snapMinutes(24 * 60 + 5) == 24 * 60 - 15)
        #expect(snapMinutes(10 * 60 + 45, step: 30) == 10 * 60 + 30)
        #expect(clockLabel(9 * 60 + 5) == "09:05")
    }

    // MARK: spans

    @Test("spans: a span is on every day it covers in the range") func spanDaysCovered() {
        #expect(keys(calendarEntries([calendarTask("出差", due: "2026-11-08", duration: 3 * 1440)], week, today: sunday))
            == ["出差@2026-11-09+1", "出差@2026-11-10+2"])
        let overnight = calendarEntries(
            [calendarTask("夜班", due: "2026-11-10", time: 22 * 60, duration: 10 * 60)], week, today: sunday
        )
        #expect(keys(overnight) == ["夜班@2026-11-10", "夜班@2026-11-11+1"])
        #expect(overnight.map { "\($0.time!)-\($0.endTime!)" } == ["1320-1440", "0-480"])
    }

    @Test("spans: a repeating span shows its later occurrences, overlapping the range too") func repeatingSpan() {
        // Every Saturday for two days, seen in the next week.
        let next = visibleRange(.week, sunday + 7) // Mon 16 - Sun 22
        #expect(keys(calendarEntries(
            [calendarTask("周末班", due: "2026-11-14", duration: 2 * 1440, repeat: "FREQ=WEEKLY")], next, today: sunday
        )) == ["周末班@2026-11-21*", "周末班@2026-11-22+1*"])
        // From Sunday's own page: the real one ends today.
        #expect(keys(calendarEntries(
            [calendarTask("周末班", due: "2026-11-14", duration: 2 * 1440, repeat: "FREQ=WEEKLY")], week, today: sunday
        )) == ["周末班@2026-11-14", "周末班@2026-11-15+1"])
    }

    @Test("spans: timed layout uses the real length") func spanLayout() {
        let day = DayRange(sunday, sunday + 1)
        #expect(layoutTimed(calendarEntries([
            calendarTask("长会", due: "2026-11-15", time: 9 * 60, duration: 120),
            calendarTask("短", due: "2026-11-15", time: 10 * 60),
            calendarTask("五分钟", due: "2026-11-15", time: 12 * 60, duration: 5),
            calendarTask("之后", due: "2026-11-15", time: 12 * 60 + 10),
        ], day, today: sunday)).map(\.description) == [
            "长会 540-660 0/2",
            "短 600-630 1/2",
            // Drawn no smaller than half an hour, so 之后 goes beside it.
            "五分钟 720-725 0/2",
            "之后 730-760 1/2",
        ])
    }

    @Test("spans: dropping moves the whole span") func dropSpan() throws {
        func entryOn(_ t: TodoTask, _ day: String) throws -> CalendarEntry {
            try #require(calendarEntries([t], DayRange(Day(2026, 11, 1), Day(2026, 12, 1)), today: sunday)
                .first { $0.date.key == day })
        }

        let trip = calendarTask("出差", due: "2026-11-16", duration: 3 * 1440) // Mon-Wed
        let tripTuesday = try entryOn(trip, "2026-11-17")
        // Its Tuesday dropped on Friday: Thursday to Saturday.
        #expect(dropTarget(tripTuesday, Day(2026, 11, 20)).description == "2026-11-19")
        #expect(dropTarget(tripTuesday, Day(2026, 11, 20), allDay: true).description == "2026-11-19")
        // Onto the hour grid: starts where dropped.
        #expect(dropTarget(tripTuesday, Day(2026, 11, 20), minute: 600).description == "2026-11-20 10:00")

        let night = calendarTask("夜班", due: "2026-11-16", time: 22 * 60, duration: 10 * 60)
        let nightMonday = try entryOn(night, "2026-11-16"), nightTuesday = try entryOn(night, "2026-11-17")
        // Its Tuesday part (0:00-8:00) dropped at Wednesday 2:00: two hours
        // later and a day on.
        #expect(dropTarget(nightTuesday, Day(2026, 11, 18), minute: 120).description == "2026-11-18 00:00")
        // The first part dropped at 21:30 the same day.
        #expect(dropTarget(nightMonday, Day(2026, 11, 16), minute: 21 * 60 + 30).description == "2026-11-16 21:30")
        // A month cell keeps the time.
        #expect(dropTarget(nightTuesday, Day(2026, 11, 20)).description == "2026-11-19 22:00")
    }

    // MARK: dragging several

    private func entryOf(_ t: TodoTask) -> CalendarEntry { CalendarEntry(t, t.dueDate!) }
    private func moves(_ m: [CalendarMove]) -> [String] { m.map(\.description) }

    private static func fixtures() -> (meeting: TodoTask, review: TodoTask, rent: TodoTask, late: TodoTask) {
        (
            calendarTask("晨会", due: "2026-11-16", time: 9 * 60),
            calendarTask("评审", due: "2026-11-17", time: 14 * 60, duration: 60),
            calendarTask("交房租", due: "2026-11-18"),
            calendarTask("上线", due: "2026-11-16", time: 23 * 60)
        )
    }

    @Test("dragging several: on a month cell everyone moves as many days and keeps its time") func dragMonthCell() {
        let f = Self.fixtures()
        #expect(moves(dropTargets(entryOf(f.meeting), [f.review, f.rent], Day(2026, 11, 19))) == [
            "晨会 2026-11-19 09:00",
            "评审 2026-11-20 14:00",
            "交房租 2026-11-21",
        ])
        // Back a week, led by the all-day one.
        #expect(moves(dropTargets(entryOf(f.rent), [f.meeting], Day(2026, 11, 11))) == [
            "交房租 2026-11-11",
            "晨会 2026-11-09 09:00",
        ])
    }

    @Test("dragging several: into the all-day row, a timed lead takes them all out of their hours") func dragAllDayRow() {
        let f = Self.fixtures()
        #expect(moves(dropTargets(entryOf(f.meeting), [f.review, f.rent], Day(2026, 11, 17), allDay: true)) == [
            "晨会 2026-11-17",
            "评审 2026-11-18",
            "交房租 2026-11-19",
        ])
        // An all-day lead moving to another day leaves the timed ones timed.
        #expect(moves(dropTargets(entryOf(f.rent), [f.meeting], Day(2026, 11, 19), allDay: true)) == [
            "交房租 2026-11-19",
            "晨会 2026-11-17 09:00",
        ])
    }

    @Test("dragging several: onto the hour grid, timed ones move by as many minutes") func dragHourGrid() {
        let f = Self.fixtures()
        // 晨会 two hours later the next day: 评审 too, 交房租 a day on.
        #expect(moves(dropTargets(entryOf(f.meeting), [f.review, f.rent, f.late], Day(2026, 11, 17), minute: 11 * 60)) == [
            "晨会 2026-11-17 11:00",
            "评审 2026-11-18 16:00",
            "交房租 2026-11-19",
            // Two hours after 23:00 is the day after.
            "上线 2026-11-18 01:00",
        ])
        // Earlier the same day.
        #expect(moves(dropTargets(entryOf(f.meeting), [f.late], Day(2026, 11, 16), minute: 7 * 60)) == [
            "晨会 2026-11-16 07:00",
            "上线 2026-11-16 21:00",
        ])
    }

    @Test("dragging several: onto the hour grid, an all-day lead gives the all-day ones its hour") func dragAllDayLead() {
        let f = Self.fixtures()
        let shop = calendarTask("买菜", due: "2026-11-20")
        #expect(moves(dropTargets(entryOf(f.rent), [shop, f.meeting], Day(2026, 11, 19), minute: 10 * 60)) == [
            "交房租 2026-11-19 10:00",
            "买菜 2026-11-21 10:00",
            "晨会 2026-11-17 09:00",
        ])
    }

    @Test("dragging several: finished, trashed and undated ones stay; the lead is not counted twice") func dragSkips() {
        let f = Self.fixtures()
        let done = calendarTask("已完成", due: "2026-11-16", status: .done)
        let trashed = calendarTask("已删除", due: "2026-11-16", trashedAt: 1)
        let undated = calendarTask("无日期")
        #expect(moves(dropTargets(entryOf(f.meeting), [f.meeting, done, trashed, undated], Day(2026, 11, 18)))
            == ["晨会 2026-11-18 09:00"])
    }

    @Test("dragging several: a span dragged by a later day moves the others by as much as its start") func dragSpan() {
        let f = Self.fixtures()
        let trip = calendarTask("出差", due: "2026-11-16", duration: 3 * 1440) // Mon-Wed
        let tuesday = CalendarEntry(trip, Day(2026, 11, 17), occurrence: Day(2026, 11, 16))
        // Tuesday dropped on Friday: the trip starts Thursday, three days on.
        #expect(moves(dropTargets(tuesday, [f.rent], Day(2026, 11, 20))) == ["出差 2026-11-19", "交房租 2026-11-21"])
    }

    @Test("dragging several: the order for Shift-click, each task once, no later dates of repeats") func shiftOrder() {
        let rent = Self.fixtures().rent
        let daily = calendarTask("打卡", due: "2026-11-16", repeat: "FREQ=DAILY")
        let trip = calendarTask("出差", due: "2026-11-16", duration: 2 * 1440)
        let entries = calendarEntries(
            [daily, trip, rent], DayRange(Day(2026, 11, 16), Day(2026, 11, 23)), today: Day(2026, 11, 15)
        )
        #expect(entryOrder(entries) == ["出差", "打卡", "交房租"])
    }

    // MARK: -

    @Test("the agenda starts today in this month, else on the first") func agenda() {
        let november = DayRange(Day(2026, 11, 1), Day(2026, 12, 1))
        #expect(agendaFrom(november, Day(2026, 11, 15)) == Day(2026, 11, 15))
        #expect(agendaFrom(november, Day(2026, 10, 30)) == Day(2026, 11, 1))
    }

    @Test("what a day says beside its number") func dayNotes() {
        #expect(dayNote(Day(2026, 2, 17)) == DayNote(label: "春节", special: true, off: true))
        #expect(dayNote(Day(2026, 2, 28)) == DayNote(label: "十二", special: false, off: false)) // worked
        #expect(dayNote(Day(2026, 10, 1)) == DayNote(label: "国庆节", special: true, off: true))
        #expect(dayNote(Day(2026, 11, 9)) == DayNote(label: "十月", special: false, off: nil))
        #expect(dayNote(sunday) == DayNote(label: "初七", special: false, off: nil))
    }
}

// From app/test/calendar_selection_test.dart: the logic behind its widget
// tests (the providers it goes through), without the screens.
@Suite("calendar selection")
struct CalendarSelectionTests {
    private let today = Day(2026, 11, 18) // a Wednesday
    private var neighbour: Day { today - 1 }

    @Test("desktop month: a drag of picked tasks to the next day moves them together, each keeping its time")
    func monthDrag() {
        let meeting = calendarTask("晨会", due: today.key, time: 9 * 60)
        let rent = calendarTask("交房租", due: today.key)
        let report = calendarTask("写周报", due: neighbour.key, time: 15 * 60)
        let all = [meeting, rent, report]
        let picked = calendarPicked(all, ids: ["晨会", "交房租"])
        #expect(picked.map(\.id) == ["晨会", "交房租"])
        let lead = calendarEntries(all, visibleRange(.month, today), today: today).first { $0.task.id == "晨会" }!
        #expect(dropTargets(lead, picked, neighbour).map(\.description) == [
            "晨会 \(neighbour.key) 09:00",
            "交房租 \(neighbour.key)",
        ])
    }

    @Test("desktop month: ⌘A picks every task on the page; Shift-click goes in the order shown") func pageOrder() {
        let all = [
            calendarTask("晨会", due: today.key, time: 9 * 60),
            calendarTask("交房租", due: today.key),
            calendarTask("写周报", due: (today + 1).key, time: 15 * 60),
            calendarTask("打卡", due: today.key, repeat: "FREQ=DAILY"),
        ]
        let range = visibleRange(.month, today)
        let entries = calendarEntries(all, range, today: today)
        // 交房租 and 打卡 all day (newer first), 晨会 9:00, then the next day.
        #expect(calendarOrder(entries, mode: .month, range: range, today: today) == ["打卡", "交房租", "晨会", "写周报"])
    }

    @Test("the agenda's order leaves out the days before today") func agendaOrder() {
        let all = [
            calendarTask("过去的", due: "2026-11-02"),
            calendarTask("今天的", due: today.key),
            calendarTask("以后的", due: "2026-11-30"),
        ]
        let range = visibleRange(.agenda, today)
        let entries = calendarEntries(all, range, today: today)
        #expect(calendarOrder(entries, mode: .agenda, range: range, today: today) == ["今天的", "以后的"])
        #expect(calendarOrder(entries, mode: .month, range: range, today: today) == ["过去的", "今天的", "以后的"])
    }

    @Test("desktop week: picked tasks move by the same minutes; an all-day one only by days") func weekDrag() {
        let meeting = calendarTask("晨会", due: today.key, time: 9 * 60)
        let review = calendarTask("评审", due: today.key, time: 14 * 60, duration: 60)
        let rent = calendarTask("交房租", due: today.key)
        let lead = CalendarEntry(meeting, today)
        #expect(dropTargets(lead, [review, rent], today, minute: 11 * 60).map(\.description) == [
            "晨会 \(today.key) 11:00",
            "评审 \(today.key) 16:00",
            "交房租 \(today.key)",
        ])
        // Into the all-day row, led by a timed one: none keep a time.
        let intoAllDay = dropTargets(CalendarEntry(review, today), [meeting, rent], today, allDay: true)
        #expect(intoAllDay.map(\.time) == [nil, nil, nil])
    }

    @Test("only open, dated, untrashed picks are taken along") func pickedFilter() {
        let all = [
            calendarTask("取快递", due: today.key),
            calendarTask("做完了", due: today.key, status: .done),
            calendarTask("删了", due: today.key, trashedAt: 1),
            calendarTask("没日期"),
        ]
        #expect(calendarPicked(all, ids: ["取快递", "做完了", "删了", "没日期"]).map(\.id) == ["取快递"])
        #expect(calendarPicked(all, ids: []).isEmpty)
    }
}
