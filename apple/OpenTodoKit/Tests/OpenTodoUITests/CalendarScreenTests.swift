// The calendar module wired to the app: AppModel over an in-memory
// database, the clock at Thursday 2026-11-26 09:41 in Shanghai. The cases
// follow what app/test/calendar_ui_test.dart and calendar_selection_test.dart
// check through the screen (moves, new tasks, the bottom edge, the mode
// remembered, picking and the batch actions), said at the model's level;
// plus the Swift version's filter and task card.

import Foundation
import OpenTodoData
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

nonisolated private let tz = TimeZone(identifier: "Asia/Shanghai")!
nonisolated private let now = LocalDateTime(2026, 11, 26, 9, 41)
nonisolated private let today = now.day
nonisolated private let neighbour = today - 1 // same week row

private func makeModel(width: WidthClass = .regular) async throws -> AppModel {
    let db = try AppDatabase.inMemory()
    let settings = LocalSettings(db)
    let repo = TaskRepo(db, clock: { now.date(in: tz) }, defaults: settings.defaultsProvider, timeZone: tz)
    let model = AppModel(repo: repo, settings: settings, now: now)
    model.setWidth(width)
    await model.start(clock: false)
    try await waitFor { model.loaded }
    model.openCalendar(mode: nil)
    return model
}

private func waitFor(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out")
}

/// Until the model has the database's latest snapshot.
private func settle(_ model: AppModel) async throws {
    let data = try await model.database.observeTaskData().first()
    try await waitFor { model.data == data }
}

private func add(_ m: AppModel, _ title: String, due: Day? = nil, time: Int? = nil, duration: Int? = nil,
                 reminders: [Int] = [], repeat rule: String? = nil, listId: String = inboxListId,
                 priority: Priority = .none) async throws -> String {
    let id = try await m.repo.addTask(title: title, listId: listId, dueDate: due, dueTime: time, duration: duration,
                                      priority: priority, reminders: reminders, repeatRule: rule)
    try await settle(m)
    return id
}

private func entry(_ m: AppModel, _ id: String, on day: Day) -> CalendarEntry? {
    calendarEntries(m.data.tasks, DayRange(day, day + 1), today: today).first { $0.task.id == id }
}

@MainActor
@Suite("calendar in the app")
struct CalendarScreenTests {
    @Test("the calendar shares the window's selection, and the mode is remembered on this device") func connected() async throws {
        let m = try await makeModel()
        #expect(m.module == .calendar)
        #expect(m.calendar.selection === m.selection)
        #expect(m.calendar.anchor == today)
        m.calendar.perform(.mode(.day), today: today)
        #expect(m.settings.calendarPrefs.mode == .day)
        #expect(try m.database.getValueNow(CalendarPrefs.storageKey)?.contains(#""mode":"day""#) == true)
        // Another module and back: still the day view.
        m.switchTo(.tasks)
        m.openCalendar(mode: nil)
        #expect(m.calendar.mode == .day)
    }

    @Test("a route opens the calendar in a mode") func route() async throws {
        let m = try await makeModel()
        m.switchTo(.tasks)
        m.apply(.calendar("week"))
        #expect(m.module == .calendar && m.calendar.mode == .week)
    }

    @Test("desktop: drag a task to another day; it keeps its time and reminders") func dragToAnotherDay() async throws {
        let m = try await makeModel()
        let id = try await add(m, "写周报", due: today, time: 15 * 60, reminders: [0])
        let e = try #require(entry(m, id, on: today))
        await m.calendarMove(dropTargets(e, [], neighbour))
        try await settle(m)
        let t = try #require(m.task(id))
        #expect(t.dueDate == neighbour && t.dueTime == 15 * 60 && t.reminders == [0])
    }

    @Test("desktop: a click on a day adds an all-day task there; a date typed wins") func addOnADay() async throws {
        let m = try await makeModel()
        let added = try #require(await m.quickAdd("写日报", target: QuickAddTarget(date: today)))
        let typed = try #require(await m.quickAdd("明天交房租", target: QuickAddTarget(date: today, time: 14 * 60)))
        try await settle(m)
        let a = try #require(m.task(added)), b = try #require(m.task(typed))
        #expect(a.dueDate == today && a.dueTime == nil && a.reminders.isEmpty)
        #expect(b.dueDate == today + 1 && b.dueTime == nil)
        #expect(m.selectedTaskId == nil && m.notices.current == nil) // nothing opens in the tasks module
    }

    @Test("week: to another time keeps the reminders; into all day drops time and reminders; a click on 14:00 adds a timed task")
    func weekMoves() async throws {
        let m = try await makeModel()
        let id = try await add(m, "晨会", due: today, time: 9 * 60, reminders: [-30])
        await m.calendarMove(dropTargets(try #require(entry(m, id, on: today)), [], today, minute: 11 * 60))
        try await settle(m)
        #expect(m.task(id)?.dueTime == 11 * 60)
        #expect(m.task(id)?.reminders == [-30])
        await m.calendarMove(dropTargets(try #require(entry(m, id, on: today)), [], today, allDay: true))
        try await settle(m)
        #expect(m.task(id)?.dueTime == nil)
        #expect(m.task(id)?.reminders == [])

        let added = try #require(await m.quickAdd("评审", target: QuickAddTarget(date: today, time: 14 * 60)))
        try await settle(m)
        #expect(m.task(added)?.dueTime == 14 * 60)
        #expect(m.task(added)?.reminders == [0])
    }

    @Test("a span's bottom edge sets the end; a task without a span gets one; a drag moves the span whole") func bottomEdge() async throws {
        let m = try await makeModel()
        let review = try await add(m, "评审", due: today, time: 14 * 60, duration: 120)
        let e = try #require(entry(m, review, on: today))
        await m.calendarSetDuration(review, try #require(CalendarLogic.durationForEnd(e, end: 17 * 60)))
        let morning = try await add(m, "晨会", due: today, time: 8 * 60)
        let e2 = try #require(entry(m, morning, on: today))
        await m.calendarSetDuration(morning, try #require(CalendarLogic.durationForEnd(e2, end: 9 * 60 + 30)))
        try await settle(m)
        #expect(m.task(review)?.duration == 180)
        #expect(m.task(morning)?.duration == 90)
        await m.calendarMove(dropTargets(try #require(entry(m, review, on: today)), [], today, minute: 11 * 60))
        try await settle(m)
        #expect(m.task(review)?.dueTime == 11 * 60)
        #expect(m.task(review)?.duration == 180)
    }

    @Test("ticking a repeating task on the calendar moves it on, with an undo") func tickRepeating() async throws {
        let m = try await makeModel()
        let id = try await add(m, "晨跑", due: today, time: 7 * 60, repeat: "FREQ=DAILY")
        await m.calendarSetDone(id, true)
        try await settle(m)
        #expect(m.task(id)?.dueDate == today + 1)
        #expect(m.notices.current?.text.hasPrefix("已完成，下次") == true)
    }

    @Test("a click opens the task beside the calendar on a wide window, as a page on a phone") func openTask() async throws {
        let wide = try await makeModel()
        let id = try await add(wide, "晨会", due: today, time: 9 * 60)
        wide.calendarActions.openTask(id)
        #expect(wide.calendar.openTaskId == id && wide.calendar.phonePath.isEmpty)
        #expect(wide.module == .calendar) // stays in the calendar

        let phone = try await makeModel(width: .compact)
        phone.calendarActions.openTask("x")
        #expect(phone.calendar.phonePath == ["x"])
    }

    @Test("picked tasks drag together; 全选 takes the page; 完成 clears the picking and can be undone") func picking() async throws {
        let m = try await makeModel()
        let meeting = try await add(m, "晨会", due: today, time: 9 * 60)
        let rent = try await add(m, "交房租", due: today)
        let report = try await add(m, "写周报", due: neighbour, time: 15 * 60)
        m.calendar.mode = .month
        m.selection.tap(meeting, modifiers: .command, order: m.calendarOrder, current: nil, touch: false)
        m.selection.tap(rent, modifiers: .command, order: m.calendarOrder, current: nil, touch: false)
        #expect(m.selection.ids == [meeting, rent])

        // One dragged to the day before takes the other along.
        let lead = try #require(entry(m, meeting, on: today))
        let others = calendarPicked(m.data.tasks, ids: m.selection.ids).filter { $0.id != meeting }
        await m.calendarMove(dropTargets(lead, others, neighbour))
        try await settle(m)
        #expect(m.task(meeting)?.dueDate == neighbour && m.task(meeting)?.dueTime == 9 * 60)
        #expect(m.task(rent)?.dueDate == neighbour && m.task(rent)?.dueTime == nil)
        #expect(m.task(report)?.dueDate == neighbour)

        // 全选: the page, in the order shown.
        await m.applyBatch(.selectAll, order: m.calendarOrder)
        #expect(m.selection.ids == [meeting, rent, report])
        await m.applyBatch(.complete(ids: [meeting, rent, report]), order: [])
        try await settle(m)
        #expect(!m.selection.isActive)
        #expect([meeting, rent, report].allSatisfy { m.task($0)?.status == .done })
        #expect(m.notices.current?.text == "已完成 3 个任务")
        await m.notices.current?.action?()
        try await settle(m)
        #expect([meeting, rent, report].allSatisfy { m.task($0)?.status == .open })
    }

    @Test("the batch's other actions write each picked task") func batchWrites() async throws {
        let m = try await makeModel()
        let a = try await add(m, "a", due: today), b = try await add(m, "b", due: today, time: 600)
        await m.applyBatch(.setPriority(ids: [a, b], .high), order: [])
        await m.applyBatch(.setDue([BatchDueChange(id: a, date: today + 2, time: nil), BatchDueChange(id: b, date: today + 2, time: 600)]), order: [])
        await m.applyBatch(.trash(ids: [a]), order: [])
        try await settle(m)
        #expect(m.task(b)?.priority == .high && m.task(b)?.dueDate == today + 2 && m.task(b)?.dueTime == 600)
        #expect(m.task(a)?.trashedAt != nil)
        #expect(m.notices.current?.text == "已把 1 个任务移到垃圾桶")
    }

    @Test("a task from the 安排任务 panel lands on the day it is dropped on, with the default reminders") func arrange() async throws {
        let m = try await makeModel()
        let id = try await add(m, "读书")
        let t = try #require(m.task(id))
        #expect(unscheduledTasks(m.data.tasks).map(\.id) == [id])
        await m.calendarMove([scheduleTarget(t, today + 1, minute: 20 * 60)])
        try await settle(m)
        #expect(m.task(id)?.dueDate == today + 1 && m.task(id)?.dueTime == 20 * 60)
        #expect(m.task(id)?.reminders == [0])
        #expect(unscheduledTasks(m.data.tasks).isEmpty)
    }

    @Test("more › 过滤器: only the filter's tasks; a deleted filter shows everything") func filter() async throws {
        let m = try await makeModel()
        let high = try await add(m, "高", due: today, priority: .high)
        let low = try await add(m, "低", due: today, priority: .low)
        try await m.repo.addFilter("高优先级", #"{"conditions":[{"field":"priority","values":["high"]}]}"#, id: "f")
        try await settle(m)
        m.calendar.prefs.filterId = "f"
        #expect(m.calendar.shownTasks(m.data.tasks, filters: m.filters, now: m.now).map(\.id) == [high])
        #expect(m.calendarOrder == [high])
        #expect(m.settings.calendarPrefs.filterId == "f") // remembered
        m.calendar.prefs.filterId = "gone"
        #expect(Set(m.calendarOrder) == [high, low])
    }

    @Test("a click shows the card when the person chose cards") func card() async throws {
        let m = try await makeModel()
        #expect(!m.calendar.prefs.taskCard) // the detail, out of the box
        m.calendar.prefs.taskCard = true
        #expect(m.settings.calendarPrefs.taskCard)
    }

    @Test("the open task closes when it goes to the trash; coming back, a finished one the calendar hides is closed too") func closeGone() async throws {
        let m = try await makeModel()
        let a = try await add(m, "a", due: today), b = try await add(m, "b", due: today)
        m.openCalendarTask(a)
        await m.trash(try #require(m.task(a)))
        try await settle(m)
        m.closeCalendarTaskIfGone() // what the screen does when the data changes
        #expect(m.calendar.openTaskId == nil)

        // Finished while the tasks module was showing.
        m.openCalendarTask(b)
        m.switchTo(.tasks)
        await m.setDone(try #require(m.task(b)), true)
        try await settle(m)
        m.closeCalendarTaskIfGone()
        #expect(m.calendar.openTaskId == b) // finished isn't gone
        m.calendar.prefs.showCompleted = false
        m.openCalendar(mode: nil)
        #expect(m.calendar.openTaskId == nil)

        // Shown finished: it stays open.
        m.calendar.prefs.showCompleted = true
        m.openCalendarTask(b)
        m.switchTo(.tasks)
        m.openCalendar(mode: nil)
        #expect(m.calendar.openTaskId == b)

        // On a phone, the pushed page goes.
        let phone = try await makeModel(width: .compact)
        let c = try await add(phone, "c", due: today)
        phone.openCalendarTask(c)
        await phone.trash(try #require(phone.task(c)))
        try await settle(phone)
        phone.closeCalendarTaskIfGone()
        #expect(phone.calendar.phonePath.isEmpty)
    }
}
