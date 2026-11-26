// The synced records, one struct per table of `app/lib/data/db.dart`. Field
// names are the Dart (drift) names; the database columns are their
// snake_case forms, mapped in `OpenTodoData`.
//
// Every record carries the sync fields: `createdAt` / `updatedAt` are epoch
// milliseconds, `updatedAt` and `dirty` are set on every local write, the
// sync engine pushes dirty rows and clears the flag once the server has
// stored them under `serverVersion`, and `deletedAt` is the permanent
// tombstone (a row is not removed locally until the server has seen it).
//
// Each initializer gives every field a default, so tests write only what
// they care about: `TodoTask(id: "a", title: "买菜", dueDate: Day(2026, 11, 15))`.

/// The list every task without a list of its own belongs to. It has no row
/// in `task_lists`; the sidebar shows it as 收集箱.
public let inboxListId = "inbox"

public enum TaskStatus: Int, Sendable, Hashable, Codable, CaseIterable {
    case open = 0
    case done = 1
    case wontDo = 2

    /// Unknown numbers (from a newer client) read as open.
    public init(from decoder: any Decoder) throws {
        self = TaskStatus(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .open
    }
}

/// Ordered so a higher priority compares greater (and sorts first when
/// sorting descending), like the Dart numbers.
public enum Priority: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    /// Out-of-range numbers are clamped.
    public init(clamping raw: Int) {
        self = Priority(rawValue: min(max(raw, 0), 3))!
    }

    public init(from decoder: any Decoder) throws {
        self = Priority(clamping: try decoder.singleValueContainer().decode(Int.self))
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What a repeating task counts its next date from (`domain/recurrence.dart`).
public enum RepeatFrom: Int, Sendable, Hashable, Codable, CaseIterable {
    /// The task's own date: 每周一 stays on Mondays.
    case dueDate = 0
    /// The day it was completed: 完成后每3天.
    case completion = 1

    /// Unknown numbers read as `dueDate`.
    public init(from decoder: any Decoder) throws {
        self = RepeatFrom(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .dueDate
    }
}

/// A list (清单). `task_lists`.
public struct TaskList: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var emoji: String?
    /// ARGB, as Flutter's `Color.value`.
    public var color: Int?
    public var sortOrder: Double

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    public init(
        id: String,
        name: String = "",
        emoji: String? = nil,
        color: Int? = nil,
        sortOrder: Double = 0,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.color = color
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }
}

/// A task. `tasks`. (Not `Task`, which is Swift concurrency's.)
public struct TodoTask: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    /// `inboxListId` or a `TaskList` id.
    public var listId: String
    /// The `ListSection` (分组) the task sits in within its list; nil, or a
    /// section of another list, means none (未分组).
    public var sectionId: String?
    public var title: String
    public var content: String
    public var priority: Priority
    /// Calendar date in the task's own time zone. Dates float: a task due on
    /// the 18th stays on the 18th when the device travels.
    public var dueDate: Day?
    /// Minutes after midnight; nil means all day.
    public var dueTime: Int?
    /// For a task that spans a while (时间段), minutes from its start (the
    /// due date and time) to its end, which is exclusive. An all-day span is
    /// whole days: 2880 covers the due date and the day after. Nil for a
    /// task at one moment or on one day; see `Dates.swift`.
    public var duration: Int?
    public var timeZone: String?
    public var tags: [String]
    public var status: TaskStatus
    /// Epoch milliseconds.
    public var completedAt: Int?
    /// Minutes relative to the due moment, negative = before; see
    /// `Reminders.swift`.
    public var reminders: [Int]
    /// RRULE text (`Recurrence.swift`); nil for a one-off task.
    public var repeatRule: String?
    public var repeatFrom: RepeatFrom
    /// When the task was pinned (置顶) to the top of its list, epoch
    /// milliseconds; nil if it isn't.
    public var pinnedAt: Int?
    /// Set when the task is moved to the trash (it can be restored);
    /// different from the sync tombstone `deletedAt`, which is permanent.
    public var trashedAt: Int?
    public var sortOrder: Double

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    public init(
        id: String,
        listId: String = inboxListId,
        sectionId: String? = nil,
        title: String = "",
        content: String = "",
        priority: Priority = .none,
        dueDate: Day? = nil,
        dueTime: Int? = nil,
        duration: Int? = nil,
        timeZone: String? = nil,
        tags: [String] = [],
        status: TaskStatus = .open,
        completedAt: Int? = nil,
        reminders: [Int] = [],
        repeatRule: String? = nil,
        repeatFrom: RepeatFrom = .dueDate,
        pinnedAt: Int? = nil,
        trashedAt: Int? = nil,
        sortOrder: Double = 0,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id
        self.listId = listId
        self.sectionId = sectionId
        self.title = title
        self.content = content
        self.priority = priority
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.duration = duration
        self.timeZone = timeZone
        self.tags = tags
        self.status = status
        self.completedAt = completedAt
        self.reminders = reminders
        self.repeatRule = repeatRule
        self.repeatFrom = repeatFrom
        self.pinnedAt = pinnedAt
        self.trashedAt = trashedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }
}

/// One line of a task's checklist (子任务). `checklist_items`.
public struct ChecklistItem: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var taskId: String
    public var title: String
    public var done: Bool
    public var sortOrder: Double

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    public init(
        id: String,
        taskId: String = "",
        title: String = "",
        done: Bool = false,
        sortOrder: Double = 0,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id
        self.taskId = taskId
        self.title = title
        self.done = done
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }
}

/// A section (分组) of a list: a header in the list, a column on the board.
/// `list_sections`.
public struct ListSection: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    /// `inboxListId` or a `TaskList` id.
    public var listId: String
    public var name: String
    public var sortOrder: Double

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    public init(
        id: String,
        listId: String = inboxListId,
        name: String = "",
        sortOrder: Double = 0,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id
        self.listId = listId
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }
}

/// A saved filter (过滤器): a named rule that gathers tasks from anywhere.
/// `task_filters`. `rule` is the JSON text, as stored and synced; see
/// `Filters.swift`.
public struct TaskFilter: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var rule: String
    public var sortOrder: Double

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    public init(
        id: String,
        name: String = "",
        rule: String = "{}",
        sortOrder: Double = 0,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.rule = rule
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }
}
