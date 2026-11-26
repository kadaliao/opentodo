// Debug routes and demo data for the efficiency modules.
//
// Routes (`-OTOpen`, DebugLaunch.swift) open a module in the app, over the
// database like everything else (`-OTSeed demo` fills it), at one of its
// screens:
//
//     habits            today's habits        habits:detail[:<id>]  habits:edit
//     habits:new        habits:all
//     focus             the timer             focus:running  focus:paused
//     focus:break       focus:stopwatch       focus:stats    focus:records
//     focus:settings
//     countdowns        the cards             countdowns:detail[:<id>]
//     countdowns:edit   countdowns:new
//     matrix            the four quadrants    matrix:quadrant  matrix:edit
//
// `-OTSeed demo` also writes the demo below through `EfficiencyRepo`
// (`EfficiencyDemo.seed`): six habits with four months of check-ins, focus
// sessions over the last ten weeks on the demo tasks, seven countdowns.
// Ids are stable: `h-water`, `c-mom` ….

import Foundation
import OpenTodoData
import OpenTodoDomain
import SwiftUI

/// Starts the efficiency reads for the window and applies an efficiency
/// route. (Attached in `RootView`.)
struct EfficiencyDebugPresenter: ViewModifier {
    @Environment(AppModel.self) private var model
    var route: DebugRoute?

    func body(content: Content) -> some View {
        content.task {
            model.efficiency.start(model)
            if case .efficiency(let text)? = route { applyEfficiencyRoute(text, model) }
        }
    }
}

/// Opens `habits:detail` and the like.
@MainActor
func applyEfficiencyRoute(_ text: String, _ model: AppModel) {
    let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
    guard let module = AppModule(rawValue: parts[0]), module.isEfficiency else { return }
    let state = parts.count > 1 ? parts[1] : nil
    let eff = model.efficiency
    if module == .focus, let state, let t = demoTimer(state, settings: model.settings.focusSettings, now: eff.nowMillis) {
        eff.timerChanged(t)
    } else if let state {
        eff.pendingStart[module] = state
    }
    model.switchTo(module)
}

/// The timer in one of the debug states, `now` being epoch ms.
func demoTimer(_ state: String, settings: FocusSettings, now: Int) -> FocusTimer? {
    var t = FocusTimer(settings: settings)
    switch state {
    case "running":
        t.start(at: now - 7 * 60_000 - 12_000, taskId: "report")
    case "paused":
        t.start(at: now - 16 * 60_000, taskId: "okr")
        t.pause(at: now - 4 * 60_000)
    case "break":
        t.start(at: now - 27 * 60_000, taskId: "report")
        _ = t.tick(at: now - 2 * 60_000)
        t.startBreak(at: now - 2 * 60_000 + 30_000)
    case "stopwatch":
        t.setMode(.stopwatch)
        t.start(at: now - 43 * 60_000 - 5_000)
    default:
        return nil
    }
    return t
}

/// The demo records, around `today`.
struct EfficiencyDemo {
    let today: Day
    var timeZone: TimeZone = .current
    var habits: [Habit] = []
    var checkins: [HabitCheckin] = []
    var sessions: [FocusSession] = []
    var countdowns: [Countdown] = []

    init(today: Day, timeZone: TimeZone = .current) {
        self.today = today
        self.timeZone = timeZone
        makeHabits()
        makeFocus()
        makeCountdowns()
    }

    /// Writes the demo through `repo` unless there are habits already.
    static func seed(_ repo: EfficiencyRepo, today: Day) async throws {
        if try await !repo.database.observeHabits().first().isEmpty { return }
        let d = EfficiencyDemo(today: today, timeZone: repo.timeZone)
        // One transaction: months of check-ins and focus sessions one write
        // each took seconds on a busy machine.
        let now = Int(Date().timeIntervalSince1970 * 1000)
        try await repo.insertAll(
            habits: d.habits.map { h in var h = h; if h.archivedAt != nil { h.archivedAt = now }; return h },
            checkins: d.checkins,
            focusSessions: d.sessions,
            countdowns: d.countdowns.enumerated().map { i, c in
                var c = c
                c.sortOrder = Double(i + 1)
                if c.pinnedAt != nil { c.pinnedAt = now }
                return c
            })
    }

    // MARK: Habits

    private mutating func makeHabits() {
        let t = today
        habits = [
            Habit(id: "h-wake", name: "早起", emoji: "☀️", color: 0xFFFF9500, startDate: t - 70, section: .morning, sortOrder: 1),
            Habit(id: "h-meditate", name: "冥想十分钟", emoji: "🧘", color: 0xFF5856D6, reminders: [7 * 60 + 30], startDate: t - 40, section: .morning, sortOrder: 2),
            Habit(id: "h-water", name: "喝水", emoji: "💧", color: 0xFF32ADE6, goalKind: .count, goal: 8, step: 1, unit: "杯",
                  reminders: [10 * 60, 15 * 60], startDate: t - 90, section: .anytime, sortOrder: 3),
            Habit(id: "h-run", name: "跑步", emoji: "🏃", color: 0xFF34C759, frequency: .timesPerWeek(3), startDate: t - 120, section: .afternoon, sortOrder: 4),
            Habit(id: "h-read", name: "读书半小时", emoji: "📖", color: 0xFFA2845E, frequency: .weekdays(1...5), startDate: t - 50, section: .evening, sortOrder: 5),
            Habit(id: "h-words", name: "背单词", emoji: "✍️", color: 0xFFFF2D55, startDate: t - 200, section: .evening, archivedAt: 1, sortOrder: 6),
        ]
        var cs: [HabitCheckin] = []
        func add(_ id: String, _ d: Day, _ value: Double = 1, _ s: CheckinStatus = .done) {
            cs.removeAll { $0.habitId == id && $0.day == d }
            cs.append(HabitCheckin(habitId: id, day: d, value: value, status: s))
        }
        for k in 1...130 {
            let d = t - k
            let n = d.julianDay
            if k <= 70, n % 9 != 0 { add("h-wake", d) }
            if k <= 40, k < 12 || n % 4 != 0 { add("h-meditate", d) }
            if k <= 90 {
                let cups = Double(5 + n % 5)
                add("h-water", d, cups, cups >= 8 ? .done : .partial)
            }
            if k <= 120, [1, 3, 6].contains(d.weekday) { add("h-run", d) }
            if k <= 50, d.weekday <= 5, n % 6 != 0 { add("h-read", d) }
            if k == 9 { add("h-read", d, 0, .abandoned) }
        }
        add("h-meditate", t)
        add("h-water", t, 5, .partial)
        checkins = cs
    }

    // MARK: Focus

    private mutating func makeFocus() {
        let tz = timeZone
        func ms(_ d: Day, _ minute: Int) -> Int { Int(LocalDateTime(d, minute: minute).date(in: tz).timeIntervalSince1970) * 1000 }
        let taskIds = ["report", "slides", "okr", "review", nil, "standup"]
        var out: [FocusSession] = []
        for k in 0...75 {
            let d = today - k
            let n = d.julianDay
            let count = k == 0 ? 3 : (n % 7 == 0 ? 0 : 1 + n % 4)
            for i in 0..<count {
                let start = (k == 0 ? [8 * 60 + 40, 10 * 60 + 5, 14 * 60 + 30] : [9 * 60, 10 * 60 + 30, 14 * 60, 16 * 60 + 15])[i]
                let stopwatch = (n + i) % 5 == 0
                let minutes = stopwatch ? 35 + (n % 4) * 10 : 25
                let s = ms(d, start)
                out.append(FocusSession(
                    startedAt: s, endedAt: s + minutes * 60_000, duration: minutes * 60,
                    kind: stopwatch ? .stopwatch : .pomodoro, completed: !(k > 0 && (n + i) % 11 == 0),
                    taskId: taskIds[(n + i) % taskIds.count]
                ))
            }
        }
        sessions = out
    }

    // MARK: Countdowns

    private mutating func makeCountdowns() {
        let t = today
        let r = [countdownReminder(daysBefore: 1, minute: 9 * 60)]
        countdowns = [
            Countdown(id: "c-together", title: "在一起", kind: .anniversary, date: t - 1000, repeats: .yearly, emoji: "❤️",
                      color: 0xFFFF2D55, pinnedAt: 1),
            Countdown(id: "c-spring", title: "春节", kind: .holiday, date: Day(2026, 2, 17), lunar: true, repeats: .yearly,
                      emoji: "🧧", color: 0xFFFF3B30, showInToday: true, reminders: r),
            Countdown(id: "c-mom", title: "妈妈的生日", kind: .birthday, date: Day(1968, 9, 26), lunar: true, repeats: .yearly,
                      emoji: "🎂", color: 0xFFFF9500, showInToday: true, reminders: r + [countdownReminder(daysBefore: 0, minute: 8 * 60)]),
            Countdown(id: "c-exam", title: "考试", kind: .countdown, date: t + 25, emoji: "📚", color: 0xFF5856D6, reminders: r),
            Countdown(id: "c-pay", title: "发工资", kind: .countdown, date: Day(2026, 1, 15), repeats: .monthly, emoji: "💰",
                      color: 0xFF34C759),
            Countdown(id: "c-kid", title: "小宇的生日", kind: .birthday, date: Day(2019, t.month, t.day), repeats: .yearly,
                      emoji: "🎈", color: 0xFF32ADE6, showInToday: true),
            Countdown(id: "c-trip", title: "去冰岛", kind: .countdown, date: t - 12, emoji: "✈️", color: 0xFF007AFF),
        ]
    }
}
