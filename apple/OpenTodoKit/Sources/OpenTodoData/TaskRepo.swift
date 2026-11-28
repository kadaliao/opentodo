// Every write the app makes, ported method by method from
// `app/lib/data/repo.dart`. Each write stamps `updatedAt` with the clock
// and marks the row dirty, so the sync engine knows to push it; deletes
// leave tombstones (`deletedAt`) for sync.
//
//     let repo = TaskRepo(db, defaults: { settings.defaults }, tokens: tokens)
//     let id = try await repo.addTask(title: "开会", dueDate: Day(2026, 11, 16), dueTime: 900)
//     try await repo.setCompleted(id, true)      // a repeating task moves on
//
// Reads for the UI are the observations on `AppDatabase` (`repo.database
// .observeTasks()` …); `getTask` is here for one-off reads.
//
// `now` and the person's defaults (`TaskDefaults`) are injected, so tests
// fix the clock. `timeZone` (by default the device's, following it when it
// changes, like Dart's local `DateTime`) turns the clock into today's date (Dart's
// `dateOnly(clock())`).

import Foundation
import GRDB

/// What finishing one occurrence of a repeating task did, so it can be
/// undone.
public struct RepeatCompletion: Sendable, Hashable {
    /// The task as it was.
    public let before: TodoTask
    /// The finished copy left in 已完成.
    public let copyId: String
    /// The task's new date.
    public let next: Day
    /// Subtasks that were ticked and got reset for the next occurrence.
    public let reopenedItemIds: [String]
}

/// One task of several dragged together on the calendar (`moveAll`).
public struct TaskMove: Sendable, Hashable {
    public var id: String
    public var date: Day
    public var time: Int?

    public init(id: String, date: Day, time: Int?) {
        self.id = id
        self.date = date
        self.time = time
    }
}

public final class TaskRepo: Sendable {
    public let database: AppDatabase
    private let clock: @Sendable () -> Date
    private let defaults: @Sendable () -> TaskDefaults
    private let tokens: (any TokenStore)?
    public let timeZone: TimeZone

    /// `tokens`: where the sign-in token is, so `seedIfEmpty` leaves a
    /// signed-in device alone.
    public init(
        _ database: AppDatabase,
        clock: @escaping @Sendable () -> Date = { Date() },
        defaults: @escaping @Sendable () -> TaskDefaults = { .standard },
        tokens: (any TokenStore)? = nil,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        self.database = database
        self.clock = clock
        self.defaults = defaults
        self.tokens = tokens
        self.timeZone = timeZone
    }

    var now: Int { nowMilliseconds(clock()) }
    var today: Day { Day(clock(), in: timeZone) }

    public func newId() -> String { Ids.newId(now: clock()) }

    private func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await database.writer.write(body)
    }

    // MARK: - Reads

    /// The task, tombstones included.
    public func getTask(_ id: String) async throws -> TodoTask? {
        try await database.writer.read { try TodoTask.fetchOne($0, key: id) }
    }

    // MARK: - Tasks

    /// A new task (id: UUID v7 unless given). A time, span, reminders and
    /// repeat only stick to a task with a date; the span is normalized.
    @discardableResult
    public func addTask(
        id: String? = nil,
        title: String,
        listId: String = inboxListId,
        sectionId: String? = nil,
        dueDate: Day? = nil,
        dueTime: Int? = nil,
        duration: Int? = nil,
        tags: [String] = [],
        priority: Priority = .none,
        reminders: [Int] = [],
        repeatRule: String? = nil,
        repeatFrom: RepeatFrom = .dueDate
    ) async throws -> String {
        let id = id ?? newId()
        let now = self.now
        let dated = dueDate != nil
        let task = TodoTask(
            id: id, listId: listId, sectionId: sectionId, title: title, priority: priority,
            dueDate: dueDate, dueTime: dated ? dueTime : nil,
            duration: dated ? normalizeDuration(dueTime, duration) : nil,
            tags: tags, reminders: dated ? reminders : [], repeatRule: dated ? repeatRule : nil,
            repeatFrom: dated ? repeatFrom : .dueDate, sortOrder: -Double(now),
            createdAt: now, updatedAt: now
        )
        try await write { try task.insert($0) }
        return id
    }

    /// Changes a task with `change`, stamping it (`updateTask`). Nothing
    /// happens if there is no such task.
    public func updateTask(_ id: String, _ change: @escaping @Sendable (inout TodoTask) -> Void) async throws {
        try await write { try self.update($0, id, change) }
    }

    func update(_ db: Database, _ id: String, _ change: (inout TodoTask) -> Void) throws {
        guard var t = try TodoTask.fetchOne(db, key: id) else { return }
        change(&t)
        t.updatedAt = now
        t.dirty = true
        try t.update(db)
    }

    public func setTitle(_ id: String, _ title: String) async throws {
        try await updateTask(id) { $0.title = title }
    }

    public func setContent(_ id: String, _ content: String) async throws {
        try await updateTask(id) { $0.content = content }
    }

    /// Moves the task to another day, keeping its time span, reminders and
    /// repeat; clearing the date clears those too. A task getting its first
    /// date gets the default reminders.
    public func setDue(_ id: String, _ date: Day?, _ time: Int?) async throws {
        try await write { try self.setDue($0, id, date, time) }
    }

    func setDue(_ db: Database, _ id: String, _ date: Day?, _ time: Int?) throws {
        guard let date else {
            try update(db, id) {
                $0.dueDate = nil
                $0.dueTime = nil
                $0.duration = nil
                $0.reminders = []
                $0.repeatRule = nil
                $0.repeatFrom = .dueDate
            }
            return
        }
        guard let t = try TodoTask.fetchOne(db, key: id) else { return }
        let reminders = t.dueDate == nil ? defaults().remindersFor(allDay: time == nil) : t.reminders
        try update(db, id) {
            $0.dueDate = date
            $0.dueTime = time
            $0.reminders = reminders
        }
    }

    /// Moves the task to start on `date` at `time` (nil: all day), as
    /// dragging it on the calendar does; a span moves as a whole. Reminders
    /// count from the due time, so going between timed and all-day starts
    /// them over with the defaults for the new kind, as the date dialog
    /// does. A span keeps the days it covered when it loses its time.
    public func moveTo(_ id: String, _ date: Day, _ time: Int?) async throws {
        try await write { try self.moveTo($0, id, date, time) }
    }

    func moveTo(_ db: Database, _ id: String, _ date: Day, _ time: Int?) throws {
        guard let t = try TodoTask.fetchOne(db, key: id) else { return }
        if t.dueDate == date && t.dueTime == time { return }
        let wasTimed = t.dueDate != nil && t.dueTime != nil
        let reminders = t.dueDate == nil || wasTimed != (time != nil)
            ? defaults().remindersFor(allDay: time == nil)
            : t.reminders
        let duration = t.dueDate.flatMap { durationForTimeChange($0, t.dueTime, time, t.duration) }
        try update(db, id) {
            $0.dueDate = date
            $0.dueTime = time
            $0.duration = duration
            $0.reminders = reminders
        }
    }

    /// `moveTo` for several tasks dragged together on the calendar, in one
    /// transaction.
    public func moveAll(_ moves: [TaskMove]) async throws {
        try await write { db in
            for m in moves { try self.moveTo(db, m.id, m.date, m.time) }
        }
    }

    /// Sets how long a task with a date lasts (nil: no span), as dragging
    /// the bottom edge of a task on the calendar does.
    public func setDuration(_ id: String, _ duration: Int?) async throws {
        try await write { db in
            guard let t = try TodoTask.fetchOne(db, key: id), t.dueDate != nil else { return }
            let d = normalizeDuration(t.dueTime, duration)
            if d == t.duration { return }
            try self.update(db, id) { $0.duration = d }
        }
    }

    /// Date, time, span, reminders and repeat together, as the date dialog
    /// sets them.
    public func setSchedule(
        _ id: String,
        date: Day?,
        time: Int? = nil,
        duration: Int? = nil,
        reminders: [Int] = [],
        repeatRule: String? = nil,
        repeatFrom: RepeatFrom = .dueDate
    ) async throws {
        guard let date else { return try await setDue(id, nil, nil) }
        try await updateTask(id) {
            $0.dueDate = date
            $0.dueTime = time
            $0.duration = normalizeDuration(time, duration)
            $0.reminders = reminders
            $0.repeatRule = repeatRule
            $0.repeatFrom = repeatFrom
        }
    }

    /// Pins the task to the top of its list (置顶), or unpins it.
    public func setPinned(_ id: String, _ pinned: Bool) async throws {
        let now = self.now
        try await updateTask(id) { $0.pinnedAt = pinned ? now : nil }
    }

    public func setPriority(_ id: String, _ priority: Priority) async throws {
        try await updateTask(id) { $0.priority = priority }
    }

    /// Sections belong to a list, so a task changing list leaves its
    /// section.
    public func moveToList(_ id: String, _ listId: String) async throws {
        try await write { try self.moveToList($0, id, listId) }
    }

    func moveToList(_ db: Database, _ id: String, _ listId: String) throws {
        guard let t = try TodoTask.fetchOne(db, key: id), t.listId != listId else { return }
        try update(db, id) {
            $0.listId = listId
            $0.sectionId = nil
        }
    }

    /// Drops a task into `sectionId` (nil: 未分组) of its list, with the new
    /// order numbers from `planMove` (the moved task's, and its neighbours'
    /// when the section had to be numbered afresh).
    public func placeTask(_ id: String, _ sectionId: String?, _ orders: [String: Double]) async throws {
        try await placeTasks([id], sectionId, orders)
    }

    /// `placeTask` for several tasks dragged together, in one transaction.
    public func placeTasks(_ ids: [String], _ sectionId: String?, _ orders: [String: Double]) async throws {
        try await write { db in
            let moving = Set(ids)
            for (id, order) in orders {
                try self.update(db, id) {
                    $0.sortOrder = order
                    if moving.contains(id) { $0.sectionId = sectionId }
                }
            }
            for id in ids where orders[id] == nil {
                if let t = try TodoTask.fetchOne(db, key: id), t.sectionId != sectionId {
                    try self.update(db, id) { $0.sectionId = sectionId }
                }
            }
        }
    }

    /// Tasks dragged into a group of a view, in one transaction: each takes
    /// on what `target` stands for (a section, a day keeping its time, no
    /// date, a priority, a list, a tag), and `orders` gives the new order
    /// numbers from `planMoveMany` when the view is in manual order.
    public func dropInto(_ ids: [String], _ target: GroupTarget, _ orders: [String: Double]) async throws {
        try await write { db in
            for id in ids {
                if let t = try TodoTask.fetchOne(db, key: id) { try self.takeOn(db, t, target) }
            }
            for (id, order) in orders {
                try self.update(db, id) { $0.sortOrder = order }
            }
        }
    }

    /// Gives `t` what `target` stands for, unless it has it already.
    func takeOn(_ db: Database, _ t: TodoTask, _ target: GroupTarget) throws {
        if target.has(t) { return }
        let id = t.id
        switch target {
        case .section(_, let sectionId): try update(db, id) { $0.sectionId = sectionId }
        case .date(let day?): try moveTo(db, id, day, t.dueTime)
        case .date(nil): try setDue(db, id, nil, nil)
        case .priority(let p): try update(db, id) { $0.priority = p }
        case .list(let listId): try moveToList(db, id, listId)
        case .tag: try update(db, id) { $0.tags = target.retag(t.tags) }
        case .order: break
        }
    }

    /// Tasks dragged on the timeline, in one transaction: dated ones move by
    /// `days` (each keeping its time and span), undated ones go on `day` all
    /// day, and all of them take on what the lane they're dropped in stands
    /// for (`target`: a section, a list, a tag, a priority; nil for nothing).
    public func placeOnTimeline(_ ids: [String], days: Int, day: Day, target: GroupTarget? = nil) async throws {
        try await write { db in
            for id in ids {
                guard let t = try TodoTask.fetchOne(db, key: id) else { continue }
                if let due = t.dueDate {
                    if days != 0 { try self.moveTo(db, id, due + days, t.dueTime) }
                } else {
                    try self.moveTo(db, id, day, nil)
                }
                if let target { try self.takeOn(db, t, target) }
            }
        }
    }

    /// Starts a task on another day keeping its time of day, with the span
    /// `duration` (so it can still end when it did), as dragging the left
    /// edge of its bar on the timeline does. Reminders count from the start
    /// and keep their offsets.
    public func setStart(_ id: String, _ date: Day, _ duration: Int?) async throws {
        try await write { db in
            guard let t = try TodoTask.fetchOne(db, key: id), t.dueDate != nil else { return }
            let d = normalizeDuration(t.dueTime, duration)
            if date == t.dueDate && d == t.duration { return }
            try self.update(db, id) {
                $0.dueDate = date
                $0.duration = d
            }
        }
    }

    public func setTags(_ id: String, _ tags: [String]) async throws {
        try await updateTask(id) { $0.tags = tags }
    }

    // MARK: Completing and repeating

    /// Ticks a task off or back on. A repeating task isn't closed: it moves
    /// to its next date and a finished copy of this occurrence is left
    /// behind (returned, for undo). The last occurrence of a series closes
    /// as usual.
    @discardableResult
    public func setCompleted(_ id: String, _ done: Bool) async throws -> RepeatCompletion? {
        try await write { db in
            if done, let t = try TodoTask.fetchOne(db, key: id), t.status == .open, let advance = self.advance(t) {
                return try self.finishOccurrence(db, t, advance)
            }
            let now = self.now
            try self.update(db, id) {
                $0.status = done ? .done : .open
                $0.completedAt = done ? now : nil
            }
            return nil
        }
    }

    func advance(_ t: TodoTask) -> RepeatAdvance? {
        guard let rule = RepeatRule.tryParse(t.repeatRule), let due = t.dueDate else { return nil }
        return advanceRepeat(rule, due, today: today, repeatFrom: t.repeatFrom)
    }

    /// Ids of finished occurrences are derived from the task and the date,
    /// so two devices finishing the same occurrence offline end up with one
    /// copy.
    private func finishOccurrence(_ db: Database, _ t: TodoTask, _ advance: RepeatAdvance) throws -> RepeatCompletion {
        let now = self.now
        let copyId = Ids.occurrenceId(of: t.id, dueDate: t.dueDate)
        // Upsert: undo leaves a tombstone under the same id.
        var copy = t
        copy.id = copyId
        copy.status = .done
        copy.completedAt = now
        copy.reminders = []
        copy.repeatRule = nil
        copy.repeatFrom = .dueDate
        copy.createdAt = now
        copy.updatedAt = now
        copy.deletedAt = nil
        copy.trashedAt = nil
        copy.pinnedAt = nil
        copy.serverVersion = 0
        copy.dirty = true
        try copy.upsert(db)

        let items = try ChecklistItem.fetchAll(
            db, sql: "SELECT * FROM checklist_items WHERE task_id = ? AND deleted_at IS NULL", arguments: [t.id]
        )
        for item in items {
            var c = item
            c.id = Ids.occurrenceId(of: item.id, dueDate: t.dueDate)
            c.taskId = copyId
            c.createdAt = now
            c.updatedAt = now
            c.deletedAt = nil
            c.serverVersion = 0
            c.dirty = true
            try c.upsert(db)
        }
        let reopened = items.filter(\.done).map(\.id)
        try setChecklistDone(db, reopened, false)
        try update(db, t.id) {
            $0.dueDate = advance.date
            $0.repeatRule = advance.rule.description
        }
        return RepeatCompletion(before: t, copyId: copyId, next: advance.date, reopenedItemIds: reopened)
    }

    /// Puts a repeating task back the way it was before `c`.
    public func undoRepeatCompletion(_ c: RepeatCompletion) async throws {
        try await write { db in
            try self.update(db, c.before.id) {
                $0.dueDate = c.before.dueDate
                $0.repeatRule = c.before.repeatRule
            }
            try self.setChecklistDone(db, c.reopenedItemIds, true)
            let now = self.now
            try self.update(db, c.copyId) { $0.deletedAt = now }
            try self.tombstoneChecklists(db, [c.copyId])
        }
    }

    /// Skips this occurrence of a repeating task: it moves to the next date
    /// without a finished copy. Skipping the last one gives the task up.
    /// Returns the new date, or nil if the series is over.
    @discardableResult
    public func skipOccurrence(_ id: String) async throws -> Day? {
        try await write { db in
            guard let t = try TodoTask.fetchOne(db, key: id) else { return nil }
            guard let advance = self.advance(t) else {
                let now = self.now
                try self.update(db, id) {
                    $0.status = .wontDo
                    $0.completedAt = now
                }
                return nil
            }
            let items = try String.fetchAll(
                db, sql: "SELECT id FROM checklist_items WHERE task_id = ? AND deleted_at IS NULL AND done = 1", arguments: [id]
            )
            try self.setChecklistDone(db, items, false)
            try self.update(db, id) {
                $0.dueDate = advance.date
                $0.repeatRule = advance.rule.description
            }
            return advance.date
        }
    }

    private func setChecklistDone(_ db: Database, _ ids: [String], _ done: Bool) throws {
        guard !ids.isEmpty else { return }
        try db.execute(
            sql: "UPDATE checklist_items SET done = ?, updated_at = ?, dirty = 1 WHERE id IN (\(databaseQuestionMarks(count: ids.count)))",
            arguments: args([done, now], ids)
        )
    }

    // MARK: Trash

    public func trashTask(_ id: String) async throws {
        let now = self.now
        try await updateTask(id) { $0.trashedAt = now }
    }

    public func restoreTask(_ id: String) async throws {
        try await updateTask(id) { $0.trashedAt = nil }
    }

    /// Permanent delete: leaves tombstones (the task's and its checklist's)
    /// for sync.
    public func purgeTask(_ id: String) async throws {
        try await write { db in
            let now = self.now
            try self.update(db, id) { $0.deletedAt = now }
            try self.tombstoneChecklists(db, [id])
        }
    }

    public func emptyTrash() async throws {
        try await write { db in
            let now = self.now
            let trashed = try String.fetchAll(db, sql: "SELECT id FROM tasks WHERE trashed_at IS NOT NULL AND deleted_at IS NULL")
            guard !trashed.isEmpty else { return }
            try db.execute(
                sql: "UPDATE tasks SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id IN (\(databaseQuestionMarks(count: trashed.count)))",
                arguments: args([now, now], trashed)
            )
            try self.tombstoneChecklists(db, trashed)
        }
    }

    private func tombstoneChecklists(_ db: Database, _ taskIds: [String]) throws {
        guard !taskIds.isEmpty else { return }
        let now = self.now
        try db.execute(
            sql: """
                UPDATE checklist_items SET deleted_at = ?, updated_at = ?, dirty = 1
                WHERE task_id IN (\(databaseQuestionMarks(count: taskIds.count))) AND deleted_at IS NULL
                """,
            arguments: args([now, now], taskIds)
        )
    }

    // MARK: - Lists

    @discardableResult
    public func addList(_ name: String, emoji: String? = nil, color: Int? = nil, id: String? = nil) async throws -> String {
        let id = id ?? newId()
        let now = self.now
        let list = TaskList(id: id, name: name, emoji: emoji, color: color, sortOrder: Double(now), createdAt: now, updatedAt: now)
        try await write { try list.insert($0) }
        return id
    }

    /// Nil leaves a field as it is; `emoji: .some(nil)` / `color: .some(nil)`
    /// take the icon / colour away.
    public func updateList(_ id: String, name: String? = nil, emoji: String?? = nil, color: Int?? = nil,
                           sortOrder: Double? = nil) async throws {
        try await write { db in
            guard var l = try TaskList.fetchOne(db, key: id) else { return }
            if let name { l.name = name }
            if let emoji { l.emoji = emoji }
            if let color { l.color = color }
            if let sortOrder { l.sortOrder = sortOrder }
            l.updatedAt = self.now
            l.dirty = true
            try l.update(db)
        }
    }

    /// Deletes the list and its sections, and moves its tasks to the trash.
    public func deleteList(_ id: String) async throws {
        try await write { db in
            let now = self.now
            try db.execute(
                sql: "UPDATE list_sections SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE list_id = ? AND deleted_at IS NULL",
                arguments: [now, now, id]
            )
            try db.execute(sql: "UPDATE task_lists SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id = ?", arguments: [now, now, id])
            try db.execute(
                sql: """
                    UPDATE tasks SET trashed_at = ?, list_id = ?, section_id = NULL, updated_at = ?, dirty = 1
                    WHERE list_id = ? AND trashed_at IS NULL
                    """,
                arguments: [now, inboxListId, now, id]
            )
        }
    }

    // MARK: - Sections

    /// Adds a section at the end of `listId`'s.
    @discardableResult
    public func addSection(_ listId: String, _ name: String, id: String? = nil) async throws -> String {
        let id = id ?? newId()
        let now = self.now
        try await write { db in
            let last = try Double.fetchOne(
                db,
                sql: "SELECT sort_order FROM list_sections WHERE list_id = ? AND deleted_at IS NULL ORDER BY sort_order DESC LIMIT 1",
                arguments: [listId]
            )
            try ListSection(id: id, listId: listId, name: name, sortOrder: last.map { $0 + 1024 } ?? 0, createdAt: now, updatedAt: now)
                .insert(db)
        }
        return id
    }

    /// Nil leaves a field as it is.
    public func updateSection(_ id: String, name: String? = nil, sortOrder: Double? = nil) async throws {
        try await write { db in
            guard var s = try ListSection.fetchOne(db, key: id) else { return }
            if let name { s.name = name }
            if let sortOrder { s.sortOrder = sortOrder }
            s.updatedAt = self.now
            s.dirty = true
            try s.update(db)
        }
    }

    /// Deletes the section; its tasks stay in the list, under 未分组.
    public func deleteSection(_ id: String) async throws {
        try await write { db in
            let now = self.now
            try db.execute(sql: "UPDATE list_sections SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id = ?", arguments: [now, now, id])
            try db.execute(sql: "UPDATE tasks SET section_id = NULL, updated_at = ?, dirty = 1 WHERE section_id = ?", arguments: [now, id])
        }
    }

    // MARK: - Filters

    /// `rule` is the JSON from `FilterRule.encode`.
    @discardableResult
    public func addFilter(_ name: String, _ rule: String, id: String? = nil) async throws -> String {
        let id = id ?? newId()
        let now = self.now
        let filter = TaskFilter(id: id, name: name, rule: rule, sortOrder: Double(now), createdAt: now, updatedAt: now)
        try await write { try filter.insert($0) }
        return id
    }

    /// Nil leaves a field as it is.
    public func updateFilter(_ id: String, name: String? = nil, rule: String? = nil, sortOrder: Double? = nil) async throws {
        try await write { db in
            guard var f = try TaskFilter.fetchOne(db, key: id) else { return }
            if let name { f.name = name }
            if let rule { f.rule = rule }
            if let sortOrder { f.sortOrder = sortOrder }
            f.updatedAt = self.now
            f.dirty = true
            try f.update(db)
        }
    }

    /// Deletes the filter; its tasks stay where they are.
    public func deleteFilter(_ id: String) async throws {
        let now = self.now
        try await write { db in
            try db.execute(sql: "UPDATE task_filters SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id = ?", arguments: [now, now, id])
        }
    }

    // MARK: - Checklist

    @discardableResult
    public func addChecklistItem(_ taskId: String, _ title: String) async throws -> String {
        let id = newId()
        let now = self.now
        let item = ChecklistItem(id: id, taskId: taskId, title: title, sortOrder: Double(now), createdAt: now, updatedAt: now)
        try await write { try item.insert($0) }
        return id
    }

    /// Nil leaves a field as it is.
    public func updateChecklistItem(_ id: String, title: String? = nil, done: Bool? = nil, sortOrder: Double? = nil) async throws {
        try await write { db in
            guard var c = try ChecklistItem.fetchOne(db, key: id) else { return }
            if let title { c.title = title }
            if let done { c.done = done }
            if let sortOrder { c.sortOrder = sortOrder }
            c.updatedAt = self.now
            c.dirty = true
            try c.update(db)
        }
    }

    public func deleteChecklistItem(_ id: String) async throws {
        let now = self.now
        try await write { db in
            try db.execute(sql: "UPDATE checklist_items SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id = ?", arguments: [now, now, id])
        }
    }

    // MARK: - First run

    /// The ids of the welcome items. Fixed: every install creates the same
    /// ones, so devices that keep them merge into one copy instead of each
    /// adding its own.
    public static let seedListId = "seed-welcome"

    /// A short welcome list on a fresh install, so the app isn't empty.
    /// Nothing on a device with tasks or lists, or one that is signed in
    /// (it gets its data from the account instead).
    public func seedIfEmpty() async throws {
        let empty = try await database.writer.read { db in
            try TodoTask.fetchCount(db) == 0 && TaskList.fetchCount(db) == 0
        }
        guard empty else { return }
        if try tokens?.token() != nil { return }
        if try await database.getValue(Keys.token) != nil { return }
        let today = self.today
        let welcome = try await addList("欢迎", emoji: "👋", id: Self.seedListId)
        let ids = [
            welcome,
            try await addTask(id: "seed-welcome-1", title: "在上方输入框里试试“明天下午3点开会 #工作”", listId: welcome, priority: .high),
            try await addTask(id: "seed-welcome-2", title: "点开任务可以写备注、加子任务", listId: welcome),
            try await addTask(id: "seed-welcome-3", title: "右键（手机上长按）任务可以改日期、优先级、清单", listId: welcome),
            try await addTask(id: "seed-today", title: "看看“今天”和“最近7天”", dueDate: today),
        ]
        try await database.setValue(Keys.seedIds, JSONValue.array(ids.map(JSONValue.string)).encoded())
    }
}

/// Statement arguments: some values, then a list for an `IN (…)`.
private func args(_ first: [any DatabaseValueConvertible], _ list: [String]) -> StatementArguments {
    StatementArguments(first + list.map { $0 as any DatabaseValueConvertible })
}
