// When a task's reminders go off, and what they are called. Ported from
// `app/lib/domain/reminders.dart`.
//
// A reminder is stored as minutes relative to the task's due moment: its
// due time, or the midnight that starts its day for an all-day task.
// Negative means before, as in iCalendar's TRIGGER, so 0 is 准时, -30 is
// 提前30分钟, and for an all-day task 540 is 当天 09:00 and -900 is
// 提前1天 09:00. Like task dates, reminders float with the device's clock:
// everything here is `LocalDateTime`; the scheduler turns it into a `Date`.

import Foundation

/// Offered for a task with a time: 准时, 提前5分钟, 30分钟, 1小时, 1天.
public let timedReminderPresets = [0, -5, -30, -60, -1440]

/// Offered for an all-day task: 当天 / 提前1天 / 提前2天 / 提前1周, at 09:00.
public let allDayReminderPresets = [540, -900, -2340, -9540]

/// The moment a reminder goes off, in wall-clock time. Wall-clock
/// arithmetic, so 提前1天 stays at the same time across DST.
public func reminderTime(_ dueDate: Day, _ dueTime: Int?, _ offset: Int) -> LocalDateTime {
    LocalDateTime(dueDate, minute: (dueTime ?? 0) + offset)
}

private func spanWords(_ minutes: Int) -> String {
    if minutes % 10080 == 0 { return "\(minutes / 10080)周" }
    let d = minutes / 1440, h = minutes % 1440 / 60, m = minutes % 60
    return (d > 0 ? "\(d)天" : "") + (h > 0 ? "\(h)小时" : "") + (m > 0 ? "\(m)分钟" : "")
}

private func clock(_ minuteOfDay: Int) -> String {
    let h = minuteOfDay / 60, m = minuteOfDay % 60
    return (h < 10 ? "0" : "") + "\(h):" + (m < 10 ? "0" : "") + "\(m)"
}

/// 准时 / 提前30分钟 / 提前1天 for a timed task; 当天 09:00 / 提前1天 09:00
/// for an all-day one.
public func reminderLabel(_ offset: Int, allDay: Bool) -> String {
    if allDay {
        let days = floorDiv(offset, 1440)
        let at = clock(offset - days * 1440)
        if days == 0 { return "当天 \(at)" }
        if days < 0 { return "提前\(spanWords(-days * 1440)) \(at)" }
        return "\(days)天后 \(at)"
    }
    if offset == 0 { return "准时" }
    return offset < 0 ? "提前\(spanWords(-offset))" : "延后\(spanWords(offset))"
}

/// Reminders in the order they go off, each once.
public func sortedReminders(_ offsets: some Sequence<Int>) -> [Int] { Set(offsets).sorted() }

/// The reminders, in words, for the detail view.
public func remindersSummary(_ offsets: [Int], allDay: Bool) -> String {
    sortedReminders(offsets).map { reminderLabel($0, allDay: allDay) }.joined(separator: "、")
}

/// What a reminder is about. Tasks are the Flutter version's; habits and
/// countdowns are the efficiency module's (see `EfficiencyReminders.swift`).
public enum ReminderKind: String, Sendable, Hashable, CaseIterable {
    case task, habit, countdown
}

/// A reminder to hand to the system.
public struct ReminderEvent: Sendable, Hashable, CustomStringConvertible {
    /// The id of the task, or of the habit or countdown for those kinds.
    public let taskId: String
    public let at: LocalDateTime
    public let title: String
    public let body: String
    public let kind: ReminderKind

    public init(taskId: String, at: LocalDateTime, title: String, body: String, kind: ReminderKind = .task) {
        self.taskId = taskId
        self.at = at
        self.title = title
        self.body = body
        self.kind = kind
    }

    /// Stable for the same task and minute, so rescheduling the same
    /// reminder leaves the system's copy alone. Same number the Dart
    /// version gave, so pending notifications it left can be matched.
    /// Habits and countdowns hash `habit:<id>` / `countdown:<id>`, so they
    /// never take a task's number.
    public func id(in timeZone: TimeZone = .current) -> Int {
        notificationId(kind == .task ? taskId : "\(kind.rawValue):\(taskId)", at, in: timeZone)
    }

    public var description: String { "ReminderEvent(\(kind == .task ? "" : kind.rawValue + " ")\(taskId) @ \(at): \(title) / \(body))" }
}

/// FNV-1a over the task id and the minute (since the Unix epoch, of `at`
/// as an instant in `timeZone`), cut to 31 bits (Android wants a positive
/// 32-bit int). The same function as the Dart version, which used the
/// local `DateTime`'s `millisecondsSinceEpoch ~/ 60000`.
public func notificationId(_ taskId: String, _ at: LocalDateTime, in timeZone: TimeZone = .current) -> Int {
    let ms = Int((at.date(in: timeZone).timeIntervalSince1970 * 1000).rounded())
    var h: UInt32 = 0x811c_9dc5
    for c in "\(taskId)@\(ms / 60000)".utf16 {
        h ^= UInt32(c)
        h = h &* 0x0100_0193
    }
    return Int(h & 0x7fff_ffff)
}

/// The system keeps only so many pending notifications (iOS and macOS: 64),
/// so only the soonest are handed over; the rest follow as these fire and
/// the app reschedules.
public let maxScheduledReminders = 48

/// The reminders still to come for open tasks, soonest first, with the
/// ones put off with 稍后提醒 (`snoozed`: task id → when it comes back).
public func upcomingReminders(
    _ tasks: some Sequence<TodoTask>,
    _ now: LocalDateTime,
    limit: Int = maxScheduledReminders,
    snoozed: [String: LocalDateTime] = [:]
) -> [ReminderEvent] {
    var out: [ReminderEvent] = []
    func event(_ t: TodoTask, _ at: LocalDateTime) -> ReminderEvent {
        let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReminderEvent(taskId: t.id, at: at, title: title.isEmpty ? "无标题" : title, body: reminderBody(t, at.day))
    }
    for t in tasks {
        guard let due = t.dueDate else { continue }
        if t.status != .open || t.trashedAt != nil || t.deletedAt != nil { continue }
        var seen = Set<Int>()
        for offset in t.reminders where seen.insert(offset).inserted {
            let at = reminderTime(due, t.dueTime, offset)
            if at > now { out.append(event(t, at)) }
        }
        if let snooze = snoozed[t.id], snooze > now { out.append(event(t, snooze)) }
    }
    out.sort { $0.at < $1.at }
    return Array(out.prefix(limit))
}

/// 今天, 下午3:00 · 带上电脑. Worded for the day the reminder shows up.
private func reminderBody(_ t: TodoTask, _ onDay: Day) -> String {
    let when = fullDueLabel(t.dueDate!, t.dueTime, today: onDay, duration: t.duration)
    let firstLine = t.content.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    let note = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if note.isEmpty { return when }
    // 60 characters (Dart counted UTF-16 units, which could cut an emoji in half).
    return "\(when) · \(note.count > 60 ? note.prefix(60) + "…" : note)"
}
