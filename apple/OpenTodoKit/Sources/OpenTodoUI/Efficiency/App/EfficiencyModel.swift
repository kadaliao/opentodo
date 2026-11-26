// `model.efficiency`: the efficiency modules' state in a window — the
// habits, check-ins, focus sessions and countdowns read from the database
// (`AppDatabase.observeHabits()` and the rest, started the first time a
// screen needs them), the focus timer, and the writes.
//
// The module screens hand back whole records (docs/apple.md §8, 界面组件);
// this turns each into the `EfficiencyRepo` call it stands for: a record
// with `deletedAt` is a delete, a check-in's status says check in / give up
// / take back, a habit or countdown that isn't there yet is added. Deletes
// of a countdown or a focus record show the undo banner.
//
// The focus timer isn't kept here but in `AppServices.focusTimer`
// (`FocusTimerStore`, OpenTodoData): one for the whole app, so every window
// shows the same run and a finished pomodoro is recorded once. This model
// passes the screens' changes on to it.

import Foundation
import Observation
import OpenTodoData
import OpenTodoDomain

@Observable
public final class EfficiencyModel {
    public private(set) var habits: [Habit] = []
    public private(set) var checkins: [HabitCheckin] = []
    public private(set) var sessions: [FocusSession] = []
    public private(set) var countdowns: [Countdown] = []
    /// Whether the first reads have come in.
    public private(set) var loaded = false

    /// The focus timer as it stands (the app's one, `focus`).
    public var timer: FocusTimer { focus?.timer ?? FocusTimer() }
    /// The app's timer: `AppServices.focusTimer`, or (no services: tests)
    /// one of this model's own.
    public private(set) var focus: FocusTimerStore?
    /// The efficiency module shown last: the iPhone's 效率 tab opens it.
    public var lastModule: AppModule = .matrix
    /// How each countdown card counts (天数 / 年月天 / 周天), for this window.
    public var countdownFormats: [String: CountdownFormat] = [:]
    /// A screen to open the next time a module appears (a debug route, a
    /// countdown tapped on 今天), by module.
    public var pendingStart: [AppModule: String] = [:]
    /// Bumped by `open(_:detail:in:)` so a module already on screen starts over.
    public private(set) var openToken = 0

    @ObservationIgnored public private(set) var repo: EfficiencyRepo?
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var handles: [ObservationHandle] = []
    /// The clock the records and the timer go by; tests pin it.
    @ObservationIgnored public var clock: @Sendable () -> Date = { Date() }
    /// For a timer of this model's own (no services): books the end
    /// notification. Tests replace it.
    @ObservationIgnored public var scheduleEnd: (@MainActor (Date?, String) -> Void)?

    public init() {}

    /// Epoch ms by the timer's clock (the services' when shared).
    var nowMillis: Int { focus?.nowMillis ?? Int((clock().timeIntervalSince1970 * 1000).rounded()) }

    // MARK: - Starting

    /// Starts reading (once) and picks the saved timer up.
    public func start(_ app: AppModel) {
        guard repo == nil else { return }
        self.app = app
        let repo = app.services?.efficiency ?? EfficiencyRepo(app.database, clock: clock, timeZone: app.timeZone)
        self.repo = repo
        let focus = app.services?.focusTimer ?? {
            let own = FocusTimerStore(settings: app.settings, repo: repo, clock: clock)
            if let scheduleEnd { own.scheduleEnd = scheduleEnd }
            return own
        }()
        self.focus = focus
        if focus.onStretchEnded == nil {
            let settings = app.settings
            focus.onStretchEnded = { if settings.focusSettings.endSound { playFocusEndSound() } }
        }
        focus.catchUp()

        let db = app.database
        let onError: @MainActor @Sendable (any Error) -> Void = { [weak app] e in app?.notices.show("读取数据出错：\(e.localizedDescription)") }
        var pending = 4
        func arrived() {
            if pending > 0 { pending -= 1; if pending == 0 { loaded = true } }
        }
        handles = [
            db.observeHabits().start(onError: onError) { [weak self] v in self?.habits = v; arrived() },
            db.observeCheckins().start(onError: onError) { [weak self] v in self?.checkins = v; arrived() },
            db.observeFocusSessions().start(onError: onError) { [weak self] v in self?.sessions = v; arrived() },
            db.observeCountdowns().start(onError: onError) { [weak self] v in self?.countdowns = v; arrived() },
        ]
    }

    /// Shows one habit's or countdown's page (from its notification, from
    /// 今天).
    public func open(_ module: AppModule, detail id: String, in app: AppModel) {
        start(app)
        pendingStart[module] = "detail:\(id)"
        openToken += 1
        app.switchTo(module)
    }

    private func run(_ body: @escaping @MainActor (EfficiencyRepo) async throws -> Void) {
        guard let app, let repo else { return }
        app.run { try await body(repo) }
    }

    // MARK: - Habits

    public func saveHabit(_ h: Habit) {
        if h.deletedAt != nil {
            run { try await $0.deleteHabit(h.id) }
        } else if habits.contains(where: { $0.id == h.id }) {
            run { try await $0.updateHabit(h.id) { $0.takeFields(of: h) } }
        } else {
            run { repo in
                try await repo.addHabit(
                    id: h.id, name: h.name, emoji: h.emoji, color: h.color, goalKind: h.goalKind, goal: h.goal, step: h.step,
                    unit: h.unit, frequency: h.frequency, reminders: h.reminders, startDate: h.startDate, section: h.section)
                if h.archivedAt != nil { try await repo.setHabitArchived(h.id, true) }
            }
        }
    }

    /// A check-in as the habits screen worked it out, written the way it
    /// says: taken back, given up, or the day's amount.
    public func saveCheckin(_ c: HabitCheckin) {
        if c.deletedAt != nil {
            run { try await $0.undoCheckin(c.habitId, on: c.day) }
        } else if c.status == .abandoned {
            run { try await $0.abandonDay(c.habitId, on: c.day) }
        } else {
            run { try await $0.setCheckinValue(c.habitId, on: c.day, value: c.value) }
        }
    }

    // MARK: - Focus

    public func saveSession(_ s: FocusSession) {
        guard s.deletedAt != nil else {
            run { try await $0.saveFocusSession(s) }
            return
        }
        var back = s
        back.deletedAt = nil
        run { try await $0.deleteFocusSession(s.id) }
        if let app, let repo {
            app.notices.show("已删除专注记录", undoName: "删除") { try? await repo.saveFocusSession(back) }
        }
    }

    public func setFocusSettings(_ s: FocusSettings) {
        if let focus { focus.setSettings(s) } else { app?.settings.setFocusSettings(s) }
    }

    /// The timer after something the person did on the focus screen.
    public func timerChanged(_ t: FocusTimer) {
        focus?.update(t)
    }

    /// 开始专注 from a task: starts a pomodoro (or the stopwatch, whichever
    /// the timer is set to) on it and shows the focus screen; if a focus is
    /// already running, it moves to this task.
    public func startFocus(on task: TodoTask) {
        guard let app else { return }
        catchUp()
        var t = timer
        switch t.phase {
        case .focusing, .paused:
            t.taskId = task.id
            t.habitId = nil
            app.notices.show("正在专注的计时改为“\(task.title)”")
        case .resting, .idle:
            if case .resting = t.phase { t.skipBreak(at: nowMillis) }
            if t.phase == .idle {
                t.settings = app.settings.focusSettings
                t.start(at: nowMillis, taskId: task.id)
            } else {
                t.taskId = task.id
            }
        }
        timerChanged(t)
        app.switchTo(.focus)
    }

    /// Records whatever ran out by now (the app's timer does this every
    /// second by itself).
    public func catchUp() {
        focus?.catchUp()
    }

    /// Books the notification for the end of what's running, or cancels it.
    public func bookEnd() {
        focus?.bookEnd()
    }

    // MARK: - Countdowns

    public func saveCountdown(_ c: Countdown) {
        if c.deletedAt != nil {
            run { try await $0.deleteCountdown(c.id) }
            if let app, let repo {
                app.notices.show("已删除“\(c.title)”", undoName: "删除") {
                    try? await repo.updateCountdown(c.id) { $0.deletedAt = nil }
                }
            }
        } else if countdowns.contains(where: { $0.id == c.id }) {
            run { try await $0.updateCountdown(c.id) { $0.takeFields(of: c) } }
        } else {
            run { repo in
                try await repo.addCountdown(
                    id: c.id, title: c.title, kind: c.kind, date: c.date, lunar: c.lunar, repeats: c.repeats, emoji: c.emoji,
                    color: c.color, showInToday: c.showInToday, reminders: c.reminders)
                if c.pinnedAt != nil { try await repo.setCountdownPinned(c.id, true) }
            }
        }
    }

    /// The countdowns 今天 shows at its top.
    public func todayCountdowns(_ today: Day) -> [Countdown] {
        OpenTodoDomain.todayCountdowns(countdowns, today: today)
    }
}

extension Habit {
    /// The fields the person edits, from `h` (the sync stamps stay).
    nonisolated mutating func takeFields(of h: Habit) {
        name = h.name
        emoji = h.emoji
        color = h.color
        goalKind = h.goalKind
        goal = h.goal
        step = h.step
        unit = h.unit
        frequency = h.frequency
        reminders = h.reminders
        startDate = h.startDate
        section = h.section
        archivedAt = h.archivedAt
        sortOrder = h.sortOrder
    }
}

extension Countdown {
    /// The fields the person edits, from `c` (the sync stamps stay).
    nonisolated mutating func takeFields(of c: Countdown) {
        title = c.title
        kind = c.kind
        date = c.date
        lunar = c.lunar
        repeats = c.repeats
        emoji = c.emoji
        color = c.color
        showInToday = c.showInToday
        reminders = c.reminders
        pinnedAt = c.pinnedAt
        sortOrder = c.sortOrder
    }
}
