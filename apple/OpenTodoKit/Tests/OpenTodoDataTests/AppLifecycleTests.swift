// The background: the database suspended, and woken (with a background
// task) for a notification button, which is done before the system hears
// back. The hooks are recorded: GRDB's real suspension is process-wide and
// would stop the other suites' databases running alongside.

import Foundation
import Testing
@testable import OpenTodoData

@MainActor
final class LifecycleLog {
    var events: [String] = []
    private var next = 0

    var hooks: AppLifecycle.Hooks {
        AppLifecycle.Hooks(
            suspendDatabase: { self.events.append("suspend") },
            resumeDatabase: { self.events.append("resume") },
            beginTask: { name in self.next += 1; self.events.append("begin \(name)"); return self.next },
            endTask: { id in self.events.append("end \(id)") }
        )
    }
}

@Suite @MainActor struct AppLifecycleTests {
    @Test("background suspends; awake resumes, runs, suspends again, inside a background task")
    func awake() async {
        let log = LifecycleLog()
        let l = AppLifecycle(hooks: log.hooks)
        l.enterBackground()
        l.enterBackground() // once
        let value = await l.awake("提醒按钮") { () async -> Int in
            log.events.append("work")
            return 7
        }
        #expect(value == 7)
        #expect(log.events == ["suspend", "begin 提醒按钮", "resume", "work", "suspend", "end 1"])

        // In the foreground there is nothing to resume or suspend.
        log.events = []
        l.enterForeground()
        await l.awake("x") { log.events.append("work") }
        #expect(log.events == ["resume", "begin x", "work", "end 2"])
    }

    @Test("coming to the front during the work: not suspended after; nested work suspends once")
    func overlapping() async {
        let log = LifecycleLog()
        let l = AppLifecycle(hooks: log.hooks)
        l.enterBackground()
        await l.awake("a") {
            await l.awake("b") { log.events.append("inner") }
            log.events.append("outer")
        }
        #expect(log.events == ["suspend", "begin a", "resume", "begin b", "inner", "end 2", "outer", "suspend", "end 1"])

        log.events = []
        await l.awake("c") {
            l.enterForeground() // the person opened the app meanwhile
            log.events.append("work")
        }
        #expect(log.events == ["begin c", "resume", "work", "end 3"])
        #expect(!l.inBackground)

        // Going to the background during the work suspends at its end.
        log.events = []
        await l.awake("d") {
            l.enterBackground()
            log.events.append("work")
        }
        #expect(log.events == ["begin d", "work", "suspend", "end 4"])
    }

    @Test("a button pressed in the background is written, rescheduled and the database suspended again before the system hears back")
    func buttonInBackground() async throws {
        let log = LifecycleLog()
        let clock = TestClock(LocalDateTime(2026, 11, 16, 15).date())
        let system = MemoryReminderBackend(allow: true, asked: true)
        let services = AppServices(database: try AppDatabase.inMemory(), tokens: MemoryTokenStore(), reminderBackend: system,
                                   clock: { clock.now }, lifecycleHooks: log.hooks)
        await services.start(seed: false)
        defer { services.reminders.stop() }
        let id = try await services.repo.addTask(title: "交报告", dueDate: Day(2026, 11, 16), dueTime: 16 * 60, reminders: [-30, 0])
        #expect(await eventually { system.scheduled.count == 2 })

        services.lifecycle.enterBackground()
        #expect(log.events == ["suspend"])

        // 完成 on the 15:30 one. When `respond` returns (the system's
        // completion handler), everything is done: no waiting here.
        clock.advance(minutes: 30)
        await system.respond(ReminderResponse(taskId: id, action: .done))
        #expect(try await services.repo.getTask(id)?.status == .done)
        #expect(system.scheduled.isEmpty, "its 16:00 reminder taken back")
        #expect(log.events == ["suspend", "begin 提醒按钮", "resume", "suspend", "end 1"])

        // 稍后提醒 on another, the same way.
        let other = try await services.repo.addTask(title: "回电话", dueDate: Day(2026, 11, 16), dueTime: 17 * 60, reminders: [0])
        log.events = []
        await system.respond(ReminderResponse(taskId: other, action: .snooze))
        #expect(try await Snoozes(services.database).load()[other] != nil)
        #expect(system.scheduled.map(\.at).contains(LocalDateTime(2026, 11, 16, 15, 45).date()))
        #expect(log.events == ["begin 提醒按钮", "resume", "suspend", "end 2"])

        // A click only asks the UI to open it: nothing to wake for.
        log.events = []
        await system.respond(ReminderResponse(taskId: other, action: .open))
        #expect(services.reminders.openRequest == .task(other))
        #expect(log.events.isEmpty)

        services.appDidBecomeActive()
        #expect(log.events == ["resume"])
    }
}
