// Everything the task screens show, read in one go: one observation over
// the five synced tables, so the lists, tasks, subtasks, sections and
// filters in a snapshot always belong together (a task never points at a
// list the same snapshot hasn't got yet).
//
//     let handle = database.observeTaskData().start { data in … }   // main actor
//
// The UI keeps the latest snapshot (`AppModel.data`) and derives every
// screen from it; writes go through `TaskRepo` and come back here.

import GRDB

public struct TaskData: Sendable, Hashable {
    /// Not deleted, in order.
    public var lists: [TaskList]
    /// Not permanently deleted; the trash included.
    public var tasks: [TodoTask]
    /// Not deleted, in order.
    public var checklistItems: [ChecklistItem]
    /// Every list's sections, not deleted, in order.
    public var sections: [ListSection]
    /// Not deleted, in order.
    public var filters: [TaskFilter]

    public init(lists: [TaskList] = [], tasks: [TodoTask] = [], checklistItems: [ChecklistItem] = [],
                sections: [ListSection] = [], filters: [TaskFilter] = []) {
        self.lists = lists
        self.tasks = tasks
        self.checklistItems = checklistItems
        self.sections = sections
        self.filters = filters
    }

    public static let empty = TaskData()
}

extension AppDatabase {
    /// The five tables together, now and after every change to any of them.
    public func observeTaskData() -> DatabaseObservation<TaskData> {
        observe { db in
            TaskData(
                lists: try TaskList.fetchAll(db, sql: "SELECT * FROM task_lists WHERE deleted_at IS NULL ORDER BY sort_order, created_at"),
                // The two big tables by position (`init(positional:)`).
                tasks: try Array(Row.fetchCursor(
                    db, sql: "SELECT \(TodoTask.positionalColumns) FROM tasks WHERE deleted_at IS NULL"
                ).map(TodoTask.init(positional:))),
                checklistItems: try Array(Row.fetchCursor(
                    db, sql: "SELECT \(ChecklistItem.positionalColumns) FROM checklist_items WHERE deleted_at IS NULL ORDER BY sort_order, created_at"
                ).map(ChecklistItem.init(positional:))),
                sections: try ListSection.fetchAll(db, sql: "SELECT * FROM list_sections WHERE deleted_at IS NULL ORDER BY sort_order, created_at"),
                filters: try TaskFilter.fetchAll(db, sql: "SELECT * FROM task_filters WHERE deleted_at IS NULL ORDER BY sort_order, created_at")
            )
        }
    }
}
