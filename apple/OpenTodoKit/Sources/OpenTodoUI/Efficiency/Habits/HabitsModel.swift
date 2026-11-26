// The habit screens' logic, apart from the views so it can be tested: the
// month calendar and heat map layouts, what a tap does, the editor's
// draft, and the text of a row.

import Foundation
import OpenTodoDomain

// MARK: - Layouts

/// The weeks of a month for a calendar, Monday first; days outside the
/// month are nil.
func monthGrid(year: Int, month: Int) -> [[Day?]] {
    let first = Day(year, month, 1)
    let last = first.endOfMonth
    var weeks: [[Day?]] = []
    var start = first.startOfWeek
    while start <= last {
        weeks.append((0..<7).map { i in
            let d = start + i
            return d.month == month && d.year == first.year ? d : nil
        })
        start += 7
    }
    return weeks
}

/// The columns of a heat map: `weeks` whole weeks (Monday to Sunday), the
/// last one the week of `today`.
func heatmapWeeks(endingOn today: Day, weeks: Int) -> [[Day]] {
    let lastMonday = today.startOfWeek
    return (0..<max(weeks, 0)).reversed().map { k in
        let monday = lastMonday - 7 * k
        return (0..<7).map { monday + $0 }
    }
}

/// The week strip: the seven days up to `today`.
func recentDays(_ today: Day, count: Int = 7) -> [Day] {
    (0..<count).reversed().map { today - $0 }
}

// MARK: - Taps

/// A tap on a habit's check button for `day`: a single check-in toggles
/// (done → taken back with a tombstone), a count adds one step. The result
/// is the row to write; a taken-back one has `deletedAt` set.
func habitTap(_ habit: Habit, on day: Day, existing: HabitCheckin?, now: Int) -> HabitCheckin {
    if habit.goalKind == .once, let e = existing, e.deletedAt == nil, e.status == .done {
        return removedCheckin(e, now: now)
    }
    return checkIn(habit, on: day, existing: existing, now: now)
}

/// The check-in taken back (取消打卡): a tombstone under the same id.
func removedCheckin(_ c: HabitCheckin, now: Int) -> HabitCheckin {
    var c = c
    c.deletedAt = now
    c.updatedAt = now
    c.dirty = true
    return c
}

/// The habit's row for `day`, live only.
func checkinOn(_ habit: Habit, _ day: Day, _ checkins: [HabitCheckin]) -> HabitCheckin? {
    checkins.first { $0.habitId == habit.id && $0.day == day && $0.deletedAt == nil }
}

// MARK: - Text

/// 每天 / 每周一、三、五 / 每周3天.
func frequencyText(_ f: HabitFrequency) -> String {
    switch f {
    case .daily: "每天"
    case .onWeekdays(let days):
        days == [1, 2, 3, 4, 5] ? "工作日" : days == [6, 7] ? "周末"
            : "每" + days.map { weekdayNames[$0 - 1] }.enumerated().map { i, n in i == 0 ? n : String(n.dropFirst()) }.joined(separator: "、")
    case .timesPerWeek(let n): "每周\(n)天"
    }
}

/// 打卡一次 / 每天8杯.
func goalText(_ h: Habit) -> String {
    h.goalKind == .once ? "打卡一次" : "每天\(amountText(h.goal))\(h.unit)"
}

/// The second line of a habit's row on `day`: progress, then the streak.
func habitSubtitle(_ h: Habit, state: HabitDayState, checkin: HabitCheckin?, streak: HabitStreak) -> String {
    var parts: [String] = []
    if h.goalKind == .count {
        parts.append("\(amountText(checkin?.value ?? 0))/\(amountText(h.goal))\(h.unit)")
    }
    switch state {
    case .abandoned: parts.append("已放弃")
    case .done where h.goalKind == .once: parts.append("已完成")
    default: break
    }
    if streak.current > 0 {
        parts.append("连续\(streak.current)\(streak.unit == .weeks ? "周" : "天")")
    } else if parts.isEmpty {
        parts.append(frequencyText(h.frequency))
    }
    return parts.joined(separator: " · ")
}

// MARK: - Editor

enum FrequencyKind: String, CaseIterable, Hashable {
    case daily, weekdays, timesPerWeek

    var label: String {
        switch self {
        case .daily: "每天"
        case .weekdays: "每周固定几天"
        case .timesPerWeek: "每周几天"
        }
    }
}

/// The fields of the habit editor.
struct HabitDraft: Hashable {
    var name = ""
    var emoji: String?
    var color: Int? = EfficiencyPalette.colors[0]
    var goalKind = HabitGoalKind.once
    var goal: Double = 8
    var step: Double = 1
    var unit = "次"
    var frequencyKind = FrequencyKind.daily
    var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    var timesPerWeek = 3
    var reminders: [Int] = []
    var section = HabitSection.anytime
    var startDate: Day

    init(today: Day) {
        startDate = today
    }

    init(_ h: Habit) {
        name = h.name
        emoji = h.emoji
        color = h.color
        goalKind = h.goalKind
        if h.goalKind == .count {
            goal = h.goal
            step = h.step
            unit = h.unit
        }
        switch h.frequency {
        case .daily: frequencyKind = .daily
        case .onWeekdays(let d):
            frequencyKind = .weekdays
            weekdays = Set(d)
        case .timesPerWeek(let n):
            frequencyKind = .timesPerWeek
            timesPerWeek = n
        }
        reminders = h.reminders
        section = h.section
        startDate = h.startDate
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSave: Bool {
        !trimmedName.isEmpty
            && (goalKind == .once || goal > 0)
            && (frequencyKind != .weekdays || !weekdays.isEmpty)
    }

    var frequency: HabitFrequency {
        switch frequencyKind {
        case .daily: .daily
        case .weekdays: .weekdays(weekdays)
        case .timesPerWeek: .timesPerWeek(min(max(timesPerWeek, 1), 6))
        }
    }

    /// The habit to save: `base` with the draft's fields (a new one when
    /// nil, with id `newId`), stamped `now`.
    func habit(base: Habit?, newId: String, now: Int) -> Habit {
        var h = base ?? Habit(id: newId, createdAt: now)
        h.name = trimmedName
        h.emoji = emoji
        h.color = color
        h.goalKind = goalKind
        h.goal = goalKind == .count ? goal : 1
        h.step = goalKind == .count ? max(step, 0.1) : 1
        h.unit = goalKind == .count ? unit.trimmingCharacters(in: .whitespaces) : ""
        h.frequency = frequency
        h.reminders = Array(Set(reminders)).sorted()
        h.section = section
        h.startDate = startDate
        h.updatedAt = now
        h.dirty = true
        return h
    }

    /// The next reminder to add: an hour after the last, 9:00 first.
    var nextReminder: Int {
        min((reminders.max() ?? 8 * 60) + 60, 23 * 60 + 59)
    }
}

