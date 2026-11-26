// What the widgets (and the macOS menu bar window) show, worked out from
// plain values so it can be tested; `WidgetStore` reads those values from
// the shared database.
//
//     let today = todayWidget(data.tasks, lists: lists, now: now, limit: 6)
//     let refresh = widgetRefreshTimes(data.tasks, now: now)   // when to redraw

import Foundation
import OpenTodoData
import OpenTodoDomain

// MARK: - 今天

/// One task line of the today widget.
public struct WidgetTask: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var priority: Priority
    /// 下午3:00 / 上午10:00-11:00 for today's, 昨天 / 11月20日 for an
    /// overdue day; nil for one due today without a time.
    public var timeText: String?
    public var overdue: Bool
    public var repeats: Bool
    /// The list's name, for the bigger sizes ("收集箱" for the inbox).
    public var listName: String

    public init(id: String, title: String, priority: Priority = .none, timeText: String? = nil, overdue: Bool = false,
                repeats: Bool = false, listName: String = "收集箱") {
        self.id = id
        self.title = title
        self.priority = priority
        self.timeText = timeText
        self.overdue = overdue
        self.repeats = repeats
        self.listName = listName
    }
}

public struct TodayWidget: Hashable, Sendable {
    /// The first few, in the order the 今天 view lists them.
    public var tasks: [WidgetTask]
    /// How many open tasks 今天 has in all (for 还有 N 项).
    public var total: Int
    /// How many of them are overdue.
    public var overdue: Int
    public var today: Day

    public init(tasks: [WidgetTask] = [], total: Int = 0, overdue: Int = 0, today: Day) {
        self.tasks = tasks
        self.total = total
        self.overdue = overdue
        self.today = today
    }

    /// 还有 3 项 under a full widget.
    public var more: Int { total - tasks.count }
}

/// The 今天 view's open tasks — overdue ones and those due today, spans
/// that have started included — in the view's own order (已过期 first,
/// then by time), the first `limit` of them as widget lines.
public func todayWidget(_ tasks: [TodoTask], lists: [TaskList], now: LocalDateTime, limit: Int) -> TodayWidget {
    let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let open = buildSections(view: .smart(.today), tasks: tasks, lists: byId, now: now)
        .filter { !$0.finished }
        .flatMap(\.tasks)
        .filter(isOpen)
    let lines = open.prefix(max(limit, 0)).map { t in
        WidgetTask(id: t.id, title: t.title.isEmpty ? "无标题" : t.title, priority: t.priority,
                   timeText: widgetTimeText(t, now: now), overdue: isOverdue(t, now),
                   repeats: t.repeatRule != nil, listName: listName(t.listId, byId))
    }
    return TodayWidget(tasks: Array(lines), total: open.count, overdue: open.count { isOverdue($0, now) }, today: now.day)
}

/// The time beside a line: the day for one from an earlier day (with its
/// time), the time or span for today's, nothing for today's all-day ones.
public func widgetTimeText(_ t: TodoTask, now: LocalDateTime) -> String? {
    guard let due = t.dueDate else { return nil }
    if due < now.day && lastDueDay(t) < now.day {
        return dueLabel(due, t.dueTime, today: now.day)
    }
    guard let time = t.dueTime else { return nil }
    if let d = t.duration, d > 0 { return timeRangeLabel(time, time + d) }
    return timeLabel(time)
}

/// When the today widget changes by itself, after `now`: the moments
/// today's timed tasks become due (a span: when it ends) — they turn red —
/// and the next midnight, when the day turns over. Earliest first, each
/// once, at most `limit` (WidgetKit wants a short timeline).
public func widgetRefreshTimes(_ tasks: [TodoTask], now: LocalDateTime, limit: Int = 24) -> [LocalDateTime] {
    var times = Set<LocalDateTime>()
    times.insert(LocalDateTime(now.day + 1))
    for t in tasks where isOpen(t) {
        guard let due = t.dueDate, let time = t.dueTime else { continue }
        let moment = spanEnd(due, time, t.duration) ?? LocalDateTime(due, minute: time)
        if now < moment && moment.day <= now.day + 1 { times.insert(moment) }
    }
    return Array(times.sorted().prefix(limit))
}

// MARK: - 习惯

public struct WidgetHabit: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var emoji: String?
    /// ARGB, as stored.
    public var color: Int?
    /// 0…1: done is 1, a count partway is its share.
    public var progress: Double
    public var done: Bool
    /// 3/8 杯 for a count; nil for a single check-in.
    public var amountText: String?

    public init(id: String, name: String, emoji: String? = nil, color: Int? = nil, progress: Double = 0,
                done: Bool = false, amountText: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.color = color
        self.progress = progress
        self.done = done
        self.amountText = amountText
    }
}

public struct HabitsWidget: Hashable, Sendable {
    public var habits: [WidgetHabit]
    public var done: Int
    public var due: Int

    public init(habits: [WidgetHabit] = [], done: Int = 0, due: Int = 0) {
        self.habits = habits
        self.done = done
        self.due = due
    }
}

/// Today's habits as the check-in page lists them (by section), each with
/// how far along today is.
public func habitsWidget(_ habits: [Habit], checkins: [HabitCheckin], today: Day) -> HabitsWidget {
    let todays = todayHabits(habits, checkins: checkins, today: today).flatMap(\.habits)
    let byKey = Dictionary(checkins.filter { $0.day == today && $0.deletedAt == nil }.map { ($0.habitId, $0) },
                           uniquingKeysWith: { a, _ in a })
    let lines = todays.map { h -> WidgetHabit in
        let c = byKey[h.id]
        let state = dayState(h, on: today, checkin: c, today: today)
        let progress: Double = switch state {
        case .done: 1
        case .partial(let p): p
        default: 0
        }
        let amount = h.goalKind == .count ? "\(trimmed(c?.value ?? 0))/\(trimmed(h.goal))\(h.unit)" : nil
        return WidgetHabit(id: h.id, name: h.name, emoji: h.emoji, color: h.color, progress: progress,
                           done: state == .done, amountText: amount)
    }
    let completion = dayCompletion(habits, checkins: checkins, on: today)
    return HabitsWidget(habits: lines, done: completion.done, due: completion.due)
}

private func trimmed(_ x: Double) -> String {
    x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
}

// MARK: - 倒数日

public struct WidgetCountdown: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var emoji: String?
    public var color: Int?
    /// The big number.
    public var days: Int
    /// 已经 / 已过 rather than 还有.
    public var past: Bool
    /// 2027年2月6日 周六 (and the lunar date for a lunar one).
    public var dateText: String

    public init(id: String, title: String, emoji: String? = nil, color: Int? = nil, days: Int, past: Bool, dateText: String) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.color = color
        self.days = days
        self.past = past
        self.dateText = dateText
    }

    /// 还有 / 已经 (an anniversary counting up) / 已过.
    public var lead: String { past ? "已经" : (days == 0 ? "就是" : "还有") }
}

/// The countdown a widget shows: the one picked (if it still exists),
/// else the first of the countdowns page (pinned, then the nearest).
public func widgetCountdown(_ countdowns: [Countdown], picked: String?, today: Day) -> WidgetCountdown? {
    let sorted = sortCountdowns(countdowns, today: today)
    guard let c = sorted.first(where: { $0.id == picked }) ?? sorted.first,
          let s = countdownStatus(c, today: today) else { return nil }
    var date = "\(s.target.year)年\(s.target.month)月\(s.target.day)日 \(weekdayName(s.target))"
    if c.lunar, let l = toLunar(s.target) { date += " · 农历\(lunarMonthName(l.month, leap: l.leap))\(lunarDayName(l.day))" }
    return WidgetCountdown(id: c.id, title: c.title, emoji: c.emoji, color: c.color, days: s.days, past: s.past,
                           dateText: date)
}

// MARK: - 专注

/// 1小时25分钟 / 25分钟 / 0分钟: today's focus time in words.
public func focusDurationText(seconds: Int) -> String {
    let minutes = max(seconds, 0) / 60
    let h = minutes / 60, m = minutes % 60
    if h > 0 { return m > 0 ? "\(h)小时\(m)分钟" : "\(h)小时" }
    return "\(m)分钟"
}

// MARK: - Reading the shared database

/// What the widgets read, from the database the app shares through its
/// App Group, opened read-only (a widget never writes; its buttons run
/// App Intents, see `SharedWriter`). No database yet (the app has never
/// run) reads as empty.
public enum WidgetStore {
    /// The shared database, read-only; nil when there isn't one yet.
    public static func open() -> AppDatabase? {
        guard let url = try? AppDatabase.defaultURL(), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? AppDatabase.openReadOnly(at: url)
    }

    public static func taskData(_ db: AppDatabase?) async -> TaskData {
        guard let db else { return .empty }
        return (try? await db.observeTaskData().first()) ?? .empty
    }

    public static func countdowns(_ db: AppDatabase?) async -> [Countdown] {
        guard let db else { return [] }
        return (try? await db.observeCountdowns().first()) ?? []
    }

    public static func habits(_ db: AppDatabase?) async -> (habits: [Habit], checkins: [HabitCheckin]) {
        guard let db else { return ([], []) }
        let habits = (try? await db.observeHabits().first()) ?? []
        let checkins = (try? await db.observeCheckins().first()) ?? []
        return (habits, checkins)
    }

    public static func focusSessions(_ db: AppDatabase?) async -> [FocusSession] {
        guard let db else { return [] }
        return (try? await db.observeFocusSessions().first()) ?? []
    }
}
