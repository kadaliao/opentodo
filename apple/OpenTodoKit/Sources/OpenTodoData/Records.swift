// Reading and writing the domain models as rows. Columns are the
// snake_case forms of the Dart (drift) names; bools are 0 / 1; `tags` and
// `reminders` are JSON arrays in text columns, written the way Dart's
// `jsonEncode` writes them. Readers are lenient like the rest of the data
// layer: an unreadable JSON column, or an unknown status or priority
// number, reads as the default.

import Foundation
import GRDB

// MARK: - Columns

/// The sync columns every synced table has.
enum SyncColumn {
    static let createdAt = "created_at"
    static let updatedAt = "updated_at"
    static let deletedAt = "deleted_at"
    static let serverVersion = "server_version"
    static let dirty = "dirty"
}

/// Every kind of synced record, in the order the sync engine pushes them
/// (lists first so a task never arrives before its list; habits before
/// their check-ins). Adding a kind: a case here, its table, its record and
/// wire conversion; the engine, the dirty count and signing out follow.
enum SyncedTable: String, CaseIterable {
    case lists = "task_lists"
    case sections = "list_sections"
    case tasks = "tasks"
    case checklist = "checklist_items"
    case filters = "task_filters"
    case habits = "habits"
    case checkins = "habit_checkins"
    case focus = "focus_sessions"
    case countdowns = "countdowns"

    /// The record type name on the wire (`Entity`).
    var entity: String {
        switch self {
        case .lists: Entity.list
        case .sections: Entity.section
        case .tasks: Entity.task
        case .checklist: Entity.checklist
        case .filters: Entity.filter
        case .habits: Entity.habit
        case .checkins: Entity.checkin
        case .focus: Entity.focus
        case .countdowns: Entity.countdown
        }
    }

    init?(entity: String) {
        guard let t = SyncedTable.allCases.first(where: { $0.entity == entity }) else { return nil }
        self = t
    }

    /// Up to `limit` dirty rows, as they go out.
    func dirtyRecords(_ db: Database, limit: Int) throws -> [WireRecord] {
        func fetch<R: FetchableRecord>(_: R.Type, _ wire: (R) -> WireRecord) throws -> [WireRecord] {
            try R.fetchAll(db, sql: "SELECT * FROM \(rawValue) WHERE dirty = 1 LIMIT ?", arguments: [limit]).map(wire)
        }
        switch self {
        case .lists: return try fetch(TaskList.self, \.wire)
        case .sections: return try fetch(ListSection.self, \.wire)
        case .tasks: return try fetch(TodoTask.self, \.wire)
        case .checklist: return try fetch(ChecklistItem.self, \.wire)
        case .filters: return try fetch(TaskFilter.self, \.wire)
        case .habits: return try fetch(Habit.self, \.wire)
        case .checkins: return try fetch(HabitCheckin.self, \.wire)
        case .focus: return try fetch(FocusSession.self, \.wire)
        case .countdowns: return try fetch(Countdown.self, \.wire)
        }
    }

    /// Stores a record that came from the server.
    func store(_ db: Database, _ r: WireRecord) throws {
        switch self {
        case .lists: try TaskList(wire: r).upsert(db)
        case .sections: try ListSection(wire: r).upsert(db)
        case .tasks: try TodoTask(wire: r).upsert(db)
        case .checklist: try ChecklistItem(wire: r).upsert(db)
        case .filters: try TaskFilter(wire: r).upsert(db)
        case .habits: try Habit(wire: r).upsert(db)
        case .checkins: try HabitCheckin(wire: r).upsert(db)
        case .focus: try FocusSession(wire: r).upsert(db)
        case .countdowns: try Countdown(wire: r).upsert(db)
        }
    }
}

// MARK: - TaskList

extension TaskList: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.lists.rawValue

    public init(row: Row) {
        self.init(
            id: row["id"],
            name: row["name"],
            emoji: row["emoji"],
            color: row["color"],
            sortOrder: row["sort_order"],
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["emoji"] = emoji
        container["color"] = color
        container["sort_order"] = sortOrder
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

// MARK: - TodoTask

extension TodoTask: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.tasks.rawValue

    public init(row: Row) {
        let dueDate: String? = row["due_date"]
        self.init(
            id: row["id"],
            listId: row["list_id"],
            sectionId: row["section_id"],
            title: row["title"],
            content: row["content"],
            priority: Priority(clamping: row["priority"]),
            dueDate: dueDate.flatMap { Day($0) },
            dueTime: row["due_time"],
            duration: row["duration"],
            timeZone: row["time_zone"],
            tags: stringList(row["tags"]),
            status: TaskStatus(rawValue: row["status"]) ?? .open,
            completedAt: row["completed_at"],
            reminders: intList(row["reminders"]),
            repeatRule: row["repeat_rule"],
            repeatFrom: RepeatFrom(rawValue: row["repeat_from"]) ?? .dueDate,
            pinnedAt: row["pinned_at"],
            trashedAt: row["trashed_at"],
            sortOrder: row["sort_order"],
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["list_id"] = listId
        container["section_id"] = sectionId
        container["title"] = title
        container["content"] = content
        container["priority"] = priority.rawValue
        container["due_date"] = dueDate?.key
        container["due_time"] = dueTime
        container["duration"] = duration
        container["time_zone"] = timeZone
        container["tags"] = encodeList(tags.map(JSONValue.string))
        container["status"] = status.rawValue
        container["completed_at"] = completedAt
        container["reminders"] = encodeList(reminders.map(JSONValue.int))
        container["repeat_rule"] = repeatRule
        container["repeat_from"] = repeatFrom.rawValue
        container["pinned_at"] = pinnedAt
        container["trashed_at"] = trashedAt
        container["sort_order"] = sortOrder
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

extension TodoTask {
    /// The columns `init(positional:)` reads, in its order, for a SELECT.
    static let positionalColumns = """
        id, list_id, section_id, title, content, priority, due_date, due_time, duration, time_zone, tags, status, \
        completed_at, reminders, repeat_rule, repeat_from, pinned_at, trashed_at, sort_order, \
        created_at, updated_at, deleted_at, server_version, dirty
        """

    /// `init(row:)` for a row of `SELECT positionalColumns`: the same
    /// values, read by position rather than looked up by name (a snapshot
    /// reads thousands of rows; by name it took twice as long).
    init(positional row: Row) {
        let dueDate: String? = row[6]
        self.init(
            id: row[0], listId: row[1], sectionId: row[2], title: row[3], content: row[4],
            priority: Priority(clamping: row[5]), dueDate: dueDate.flatMap { Day($0) },
            dueTime: row[7], duration: row[8], timeZone: row[9], tags: stringList(row[10]),
            status: TaskStatus(rawValue: row[11]) ?? .open, completedAt: row[12], reminders: intList(row[13]),
            repeatRule: row[14], repeatFrom: RepeatFrom(rawValue: row[15]) ?? .dueDate,
            pinnedAt: row[16], trashedAt: row[17], sortOrder: row[18],
            createdAt: row[19], updatedAt: row[20], deletedAt: row[21], serverVersion: row[22], dirty: row[23]
        )
    }
}

// MARK: - ChecklistItem

extension ChecklistItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.checklist.rawValue

    public init(row: Row) {
        self.init(
            id: row["id"],
            taskId: row["task_id"],
            title: row["title"],
            done: row["done"],
            sortOrder: row["sort_order"],
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["task_id"] = taskId
        container["title"] = title
        container["done"] = done
        container["sort_order"] = sortOrder
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

extension ChecklistItem {
    /// The columns `init(positional:)` reads, in its order.
    static let positionalColumns = "id, task_id, title, done, sort_order, created_at, updated_at, deleted_at, server_version, dirty"

    /// `init(row:)` for a row of `SELECT positionalColumns`, by position.
    init(positional row: Row) {
        self.init(
            id: row[0], taskId: row[1], title: row[2], done: row[3], sortOrder: row[4],
            createdAt: row[5], updatedAt: row[6], deletedAt: row[7], serverVersion: row[8], dirty: row[9]
        )
    }
}

// MARK: - ListSection

extension ListSection: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.sections.rawValue

    public init(row: Row) {
        self.init(
            id: row["id"],
            listId: row["list_id"],
            name: row["name"],
            sortOrder: row["sort_order"],
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["list_id"] = listId
        container["name"] = name
        container["sort_order"] = sortOrder
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

// MARK: - TaskFilter

extension TaskFilter: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.filters.rawValue

    public init(row: Row) {
        self.init(
            id: row["id"],
            name: row["name"],
            rule: row["rule"],
            sortOrder: row["sort_order"],
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["rule"] = rule
        container["sort_order"] = sortOrder
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

// MARK: - Habit

extension Habit: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.habits.rawValue

    public init(row: Row) {
        let start: String = row["start_date"]
        let frequency: String = row["frequency"]
        self.init(
            id: row["id"],
            name: row["name"],
            emoji: row["emoji"],
            color: row["color"],
            goalKind: HabitGoalKind(rawValue: row["goal_kind"]) ?? .once,
            goal: row["goal"],
            step: row["step"],
            unit: row["unit"],
            frequency: HabitFrequency(rule: frequency),
            reminders: intList(row["reminders"]),
            startDate: Day(start) ?? Day(2000, 1, 1),
            section: HabitSection(rawValue: row["section"]) ?? .anytime,
            archivedAt: row["archived_at"],
            sortOrder: row["sort_order"],
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["emoji"] = emoji
        container["color"] = color
        container["goal_kind"] = goalKind.rawValue
        container["goal"] = goal
        container["step"] = step
        container["unit"] = unit
        container["frequency"] = frequency.rule
        container["reminders"] = encodeList(reminders.map(JSONValue.int))
        container["start_date"] = startDate.key
        container["section"] = section.rawValue
        container["archived_at"] = archivedAt
        container["sort_order"] = sortOrder
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

// MARK: - HabitCheckin

extension HabitCheckin: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.checkins.rawValue

    public init(row: Row) {
        let day: String = row["day"]
        self.init(
            id: row["id"] as String,
            habitId: row["habit_id"],
            day: Day(day) ?? Day(2000, 1, 1),
            value: row["value"],
            status: CheckinStatus(rawValue: row["status"]) ?? .partial,
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["habit_id"] = habitId
        container["day"] = day.key
        container["value"] = value
        container["status"] = status.rawValue
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

// MARK: - FocusSession

extension FocusSession: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.focus.rawValue

    public init(row: Row) {
        self.init(
            id: row["id"] as String,
            startedAt: row["started_at"],
            endedAt: row["ended_at"],
            duration: row["duration"],
            kind: FocusKind(rawValue: row["kind"]) ?? .pomodoro,
            completed: row["completed"],
            taskId: row["task_id"],
            habitId: row["habit_id"],
            note: row["note"],
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["started_at"] = startedAt
        container["ended_at"] = endedAt
        container["duration"] = duration
        container["kind"] = kind.rawValue
        container["completed"] = completed
        container["task_id"] = taskId
        container["habit_id"] = habitId
        container["note"] = note
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

// MARK: - Countdown

extension Countdown: FetchableRecord, PersistableRecord {
    public static let databaseTableName = SyncedTable.countdowns.rawValue

    public init(row: Row) {
        let date: String = row["date"]
        self.init(
            id: row["id"],
            title: row["title"],
            kind: CountdownKind(rawValue: row["kind"]) ?? .countdown,
            date: Day(date) ?? Day(2000, 1, 1),
            lunar: row["lunar"],
            repeats: CountdownRepeat(rawValue: row["repeats"]) ?? .none,
            emoji: row["emoji"],
            color: row["color"],
            showInToday: row["show_in_today"],
            reminders: intList(row["reminders"]),
            pinnedAt: row["pinned_at"],
            sortOrder: row["sort_order"],
            createdAt: row[SyncColumn.createdAt],
            updatedAt: row[SyncColumn.updatedAt],
            deletedAt: row[SyncColumn.deletedAt],
            serverVersion: row[SyncColumn.serverVersion],
            dirty: row[SyncColumn.dirty]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["title"] = title
        container["kind"] = kind.rawValue
        container["date"] = date.key
        container["lunar"] = lunar
        container["repeats"] = repeats.rawValue
        container["emoji"] = emoji
        container["color"] = color
        container["show_in_today"] = showInToday
        container["reminders"] = encodeList(reminders.map(JSONValue.int))
        container["pinned_at"] = pinnedAt
        container["sort_order"] = sortOrder
        encodeSync(createdAt, updatedAt, deletedAt, serverVersion, dirty, to: &container)
    }
}

// MARK: - Helpers

private func encodeSync(
    _ createdAt: Int, _ updatedAt: Int, _ deletedAt: Int?, _ serverVersion: Int, _ dirty: Bool,
    to container: inout PersistenceContainer
) {
    container[SyncColumn.createdAt] = createdAt
    container[SyncColumn.updatedAt] = updatedAt
    container[SyncColumn.deletedAt] = deletedAt
    container[SyncColumn.serverVersion] = serverVersion
    container[SyncColumn.dirty] = dirty
}

/// A JSON array as Dart's `jsonEncode` writes it: `["工作","重要"]`, `[0,-30]`.
func encodeList(_ items: [JSONValue]) -> String { JSONValue.array(items).encoded() }

/// `StringListConverter.fromSql`; non-strings are dropped.
func stringList(_ text: String?) -> [String] {
    // Most rows have none: skip the parser.
    if text == nil || text == "[]" { return [] }
    return text.flatMap(JSONValue.parse)?.arrayValue?.compactMap(\.stringValue) ?? []
}

/// `IntListConverter.fromSql`: numbers, truncated to integers.
func intList(_ text: String?) -> [Int] {
    if text == nil || text == "[]" { return [] }
    return text.flatMap(JSONValue.parse)?.arrayValue?.compactMap(\.intValue) ?? []
}
