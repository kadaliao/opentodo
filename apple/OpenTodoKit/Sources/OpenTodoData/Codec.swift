// Turns local rows into the records the sync server stores, and back;
// ported field by field from `app/lib/sync/codec.dart`.
//
// The wire format is spelled out field by field so it stays stable when
// columns are renamed, and old clients can read records written by newer
// ones: unknown fields are ignored, missing (or mistyped) ones fall back to
// defaults.
//
//     task.wire                      // taskToWire(task)
//     TodoTask(wire: record)         // wireToTask(record): clean, at the record's version

import Foundation

public enum Entity {
    public static let list = "list"
    public static let task = "task"
    public static let checklist = "checklist"
    public static let filter = "filter"
    public static let section = "section"
    // The efficiency module (schema 8).
    public static let habit = "habit"
    public static let checkin = "checkin"
    public static let focus = "focus"
    public static let countdown = "countdown"
}

/// One record as it travels to and from the server.
public struct WireRecord: Sendable, Hashable {
    public var entity: String
    public var id: String
    public var updatedAt: Int
    public var deletedAt: Int?
    /// The record's fields, in the order they are written.
    public var data: [(String, JSONValue)]
    /// The server's version of the record; 0 for one going out.
    public var version: Int

    public init(entity: String, id: String, updatedAt: Int, deletedAt: Int?, data: [(String, JSONValue)], version: Int = 0) {
        self.entity = entity
        self.id = id
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.data = data
        self.version = version
    }

    public static func == (lhs: WireRecord, rhs: WireRecord) -> Bool {
        lhs.json == rhs.json && lhs.version == rhs.version
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(json)
        hasher.combine(version)
    }

    /// `WireRecord.fromJson`. Nil when `entity`, `id` or `updatedAt` is
    /// missing or of the wrong type (Dart throws there).
    public init?(json j: JSONValue) {
        guard let entity = j["entity"]?.stringValue,
              let id = j["id"]?.stringValue,
              let updatedAt = j["updatedAt"]?.intValue
        else { return nil }
        let data = j["data"]?.pairs ?? []
        self.init(
            entity: entity,
            id: id,
            updatedAt: updatedAt,
            deletedAt: j["deletedAt"]?.intValue,
            data: data,
            version: j["version"]?.intValue ?? 0
        )
    }

    /// `toJson`: what is pushed. (The version isn't; the server assigns it.)
    public var json: JSONValue {
        .fields([
            ("entity", .string(entity)),
            ("id", .string(id)),
            ("updatedAt", .int(updatedAt)),
            ("deletedAt", JSONValue(deletedAt)),
            ("data", .fields(data)),
        ])
    }

    /// A field of `data` (nil if missing).
    public subscript(field: String) -> JSONValue? {
        data.last(where: { $0.0 == field })?.1
    }

    // Typed reads of `data`, each nil when the field is missing, null or
    // of another type.
    func string(_ f: String) -> String? { self[f]?.stringValue }
    func int(_ f: String) -> Int? { self[f]?.intValue }
    func double(_ f: String) -> Double { self[f]?.doubleValue ?? 0 }
    func bool(_ f: String) -> Bool? { self[f]?.boolValue }
    func day(_ f: String) -> Day? { string(f).flatMap { Day($0) } }
    func ints(_ f: String) -> [Int] { self[f]?.arrayValue?.compactMap(\.intValue) ?? [] }
    /// `createdAt`, or `updatedAt` for a record from before it was sent.
    var createdAt: Int { int("createdAt") ?? updatedAt }
}

// MARK: - To the wire

extension TaskList {
    public var wire: WireRecord {
        WireRecord(entity: Entity.list, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("name", .string(name)),
            ("emoji", JSONValue(emoji)),
            ("color", JSONValue(color)),
            ("sortOrder", .double(sortOrder)),
            ("createdAt", .int(createdAt)),
        ])
    }
}

extension TodoTask {
    public var wire: WireRecord {
        WireRecord(entity: Entity.task, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("listId", .string(listId)),
            ("sectionId", JSONValue(sectionId)),
            ("title", .string(title)),
            ("content", .string(content)),
            ("priority", .int(priority.rawValue)),
            ("dueDate", JSONValue(dueDate?.key)),
            ("dueTime", JSONValue(dueTime)),
            ("duration", JSONValue(duration)),
            ("timeZone", JSONValue(timeZone)),
            ("tags", .array(tags.map(JSONValue.string))),
            ("status", .int(status.rawValue)),
            ("completedAt", JSONValue(completedAt)),
            ("reminders", .array(reminders.map(JSONValue.int))),
            ("repeatRule", JSONValue(repeatRule)),
            ("repeatFrom", .int(repeatFrom.rawValue)),
            ("pinnedAt", JSONValue(pinnedAt)),
            ("trashedAt", JSONValue(trashedAt)),
            ("sortOrder", .double(sortOrder)),
            ("createdAt", .int(createdAt)),
        ])
    }
}

extension ChecklistItem {
    public var wire: WireRecord {
        WireRecord(entity: Entity.checklist, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("taskId", .string(taskId)),
            ("title", .string(title)),
            ("done", .bool(done)),
            ("sortOrder", .double(sortOrder)),
            ("createdAt", .int(createdAt)),
        ])
    }
}

extension ListSection {
    public var wire: WireRecord {
        WireRecord(entity: Entity.section, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("listId", .string(listId)),
            ("name", .string(name)),
            ("sortOrder", .double(sortOrder)),
            ("createdAt", .int(createdAt)),
        ])
    }
}

extension TaskFilter {
    /// The rule travels as a JSON object, not as the text it's stored in;
    /// text that isn't an object goes as `{}`.
    public var wire: WireRecord {
        let parsed = JSONValue.parse(rule)
        let object: JSONValue = parsed?.isObject == true ? parsed! : .fields([])
        return WireRecord(entity: Entity.filter, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("name", .string(name)),
            ("rule", object),
            ("sortOrder", .double(sortOrder)),
            ("createdAt", .int(createdAt)),
        ])
    }
}

// MARK: - From the wire
//
// A row that arrives from the server is in step with it: not dirty, at the
// record's version.

extension TaskList {
    public init(wire r: WireRecord) {
        self.init(
            id: r.id,
            name: r.string("name") ?? "",
            emoji: r.string("emoji"),
            color: r.int("color"),
            sortOrder: r.double("sortOrder"),
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}

extension TodoTask {
    public init(wire r: WireRecord) {
        self.init(
            id: r.id,
            listId: r.string("listId") ?? inboxListId,
            sectionId: r.string("sectionId"),
            title: r.string("title") ?? "",
            content: r.string("content") ?? "",
            priority: r.int("priority").map(Priority.init(clamping:)) ?? .none,
            dueDate: r.string("dueDate").flatMap { Day($0) },
            dueTime: r.int("dueTime"),
            duration: r.int("duration"),
            timeZone: r.string("timeZone"),
            tags: r["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            status: r.int("status").flatMap(TaskStatus.init(rawValue:)) ?? .open,
            completedAt: r.int("completedAt"),
            reminders: r["reminders"]?.arrayValue?.compactMap(\.intValue) ?? [],
            repeatRule: r.string("repeatRule"),
            repeatFrom: r.int("repeatFrom").flatMap(RepeatFrom.init(rawValue:)) ?? .dueDate,
            pinnedAt: r.int("pinnedAt"),
            trashedAt: r.int("trashedAt"),
            sortOrder: r.double("sortOrder"),
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}

extension ChecklistItem {
    public init(wire r: WireRecord) {
        self.init(
            id: r.id,
            taskId: r.string("taskId") ?? "",
            title: r.string("title") ?? "",
            done: r["done"]?.boolValue ?? false,
            sortOrder: r.double("sortOrder"),
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}

extension ListSection {
    public init(wire r: WireRecord) {
        self.init(
            id: r.id,
            listId: r.string("listId") ?? inboxListId,
            name: r.string("name") ?? "",
            sortOrder: r.double("sortOrder"),
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}

extension TaskFilter {
    /// A record without a rule, or with one that isn't an object, reads as
    /// `{}` (everything).
    public init(wire r: WireRecord) {
        let rule = r["rule"]
        self.init(
            id: r.id,
            name: r.string("name") ?? "",
            rule: rule?.isObject == true ? rule!.encoded() : "{}",
            sortOrder: r.double("sortOrder"),
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}

// MARK: - The efficiency module (schema 8)
//
// Same rules: every field spelled out, missing or mistyped ones read as the
// model's defaults, unknown enum numbers as the first case.

extension Habit {
    public var wire: WireRecord {
        WireRecord(entity: Entity.habit, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("name", .string(name)),
            ("emoji", JSONValue(emoji)),
            ("color", JSONValue(color)),
            ("goalKind", .int(goalKind.rawValue)),
            ("goal", .double(goal)),
            ("step", .double(step)),
            ("unit", .string(unit)),
            ("frequency", .string(frequency.rule)),
            ("reminders", .array(reminders.map(JSONValue.int))),
            ("startDate", .string(startDate.key)),
            ("section", .int(section.rawValue)),
            ("archivedAt", JSONValue(archivedAt)),
            ("sortOrder", .double(sortOrder)),
            ("createdAt", .int(createdAt)),
        ])
    }

    public init(wire r: WireRecord) {
        let defaults = Habit(id: r.id)
        self.init(
            id: r.id,
            name: r.string("name") ?? "",
            emoji: r.string("emoji"),
            color: r.int("color"),
            goalKind: r.int("goalKind").flatMap(HabitGoalKind.init(rawValue:)) ?? .once,
            goal: r["goal"]?.doubleValue ?? defaults.goal,
            step: r["step"]?.doubleValue ?? defaults.step,
            unit: r.string("unit") ?? "",
            frequency: HabitFrequency(rule: r.string("frequency") ?? ""),
            reminders: r.ints("reminders"),
            startDate: r.day("startDate") ?? Day(Date(timeIntervalSince1970: Double(r.createdAt) / 1000)),
            section: r.int("section").flatMap(HabitSection.init(rawValue:)) ?? .anytime,
            archivedAt: r.int("archivedAt"),
            sortOrder: r.double("sortOrder"),
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}

extension HabitCheckin {
    public var wire: WireRecord {
        WireRecord(entity: Entity.checkin, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("habitId", .string(habitId)),
            ("day", .string(day.key)),
            ("value", .double(value)),
            ("status", .int(status.rawValue)),
            ("createdAt", .int(createdAt)),
        ])
    }

    public init(wire r: WireRecord) {
        self.init(
            id: r.id,
            habitId: r.string("habitId") ?? "",
            day: r.day("day") ?? Day(2000, 1, 1),
            value: r.double("value"),
            status: r.int("status").flatMap(CheckinStatus.init(rawValue:)) ?? .partial,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}

extension FocusSession {
    public var wire: WireRecord {
        WireRecord(entity: Entity.focus, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("startedAt", .int(startedAt)),
            ("endedAt", .int(endedAt)),
            ("duration", .int(duration)),
            ("kind", .int(kind.rawValue)),
            ("completed", .bool(completed)),
            ("taskId", JSONValue(taskId)),
            ("habitId", JSONValue(habitId)),
            ("note", .string(note)),
            ("createdAt", .int(createdAt)),
        ])
    }

    public init(wire r: WireRecord) {
        let started = r.int("startedAt") ?? 0
        self.init(
            id: r.id,
            startedAt: started,
            endedAt: r.int("endedAt") ?? started,
            duration: r.int("duration") ?? 0,
            kind: r.int("kind").flatMap(FocusKind.init(rawValue:)) ?? .pomodoro,
            completed: r.bool("completed") ?? true,
            taskId: r.string("taskId"),
            habitId: r.string("habitId"),
            note: r.string("note") ?? "",
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}

extension Countdown {
    public var wire: WireRecord {
        WireRecord(entity: Entity.countdown, id: id, updatedAt: updatedAt, deletedAt: deletedAt, data: [
            ("title", .string(title)),
            ("kind", .int(kind.rawValue)),
            ("date", .string(date.key)),
            ("lunar", .bool(lunar)),
            ("repeats", .int(repeats.rawValue)),
            ("emoji", JSONValue(emoji)),
            ("color", JSONValue(color)),
            ("showInToday", .bool(showInToday)),
            ("reminders", .array(reminders.map(JSONValue.int))),
            ("pinnedAt", JSONValue(pinnedAt)),
            ("sortOrder", .double(sortOrder)),
            ("createdAt", .int(createdAt)),
        ])
    }

    public init(wire r: WireRecord) {
        self.init(
            id: r.id,
            title: r.string("title") ?? "",
            kind: r.int("kind").flatMap(CountdownKind.init(rawValue:)) ?? .countdown,
            date: r.day("date") ?? Day(2000, 1, 1),
            lunar: r.bool("lunar") ?? false,
            repeats: r.int("repeats").flatMap(CountdownRepeat.init(rawValue:)) ?? .none,
            emoji: r.string("emoji"),
            color: r.int("color"),
            showInToday: r.bool("showInToday") ?? false,
            reminders: r.ints("reminders"),
            pinnedAt: r.int("pinnedAt"),
            sortOrder: r.double("sortOrder"),
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            deletedAt: r.deletedAt,
            serverVersion: r.version,
            dirty: false
        )
    }
}
