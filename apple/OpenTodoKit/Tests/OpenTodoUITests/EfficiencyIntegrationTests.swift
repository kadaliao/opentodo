// The efficiency modules in the app (`model.efficiency`, EfficiencyScreen):
// what each screen's records turn into in the database, the focus timer
// kept and caught up, 开始专注 from a task, the countdowns on 今天, the
// phone's tabs, the demo and the debug routes. Over an in-memory database,
// the clock pinned at 2026-11-26 (a Thursday) 09:41 in Shanghai.

import Foundation
import OpenTodoData
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

nonisolated private let tz = TimeZone(identifier: "Asia/Shanghai")!
nonisolated private let start = LocalDateTime(2026, 11, 26, 9, 41)
nonisolated private let today = start.day

/// A clock the tests move.
nonisolated private final class TestClock: @unchecked Sendable {
    var date = start.date(in: tz)
    func advance(minutes: Int) { date += Double(minutes * 60) }
}

private struct Harness {
    let model: AppModel
    let eff: EfficiencyModel
    let clock: TestClock
    let booked: Booked
}

private final class Booked {
    var ends: [(Date?, String)] = []
}

private func makeHarness(demoTasks: Bool = true) async throws -> Harness {
    let db = try AppDatabase.inMemory()
    let settings = LocalSettings(db)
    let clock = TestClock()
    let repo = TaskRepo(db, clock: { clock.date }, defaults: settings.defaultsProvider, timeZone: tz)
    if demoTasks { try await DemoData.seed(repo, now: start) }
    let model = AppModel(repo: repo, settings: settings, now: start)
    await model.start(clock: false)
    try await waitUntil { model.loaded }
    let booked = Booked()
    model.efficiency.clock = { clock.date }
    model.efficiency.scheduleEnd = { booked.ends.append(($0, $1)) }
    model.efficiency.start(model)
    try await waitUntil { model.efficiency.loaded }
    return Harness(model: model, eff: model.efficiency, clock: clock, booked: booked)
}

private func waitUntil(_ what: String = "", _ condition: () -> Bool) async throws {
    // Up to 10 s: other suites run alongside and can slow the observation.
    for _ in 0..<2000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out \(what)")
}

private func ms(_ minutes: Int) -> Int { Int(start.date(in: tz).timeIntervalSince1970) * 1000 + minutes * 60_000 }

@Suite struct EfficiencyTabsTests {
    @Test func phonesFoldTheEfficiencyModulesIntoOneTab() {
        #expect(AppModule.tabs(compact: false, current: .tasks, last: .habits) == AppModule.allCases)
        #expect(AppModule.tabs(compact: true, current: .tasks, last: .habits) == [.tasks, .calendar, .habits])
        #expect(AppModule.tabs(compact: true, current: .focus, last: .habits) == [.tasks, .calendar, .focus])
        #expect(AppModule.efficiencyModules == [.matrix, .focus, .habits, .countdowns])
        #expect(AppModule.focus.tabTitle(compact: true) == "效率" && AppModule.focus.tabTitle(compact: false) == "专注")
        #expect(AppModule.tasks.tabTitle(compact: true) == "任务")
    }
}

@Suite struct EfficiencyHabitsIntegrationTests {
    @Test func addCheckInTakeBackGiveUp() async throws {
        let h = try await makeHarness(demoTasks: false)
        let eff = h.eff
        var draft = HabitDraft(today: today)
        draft.name = "喝水"
        draft.goalKind = .count
        draft.goal = 3
        draft.unit = "杯"
        eff.saveHabit(draft.habit(base: nil, newId: "w", now: eff.nowMillis))
        try await waitUntil("added") { eff.habits.count == 1 }
        let water = eff.habits[0]
        #expect(water.name == "喝水" && water.goal == 3 && water.startDate == today)

        // Two taps, then the amount typed in.
        eff.saveCheckin(habitTap(water, on: today, existing: nil, now: eff.nowMillis))
        try await waitUntil("tap") { eff.checkins.first?.value == 1 }
        eff.saveCheckin(habitTap(water, on: today, existing: eff.checkins.first, now: eff.nowMillis))
        try await waitUntil("tap 2") { eff.checkins.first?.value == 2 }
        eff.saveCheckin(setCheckinValue(water, on: today, existing: eff.checkins.first, value: 3, now: eff.nowMillis))
        try await waitUntil("done") { eff.checkins.first?.status == .done }

        // A day missed earlier, filled in (补打卡), then given up.
        eff.saveCheckin(checkIn(water, on: today - 2, existing: nil, amount: 3, now: eff.nowMillis))
        try await waitUntil("late") { eff.checkins.count == 2 }
        let late = eff.checkins.first { $0.day == today - 2 }!
        #expect(late.status == .done)
        eff.saveCheckin(abandonDay(water, on: today - 2, existing: late, now: eff.nowMillis))
        try await waitUntil("given up") { eff.checkins.first { $0.day == today - 2 }?.status == .abandoned }

        // Taken back.
        eff.saveCheckin(removedCheckin(eff.checkins.first { $0.day == today }!, now: eff.nowMillis))
        try await waitUntil("taken back") { eff.checkins.count == 1 }
        #expect(streak(water, checkins: eff.checkins, today: today).current == 0)
    }

    @Test func editArchiveDelete() async throws {
        let h = try await makeHarness(demoTasks: false)
        let eff = h.eff
        var d = HabitDraft(today: today)
        d.name = "早起"
        eff.saveHabit(d.habit(base: nil, newId: "e", now: eff.nowMillis))
        try await waitUntil { eff.habits.count == 1 }
        let created = eff.habits[0]
        eff.saveCheckin(habitTap(created, on: today, existing: nil, now: eff.nowMillis))
        try await waitUntil { eff.checkins.count == 1 }

        var e = HabitDraft(created)
        e.name = "六点起"
        e.section = .morning
        h.clock.advance(minutes: 1)
        eff.saveHabit(e.habit(base: created, newId: "x", now: eff.nowMillis))
        try await waitUntil("edited") { eff.habits.first?.name == "六点起" }
        #expect(eff.habits[0].createdAt == created.createdAt && eff.habits[0].section == .morning)

        var archived = eff.habits[0]
        archived.archivedAt = eff.nowMillis
        eff.saveHabit(archived)
        try await waitUntil("archived") { eff.habits.first?.archivedAt != nil }
        #expect(todayHabits(eff.habits, checkins: eff.checkins, today: today).isEmpty)

        eff.saveHabit(deletedHabit(eff.habits[0], now: eff.nowMillis))
        try await waitUntil("deleted") { eff.habits.isEmpty && eff.checkins.isEmpty }
    }
}

@Suite struct EfficiencyFocusIntegrationTests {
    @Test func startFocusFromATask() async throws {
        let h = try await makeHarness()
        let m = h.model, eff = h.eff
        let report = try #require(m.task("report"))
        eff.startFocus(on: report)
        #expect(m.module == .focus)
        #expect(eff.timer.phase == .focusing && eff.timer.taskId == "report" && eff.timer.startedAt == ms(0))
        // Saved, so a relaunch carries on.
        #expect(m.settings.focusTimer == eff.timer)
        #expect(LocalSettings(m.database).focusTimer == eff.timer)
        // The end is booked 25 minutes on.
        #expect(h.booked.ends.last?.0 == Date(timeIntervalSince1970: Double(ms(25)) / 1000))
        #expect(h.booked.ends.last?.1 == "番茄完成了，休息一下吧")

        // Another task while running: the running focus moves to it.
        let slides = try #require(m.task("slides"))
        h.clock.advance(minutes: 3)
        eff.startFocus(on: slides)
        #expect(eff.timer.taskId == "slides" && eff.timer.startedAt == ms(0))
        #expect(m.notices.current?.text.contains("准备下周例会的幻灯片") == true || m.notices.current != nil)
    }

    @Test func aPomodoroThatRanOutIsRecordedAndTheTimerSurvivesARelaunch() async throws {
        let h = try await makeHarness()
        let m = h.model, eff = h.eff
        eff.startFocus(on: try #require(m.task("okr")))
        m.switchTo(.tasks)
        h.clock.advance(minutes: 30)
        eff.catchUp()
        try await waitUntil("recorded") { eff.sessions.count == 1 }
        let s = eff.sessions[0]
        #expect(s.startedAt == ms(0) && s.endedAt == ms(25) && s.duration == 1500 && s.taskId == "okr" && s.isPomodoro)
        #expect(eff.timer.phase == .idle && eff.timer.upNext == .shortBreak)
        // A new window over the same database picks the timer up.
        let again = EfficiencyModel()
        again.clock = { h.clock.date }
        again.scheduleEnd = { _, _ in }
        again.start(m)
        #expect(again.timer == eff.timer)
        #expect(focusSummary(eff.sessions, on: today, in: tz).pomodoros == 1)
    }

    @Test func recordsAddedByHandAndDeletedWithUndo() async throws {
        let h = try await makeHarness()
        let m = h.model, eff = h.eff
        let s = manualFocusSession(day: today, startMinute: 8 * 60, minutes: 40, kind: .stopwatch, taskId: "report",
                                   note: "", in: tz, now: eff.nowMillis)
        eff.saveSession(s)
        try await waitUntil("added") { eff.sessions.count == 1 }
        eff.saveSession(deletedSession(eff.sessions[0], now: eff.nowMillis))
        try await waitUntil("deleted") { eff.sessions.isEmpty }
        #expect(m.notices.current?.text == "已删除专注记录")
        await m.notices.runAction()
        try await waitUntil("undone") { eff.sessions.count == 1 }
        #expect(eff.sessions[0].duration == 2400)
    }

    @Test func settingsApplyFromTheNextStart() async throws {
        let h = try await makeHarness()
        let eff = h.eff
        eff.setFocusSettings(FocusSettings(pomodoroMinutes: 50))
        #expect(h.model.settings.focusSettings.pomodoroMinutes == 50)
        #expect(eff.timer.settings.pomodoroMinutes == 50)
        eff.startFocus(on: try #require(h.model.task("report")))
        #expect(eff.timer.remaining(at: ms(0)) == 3000)
    }
}

@Suite struct EfficiencyCountdownsIntegrationTests {
    @Test func addEditPinDeleteUndo() async throws {
        let h = try await makeHarness(demoTasks: false)
        let m = h.model, eff = h.eff
        var d = CountdownDraft(kind: .birthday, today: today)
        d.title = "妈妈的生日"
        d.date = Day(1968, 11, 26)
        d.pinned = true
        eff.saveCountdown(d.countdown(base: nil, newId: "mom", now: eff.nowMillis))
        try await waitUntil("added and pinned") { eff.countdowns.first?.pinnedAt != nil }
        #expect(eff.countdowns[0].repeats == .yearly)
        #expect(eff.todayCountdowns(today).map(\.id) == ["mom"]) // 显示在今天 is on by default, and it's today
        #expect(todayCountdownCaption(eff.countdowns[0], today: today) == "58岁生日")

        var e = CountdownDraft(eff.countdowns[0])
        e.title = "妈妈生日"
        e.showInToday = false
        eff.saveCountdown(e.countdown(base: eff.countdowns[0], newId: "x", now: eff.nowMillis))
        try await waitUntil("edited") { eff.countdowns.first?.title == "妈妈生日" }
        #expect(eff.todayCountdowns(today).isEmpty)

        eff.saveCountdown(deletedCountdown(eff.countdowns[0], now: eff.nowMillis))
        try await waitUntil("deleted") { eff.countdowns.isEmpty }
        await m.notices.runAction()
        try await waitUntil("undone") { eff.countdowns.count == 1 }
    }

    @Test func todayCaptions() {
        #expect(todayCountdownCaption(Countdown(id: "a", kind: .anniversary, date: Day(2023, 11, 26)), today: today) == "3周年")
        #expect(todayCountdownCaption(Countdown(id: "b", date: today), today: today) == "今天")
        #expect(todayCountdownCaption(Countdown(id: "c", kind: .birthday, date: today), today: today) == "生日")
    }
}

@Suite struct EfficiencyMatrixIntegrationTests {
    @Test func droppingAndQuickAddWriteTheTasks() async throws {
        let h = try await makeHarness()
        let m = h.model
        let prefs = m.settings.matrixPrefs
        let call = try #require(m.task("call"))
        let before = try #require(matrixQuadrantIndex(of: call, prefs: prefs, now: m.now))
        let target = before == 0 ? 1 : 0
        let (_, new) = try #require(matrixDrop(taskId: "call", into: target, tasks: m.data.tasks, prefs: prefs, now: m.now))
        try await m.repo.updateTask(new.id) { $0.takeMatrixMove(new) }
        try await waitUntil("moved") { m.task("call")?.priority == new.priority }
        #expect(matrixQuadrantIndex(of: m.task("call")!, prefs: prefs, now: m.now) == target)

        let d = matrixQuickAddDefaults(0, prefs: prefs, today: m.today)
        let id = await m.quickAdd("matrix 新任务", target: QuickAddTarget(listId: d.listId, date: d.date, tags: d.tags, priority: d.priority))
        try await waitUntil("added") { id.flatMap(m.task) != nil }
        #expect(m.task(id!)?.priority == .high)

        // Prefs are kept on this device.
        var p = prefs
        p.quadrants[0].name = "马上做"
        m.settings.setMatrixPrefs(p)
        #expect(LocalSettings(m.database).matrixPrefs.quadrants[0].name == "马上做")
    }
}

@Suite struct EfficiencyDemoAndRoutesTests {
    @Test func demoSeedsOnce() async throws {
        let h = try await makeHarness()
        let repo = EfficiencyRepo(h.model.database, clock: { h.clock.date }, timeZone: tz)
        try await EfficiencyDemo.seed(repo, today: today)
        try await waitUntil("seeded") { h.eff.habits.count == 6 && h.eff.countdowns.count == 7 }
        #expect(h.eff.checkins.count > 100 && h.eff.sessions.count > 50)
        #expect(h.eff.habits.contains { $0.archivedAt != nil })
        // Focus records point at the demo tasks.
        #expect(Set(h.eff.sessions.compactMap(\.taskId)).isSubset(of: Set(h.model.data.tasks.map(\.id))))
        let n = h.eff.habits.count
        try await EfficiencyDemo.seed(repo, today: today)
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.eff.habits.count == n)
        #expect(efficiencySummary(.habits, model: h.model).hasPrefix("今天 "))
        #expect(efficiencySummary(.countdowns, model: h.model).contains("还有") || efficiencySummary(.countdowns, model: h.model).contains("就是今天"))
    }

    @Test func routesOpenTheModules() async throws {
        let h = try await makeHarness()
        applyEfficiencyRoute("focus:running", h.model)
        #expect(h.model.module == .focus && h.eff.timer.phase == .focusing && h.eff.timer.taskId == "report")
        applyEfficiencyRoute("habits:detail:h-water", h.model)
        #expect(h.model.module == .habits && h.eff.pendingStart[.habits] == "detail:h-water")
        applyEfficiencyRoute("tasks", h.model)
        #expect(h.model.module == .habits)
        #expect(efficiencySummary(.focus, model: h.model) == "专注中")
    }

    @Test func notificationsOpenTheHabitOrTheCountdown() async throws {
        let h = try await makeHarness()
        h.model.handle(.habit("h-water"))
        #expect(h.model.module == .habits && h.eff.pendingStart[.habits] == "detail:h-water")
        let token = h.eff.openToken
        h.model.handle(.countdown("c-mom"))
        #expect(h.model.module == .countdowns && h.eff.pendingStart[.countdowns] == "detail:c-mom")
        #expect(h.eff.openToken == token + 1)
        h.model.handle(.task("report"))
        #expect(h.model.module == .tasks && h.model.selectedTaskId == "report")
    }
}

@Suite struct EfficiencySharedTimerTests {
    /// Two windows (two AppModels) over the app's one AppServices.
    @Test func windowsShareOneTimerAndRecordAPomodoroOnce() async throws {
        let db = try AppDatabase.inMemory()
        let clock = TestClock()
        let services = AppServices(database: db, tokens: KeyValueTokenStore(db), reminderBackend: MemoryReminderBackend(),
                                   clock: { clock.date })
        let booked = Booked()
        services.focusTimer.scheduleEnd = { booked.ends.append(($0, $1)) }
        try await DemoData.seed(services.repo, now: start)
        func window() async throws -> AppModel {
            let m = AppModel(repo: services.repo, settings: services.settings, services: services, now: start)
            await m.start(clock: false)
            try await waitUntil { m.loaded }
            m.efficiency.start(m)
            return m
        }
        let a = try await window(), b = try await window()
        #expect(a.efficiency.focus === services.focusTimer && b.efficiency.focus === services.focusTimer)

        a.efficiency.startFocus(on: try #require(a.task("report")))
        #expect(a.efficiency.timer.startedAt == ms(0))
        #expect(b.efficiency.timer == a.efficiency.timer && b.efficiency.timer.phase == .focusing)
        #expect(services.settings.focusTimer == a.efficiency.timer)

        // Paused in one window, paused in the other.
        var t = b.efficiency.timer
        t.pause(at: ms(5))
        b.efficiency.timerChanged(t)
        #expect(a.efficiency.timer.phase == .paused)
        t.resume(at: ms(5))
        b.efficiency.timerChanged(t)

        // The pomodoro runs out: both windows look, it's recorded once.
        clock.advance(minutes: 30)
        a.efficiency.catchUp()
        b.efficiency.catchUp()
        try await waitUntil("recorded") { a.efficiency.sessions.count == 1 }
        try await Task.sleep(for: .milliseconds(50))
        let rows = try await db.observeFocusSessions().first()
        #expect(rows.count == 1 && rows.first?.duration == 1500 && rows.first?.taskId == "report", "\(rows.map { ($0.duration, $0.taskId ?? "-", $0.kind) })")
        #expect(b.efficiency.sessions.count == 1)
        #expect(a.efficiency.timer.phase == .idle && b.efficiency.timer == a.efficiency.timer)
    }

    @Test func theSharedTimerRecordsByItselfWithNoWindowLooking() async throws {
        let db = try AppDatabase.inMemory()
        let clock = TestClock()
        let settings = LocalSettings(db)
        let repo = EfficiencyRepo(db, clock: { clock.date }, timeZone: tz)
        let store = FocusTimerStore(settings: settings, repo: repo, clock: { clock.date }, interval: .milliseconds(10))
        store.scheduleEnd = { _, _ in }
        var ended = 0
        store.onStretchEnded = { ended += 1 }
        var t = store.timer
        t.start(at: ms(0))
        store.update(t)
        clock.advance(minutes: 26)
        try await waitUntil("ticked") { store.timer.phase == .idle }
        var rows: [FocusSession] = []
        for _ in 0..<200 where rows.isEmpty {
            rows = try await db.observeFocusSessions().first()
            if rows.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        }
        #expect(rows.count == 1 && rows[0].duration == 1500)
        #expect(ended == 1)
        // A relaunch reads the saved timer back.
        #expect(FocusTimerStore(settings: LocalSettings(db), repo: repo, clock: { clock.date }).timer == store.timer)
    }
}
