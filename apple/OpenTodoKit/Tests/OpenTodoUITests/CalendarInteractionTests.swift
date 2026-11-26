// The calendar screen's logic that screenshots can't show: picking with ⌘
// and Shift, the keys, where a drop lands, the in-place rule, resizing,
// what fits in a month cell. The cases follow app/test/calendar_ui_test.dart
// and calendar_selection_test.dart where those check these through the UI.

import CoreGraphics
import Foundation
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

private let today = Day(2026, 11, 18) // a Wednesday

private func task(_ id: String, due: Day? = nil, time: Int? = nil, duration: Int? = nil, created: Int = 0) -> TodoTask {
    TodoTask(id: id, title: id, dueDate: due, dueTime: time, duration: duration, createdAt: created)
}

@Suite("calendar picking")
struct CalendarPickingTests {
    // The click rules (⌘, Shift, touch) are `tapTask` / `SelectionModel`'s,
    // tested with them; here, what the calendar adds.

    @MainActor @Test("⌘A picks the page, Esc lets go; the app's selection is the one used") func selectAllAndEscape() {
        let model = CalendarModel(anchor: today)
        let shared = SelectionModel()
        model.connect(selection: shared, prefs: CalendarPrefs(mode: .week))
        #expect(model.mode == .week)
        model.perform(.selectAll, today: today, order: ["交房租", "晨会", "写周报"])
        #expect(shared.ids.count == 3)
        model.perform(.clearPicking, today: today)
        #expect(!shared.isActive)
        // Connecting again changes nothing: a mode a route set stays.
        model.prefs.mode = .day
        model.connect(selection: SelectionModel(), prefs: CalendarPrefs(mode: .month))
        #expect(model.mode == .day)
        #expect(model.selection === shared)
    }
}

@Suite("calendar keys and paging")
struct CalendarKeyTests {
    @Test("D 3 W M A Y for the modes, T for today, ← → for pages, ⌘A and Esc") func keys() {
        func cmd(_ c: Character, _ command: Bool = false) -> CalendarCommand? {
            CalendarLogic.command(for: .character(c), command: command)
        }
        #expect(cmd("d") == .mode(.day))
        #expect(cmd("D") == .mode(.day))
        #expect(cmd("3") == .mode(.threeDays))
        #expect(cmd("w") == .mode(.week))
        #expect(cmd("m") == .mode(.month))
        #expect(cmd("a") == .mode(.agenda))
        #expect(cmd("y") == .mode(.year))
        #expect(cmd("t") == .today)
        #expect(cmd("x") == nil)
        #expect(cmd("a", true) == .selectAll)
        #expect(cmd("d", true) == nil)
        #expect(CalendarLogic.command(for: .left) == .page(-1))
        #expect(CalendarLogic.command(for: .right) == .page(1))
        #expect(CalendarLogic.command(for: .left, command: true) == nil)
        #expect(CalendarLogic.command(for: .escape) == .clearPicking)
        #expect(CalendarLogic.modesOffered.compactMap(CalendarLogic.modeKey) == ["D", "3", "W", "M", "Y", "A"])
    }

    @MainActor @Test("the model turns pages by the mode, goes to today, opens a day") func paging() {
        let model = CalendarModel(anchor: Day(2027, 1, 31))
        model.perform(.page(1), today: today)
        #expect(model.anchor == Day(2027, 2, 28))
        model.perform(.mode(.week), today: today)
        model.perform(.page(-1), today: today)
        #expect(model.anchor == Day(2027, 2, 21))
        model.prefs.weeks = 3
        model.perform(.mode(.multiWeek), today: today)
        model.perform(.page(1), today: today)
        #expect(model.anchor == Day(2027, 3, 14))
        #expect(model.range.length == 21)
        model.perform(.today, today: today)
        #expect(model.anchor == today)
        model.showDay(Day(2026, 11, 20))
        #expect(model.mode == .day && model.anchor == Day(2026, 11, 20))
        #expect(model.prefs.mode == .day) // stored with the prefs
    }

    @Test("the toolbar's + puts a task on today if shown, else the anchor or the first day") func defaultNewDay() {
        let week = visibleRange(.week, Day(2026, 12, 2))
        #expect(CalendarLogic.defaultNewDay(mode: .week, range: visibleRange(.week, today), anchor: today, today: today) == today)
        #expect(CalendarLogic.defaultNewDay(mode: .week, range: week, anchor: Day(2026, 12, 2), today: today) == Day(2026, 11, 30))
        #expect(CalendarLogic.defaultNewDay(mode: .month, range: monthGrid(2027, 1), anchor: Day(2027, 1, 9), today: today) == Day(2027, 1, 9))
        // phone: + adds to the selected day (calendar_ui_test 'phone: the calendar is a tab…').
        #expect(CalendarLogic.defaultNewDay(mode: .month, range: monthGrid(2026, 11), anchor: Day(2026, 11, 25), today: today, compact: true) == Day(2026, 11, 25))
    }

    @Test("a new task's heading says when") func heading() {
        #expect(CalendarLogic.newTaskHeading(date: today, time: nil, today: today) == "今天, 周三")
        #expect(CalendarLogic.newTaskHeading(date: today + 1, time: 14 * 60, today: today) == "明天, 周四 下午2:00")
        #expect(CalendarLogic.cellDayLabel(Day(2026, 12, 1)) == "12月1日")
        #expect(CalendarLogic.cellDayLabel(Day(2026, 12, 2)) == "2")
    }
}

@Suite("calendar hour grid")
struct CalendarGridTests {
    @Test("48 points an hour; drops snap down to 15 minutes, clicks to 30") func geometry() {
        #expect(CalendarLogic.gridY(60) == 48)
        #expect(CalendarLogic.gridY(9 * 60 + 30) == 456)
        #expect(CalendarLogic.gridMinute(atY: 2 * 48 + 6) == 120)
        #expect(CalendarLogic.gridMinute(atY: 14 * 48 + 20) == 14 * 60 + 15)
        #expect(CalendarLogic.gridMinute(atY: 14 * 48 + 20, step: 30) == 14 * 60)
        #expect(CalendarLogic.gridMinute(atY: -10) == 0)
        #expect(CalendarLogic.gridMinute(atY: 25 * 48) == 24 * 60 - 15)
    }

    @Test("a dragged block lands where its top is: where it was plus how far it moved") func dropMinute() {
        // 晨会 at 9:00, grabbed 10 points down its bar, dragged two hours
        // down and a little: 11:00 (the week test of calendar_ui_test).
        let top = CalendarLogic.gridY(9 * 60)
        #expect(CalendarLogic.dropMinute(pointerY: top + 10 + 2 * 48 + 6, startPointerY: top + 10, barTop: top) == 11 * 60)
        // A nudge up would snap a quarter earlier; the in-place rule stops it.
        #expect(CalendarLogic.dropMinute(pointerY: top + 7, startPointerY: top + 10, barTop: top) == 8 * 60 + 45)
        #expect(CalendarLogic.droppedInPlace(CGPoint(x: 50, y: top + 10), CGPoint(x: 52, y: top + 7)))
        #expect(!CalendarLogic.droppedInPlace(CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 18)))
        // Dragged in from elsewhere: its top at the pointer.
        #expect(CalendarLogic.dropMinute(pointerY: 14 * 48 + 5, startPointerY: nil, barTop: nil) == 14 * 60)
    }

    @Test("the bottom edge: 15-minute steps, at least 15 minutes long, at most midnight") func resize() {
        // 评审 14:00-16:00, an hour more (calendar_ui_test: duration 180).
        #expect(CalendarLogic.resizedEnd(start: 14 * 60, end: 16 * 60, dy: 48) == 17 * 60)
        #expect(CalendarLogic.resizedEnd(start: 14 * 60, end: 16 * 60, dy: 7) == 16 * 60 + 15)
        #expect(CalendarLogic.resizedEnd(start: 14 * 60, end: 16 * 60, dy: -500) == 14 * 60 + 15)
        #expect(CalendarLogic.resizedEnd(start: 22 * 60, end: 23 * 60, dy: 500) == 24 * 60)
        let review = CalendarEntry(task("评审", due: today, time: 14 * 60, duration: 120), today)
        #expect(CalendarLogic.durationForEnd(review, end: 17 * 60) == 180)
        // A task without a span gets one: 8:00 to 9:30.
        let early = CalendarEntry(task("早", due: today, time: 8 * 60), today)
        #expect(CalendarLogic.durationForEnd(early, end: 9 * 60 + 30) == 90)
        // The second day of an overnight span counts from its start.
        let night = CalendarEntry(task("夜班", due: today, time: 22 * 60, duration: 600), today + 1, occurrence: today)
        #expect(CalendarLogic.durationForEnd(night, end: 9 * 60) == 11 * 60)
        #expect(CalendarLogic.durationForEnd(CalendarEntry(task("全天", due: today), today), end: 60) == nil)
    }

    @Test("projected, finished and trashed entries don't move") func canMove() {
        let open = task("a", due: today)
        #expect(CalendarLogic.canMoveEntry(CalendarEntry(open, today)))
        #expect(!CalendarLogic.canMoveEntry(CalendarEntry(open, today + 1, projected: true)))
        var done = open
        done.status = .done
        #expect(!CalendarLogic.canMoveEntry(CalendarEntry(done, today)))
        var trashed = open
        trashed.trashedAt = 1
        #expect(!CalendarLogic.canMoveEntry(CalendarEntry(trashed, today)))
    }

    @Test("the hours open two hours before now on today's page, else at 7:00") func initialScroll() {
        let now = LocalDateTime(2026, 11, 18, 10, 30)
        #expect(CalendarLogic.initialScrollMinute(range: visibleRange(.week, today), now: now) == 8 * 60 + 30)
        #expect(CalendarLogic.initialScrollMinute(range: visibleRange(.week, today + 7), now: now) == 7 * 60)
        #expect(CalendarLogic.initialScrollMinute(range: visibleRange(.day, today), now: LocalDateTime(2026, 11, 18, 1, 0)) == 0)
    }

    @Test("the hover box says the time, and how many go") func hover() {
        #expect(CalendarLogic.hoverLabel(minute: 11 * 60, count: 3) == "11:00 · 3 项")
        #expect(CalendarLogic.hoverLabel(minute: 9 * 60, count: 1) == "09:00")
    }

    @Test("the all-day row grows with the busiest day, up to 6 lines for a day and 3 for several") func allDay() {
        #expect(CalendarLogic.allDayLines(busiest: 0, days: 7) == 1)
        #expect(CalendarLogic.allDayLines(busiest: 5, days: 7) == 3)
        #expect(CalendarLogic.allDayLines(busiest: 5, days: 1) == 5)
        #expect(CalendarLogic.allDayLines(busiest: 9, days: 1) == 6)
    }
}

@Suite("calendar month cells")
struct CalendarMonthCellTests {
    @Test("a cell has room for whole lines under its number") func room() {
        #expect(CalendarLogic.cellLines(height: 26 + 4 + 22 * 3) == 3)
        #expect(CalendarLogic.cellLines(height: 26 + 4 + 22 * 3 - 1) == 2)
        #expect(CalendarLogic.cellLines(height: 10) == 0)
    }

    @Test("everything shows when it fits; otherwise one line is kept for +N") func fit() {
        let week = visibleRange(.week, today)
        let entries = calendarEntries([
            task("出差", due: Day(2026, 11, 16), duration: 3 * 1440, created: 1), // Mon-Wed
            task("a", due: Day(2026, 11, 17), created: 2),
            task("b", due: Day(2026, 11, 17), created: 3),
            task("c", due: Day(2026, 11, 17), created: 4),
        ], week, today: today)
        let items = weekLayout(entries, week: week)
        #expect(CalendarLogic.monthRowFit(items, room: 4).lines == 4)
        #expect(CalendarLogic.monthRowFit(items, room: 4).hidden == [0, 0, 0, 0, 0, 0, 0])
        let tight = CalendarLogic.monthRowFit(items, room: 3)
        #expect(tight.lines == 2)
        #expect(tight.hidden == [0, 2, 0, 0, 0, 0, 0])
        #expect(CalendarLogic.monthRowFit([], room: 3).lines == 0)
    }
}

@Suite("calendar drags")
struct CalendarDragTests {
    @MainActor @Test("a drag of a picked task takes the others along; a drop where it began moves nothing") func session() {
        let model = CalendarModel(anchor: today)
        let meeting = task("晨会", due: today, time: 9 * 60)
        let rent = task("交房租", due: today)
        model.beginDrag(CalendarEntry(meeting, today), others: [rent])
        #expect(model.drag?.count == 2)
        #expect(model.drag?.has("交房租") == true)
        #expect(model.drag?.moves(to: today + 1).map(\.description) == ["晨会 2026-11-19 09:00", "交房租 2026-11-19"])
        model.dragSeen(at: CGPoint(x: 100, y: 440), in: "grid")
        model.dragSeen(at: CGPoint(x: 300, y: 500), in: "grid") // only the first counts
        #expect(model.dropIsInPlace(CGPoint(x: 103, y: 444), in: "grid"))
        #expect(!model.dropIsInPlace(CGPoint(x: 103, y: 444), in: "month"))
        #expect(!model.dropIsInPlace(CGPoint(x: 100, y: 460), in: "grid"))
        model.endDrag()
        #expect(model.drag == nil)
    }

    @MainActor @Test("a task from the 安排任务 panel lands on the day, at the hour on the grid") func unscheduled() {
        let model = CalendarModel(anchor: today)
        model.beginDrag(unscheduled: task("读书"))
        #expect(model.drag?.moves(to: today, minute: 20 * 60).map(\.description) == ["读书 2026-11-18 20:00"])
        #expect(model.drag?.moves(to: today, minute: 20 * 60, allDay: true).map(\.description) == ["读书 2026-11-18"])
        #expect(model.drag?.moves(to: today).map(\.description) == ["读书 2026-11-18"])
    }
}

@Test(arguments: ["calendar-demo", "calendar-demo:month", "calendar-demo:week", "calendar-demo:panels"])
func calendarDemoRoutes(_ text: String) {
    #expect(DebugRoute(text)?.text == text)
}

@Test func rejectsUnknownCalendarDemoStates() {
    #expect(DebugRoute("calendar-demo:nowhere") == nil)
    #expect(DebugRoute("calendar-demo:") == nil)
}

@Suite("calendar layout")
struct CalendarLayoutTests {
    @Test("a panel goes beside the calendar only with room for both; narrower, the batch bar and a sheet") func panelsBeside() {
        #expect(CalendarLogic.panelsBeside(width: 1180 - 250))     // the default window, sidebar open
        #expect(CalendarLogic.panelsBeside(width: 920))
        #expect(!CalendarLogic.panelsBeside(width: 919))
        #expect(!CalendarLogic.panelsBeside(width: 760 - 220))     // the smallest window
        // The panels never squeeze the calendar below its least width.
        #expect(CalendarLogic.minCalendarWidth + CalendarLogic.sidePanelWidth == 920)
    }
}
