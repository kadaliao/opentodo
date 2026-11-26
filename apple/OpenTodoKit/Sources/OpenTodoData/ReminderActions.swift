// What the buttons on a reminder do, ported from
// `app/lib/notify/reminder_actions.dart`. 完成 ticks the task off (a
// repeating one moves on to its next date); 稍后提醒 brings the reminder
// back after the snooze time set in 设置. Snoozes are kept on this device
// only, in `key_values` (`Keys.snoozes`: task id → epoch milliseconds).

import Foundation
import GRDB

/// Reminders put off with 稍后提醒: when each task's comes back.
public struct Snoozes: Sendable {
    public let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Damaged or missing: none.
    public func load() async throws -> [String: Date] {
        guard let raw = try await database.getValue(Keys.snoozes), let pairs = JSONValue.parse(raw)?.pairs else { return [:] }
        var out: [String: Date] = [:]
        for (taskId, value) in pairs {
            if case let .int(ms) = value { out[taskId] = Date(timeIntervalSince1970: Double(ms) / 1000) }
        }
        return out
    }

    private func save(_ snoozes: [String: Date]) async throws {
        let pairs = snoozes.sorted { $0.key < $1.key }.map { ($0.key, JSONValue.int(nowMilliseconds($0.value))) }
        try await database.setValue(Keys.snoozes, pairs.isEmpty ? nil : JSONValue.fields(pairs).encoded())
    }

    public func put(_ taskId: String, _ at: Date) async throws {
        var all = try await load()
        all[taskId] = at
        try await save(all)
    }

    public func remove(_ taskId: String) async throws {
        var all = try await load()
        if all.removeValue(forKey: taskId) != nil { try await save(all) }
    }

    /// The snoozes still to come; the ones that went off are dropped.
    public func upcoming(_ now: Date) async throws -> [String: Date] {
        let all = try await load()
        let ahead = all.filter { $0.value > now }
        if ahead.count != all.count { try await save(ahead) }
        return ahead
    }
}

/// Carries out a button press. Opening a reminder is the app's business,
/// not this.
public func applyReminderAction(
    _ repo: TaskRepo,
    _ snoozes: Snoozes,
    _ r: ReminderResponse,
    now: Date,
    snoozeMinutes: Int
) async throws {
    switch r.action {
    case .done:
        // It may have been finished or deleted elsewhere in the meantime.
        if let t = try await repo.getTask(r.taskId), t.status == .open, t.trashedAt == nil, t.deletedAt == nil {
            try await repo.setCompleted(t.id, true)
        }
        try await snoozes.remove(r.taskId)
    case .snooze:
        try await snoozes.put(r.taskId, now.addingTimeInterval(TimeInterval(snoozeMinutes * 60)))
    case .open:
        break
    }
}

/// Everything reminders are worked out from: the tasks, and the efficiency
/// module's habits (with their recent check-ins) and countdowns.
public struct ReminderSources: Sendable, Equatable {
    public var tasks: [TodoTask]
    public var habits: [Habit]
    public var checkins: [HabitCheckin]
    public var countdowns: [Countdown]

    public init(tasks: [TodoTask] = [], habits: [Habit] = [], checkins: [HabitCheckin] = [], countdowns: [Countdown] = []) {
        self.tasks = tasks
        self.habits = habits
        self.checkins = checkins
        self.countdowns = countdowns
    }

    /// As stored, with the check-ins from `since` on (this week's are
    /// what decide whether a habit still needs reminding).
    static func fetch(_ db: Database, since: Day) throws -> ReminderSources {
        ReminderSources(
            tasks: try TodoTask.fetchAll(db, sql: "SELECT * FROM tasks WHERE deleted_at IS NULL"),
            habits: try Habit.fetchAll(db, sql: "SELECT * FROM habits WHERE deleted_at IS NULL AND archived_at IS NULL"),
            checkins: try HabitCheckin.fetchAll(
                db, sql: "SELECT * FROM habit_checkins WHERE deleted_at IS NULL AND day >= ?", arguments: [since.key]
            ),
            countdowns: try Countdown.fetchAll(db, sql: "SELECT * FROM countdowns WHERE deleted_at IS NULL")
        )
    }
}

/// The reminders everything calls for at `now`, the tasks' snoozes included.
func reminderEvents(_ sources: ReminderSources, now: Date, snoozed: [String: Date], timeZone: TimeZone) -> [ReminderEvent] {
    upcomingReminders(
        tasks: sources.tasks, habits: sources.habits, checkins: sources.checkins, countdowns: sources.countdowns,
        now: LocalDateTime(now, in: timeZone),
        snoozed: snoozed.mapValues { LocalDateTime($0, in: timeZone) }
    )
}

/// The tasks' reminders alone.
func reminderEvents(_ tasks: [TodoTask], now: Date, snoozed: [String: Date], timeZone: TimeZone) -> [ReminderEvent] {
    reminderEvents(ReminderSources(tasks: tasks), now: now, snoozed: snoozed, timeZone: timeZone)
}

/// A button press handled on its own, without a `ReminderController` (an
/// extension, or code that runs before the app's model is up): the action,
/// then the system's reminders brought in line (the task's later ones go
/// when it's done; a snooze is handed over). Flutter's
/// `runReminderActionAlone`.
public func runReminderAction(
    _ database: AppDatabase,
    _ backend: any ReminderBackend,
    _ r: ReminderResponse,
    now: Date,
    timeZone: TimeZone = .current
) async throws {
    let settings = try AppSettings.load(database)
    let snoozes = Snoozes(database)
    let repo = TaskRepo(database, clock: { now }, defaults: { settings.defaults }, timeZone: timeZone)
    try await applyReminderAction(repo, snoozes, r, now: now, snoozeMinutes: settings.snoozeMinutes)
    let since = Day(now, in: timeZone).startOfWeek
    let sources = try await database.writer.read { try ReminderSources.fetch($0, since: since) }
    // Notifications are allowed: one of them was just pressed.
    try await ReminderScheduler(backend, allowed: true, timeZone: timeZone)
        .apply(reminderEvents(sources, now: now, snoozed: try await snoozes.upcoming(now), timeZone: timeZone))
}
