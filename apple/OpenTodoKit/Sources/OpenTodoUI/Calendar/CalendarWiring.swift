// The calendar module in the app: `model.calendar` (a `CalendarModel`)
// connected to the window's selection and the stored `calendar.prefs`, and
// the calendar's callbacks carried out on the database — moves and the
// bottom edge through `TaskRepo.moveAll` / `setDuration`, ticks through
// `AppModel.setDone` (with its undo for a repeating task), new tasks
// through the tasks module's `QuickAddField`. The screen is
// `Shell/CalendarScreen.swift`.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

extension AppModel {
    /// Hands the calendar the window's selection, the stored prefs (saved
    /// back as they change) and today; once.
    public func connectCalendar() {
        let settings = self.settings
        calendar.connect(selection: selection, prefs: settings.calendarPrefs, today: today) { prefs in
            settings.setCalendarPrefs(prefs)
        }
    }

    /// Switches to the calendar, in `mode` if it names one (`-OTOpen
    /// calendar:week`).
    public func openCalendar(mode: String?) {
        switchTo(.calendar)
        connectCalendar()
        closeCalendarTaskIfGone(hidden: true)
        if let m = mode.flatMap(CalendarMode.init(rawValue:)) { calendar.mode = m }
    }

    /// The calendar's callbacks, on this window's data.
    var calendarActions: CalendarActions {
        CalendarActions(
            openTask: { [weak self] id in self?.openCalendarTask(id) },
            move: { [weak self] moves in self?.run { await self?.calendarMove(moves) } },
            setDuration: { [weak self] id, minutes in self?.run { await self?.calendarSetDuration(id, minutes) } },
            setDone: { [weak self] id, done in self?.run { await self?.calendarSetDone(id, done) } },
            newTask: { [weak self] request in self?.calendar.newTask = request }
        )
    }

    /// Opens a task from the calendar: in the detail beside it on a wide
    /// window, pushed on a phone.
    public func openCalendarTask(_ id: String) {
        if width == .compact {
            calendar.phonePath = [id]
        } else {
            calendar.openTaskId = id
        }
    }

    /// Closes the calendar's open task once it is gone — trashed or deleted
    /// (from its menu or detail, or elsewhere) — as the tasks module closes
    /// its detail. With `hidden`, also when it is finished and the calendar
    /// hides finished tasks: what coming back to the calendar checks, since
    /// the calendar keeps its open task apart from `selectedTaskId`.
    public func closeCalendarTaskIfGone(hidden: Bool = false) {
        func gone(_ id: String) -> Bool {
            guard let t = task(id), t.trashedAt == nil, t.deletedAt == nil else { return true }
            return hidden && t.status != .open && !calendar.prefs.showCompleted
        }
        if let id = calendar.openTaskId, gone(id) { calendar.openTaskId = nil }
        if let id = calendar.phonePath.last, gone(id) { calendar.phonePath = [] }
    }

    /// Tasks dragged to other days or times (several picked together, or
    /// one from the 安排任务 panel): `TaskRepo.moveAll`, which keeps spans and
    /// starts reminders over when a task changes between timed and all day.
    public func calendarMove(_ moves: [CalendarMove]) async {
        await attempt {
            try await repo.moveAll(moves.map { TaskMove(id: $0.id, date: $0.date, time: $0.time) })
        }
    }

    /// A task's bottom edge dragged on the hour grid.
    public func calendarSetDuration(_ id: String, _ minutes: Int) async {
        await attempt { try await repo.setDuration(id, minutes) }
    }

    public func calendarSetDone(_ id: String, _ done: Bool) async {
        guard let t = task(id) else { return }
        await setDone(t, done)
    }

    /// What the batch views report on the calendar: `performBatch`, except
    /// that 全选 picks the calendar page rather than the task list's view.
    public func applyBatch(_ action: BatchAction, order: [String]) async {
        if action == .selectAll {
            selection.selectAll(order)
        } else {
            await performBatch(action)
        }
    }

    /// The calendar page's tasks in the order shown (for 全选 in the batch
    /// views).
    public var calendarOrder: [String] {
        calendar.pageOrder(tasks: data.tasks, filters: filters, now: now, compact: width == .compact)
    }
}

extension CalendarModel {
    /// The tasks the calendar shows: all of them, or those of the filter
    /// chosen in 更多 (a filter since deleted counts as none).
    public func shownTasks(_ tasks: [TodoTask], filters: [TaskFilter], now: LocalDateTime) -> [TodoTask] {
        guard let id = prefs.filterId, let f = filters.first(where: { $0.id == id }) else { return tasks }
        let matches = FilterRule.parse(f.rule).matcher(now)
        return tasks.filter(matches)
    }

    /// The tasks on the page in the order shown, for Shift-click and ⌘A: on
    /// the phone's month, the day below it.
    public func pageOrder(tasks: [TodoTask], filters: [TaskFilter], now: LocalDateTime, compact: Bool) -> [String] {
        let entries = calendarEntries(shownTasks(tasks, filters: filters, now: now), range, today: now.day, filter: prefs.filter)
        if compact && mode == .month { return entryOrder(entries.filter { $0.date == anchor }) }
        return calendarOrder(entries, mode: mode, range: range, today: now.day)
    }
}

/// The new-task popover's field: the tasks module's quick add, on the day
/// (and time) clicked; a date typed into it wins. The list to add to can
/// be changed, as in the Flutter version's new-task dialog.
struct CalendarQuickAdd: View {
    @Environment(AppModel.self) private var model
    let request: CalendarNewTask
    let done: () -> Void
    @State private var listId = inboxListId

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuickAddField(
                target: QuickAddTarget(listId: listId, date: request.date, time: request.time),
                prompt: "准备做什么？回车创建", focusRequests: 1
            ) { _ in done() }
            Picker(selection: $listId) {
                Label("收集箱", systemImage: "tray").tag(inboxListId)
                ForEach(model.lists) { l in
                    Text(l.emoji.map { "\($0) \(l.name)" } ?? l.name).tag(l.id)
                }
            } label: {
                Label("清单", systemImage: "list.bullet")
            }
            .fixedSize()
        }
    }
}
