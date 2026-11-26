// Port of app/test/reminder_scheduler_test.dart and
// reminder_actions_test.dart, plus ReminderController (reminder_providers.dart).

import Foundation
import Testing
@testable import OpenTodoData

private func event(_ task: String, _ hour: Int, title: String? = nil) -> ReminderEvent {
    ReminderEvent(taskId: task, at: LocalDateTime(2026, 11, 16, hour), title: title ?? task, body: "明天")
}

@Suite struct ReminderSchedulerTests {
    @Test("only what changed is touched")
    func onlyChanges() async throws {
        let backend = MemoryReminderBackend()
        let s = ReminderScheduler(backend)

        try await s.apply([event("a", 9), event("b", 10)])
        #expect(backend.log == ["schedule a", "schedule b"])

        backend.clearLog()
        try await s.apply([event("a", 9), event("b", 10)])
        #expect(backend.log.isEmpty)

        // b renamed, a moved, c new.
        backend.clearLog()
        try await s.apply([event("a", 11), event("b", 10, title: "B"), event("c", 12)])
        #expect(backend.log == ["cancel a", "cancel b", "schedule a", "schedule B", "schedule c"])

        backend.clearLog()
        try await s.apply([])
        #expect(Set(backend.log) == ["cancel a", "cancel B", "cancel c"])
        #expect(backend.scheduled.isEmpty)
    }

    @Test("permission is asked once there is something to remind about")
    func permission() async throws {
        let backend = MemoryReminderBackend(allow: false)
        let s = ReminderScheduler(backend)
        try await s.apply([])
        #expect(backend.permissionRequests == 0)
        #expect(await s.allowed == nil)

        try await s.apply([event("a", 9)])
        try await s.apply([event("a", 9)])
        #expect(backend.permissionRequests == 1)
        #expect(await s.allowed == false)

        // Back from Settings with notifications turned on.
        backend.allow = true
        await s.recheckPermission()
        try await s.apply([event("a", 9)])
        #expect(backend.permissionRequests == 2)
        #expect(await s.allowed == true)
    }

    @Test("replacing all hands every reminder over again")
    func replaceAll() async throws {
        let system = MemoryReminderBackend()
        let s = ReminderScheduler(system)
        let e = ReminderEvent(taskId: "t", at: LocalDateTime(2026, 11, 17, 9), title: "t", body: "明天")
        try await s.apply([e])
        system.clearLog()
        try await s.apply([e])
        #expect(system.log.isEmpty)
        try await s.apply([e], replaceAll: true)
        #expect(system.log == ["cancel t", "schedule t"])
        // Handed over as the moment the wall-clock time names here.
        #expect(system.scheduled.single?.at == LocalDateTime(2026, 11, 17, 9).date())
    }
}

extension Array {
    var single: Element? { count == 1 ? first : nil }
}

@Suite struct ReminderActionTests {
    let now = LocalDateTime(2026, 11, 16, 15).date() // Monday 15:00
    let f: RepoFixture
    var db: AppDatabase { f.db }
    var repo: TaskRepo { f.repo }

    init() throws {
        f = try RepoFixture(clock: TestClock(LocalDateTime(2026, 11, 16, 15).date()))
    }

    @Test("responses from a notification's userInfo: the Swift version's, and the ones the Flutter version left (task id as `payload`)")
    func responsesFromUserInfo() {
        #expect(reminderResponse(userInfo: ["taskId": "t", "kind": "task"], actionIdentifier: "done") == ReminderResponse(taskId: "t", action: .done))
        #expect(reminderResponse(userInfo: ["taskId": "h", "kind": "habit"], actionIdentifier: "done") == ReminderResponse(taskId: "h", action: .open, kind: .habit))
        // flutter_local_notifications keeps the payload under "payload" (and
        // its own id under "NotificationId"); the Swift version kept those
        // pending notifications when title and body matched.
        #expect(reminderResponse(userInfo: ["NotificationId": 123, "payload": "t"], actionIdentifier: "done") == ReminderResponse(taskId: "t", action: .done))
        #expect(reminderResponse(userInfo: ["payload": "t"], actionIdentifier: "snooze") == ReminderResponse(taskId: "t", action: .snooze))
        #expect(reminderResponse(userInfo: ["payload": NSNull()], actionIdentifier: "done") == nil)
        #expect(reminderResponse(userInfo: [:], actionIdentifier: "done") == nil)
    }

    @Test("responses: a click opens, the buttons are done and snooze")
    func responses() {
        #expect(reminderResponse(taskId: "t", actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier") == ReminderResponse(taskId: "t", action: .open))
        #expect(reminderResponse(taskId: "t", actionIdentifier: "done") == ReminderResponse(taskId: "t", action: .done))
        #expect(reminderResponse(taskId: "t", actionIdentifier: "snooze") == ReminderResponse(taskId: "t", action: .snooze))
        #expect(reminderResponse(taskId: "t", actionIdentifier: "default") == ReminderResponse(taskId: "t", action: .open))
        #expect(reminderResponse(taskId: nil, actionIdentifier: "done") == nil)
        #expect(reminderResponse(taskId: "", actionIdentifier: "default") == nil)
        #expect(reminderResponse(taskId: "t", actionIdentifier: "com.apple.UNNotificationDismissActionIdentifier") == nil)
        // Habits and countdowns have no buttons: whatever comes, it opens them.
        #expect(reminderResponse(taskId: "h", kind: "habit", actionIdentifier: "done") == ReminderResponse(taskId: "h", action: .open, kind: .habit))
        #expect(reminderResponse(taskId: "c", kind: "countdown", actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier")
            == ReminderResponse(taskId: "c", action: .open, kind: .countdown))
        #expect(reminderResponse(taskId: "t", kind: "something new", actionIdentifier: "done")?.kind == .task)
        // (Dart's encode/decodeReminderResponse carried a press between
        // isolates; the native app handles it in its own process.)
    }

    @Test("snoozes are kept until they go off")
    func snoozes() async throws {
        let s = Snoozes(db)
        try await s.put("a", now + 600)
        try await s.put("b", now - 60)
        #expect(Set(try await s.load().keys) == ["a", "b"])
        #expect(Set(try await s.upcoming(now).keys) == ["a"])
        #expect(Set(try await s.load().keys) == ["a"], "b went off and is dropped")
        #expect(try await db.getValue(Keys.snoozes) == "{\"a\":\(nowMilliseconds(now + 600))}")
        try await s.remove("a")
        #expect(try await db.getValue(Keys.snoozes) == nil)
        // Damaged: nothing, not an error.
        try await db.setValue(Keys.snoozes, "nonsense")
        #expect(try await s.load().isEmpty)
    }

    @Test("a snooze comes back as a reminder while its task is open")
    func snoozeComesBack() async throws {
        let open = try await f.task(try await repo.addTask(title: "开会", dueDate: Day(2026, 11, 16), dueTime: 900))
        var done = try await f.task(try await repo.addTask(title: "已完成", dueDate: Day(2026, 11, 16)))
        done.status = .done
        let later = now + 15 * 60
        let events = reminderEvents([open, done], now: now, snoozed: [open.id: later, done.id: later, "gone": later], timeZone: .current)
        #expect(events.map { "\($0.title) \($0.at)" } == ["开会 \(LocalDateTime(later))"])
        #expect(events.single?.body == "今天, 下午3:00")
        // One that went off is no reminder.
        #expect(reminderEvents([open], now: now, snoozed: [open.id: now], timeZone: .current).isEmpty)
    }

    // MARK: On its own (Dart: in the background, with the app not running)

    func scheduleAll(_ system: MemoryReminderBackend, at: Date) async throws {
        let tasks = try await db.observeTasks().first()
        try await ReminderScheduler(system).apply(reminderEvents(tasks, now: at, snoozed: [:], timeZone: .current))
    }

    @Test("完成 ticks the task off and takes back its later reminders")
    func doneAlone() async throws {
        let system = MemoryReminderBackend()
        let id = try await repo.addTask(title: "交报告", dueDate: Day(2026, 11, 16), dueTime: 16 * 60, reminders: [-60, 0])
        try await scheduleAll(system, at: now - 2 * 3600)
        #expect(system.scheduled.count == 2)

        // The 15:00 one went off and 完成 was pressed on it.
        try await runReminderAction(db, system, ReminderResponse(taskId: id, action: .done), now: now)
        #expect(try await f.task(id).status == .done)
        #expect(system.scheduled.isEmpty)
    }

    @Test("完成 on a repeating task moves it on, with its next reminder")
    func doneRepeating() async throws {
        let system = MemoryReminderBackend()
        let id = try await repo.addTask(title: "吃药", dueDate: Day(2026, 11, 16), dueTime: 15 * 60, reminders: [0], repeatRule: "FREQ=DAILY")
        try await runReminderAction(db, system, ReminderResponse(taskId: id, action: .done), now: now)
        let t = try await f.task(id)
        #expect(t.status == .open && t.dueDate == Day(2026, 11, 17))
        #expect(system.scheduled.single?.at == LocalDateTime(2026, 11, 17, 15).date())
    }

    @Test("稍后提醒 hands over a reminder after the snooze time from the settings")
    func snoozeAlone() async throws {
        let system = MemoryReminderBackend()
        let id = try await repo.addTask(title: "回电话", dueDate: Day(2026, 11, 16), dueTime: 15 * 60, reminders: [0])
        try await db.setValue(Keys.settings, #"{"snoozeMinutes":10}"#)
        try await runReminderAction(db, system, ReminderResponse(taskId: id, action: .snooze), now: now)
        let e = try #require(system.scheduled.single)
        #expect(e.title == "回电话" && e.at == LocalDateTime(2026, 11, 16, 15, 10).date())
        #expect(system.permissionRequests == 0, "no asking: a notification was just pressed")
        #expect(try await Snoozes(db).load()[id] == LocalDateTime(2026, 11, 16, 15, 10).date())

        // Done before it comes back: the snooze goes too.
        try await runReminderAction(db, system, ReminderResponse(taskId: id, action: .done), now: now)
        #expect(system.scheduled.isEmpty)
        #expect(try await Snoozes(db).load().isEmpty)
    }

    @Test("a task finished or deleted elsewhere is left alone")
    func leftAlone() async throws {
        let system = MemoryReminderBackend()
        let id = try await repo.addTask(title: "旧的", dueDate: Day(2026, 11, 16))
        try await repo.setCompleted(id, true)
        let before = try await f.task(id).updatedAt
        f.clock.advance(minutes: 1)
        try await runReminderAction(db, system, ReminderResponse(taskId: id, action: .done), now: now + 60)
        #expect(try await f.task(id).updatedAt == before)
        try await runReminderAction(db, system, ReminderResponse(taskId: "nope", action: .done), now: now)
    }
}

// MARK: - ReminderController

/// Waits (up to five seconds) for `condition`.
@MainActor
func eventually(_ condition: () async throws -> Bool) async rethrows -> Bool {
    for _ in 0 ..< 500 {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return try await condition()
}

@Suite @MainActor struct ReminderControllerTests {
    let clock = TestClock(LocalDateTime(2026, 11, 16, 15).date())

    func make(_ system: MemoryReminderBackend, settings: AppSettings = AppSettings()) throws -> (ReminderController, TaskRepo, AppDatabase) {
        let db = try AppDatabase.inMemory()
        let repo = TaskRepo(db, clock: { [clock] in clock.now })
        let c = ReminderController(db, repo: repo, backend: system, settings: { settings }, clock: { [clock] in clock.now },
                                   debounce: .milliseconds(20), refresh: .seconds(3600))
        return (c, repo, db)
    }

    @Test("tasks changing reschedule; the format is recorded once everything is handed over")
    func reschedules() async throws {
        let system = MemoryReminderBackend()
        let (c, repo, db) = try make(system)
        await c.start()
        defer { c.stop() }
        let id = try await repo.addTask(title: "开会", dueDate: Day(2026, 11, 16), dueTime: 16 * 60, reminders: [0, -30])
        #expect(await eventually { system.scheduled.count == 2 })
        #expect(await eventually { c.allowed == true })
        #expect(try await db.getValue(Keys.reminderFormat) == ReminderController.reminderFormat)

        try await repo.setTitle(id, "开大会")
        #expect(await eventually { system.scheduled.map(\.title) == ["开大会", "开大会"] })
        try await repo.trashTask(id)
        #expect(await eventually { system.scheduled.isEmpty })
    }

    @Test("an older format is replaced as a whole")
    func olderFormat() async throws {
        let system = MemoryReminderBackend()
        let (c, repo, db) = try make(system)
        _ = try await repo.addTask(title: "开会", dueDate: Day(2026, 11, 16), dueTime: 16 * 60, reminders: [0])
        // What an earlier version left: the same reminder, the old format.
        try await ReminderScheduler(system, allowed: true).apply(reminderEvents(try await db.observeTasks().first(), now: clock.now, snoozed: [:], timeZone: .current))
        try await db.setValue(Keys.reminderFormat, "1")
        system.clearLog()
        await c.start()
        defer { c.stop() }
        #expect(await eventually { system.log == ["cancel 开会", "schedule 开会"] })
        #expect(try await eventually { try await db.getValue(Keys.reminderFormat) == "2" })

        // From then on, only changes.
        system.clearLog()
        c.appDidBecomeActive()
        try await Task.sleep(for: .milliseconds(100))
        #expect(system.log.isEmpty)
    }

    @Test("a click asks the UI to show the task; the buttons act on it")
    func responses() async throws {
        let system = MemoryReminderBackend()
        let (c, repo, db) = try make(system, settings: AppSettings(snoozeMinutes: 5))
        await c.start()
        defer { c.stop() }
        let id = try await repo.addTask(title: "回电话", dueDate: Day(2026, 11, 16), dueTime: 15 * 60, reminders: [0])

        await system.respond(ReminderResponse(taskId: id, action: .open))
        #expect(await eventually { c.openRequest == .task(id) })
        c.openRequest = nil

        await system.respond(ReminderResponse(taskId: id, action: .snooze))
        #expect(await eventually { system.scheduled.map(\.at) == [LocalDateTime(2026, 11, 16, 15, 5).date()] })

        await system.respond(ReminderResponse(taskId: id, action: .done))
        #expect(await eventually { (try? await repo.getTask(id))?.status == .done })
        #expect(await eventually { system.scheduled.isEmpty })
        #expect(try await Snoozes(db).load().isEmpty)
    }

    @Test("refused, then allowed in Settings: asked again on coming back")
    func refused() async throws {
        let system = MemoryReminderBackend(allow: false)
        let (c, repo, _) = try make(system)
        await c.start()
        defer { c.stop() }
        _ = try await repo.addTask(title: "开会", dueDate: Day(2026, 11, 16), dueTime: 16 * 60, reminders: [0])
        #expect(await eventually { c.allowed == false })
        system.allow = true
        c.appDidBecomeActive()
        #expect(await eventually { c.allowed == true })
        #expect(system.permissionRequests == 2)
    }

    @Test("habits and countdowns remind too; checking in takes today's back; a click opens the page")
    func efficiency() async throws {
        let system = MemoryReminderBackend()
        let (c, repo, db) = try make(system)
        let eff = EfficiencyRepo(db, clock: { [clock] in clock.now })
        await c.start()
        defer { c.stop() }
        // Monday 15:00: the habit reminds at 16:00 today and on, the
        // countdown the day before at 9:00.
        let h = try await eff.addHabit(name: "喝水", reminders: [16 * 60])
        let cd = try await eff.addCountdown(title: "生日", date: Day(2026, 11, 20), reminders: [countdownReminder(daysBefore: 1, minute: 540)])
        _ = try await repo.addTask(title: "开会", dueDate: Day(2026, 11, 16), dueTime: 17 * 60, reminders: [0])
        #expect(await eventually { system.scheduled.count == 7 + 1 + 1 })
        let kinds = system.scheduled.map(\.kind)
        #expect(kinds.filter { $0 == .habit }.count == 7 && kinds.contains(.countdown) && kinds.contains(.task))
        #expect(system.scheduled.first { $0.kind == .countdown }?.at == LocalDateTime(2026, 11, 19, 9).date())

        try await eff.checkIn(h, on: Day(2026, 11, 16))
        #expect(await eventually { system.scheduled.filter { $0.kind == .habit }.count == 6 })
        #expect(!system.scheduled.contains { $0.kind == .habit && $0.at == LocalDateTime(2026, 11, 16, 16).date() })

        await system.respond(ReminderResponse(taskId: h, action: .open, kind: .habit))
        #expect(await eventually { c.openRequest == .habit(h) })
        await system.respond(ReminderResponse(taskId: cd, action: .open, kind: .countdown))
        #expect(await eventually { c.openRequest == .countdown(cd) })
    }
}
