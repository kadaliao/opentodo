// The efficiency module's storage: EfficiencyRepo, its rows, its wire
// format, and (with the Go server) two devices syncing it.

import Foundation
import GRDB
import Testing
@testable import OpenTodoData

struct EfficiencyFixture {
    let db: AppDatabase
    let clock: TestClock
    let repo: EfficiencyRepo

    init(clock: TestClock = TestClock()) throws {
        db = try AppDatabase.inMemory()
        self.clock = clock
        repo = EfficiencyRepo(db, clock: { clock.now })
    }

    func checkin(_ habitId: String, _ day: Day) async throws -> HabitCheckin? {
        try await db.writer.read { try HabitCheckin.fetchOne($0, key: HabitCheckin.id(habitId: habitId, day: day)) }
    }
}

private let d1115 = Day(2026, 11, 15)

@Suite struct EfficiencyRepoTests {
    let f: EfficiencyFixture
    var repo: EfficiencyRepo { f.repo }
    init() throws { f = try EfficiencyFixture() }

    @Test("a habit: added at the end, edited, ordered, archived, all stamped and dirty")
    func habits() async throws {
        let a = try await repo.addHabit(name: "喝水", goalKind: .count, goal: 8, unit: "杯", frequency: .weekdays([1, 3, 5]))
        f.clock.advance(seconds: 1)
        let b = try await repo.addHabit(name: "跑步", reminders: [7 * 60], section: .morning)
        var habits = try await f.db.observeHabits().first()
        #expect(habits.map(\.name) == ["喝水", "跑步"])
        #expect(habits[0].startDate == d1115) // today
        #expect(habits[0].frequency == .onWeekdays([1, 3, 5]))
        let allDirty = habits.allSatisfy { $0.dirty }
        #expect(allDirty)
        #expect(Array(a)[14] == "7")

        try await f.db.writer.write { try $0.execute(sql: "UPDATE habits SET dirty = 0") }
        f.clock.advance(minutes: 1)
        try await repo.updateHabit(a) { $0.goal = 6 }
        try await repo.setHabitOrders([b: -1])
        try await repo.setHabitArchived(a, true)
        habits = try await f.db.observeHabits().first()
        #expect(habits.map(\.name) == ["跑步", "喝水"])
        #expect(habits[1].goal == 6 && habits[1].archivedAt == f.clock.ms && habits[1].dirty && habits[1].updatedAt == f.clock.ms)
        try await repo.setHabitArchived(a, false)
        #expect(try await f.db.observeHabits().first()[1].archivedAt == nil)
    }

    @Test("check-ins: one row a day, counted up to the goal, taken back and brought back under the same id")
    func checkins() async throws {
        let h = try await repo.addHabit(name: "喝水", goalKind: .count, goal: 3, step: 1, unit: "杯")
        var c = try #require(try await repo.checkIn(h, on: d1115))
        #expect(c.value == 1 && c.status == .partial)
        #expect(c.id == uuidV5(namespace: habitCheckinNamespace, name: "\(h)/2026-11-15"))
        try await repo.checkIn(h, on: d1115, amount: 2)
        c = try #require(try await f.checkin(h, d1115))
        #expect(c.value == 3 && c.status == .done && c.dirty)
        let created = c.createdAt

        f.clock.advance(minutes: 1)
        try await repo.undoCheckin(h, on: d1115)
        #expect(try await f.checkin(h, d1115)?.deletedAt == f.clock.ms)
        #expect(try await f.db.observeCheckins(habitId: h).first().isEmpty)

        // Back again: same id, starting afresh.
        try await repo.checkIn(h, on: d1115)
        c = try #require(try await f.checkin(h, d1115))
        #expect(c.deletedAt == nil && c.value == 1 && c.createdAt == created)

        try await repo.setCheckinValue(h, on: d1115, value: 5)
        #expect(try await f.checkin(h, d1115)?.status == .done)
        try await repo.abandonDay(h, on: d1115 + 1)
        #expect(try await f.checkin(h, d1115 + 1)?.status == .abandoned)
        #expect(try await f.db.observeCheckins().first().count == 2)

        // A habit that isn't there takes no check-in.
        #expect(try await repo.checkIn("nope", on: d1115) == nil)
    }

    @Test("deleting a habit takes its check-ins with it")
    func deleteHabit() async throws {
        let h = try await repo.addHabit(name: "读书")
        try await repo.checkIn(h, on: d1115)
        try await repo.checkIn(h, on: d1115 + 1)
        try await repo.deleteHabit(h)
        #expect(try await f.db.observeHabits().first().isEmpty)
        #expect(try await f.db.observeCheckins().first().isEmpty)
        #expect(try await f.db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM habit_checkins WHERE deleted_at IS NOT NULL AND dirty = 1") } == 2)
    }

    @Test("a focus session saved twice is one row; edited; deleted")
    func focus() async throws {
        let start = f.clock.ms
        let s = FocusSession(startedAt: start, endedAt: start + 25 * 60_000, duration: 1500, kind: .pomodoro, taskId: "t")
        try await repo.saveFocusSession(s)
        let first = try #require(try await f.db.observeFocusSessions().first().first)
        f.clock.advance(minutes: 1)
        try await repo.saveFocusSession(s)
        let all = try await f.db.observeFocusSessions().first()
        #expect(all.count == 1)
        #expect(all[0].id == uuidV5(namespace: focusSessionNamespace, name: String(start)))
        #expect(all[0].createdAt == first.createdAt && all[0].updatedAt == f.clock.ms)

        try await repo.updateFocusSession(s.id) { $0.note = "写周报" }
        #expect(try await f.db.observeFocusSessions().first().first?.note == "写周报")
        try await repo.deleteFocusSession(s.id)
        #expect(try await f.db.observeFocusSessions().first().isEmpty)
        // Saving it again brings it back.
        try await repo.saveFocusSession(s)
        #expect(try await f.db.observeFocusSessions().first().count == 1)
    }

    @Test("countdowns: added, edited, pinned, deleted")
    func countdowns() async throws {
        let id = try await repo.addCountdown(title: "生日", kind: .birthday, date: Day(1990, 3, 1), lunar: true, repeats: .yearly, reminders: [-900])
        try await repo.updateCountdown(id) { $0.showInToday = true }
        try await repo.setCountdownPinned(id, true)
        let c = try #require(try await f.db.observeCountdowns().first().first)
        #expect(c.title == "生日" && c.kind == .birthday && c.lunar && c.repeats == .yearly && c.reminders == [-900])
        #expect(c.showInToday && c.pinnedAt == f.clock.ms && c.dirty)
        try await repo.setCountdownPinned(id, false)
        #expect(try await f.db.observeCountdowns().first().first?.pinnedAt == nil)
        try await repo.deleteCountdown(id)
        #expect(try await f.db.observeCountdowns().first().isEmpty)
    }

    @Test("many at once: one transaction, each row stamped and dirty, a row already there replaced keeping its createdAt")
    func insertAll() async throws {
        let first = try await repo.addHabit(id: "h1", name: "旧名字")
        let created = try #require(try await f.db.observeHabits().first().first).createdAt
        try await f.db.writer.write { try $0.execute(sql: "UPDATE habits SET dirty = 0, server_version = 7") }
        f.clock.advance(minutes: 1)
        let start = f.clock.ms - 3_600_000
        try await repo.insertAll(
            habits: [Habit(id: first, name: "喝水", goalKind: .count, goal: 8, startDate: d1115, sortOrder: 2),
                     Habit(id: "h2", name: "跑步", startDate: d1115, archivedAt: 5, sortOrder: 1)],
            checkins: [HabitCheckin(habitId: first, day: d1115, value: 3, status: .partial),
                       HabitCheckin(habitId: "h2", day: d1115 - 1, value: 0, status: .abandoned)],
            focusSessions: [FocusSession(startedAt: start, endedAt: start + 1_500_000, duration: 1500, kind: .pomodoro)],
            countdowns: [Countdown(id: "c1", title: "考试", date: d1115 + 10, pinnedAt: 9, sortOrder: 1)])

        let habits = try await f.db.writer.read { try Habit.order(Column("sort_order")).fetchAll($0) }
        #expect(habits.map(\.name) == ["跑步", "喝水"])
        #expect(habits[1].createdAt == created && habits[1].serverVersion == 7)
        #expect(habits[0].createdAt == f.clock.ms && habits[0].archivedAt == 5)
        let checkins = try await f.db.writer.read { try HabitCheckin.fetchAll($0) }
        let sessions = try await f.db.writer.read { try FocusSession.fetchAll($0) }
        let countdowns = try await f.db.writer.read { try Countdown.fetchAll($0) }
        #expect(checkins.count == 2 && sessions.count == 1 && countdowns.count == 1)
        // Taken as given: no status worked out again, the pin kept.
        #expect(try await f.checkin(first, d1115)?.status == .partial)
        #expect(countdowns[0].pinnedAt == 9)
        let stamps = habits.map(\.updatedAt) + checkins.map(\.updatedAt) + sessions.map(\.updatedAt) + countdowns.map(\.updatedAt)
        #expect(Set(stamps) == [f.clock.ms])
        let dirty = habits.map(\.dirty) + checkins.map(\.dirty) + sessions.map(\.dirty) + countdowns.map(\.dirty)
        #expect(!dirty.contains(false))
        #expect(try await f.db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM habit_checkins WHERE created_at = 0") } == 0)
    }

    @Test("the dirty count and signing out cover them")
    func dirtyAndClear() async throws {
        let h = try await repo.addHabit(name: "喝水")
        try await repo.checkIn(h, on: d1115)
        try await repo.saveFocusSession(FocusSession(startedAt: 1, endedAt: 2))
        try await repo.addCountdown(title: "x", date: d1115)
        #expect(try await f.db.observeDirtyCount().first() == 4)
        try await clearLocalData(f.db, tokens: KeyValueTokenStore(f.db))
        let left = try await f.db.writer.read { db in
            try ["habits", "habit_checkins", "focus_sessions", "countdowns"].map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? -1 }
        }
        #expect(left == [0, 0, 0, 0])
    }
}

@Suite struct EfficiencyCodecTests {
    func trip<R: Equatable>(_ r: R, _ wire: (R) -> WireRecord, _ back: (WireRecord) -> R) throws -> R {
        back(try OpenTodoDataTests.trip(wire(r), version: 4))
    }

    @Test("each kind survives the trip to the server and back")
    func roundTrips() throws {
        let h = Habit(id: "h", name: "喝水", emoji: "💧", color: 0xFF14A38B, goalKind: .count, goal: 8, step: 0.5, unit: "杯",
                      frequency: .timesPerWeek(3), reminders: [480, 1200], startDate: Day(2026, 11, 1), section: .evening,
                      archivedAt: 9, sortOrder: 3, createdAt: 1, updatedAt: 2)
        let c = HabitCheckin(habitId: "h", day: Day(2026, 11, 2), value: 2.5, status: .abandoned, createdAt: 1, updatedAt: 2, deletedAt: 3)
        let s = FocusSession(startedAt: 1000, endedAt: 9000, duration: 7, kind: .stopwatch, completed: true, taskId: "t", habitId: nil,
                             note: "备注", createdAt: 1, updatedAt: 2)
        let d = Countdown(id: "d", title: "纪念日", kind: .anniversary, date: Day(2020, 2, 29), lunar: false, repeats: .monthly,
                          emoji: "🎉", color: nil, showInToday: true, reminders: [-1440 + 540], pinnedAt: 5, sortOrder: 1, createdAt: 1, updatedAt: 2)
        func clean<T>(_ x: T, _ set: (inout T) -> Void) -> T { var x = x; set(&x); return x }

        #expect(try trip(h, \.wire, Habit.init(wire:)) == clean(h) { $0.dirty = false; $0.serverVersion = 4 })
        #expect(try trip(c, \.wire, HabitCheckin.init(wire:)) == clean(c) { $0.dirty = false; $0.serverVersion = 4 })
        #expect(try trip(s, \.wire, FocusSession.init(wire:)) == clean(s) { $0.dirty = false; $0.serverVersion = 4 })
        #expect(try trip(d, \.wire, Countdown.init(wire:)) == clean(d) { $0.dirty = false; $0.serverVersion = 4 })
        #expect(h.wire.entity == "habit" && c.wire.entity == "checkin" && s.wire.entity == "focus" && d.wire.entity == "countdown")
        #expect(c.wire.json.encoded() == #"{"entity":"checkin","id":"\#(c.id)","updatedAt":2,"deletedAt":3,"data":{"habitId":"h","day":"2026-11-02","value":2.5,"status":2,"createdAt":1}}"#)
    }

    @Test("missing fields fall back to defaults; unknown numbers to the first case")
    func defaults() throws {
        func record(_ entity: String, _ data: String) throws -> WireRecord {
            try #require(WireRecord(json: try JSONValue.decode(#"{"entity":"\#(entity)","id":"x","updatedAt":5,"deletedAt":null,"data":\#(data)}"#)))
        }
        let h = Habit(wire: try record("habit", #"{"name":"旧的","goalKind":9,"frequency":"nonsense","section":7}"#))
        #expect(h.name == "旧的" && h.goalKind == .once && h.goal == 1 && h.step == 1 && h.frequency == .daily && h.section == .anytime)
        #expect(h.createdAt == 5 && !h.dirty)
        let c = HabitCheckin(wire: try record("checkin", #"{"habitId":"h","day":"2026-11-02","status":5}"#))
        #expect(c.status == .partial && c.value == 0 && c.id == "x")
        let s = FocusSession(wire: try record("focus", #"{"startedAt":100}"#))
        #expect(s.endedAt == 100 && s.duration == 0 && s.kind == .pomodoro && s.completed && s.note == "")
        let d = Countdown(wire: try record("countdown", #"{"title":"x","date":"2027-01-01","kind":8,"repeats":9,"lunar":1}"#))
        #expect(d.date == Day(2027, 1, 1) && d.kind == .countdown && d.repeats == CountdownRepeat.none && !d.lunar && d.reminders == [])
    }
}

// MARK: - With the Go server

extension SyncIntegrationTests {
    @Test("habits, check-ins, focus and countdowns sync both ways; deletes travel")
    func efficiencySync() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)
        let p = EfficiencyRepo(phone.db, clock: { [clock = phone.clock] in clock.now })
        let m = EfficiencyRepo(mac.db, clock: { [clock = mac.clock] in clock.now })

        let h = try await p.addHabit(name: "喝水", goalKind: .count, goal: 8, unit: "杯")
        try await p.checkIn(h, on: d1115)
        let session = FocusSession(startedAt: phone.clock.ms, endedAt: phone.clock.ms + 1_500_000, duration: 1500)
        try await p.saveFocusSession(session)
        let cd = try await p.addCountdown(title: "生日", kind: .birthday, date: Day(1990, 3, 1), repeats: .yearly)
        #expect(try await phone.sync().pushed == 4)

        try await mac.sync()
        #expect(try await mac.db.observeHabits().first().map(\.name) == ["喝水"])
        #expect(try await mac.db.observeCheckins(habitId: h).first().map(\.value) == [1])
        #expect(try await mac.db.observeFocusSessions().first().map(\.id) == [session.id])
        #expect(try await mac.db.observeCountdowns().first().map(\.title) == ["生日"])
        #expect(try await mac.dirtyCount() == 0)

        // Edits from the Mac come back.
        mac.advance()
        try await m.checkIn(h, on: d1115)
        try await m.setCountdownPinned(cd, true)
        try await mac.sync()
        try await phone.sync()
        #expect(try await phone.db.observeCheckins(habitId: h).first().map(\.value) == [2])
        #expect(try await phone.db.observeCountdowns().first().first?.pinnedAt != nil)

        // Deletes travel, and the tombstones go once the server has them.
        phone.advance(minutes: 2)
        try await p.deleteHabit(h)
        try await p.deleteFocusSession(session.id)
        try await p.deleteCountdown(cd)
        try await phone.sync()
        try await mac.sync()
        #expect(try await mac.db.observeHabits().first().isEmpty)
        #expect(try await mac.db.observeCheckins().first().isEmpty)
        #expect(try await mac.db.observeFocusSessions().first().isEmpty)
        #expect(try await mac.db.observeCountdowns().first().isEmpty)
        let left = try await mac.db.writer.read { db in
            try ["habits", "habit_checkins", "focus_sessions", "countdowns"].map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? -1 }
        }
        #expect(left == [0, 0, 0, 0])
    }

    @Test("both devices checking in the same day offline end up with one check-in")
    func sameDayOffline() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)
        let p = EfficiencyRepo(phone.db, clock: { [clock = phone.clock] in clock.now })
        let m = EfficiencyRepo(mac.db, clock: { [clock = mac.clock] in clock.now })
        let h = try await p.addHabit(name: "跑步", goalKind: .count, goal: 5, unit: "公里")
        try await phone.sync()
        try await mac.sync()

        phone.advance(minutes: 1)
        try await p.checkIn(h, on: d1115, amount: 3)
        mac.advance(minutes: 2)
        try await m.checkIn(h, on: d1115, amount: 5)
        try await phone.sync()
        try await mac.sync()
        try await phone.sync()

        for d in [phone, mac] {
            let rows = try await d.db.writer.read { try HabitCheckin.fetchAll($0) }
            #expect(rows.count == 1)
            #expect(rows.first?.value == 5) // the later one
            #expect(rows.first?.status == .done)
            #expect(rows.first?.dirty == false)
        }
    }
}
