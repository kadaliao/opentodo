// Reminders of the efficiency module, handed to the system in the same
// budget as the tasks' (`maxScheduledReminders`, the soonest first):
//
// - a habit reminds at each of its `reminders` (minutes after midnight) on
//   the days it is due, from its start, while it isn't archived; not on a
//   day already done or given up, nor, for 每周 N 次, once the week has its
//   N. Looks a week ahead (the app reschedules long before that runs out).
// - a countdown reminds at its `reminders` before the next occurrence
//   (`countdownReminderTimes`).
//
// The events carry their kind (`ReminderKind`), so their notification ids
// can't meet a task's, and so opening one goes to the right place.

/// How far ahead habit reminders are worked out, in days (today included).
public let habitReminderDays = 7

/// The reminders still to come for tasks, habits and countdowns, soonest
/// first, at most `limit`. `snoozed` (task id → when) is the tasks' 稍后提醒.
public func upcomingReminders(
    tasks: some Sequence<TodoTask>,
    habits: some Sequence<Habit> = [Habit](),
    checkins: some Sequence<HabitCheckin> = [HabitCheckin](),
    countdowns: some Sequence<Countdown> = [Countdown](),
    now: LocalDateTime,
    limit: Int = maxScheduledReminders,
    snoozed: [String: LocalDateTime] = [:]
) -> [ReminderEvent] {
    var all = upcomingReminders(tasks, now, limit: Int.max, snoozed: snoozed)
    all += habitReminders(habits, checkins: checkins, now: now)
    all += countdownReminders(countdowns, now: now)
    // Stable: at the same minute, tasks before habits before countdowns.
    let order = Dictionary(uniqueKeysWithValues: ReminderKind.allCases.enumerated().map { ($1, $0) })
    let sorted = all.enumerated().sorted { a, b in
        a.element.at != b.element.at ? a.element.at < b.element.at
            : order[a.element.kind]! != order[b.element.kind]! ? order[a.element.kind]! < order[b.element.kind]! : a.offset < b.offset
    }
    return Array(sorted.prefix(limit).map(\.element))
}

/// The habits' reminders from `now` on, for `days` days, soonest first.
public func habitReminders(
    _ habits: some Sequence<Habit>,
    checkins: some Sequence<HabitCheckin>,
    now: LocalDateTime,
    days: Int = habitReminderDays
) -> [ReminderEvent] {
    var byHabit: [String: [Day: HabitCheckin]] = [:]
    for c in checkins where c.deletedAt == nil { byHabit[c.habitId, default: [:]][c.day] = c }
    var out: [ReminderEvent] = []
    for h in habits where h.deletedAt == nil && h.archivedAt == nil && !h.reminders.isEmpty {
        let mine = byHabit[h.id] ?? [:]
        for day in now.day ..< now.day + days where isDue(h, on: day) {
            if let c = mine[day], c.status != .partial { continue } // done or given up
            if case .timesPerWeek(let n) = h.frequency {
                let week = day.startOfWeek
                let done = (week ..< week + 7).count { mine[$0]?.isDone == true }
                if done >= n { continue }
            }
            for minute in Set(h.reminders).sorted() {
                let at = LocalDateTime(day, minute: minute)
                if at > now { out.append(habitEvent(h, at)) }
            }
        }
    }
    return out.sorted { $0.at < $1.at }
}

private func habitEvent(_ h: Habit, _ at: LocalDateTime) -> ReminderEvent {
    let name = h.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = [h.emoji, name.isEmpty ? "习惯" : name].compactMap { $0 }.joined(separator: " ")
    let body = h.goalKind == .count ? "今天的目标：\(amountText(h.target))\(h.unit)" : "该打卡了"
    return ReminderEvent(taskId: h.id, at: at, title: title, body: body, kind: .habit)
}

/// 8, 2.5 — no trailing `.0`.
func amountText(_ x: Double) -> String {
    x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : String(x)
}

/// The countdowns' reminders still ahead of `now`, soonest first: those
/// of the next occurrence that hasn't had them all yet.
public func countdownReminders(_ countdowns: some Sequence<Countdown>, now: LocalDateTime) -> [ReminderEvent] {
    var out: [ReminderEvent] = []
    for c in countdowns where c.deletedAt == nil && !c.reminders.isEmpty {
        for occurrence in countdownOccurrences(c, from: now.day, limit: 3) {
            let times = Set(c.reminders).map { LocalDateTime(occurrence, minute: $0) }.filter { $0 > now }.sorted()
            if times.isEmpty { continue }
            out += times.map { countdownEvent(c, occurrence, $0) }
            break
        }
    }
    return out.sorted { $0.at < $1.at }
}

private func countdownEvent(_ c: Countdown, _ occurrence: Day, _ at: LocalDateTime) -> ReminderEvent {
    let name = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = [c.emoji, name.isEmpty ? c.kind.name : name].compactMap { $0 }.joined(separator: " ")
    let when = "\(occurrence.month)月\(occurrence.day)日"
    let days = at.day.days(to: occurrence)
    let body = days == 0 ? "就是今天 · \(when)" : days > 0 ? "还有\(days)天 · \(when)" : "\(when)"
    return ReminderEvent(taskId: c.id, at: at, title: title, body: body, kind: .countdown)
}
