// Watching the database: the streams `TaskRepo.watch…` and the providers
// in `app/lib/state/providers.dart` give the Flutter UI, as GRDB
// `ValueObservation`s. Each delivers the current value first, then a new
// one after every committed change that touches what it read (repeats
// dropped).
//
//     for try await tasks in db.observeTasks().values() { … }   // async
//     let handle = db.observeLists().start { lists in … }      // main actor
//     let lists = try await db.observeLists().first()          // read once

import GRDB

public struct DatabaseObservation<Value: Sendable & Equatable>: Sendable {
    let writer: any DatabaseWriter
    let fetch: @Sendable (Database) throws -> Value

    private var observation: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<Value>>> {
        ValueObservation.tracking(fetch).removeDuplicates()
    }

    /// The value now and after every change, until the loop ends or the
    /// task is cancelled. Throws if reading fails.
    public func values() -> AsyncValueObservation<Value> {
        observation.values(in: writer)
    }

    /// Calls `onChange` on the main actor with the value now (right away)
    /// and after every change, until the handle is cancelled or released.
    @MainActor
    public func start(
        onError: @escaping @MainActor (any Error) -> Void = { _ in },
        onChange: @escaping @MainActor (Value) -> Void
    ) -> ObservationHandle {
        let cancellable = observation.start(
            in: writer,
            scheduling: .immediate,
            onError: onError,
            onChange: onChange
        )
        return ObservationHandle(cancellable)
    }

    /// The value as it is now (Dart's `stream.first`).
    public func first() async throws -> Value {
        try await writer.read(fetch)
    }

    /// The same value turned into another.
    public func map<T: Sendable & Equatable>(_ transform: @escaping @Sendable (Value) -> T) -> DatabaseObservation<T> {
        let fetch = self.fetch
        return DatabaseObservation<T>(writer: writer) { try transform(fetch($0)) }
    }
}

/// Keeps an observation running; it stops on `cancel()` or when released.
public final class ObservationHandle: Sendable {
    private let cancellable: AnyDatabaseCancellable

    init(_ cancellable: AnyDatabaseCancellable) {
        self.cancellable = cancellable
    }

    public func cancel() { cancellable.cancel() }

    deinit { cancellable.cancel() }
}

extension AppDatabase {
    func observe<Value: Sendable & Equatable>(_ fetch: @escaping @Sendable (Database) throws -> Value) -> DatabaseObservation<Value> {
        DatabaseObservation(writer: writer, fetch: fetch)
    }

    /// Lists that aren't deleted, in order (`watchLists`).
    public func observeLists() -> DatabaseObservation<[TaskList]> {
        observe { try TaskList.fetchAll($0, sql: "SELECT * FROM task_lists WHERE deleted_at IS NULL ORDER BY sort_order, created_at") }
    }

    /// All tasks that aren't permanently deleted, the trash included
    /// (`watchTasks`). In table order, as drift returns them.
    public func observeTasks() -> DatabaseObservation<[TodoTask]> {
        observe { try TodoTask.fetchAll($0, sql: "SELECT * FROM tasks WHERE deleted_at IS NULL") }
    }

    /// A task's subtasks, in order (`watchChecklist`).
    public func observeChecklist(taskId: String) -> DatabaseObservation<[ChecklistItem]> {
        observe {
            try ChecklistItem.fetchAll(
                $0,
                sql: "SELECT * FROM checklist_items WHERE task_id = ? AND deleted_at IS NULL ORDER BY sort_order, created_at",
                arguments: [taskId]
            )
        }
    }

    /// Every subtask that isn't deleted, for search (`watchAllChecklistItems`).
    public func observeAllChecklistItems() -> DatabaseObservation<[ChecklistItem]> {
        observe { try ChecklistItem.fetchAll($0, sql: "SELECT * FROM checklist_items WHERE deleted_at IS NULL") }
    }

    /// Every list's sections, in order (`watchSections`).
    public func observeSections() -> DatabaseObservation<[ListSection]> {
        observe { try ListSection.fetchAll($0, sql: "SELECT * FROM list_sections WHERE deleted_at IS NULL ORDER BY sort_order, created_at") }
    }

    /// Saved filters, in order (`watchFilters`).
    public func observeFilters() -> DatabaseObservation<[TaskFilter]> {
        observe { try TaskFilter.fetchAll($0, sql: "SELECT * FROM task_filters WHERE deleted_at IS NULL ORDER BY sort_order, created_at") }
    }

    // MARK: The efficiency module

    /// Habits that aren't deleted, archived ones included (the UI splits
    /// them), in order.
    public func observeHabits() -> DatabaseObservation<[Habit]> {
        observe { try Habit.fetchAll($0, sql: "SELECT * FROM habits WHERE deleted_at IS NULL ORDER BY sort_order, created_at") }
    }

    /// Every habit's check-ins that aren't taken back, by day.
    public func observeCheckins() -> DatabaseObservation<[HabitCheckin]> {
        observe { try HabitCheckin.fetchAll($0, sql: "SELECT * FROM habit_checkins WHERE deleted_at IS NULL ORDER BY day") }
    }

    /// One habit's check-ins, by day.
    public func observeCheckins(habitId: String) -> DatabaseObservation<[HabitCheckin]> {
        observe {
            try HabitCheckin.fetchAll(
                $0, sql: "SELECT * FROM habit_checkins WHERE habit_id = ? AND deleted_at IS NULL ORDER BY day", arguments: [habitId]
            )
        }
    }

    /// Focus sessions that aren't deleted, by start.
    public func observeFocusSessions() -> DatabaseObservation<[FocusSession]> {
        observe { try FocusSession.fetchAll($0, sql: "SELECT * FROM focus_sessions WHERE deleted_at IS NULL ORDER BY started_at") }
    }

    /// Countdowns that aren't deleted, in order (`sortCountdowns` puts the
    /// pinned and the nearest first).
    public func observeCountdowns() -> DatabaseObservation<[Countdown]> {
        observe { try Countdown.fetchAll($0, sql: "SELECT * FROM countdowns WHERE deleted_at IS NULL ORDER BY sort_order, created_at") }
    }

    /// Rows waiting to be pushed, across every synced table
    /// (`watchDirtyCount`, for the sync scheduler).
    public func observeDirtyCount() -> DatabaseObservation<Int> {
        observe { try dirtyCount($0) }
    }
}

func dirtyCount(_ db: Database) throws -> Int {
    let sum = SyncedTable.allCases.map { "(SELECT COUNT(*) FROM \($0.rawValue) WHERE dirty)" }.joined(separator: " + ")
    return try Int.fetchOne(db, sql: "SELECT " + sum) ?? 0
}
