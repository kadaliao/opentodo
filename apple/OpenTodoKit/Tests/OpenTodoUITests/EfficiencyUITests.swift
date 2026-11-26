// The efficiency screens' logic (Efficiency/*/…Model.swift): what can't be
// checked on a screenshot — taps, drops, drafts, layouts.

import Foundation
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

@Suite("Efficiency text")
struct EfficiencyTextTests {
    @Test func clockAndDurations() {
        #expect(clockText(1500) == "25:00")
        #expect(clockText(59) == "00:59")
        #expect(clockText(3723) == "1:02:03")
        #expect(clockText(-5) == "00:00")
        #expect(durationText(0) == "0分")
        #expect(durationText(25 * 60 + 59) == "25分")
        #expect(durationText(85 * 60) == "1小时25分")
        #expect(durationText(120 * 60) == "2小时")
        #expect(amountText(8) == "8" && amountText(2.5) == "2.5")
    }

    @Test func days() {
        let d = Day(2026, 11, 26)
        #expect(dayText(d) == "11月26日 周四")
        #expect(dayText(d, today: Day(2027, 1, 1)) == "2026年11月26日 周四")
        #expect(weekdayLetter(d) == "四")
    }

    @Test func colours() {
        #expect(EfficiencyPalette.colors.count == 12)
        #expect(Set(EfficiencyPalette.colors).count == 12)
    }

    @Test(arguments: ["habits", "habits:detail", "focus:stats", "countdowns:edit", "matrix"])
    func debugRoutes(_ text: String) {
        #expect(DebugRoute(text) == .efficiency(text))
        #expect(DebugRoute(text)?.text == text)
    }
}

@Suite("Habit screens")
struct HabitScreenTests {
    @Test func monthGridStartsOnMonday() {
        // November 2026 starts on a Sunday and ends on a Monday.
        let g = monthGrid(year: 2026, month: 11)
        #expect(g.count == 6)
        #expect(g[0] == [nil, nil, nil, nil, nil, nil, Day(2026, 11, 1)])
        #expect(g[5] == [Day(2026, 11, 30), nil, nil, nil, nil, nil, nil])
        #expect(g.flatMap { $0 }.compactMap { $0 }.count == 30)
        // February 2027 starts on a Monday: four whole weeks.
        let f = monthGrid(year: 2027, month: 2)
        #expect(f.count == 4 && f.allSatisfy { !$0.contains(nil) })
        // A leap February.
        #expect(monthGrid(year: 2028, month: 2).flatMap { $0 }.compactMap { $0 }.last == Day(2028, 2, 29))
    }

    @Test func heatmapAndRecentDays() {
        let today = Day(2027, 1, 2) // Saturday
        let w = heatmapWeeks(endingOn: today, weeks: 3)
        #expect(w.count == 3 && w.allSatisfy { $0.count == 7 && $0[0].weekday == 1 })
        #expect(w.last!.contains(today))
        #expect(w[0][0] == Day(2026, 12, 14))
        #expect(recentDays(today) == (0..<7).map { Day(2026, 12, 27) + $0 })
    }

    @Test func tapping() {
        let once = Habit(id: "h")
        let d = Day(2026, 11, 26)
        let c = habitTap(once, on: d, existing: nil, now: 1)
        #expect(c.status == .done && c.deletedAt == nil)
        let undone = habitTap(once, on: d, existing: c, now: 2)
        #expect(undone.deletedAt == 2 && undone.id == c.id)
        #expect(habitTap(once, on: d, existing: undone, now: 3).status == .done)

        let count = Habit(id: "w", goalKind: .count, goal: 2, step: 1)
        var x = habitTap(count, on: d, existing: nil, now: 1)
        x = habitTap(count, on: d, existing: x, now: 2)
        #expect(x.status == .done && x.value == 2)
        #expect(habitTap(count, on: d, existing: x, now: 3).value == 3) // keeps counting
        #expect(checkinOn(count, d, [x, removedCheckin(x, now: 4)].dropLast()) == x)
        #expect(checkinOn(count, d, [removedCheckin(x, now: 4)]) == nil)
    }

    @Test func text() {
        #expect(frequencyText(.daily) == "每天")
        #expect(frequencyText(.weekdays(1...5)) == "工作日")
        #expect(frequencyText(.weekdays([6, 7])) == "周末")
        #expect(frequencyText(.weekdays([1, 3, 5])) == "每周一、三、五")
        #expect(frequencyText(.timesPerWeek(3)) == "每周3天")
        let water = Habit(id: "w", goalKind: .count, goal: 8, unit: "杯")
        #expect(goalText(water) == "每天8杯")
        #expect(goalText(Habit(id: "h")) == "打卡一次")
        let s = HabitStreak(current: 5, longest: 9, unit: .days)
        #expect(habitSubtitle(water, state: .partial(0.5), checkin: HabitCheckin(habitId: "w", day: Day(2026, 1, 1), value: 4), streak: s)
            == "4/8杯 · 连续5天")
        #expect(habitSubtitle(Habit(id: "h"), state: .done, checkin: nil, streak: HabitStreak(current: 0, longest: 0, unit: .days)) == "已完成")
        #expect(habitSubtitle(Habit(id: "h", frequency: .timesPerWeek(2)), state: .pending, checkin: nil,
                              streak: HabitStreak(current: 2, longest: 2, unit: .weeks)) == "连续2周")
        #expect(habitSubtitle(Habit(id: "h", frequency: .timesPerWeek(2)), state: .pending, checkin: nil,
                              streak: HabitStreak(current: 0, longest: 2, unit: .weeks)) == "每周2天")
    }

    @Test func draftRoundTrip() {
        let h = Habit(id: "h", name: "喝水", emoji: "💧", color: 0xFF32ADE6, goalKind: .count, goal: 8, step: 2, unit: "杯",
                      frequency: .weekdays([1, 3]), reminders: [600, 540], startDate: Day(2026, 1, 1), section: .morning,
                      createdAt: 5, serverVersion: 3, dirty: false)
        let d = HabitDraft(h)
        #expect(d.frequencyKind == .weekdays && d.weekdays == [1, 3])
        let back = d.habit(base: h, newId: "x", now: 9)
        #expect(back.id == "h" && back.createdAt == 5 && back.serverVersion == 3)
        #expect(back.updatedAt == 9 && back.dirty)
        #expect(back.reminders == [540, 600])
        var same = back
        same.reminders = h.reminders
        same.updatedAt = 0
        same.dirty = false
        #expect(same == h)
    }

    @Test func draftRules() {
        var d = HabitDraft(today: Day(2026, 11, 26))
        #expect(!d.canSave)
        d.name = "  跑步 "
        #expect(d.canSave)
        d.frequencyKind = .weekdays
        d.weekdays = []
        #expect(!d.canSave)
        d.frequencyKind = .timesPerWeek
        d.timesPerWeek = 9
        #expect(d.frequency == .timesPerWeek(6))
        let h = d.habit(base: nil, newId: "new", now: 7)
        #expect(h.id == "new" && h.name == "跑步" && h.createdAt == 7 && h.goal == 1 && h.unit == "")
        #expect(h.startDate == Day(2026, 11, 26))
        #expect(d.nextReminder == 9 * 60)
        d.reminders = [23 * 60 + 30]
        #expect(d.nextReminder == 23 * 60 + 59)
    }
}

@Suite("Focus screens")
struct FocusScreenTests {
    let t0 = 1_800_000_000_000

    @Test func controlsFollowThePhase() {
        var t = FocusTimer()
        #expect(focusControls(t) == [.start])
        #expect(focusPhaseTitle(t) == "番茄专注")
        _ = applyFocusControl(.start, to: &t, at: t0)
        #expect(focusControls(t) == [.pause, .abandon])
        #expect(focusPhaseTitle(t) == "专注中")
        _ = applyFocusControl(.pause, to: &t, at: t0 + 60_000)
        #expect(focusControls(t) == [.resume, .abandon] && focusPhaseTitle(t) == "已暂停")
        _ = applyFocusControl(.resume, to: &t, at: t0 + 120_000)
        _ = t.tick(at: t0 + 30 * 60_000)
        #expect(focusControls(t) == [.startBreak, .skipBreak] && focusPhaseTitle(t) == "休息一下")
        _ = applyFocusControl(.startBreak, to: &t, at: t0 + 31 * 60_000)
        #expect(focusControls(t) == [.skipBreak] && focusPhaseTitle(t) == "短休息")
        _ = applyFocusControl(.skipBreak, to: &t, at: t0 + 32 * 60_000)
        #expect(focusControls(t) == [.start])
        #expect(focusCycleDots(t) == (1, 4))

        var s = FocusTimer(mode: .stopwatch)
        #expect(focusPhaseTitle(s) == "正计时")
        _ = applyFocusControl(.start, to: &s, at: t0)
        #expect(focusControls(s) == [.pause, .finish])
        #expect(focusClockSeconds(s, at: t0 + 90_000) == 90)
        let rec = applyFocusControl(.finish, to: &s, at: t0 + 10 * 60_000)
        #expect(rec?.duration == 600 && rec?.kind == .stopwatch)
    }

    @Test func clockCountsDownForPomodoros() {
        var t = FocusTimer()
        #expect(focusClockSeconds(t, at: t0) == 1500)
        t.start(at: t0)
        #expect(focusClockSeconds(t, at: t0 + 61_000) == 1439)
    }

    @Test func recordsByDay() {
        func ms(_ d: Int, _ h: Int) -> Int { Int(LocalDateTime(2026, 11, d, h, 0).date(in: shanghai).timeIntervalSince1970) * 1000 }
        let a = FocusSession(startedAt: ms(25, 9), endedAt: ms(25, 10), duration: 1500)
        let b = FocusSession(startedAt: ms(26, 8), endedAt: ms(26, 9), duration: 1500)
        let c = FocusSession(startedAt: ms(26, 14), endedAt: ms(26, 15), duration: 1500)
        let gone = FocusSession(startedAt: ms(26, 16), duration: 9, deletedAt: 1)
        let days = focusRecordDays([a, b, c, gone], in: shanghai)
        #expect(days.map(\.day) == [Day(2026, 11, 26), Day(2026, 11, 25)])
        #expect(days[0].sessions.map(\.id) == [c.id, b.id])
        #expect(focusTimeRange(b, in: shanghai) == "08:00–09:00")
        #expect(deletedSession(a, now: 5).deletedAt == 5)
    }

    @Test func manualSessions() {
        let s = manualFocusSession(day: Day(2026, 11, 26), startMinute: 9 * 60 + 30, minutes: 45, kind: .stopwatch,
                                   taskId: "t", note: "补", in: shanghai, now: 7)
        #expect(s.start(in: shanghai) == LocalDateTime(2026, 11, 26, 9, 30))
        #expect(s.end(in: shanghai) == LocalDateTime(2026, 11, 26, 10, 15))
        #expect(s.duration == 2700 && s.completed && s.taskId == "t" && s.createdAt == 7)
        #expect(manualFocusSession(day: Day(2026, 11, 26), startMinute: 0, minutes: 0, kind: .pomodoro, taskId: nil, note: "",
                                   in: shanghai, now: 0).duration == 60)
    }

    @Test func chartRanges() {
        let today = Day(2026, 11, 26) // Thursday
        #expect(focusChartRange(.day, today: today) == (Day(2026, 11, 20), today))
        #expect(focusChartRange(.week, today: today) == (Day(2026, 10, 5), today))
        #expect(focusChartRange(.month, today: today) == (Day(2026, 6, 1), today))
        #expect(focusBarLabel(Day(2026, 11, 23), .week) == "11/23")
        #expect(focusBarLabel(Day(2026, 11, 1), .month) == "11月")
    }

    @Test func slicesGroupTheRest() {
        let shares = (1...7).map { FocusShare(id: "t\($0)", seconds: 800 - $0 * 100) } + [FocusShare(id: nil, seconds: 10)]
        let s = focusSlices(shares) { $0 ?? "无" }
        #expect(s.count == 6)
        #expect(s.last == FocusSlice(id: "+", name: "其他", seconds: 200 + 100 + 10))
        #expect(focusSlices([FocusShare(id: nil, seconds: 5)]) { $0 ?? "未关联" } == [FocusSlice(id: "-", name: "未关联", seconds: 5)])
    }
}

@Suite("Countdown screens")
struct CountdownScreenTests {
    let today = Day(2026, 11, 26)

    @Test func runs() {
        #expect(textRuns("2个月22天").map(\.text) == ["2", "个月", "22", "天"])
        #expect(textRuns("2个月22天").map(\.isNumber) == [true, false, true, false])
        #expect(textRuns("").isEmpty)
    }

    @Test func cards() {
        let exam = Countdown(id: "e", date: today + 25)
        let t = countdownCardText(exam, today: today, format: .days)
        #expect(t.caption == "还有" && t.runs.map(\.text) == ["25", "天"])
        #expect(t.date == "12月21日 周一")
        let met = Countdown(id: "m", kind: .anniversary, date: today - 400)
        #expect(countdownCardText(met, today: today, format: .yearsMonthsDays).caption == "已经")
        #expect(countdownCardText(Countdown(id: "p", date: today - 3), today: today, format: .days).caption == "已过")
        let now = countdownCardText(Countdown(id: "n", date: today), today: today, format: .weeksDays)
        #expect(now.caption == nil && now.runs == [.init(text: "今天", isNumber: true)])
        let lunar = Countdown(id: "s", kind: .holiday, date: Day(2026, 2, 17), lunar: true, repeats: .yearly)
        #expect(countdownCardText(lunar, today: today, format: .days).date == "2027年2月6日 周六 · 正月初一")
        #expect(countdownCardText(Countdown(id: "x", date: Day(1800, 1, 1), lunar: true), today: today, format: .days).date == "超出农历范围")
    }

    @Test func formatsCycle() {
        #expect(nextFormat(.days) == .yearsMonthsDays)
        #expect(nextFormat(.yearsMonthsDays) == .weeksDays)
        #expect(nextFormat(.weeksDays) == .days)
    }

    @Test func text() {
        #expect(countdownReminderText(countdownReminder(daysBefore: 1, minute: 9 * 60)) == "提前1天 上午9:00")
        #expect(countdownReminderText(20 * 60) == "当天 下午8:00")
        #expect(repeatText(Countdown(id: "a", lunar: true, repeats: .yearly)) == "农历每年")
        #expect(repeatText(Countdown(id: "a", repeats: .monthly)) == "每月")
    }

    @Test func drafts() {
        var d = CountdownDraft(kind: .birthday, today: today)
        #expect(d.repeats == .yearly && d.reminders == [-900])
        #expect(!d.canSave)
        d.title = "生日"
        #expect(d.canSave)
        d.setKind(.countdown)
        #expect(d.repeats == CountdownRepeat.none)
        d.repeats = .monthly
        d.setKind(.holiday)
        #expect(d.repeats == .monthly) // changed by hand: kept
        d.lunar = true
        d.date = Day(1800, 1, 1)
        #expect(!d.canSave)

        let base = Countdown(id: "c", title: "旧", createdAt: 1, serverVersion: 4)
        var e = CountdownDraft(base)
        e.title = " 新 "
        e.pinned = true
        let c = e.countdown(base: base, newId: "x", now: 9)
        #expect(c.id == "c" && c.title == "新" && c.pinnedAt == 9 && c.serverVersion == 4 && c.updatedAt == 9)
        // Still pinned: keeps when.
        #expect(CountdownDraft(c).countdown(base: c, newId: "x", now: 20).pinnedAt == 9)
        #expect(togglingPin(c, now: 30).pinnedAt == nil)
        #expect(deletedCountdown(c, now: 31).deletedAt == 31)
        #expect(CountdownDraft(kind: .holiday, today: today).countdown(base: nil, newId: "n", now: 2).id == "n")
    }
}

@Suite("Matrix screens")
struct MatrixScreenTests {
    let now = LocalDateTime(2026, 11, 26, 10, 0)
    let tasks = [
        TodoTask(id: "h", priority: .high),
        TodoTask(id: "l", listId: "work", priority: .low),
    ]

    @Test func droppingChangesThePriority() {
        let p = MatrixPrefs.standard
        #expect(matrixQuadrantIndex(of: tasks[0], prefs: p, now: now) == 0)
        let r = matrixDrop(taskId: "l", into: 0, tasks: tasks, prefs: p, now: now)
        #expect(r?.old == tasks[1] && r?.new.priority == .high && r?.new.listId == "work")
        #expect(matrixDrop(taskId: "h", into: 0, tasks: tasks, prefs: p, now: now) == nil) // already there
        #expect(matrixDrop(taskId: "?", into: 1, tasks: tasks, prefs: p, now: now) == nil)
        #expect(matrixDrop(taskId: "h", into: 7, tasks: tasks, prefs: p, now: now) == nil)
        // A quadrant whose rule a drop can't satisfy changes nothing.
        let vague = MatrixPrefs(quadrants: [MatrixQuadrant(name: "x", rule: FilterRule(conditions: [FilterCondition(.keyword, ["会"])]))]
            + MatrixPrefs.defaultQuadrants.dropFirst())
        #expect(matrixDrop(taskId: "l", into: 0, tasks: tasks, prefs: vague, now: now) == nil)
    }

    @Test func quickAddTakesTheRule() {
        let rule = FilterRule(conditions: [FilterCondition(.list, ["work"]), FilterCondition(.date, ["today"]), FilterCondition(.priority, ["high"])])
        let p = MatrixPrefs(quadrants: [MatrixQuadrant(name: "急", rule: rule)])
        let d = matrixQuickAddDefaults(0, prefs: p, today: now.day)
        #expect(d == QuickAddDefaults(listId: "work", date: now.day, tags: [], priority: .high))
        #expect(matrixQuickAddDefaults(3, prefs: .standard, today: now.day).priority == Priority.none)
        #expect(matrixQuickAddDefaults(9, prefs: .standard, today: now.day) == QuickAddDefaults())
    }

    @Test func priorityRuleEditor() {
        let r = MatrixPrefs.standard.quadrants[0].filterRule
        #expect(rulePriorities(r) == [.high])
        let two = ruleWithPriorities(r, [.high, .medium])
        #expect(rulePriorities(two) == [.high, .medium])
        #expect(two.valuesOf(.priority) == ["high", "medium"]) // highest first
        #expect(ruleSummary(two) == "高、中优先级")
        #expect(ruleSummary(MatrixPrefs.standard.quadrants[3].filterRule) == "无优先级")
        let none = ruleWithPriorities(r, [])
        #expect(none.conditions.isEmpty && ruleSummary(none) == "所有任务")
        // Other conditions stay.
        let mixed = FilterRule(conditions: [FilterCondition(.tag, ["x"]), FilterCondition(.priority, ["low"])])
        let changed = ruleWithPriorities(mixed, [.high])
        #expect(changed.valuesOf(.tag) == ["x"] && changed.valuesOf(.priority) == ["high"])
        #expect(ruleSummary(changed) == "自定义条件")
    }
}
