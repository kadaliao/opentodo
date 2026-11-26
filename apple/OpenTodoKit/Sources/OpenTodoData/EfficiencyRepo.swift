// Every write of the efficiency module (效率模块: habits, check-ins, focus
// sessions, countdowns; docs/apple.md §8), like `TaskRepo`: each stamps
// `updatedAt` with the clock and marks the row dirty, deletes leave
// tombstones for sync. Ids: new habits and countdowns get UUID v7; a
// check-in's id comes from its habit and day, a focus session's from its
// start (UUID v5, the domain's), so two devices recording the same thing
// offline end up with one row.
//
//     let eff = EfficiencyRepo(db, clock: { Date() })
//     let id = try await eff.addHabit(name: "喝水", goalKind: .count, goal: 8, unit: "杯")
//     try await eff.checkIn(id, on: today)            // +1 杯
//     try await eff.saveFocusSession(session)         // from FocusTimer
//     try await eff.insertAll(habits: hs, checkins: cs) // many at once, one transaction
//
// Reads are `AppDatabase.observeHabits()` and the rest.

import Foundation
import GRDB

/// The sync stamp every record carries.
protocol Stamped {
    var updatedAt: Int { get set }
    var deletedAt: Int? { get set }
    var dirty: Bool { get set }
}

extension Habit: Stamped {}
extension HabitCheckin: Stamped {}
extension FocusSession: Stamped {}
extension Countdown: Stamped {}

public final class EfficiencyRepo: Sendable {
    public let database: AppDatabase
    private let clock: @Sendable () -> Date
    public let timeZone: TimeZone

    public init(_ database: AppDatabase, clock: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .autoupdatingCurrent) {
        self.database = database
        self.clock = clock
        self.timeZone = timeZone
    }

    var now: Int { nowMilliseconds(clock()) }
    var today: Day { Day(clock(), in: timeZone) }

    private func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await database.writer.write(body)
    }

    /// Changes a row with `change`, stamping it; nothing if there's none.
    private func stamp<R: FetchableRecord & PersistableRecord & Stamped>(
        _ db: Database, _: R.Type, _ id: String, _ change: (inout R) -> Void
    ) throws {
        guard var r = try R.fetchOne(db, key: id) else { return }
        change(&r)
        r.updatedAt = now
        r.dirty = true
        try r.update(db)
    }

    private func tombstone<R: FetchableRecord & PersistableRecord & Stamped>(_ db: Database, _ type: R.Type, _ id: String) throws {
        let now = self.now
        try stamp(db, type, id) { $0.deletedAt = now }
    }

    // MARK: - Habits

    /// A new habit, at the end of the list; it starts today unless told.
    @discardableResult
    public func addHabit(
        id: String? = nil,
        name: String,
        emoji: String? = nil,
        color: Int? = nil,
        goalKind: HabitGoalKind = .once,
        goal: Double = 1,
        step: Double = 1,
        unit: String = "",
        frequency: HabitFrequency = .daily,
        reminders: [Int] = [],
        startDate: Day? = nil,
        section: HabitSection = .anytime
    ) async throws -> String {
        let id = id ?? Ids.newId(now: clock())
        let now = self.now
        let habit = Habit(
            id: id, name: name, emoji: emoji, color: color, goalKind: goalKind, goal: goal, step: step, unit: unit,
            frequency: frequency, reminders: reminders, startDate: startDate ?? today, section: section,
            sortOrder: Double(now), createdAt: now, updatedAt: now
        )
        try await write { try habit.insert($0) }
        return id
    }

    /// Edits a habit (name, goal, frequency, reminders, section…).
    public func updateHabit(_ id: String, _ change: @escaping @Sendable (inout Habit) -> Void) async throws {
        try await write { try self.stamp($0, Habit.self, id, change) }
    }

    /// Archives (归档) or brings back a habit; its history stays.
    public func setHabitArchived(_ id: String, _ archived: Bool) async throws {
        let now = self.now
        try await updateHabit(id) { $0.archivedAt = archived ? now : nil }
    }

    /// New order numbers from `planMove` (dragging habits).
    public func setHabitOrders(_ orders: [String: Double]) async throws {
        try await write { db in
            for (id, order) in orders { try self.stamp(db, Habit.self, id) { $0.sortOrder = order } }
        }
    }

    /// Deletes the habit and its check-ins (tombstones for sync). Focus
    /// sessions on it keep their record.
    public func deleteHabit(_ id: String) async throws {
        try await write { db in
            let now = self.now
            try self.stamp(db, Habit.self, id) { $0.deletedAt = now }
            try db.execute(
                sql: "UPDATE habit_checkins SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE habit_id = ? AND deleted_at IS NULL",
                arguments: [now, now, id]
            )
        }
    }

    // MARK: Check-ins

    /// A tap on `day`: a single check-in is done; a count adds `amount`
    /// (default the habit's step). Returns the day's check-in.
    @discardableResult
    public func checkIn(_ habitId: String, on day: Day, amount: Double? = nil) async throws -> HabitCheckin? {
        try await record(habitId, day) { h, existing, now in OpenTodoDomain.checkIn(h, on: day, existing: existing, amount: amount, now: now) }
    }

    /// Sets the day's amount (typed in); done when it reaches the goal.
    @discardableResult
    public func setCheckinValue(_ habitId: String, on day: Day, value: Double) async throws -> HabitCheckin? {
        try await record(habitId, day) { h, existing, now in OpenTodoDomain.setCheckinValue(h, on: day, existing: existing, value: value, now: now) }
    }

    /// Gives up on the day (放弃).
    @discardableResult
    public func abandonDay(_ habitId: String, on day: Day) async throws -> HabitCheckin? {
        try await record(habitId, day) { h, existing, now in OpenTodoDomain.abandonDay(h, on: day, existing: existing, now: now) }
    }

    /// Takes the day's check-in back (取消): a tombstone under the same id,
    /// which a later check-in brings back.
    public func undoCheckin(_ habitId: String, on day: Day) async throws {
        try await write { try self.tombstone($0, HabitCheckin.self, HabitCheckin.id(habitId: habitId, day: day)) }
    }

    private func record(
        _ habitId: String, _ day: Day,
        _ make: @escaping @Sendable (Habit, HabitCheckin?, Int) -> HabitCheckin
    ) async throws -> HabitCheckin? {
        try await write { db in
            guard let habit = try Habit.fetchOne(db, key: habitId), habit.deletedAt == nil else { return nil }
            let existing = try HabitCheckin.fetchOne(db, key: HabitCheckin.id(habitId: habitId, day: day))
            var c = make(habit, existing, self.now)
            c.dirty = true
            try c.upsert(db)
            return c
        }
    }

    // MARK: - Focus sessions

    /// Stores a session the timer produced (or one typed in). Its id comes
    /// from its start, so saving the same run twice keeps one row (the
    /// first save's `createdAt`); a deleted one comes back.
    public func saveFocusSession(_ session: FocusSession) async throws {
        let now = self.now
        try await write { db in
            var s = session
            let existing = try FocusSession.fetchOne(db, key: s.id)
            s.createdAt = existing?.createdAt ?? (s.createdAt == 0 ? now : s.createdAt)
            s.serverVersion = existing?.serverVersion ?? s.serverVersion
            s.updatedAt = now
            s.deletedAt = nil
            s.dirty = true
            try s.upsert(db)
        }
    }

    /// Edits a session (its note, task, length).
    public func updateFocusSession(_ id: String, _ change: @escaping @Sendable (inout FocusSession) -> Void) async throws {
        try await write { try self.stamp($0, FocusSession.self, id, change) }
    }

    public func deleteFocusSession(_ id: String) async throws {
        try await write { try self.tombstone($0, FocusSession.self, id) }
    }

    // MARK: - Countdowns

    @discardableResult
    public func addCountdown(
        id: String? = nil,
        title: String,
        kind: CountdownKind = .countdown,
        date: Day,
        lunar: Bool = false,
        repeats: CountdownRepeat = .none,
        emoji: String? = nil,
        color: Int? = nil,
        showInToday: Bool = false,
        reminders: [Int] = []
    ) async throws -> String {
        let id = id ?? Ids.newId(now: clock())
        let now = self.now
        let c = Countdown(
            id: id, title: title, kind: kind, date: date, lunar: lunar, repeats: repeats, emoji: emoji, color: color,
            showInToday: showInToday, reminders: reminders, sortOrder: Double(now), createdAt: now, updatedAt: now
        )
        try await write { try c.insert($0) }
        return id
    }

    public func updateCountdown(_ id: String, _ change: @escaping @Sendable (inout Countdown) -> Void) async throws {
        try await write { try self.stamp($0, Countdown.self, id, change) }
    }

    /// Pins (置顶) or unpins.
    public func setCountdownPinned(_ id: String, _ pinned: Bool) async throws {
        let now = self.now
        try await updateCountdown(id) { $0.pinnedAt = pinned ? now : nil }
    }

    public func deleteCountdown(_ id: String) async throws {
        try await write { try self.tombstone($0, Countdown.self, id) }
    }

    // MARK: - Many at once

    /// Writes whole records as they are, all in one transaction (an import,
    /// the demo data): each stamped like every other write — `updatedAt`
    /// now, dirty, not deleted, `createdAt` now when it has none — and
    /// replacing a row with the same id (keeping its `createdAt` and
    /// `serverVersion`). Nothing is worked out on the way: a check-in's
    /// status, archive and pin times, order numbers are taken as given.
    public func insertAll(
        habits: [Habit] = [], checkins: [HabitCheckin] = [],
        focusSessions: [FocusSession] = [], countdowns: [Countdown] = []
    ) async throws {
        let now = self.now
        try await write { db in
            try Self.put(db, habits, now: now)
            try Self.put(db, checkins, now: now)
            try Self.put(db, focusSessions, now: now)
            try Self.put(db, countdowns, now: now)
        }
    }

    private static func put<R: FetchableRecord & PersistableRecord & Stamped & Synced>(_ db: Database, _ records: [R], now: Int) throws {
        for var r in records {
            if let existing = try R.fetchOne(db, key: r.id) {
                r.createdAt = existing.createdAt
                r.serverVersion = existing.serverVersion
            } else if r.createdAt == 0 {
                r.createdAt = now
            }
            r.updatedAt = now
            r.deletedAt = nil
            r.dirty = true
            try r.upsert(db)
        }
    }
}

/// What `insertAll` keeps from a row it replaces.
protocol Synced {
    var id: String { get }
    var createdAt: Int { get set }
    var serverVersion: Int { get set }
}

extension Habit: Synced {}
extension HabitCheckin: Synced {}
extension FocusSession: Synced {}
extension Countdown: Synced {}
