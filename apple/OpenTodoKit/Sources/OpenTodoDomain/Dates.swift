// Calendar-date helpers, ported from `app/lib/domain/dates.dart`. Task dates
// are `Day`s (the database's `YYYY-MM-DD`) and wall-clock moments are
// `LocalDateTime`s; see `Day.swift`.
//
// Dart → Swift for the helpers that became methods on `Day`:
//
//     dateKey(d)            d.key
//     parseDateKey(s)       Day(s)        (nil if invalid)
//     dateOnly(dt)          dt.day        (LocalDateTime → Day)
//     daysBetween(a, b)     a.days(to: b) or b - a
//     addDays(d, n)         d + n         or d.adding(days: n)
//     startOfWeek(d)        d.startOfWeek
//
// Everything else keeps its Dart name. Functions that took a task's
// `String dueDate` take its `Day`.

/// 周一 … 周日, indexed by `weekday - 1`.
public let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

public func weekdayName(_ d: Day) -> String { weekdayNames[d.weekday - 1] }

/// 今天 / 明天 / 后天 / 昨天 / 周三 / 下周一 / 11月20日 / 2027年1月3日.
public func dateLabel(_ date: Day, today: Day) -> String {
    let d = today.days(to: date)
    switch d {
    case 0: return "今天"
    case 1: return "明天"
    case 2: return "后天"
    case -1: return "昨天"
    default: break
    }
    let nextWeek = today.startOfWeek + 7
    if d > 0 && date < nextWeek { return weekdayName(date) }
    if d > 0 && date < nextWeek + 7 { return "下\(weekdayName(date))" }
    if date.year == today.year { return "\(date.month)月\(date.day)日" }
    return "\(date.year)年\(date.month)月\(date.day)日"
}

/// 上午9:00 / 下午3:30.
public func timeLabel(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = floorMod(minutes, 60)
    let h12 = floorMod(h, 12) == 0 ? 12 : floorMod(h, 12)
    return "\(h < 12 ? "上午" : "下午")\(h12):\(m < 10 ? "0" : "")\(m)"
}

/// Short due label for a task row: just the time for today's timed tasks,
/// otherwise the date label. A span shows both ends: 上午9:00-11:00 today,
/// 今天-11月17日 across days.
public func dueLabel(_ dueDate: Day, _ dueTime: Int?, today: Day, duration: Int? = nil) -> String {
    let last = spanLastDay(dueDate, dueTime, duration)
    if last != dueDate { return "\(dateLabel(dueDate, today: today))-\(dateLabel(last, today: today))" }
    if let dueTime, today == dueDate {
        guard let duration else { return timeLabel(dueTime) }
        return timeRangeLabel(dueTime, dueTime + duration)
    }
    return dateLabel(dueDate, today: today)
}

/// Full label for the detail view: 明天, 下午3:00; with a span 明天,
/// 下午3:00-5:00, 今天 - 11月17日 or 今天 下午10:00 - 明天 上午1:00.
public func fullDueLabel(_ dueDate: Day, _ dueTime: Int?, today: Day, duration: Int? = nil) -> String {
    let label = dateLabel(dueDate, today: today)
    guard let end = spanEnd(dueDate, dueTime, duration), let duration else {
        return dueTime.map { "\(label), \(timeLabel($0))" } ?? label
    }
    let last = spanLastDay(dueDate, dueTime, duration)
    guard let dueTime else { return last == dueDate ? label : "\(label) - \(dateLabel(last, today: today))" }
    if last == dueDate { return "\(label), \(timeRangeLabel(dueTime, dueTime + duration))" }
    return "\(label) \(timeLabel(dueTime)) - \(dateLabel(end.day, today: today)) \(timeLabel(end.minuteOfDay))"
}

/// Section header for a day: 今天, 周日 / 11月18日, 周三.
public func daySectionTitle(_ date: Day, today: Day) -> String {
    let head = switch today.days(to: date) {
    case 0: "今天"
    case 1: "明天"
    case -1: "昨天"
    default: date.year == today.year
        ? "\(date.month)月\(date.day)日"
        : "\(date.year)年\(date.month)月\(date.day)日"
    }
    return "\(head), \(weekdayName(date))"
}

// MARK: - Spans (时间段)
//
// A task that spans a while starts at its due date and time and lasts
// `duration` minutes; the end is exclusive. An all-day span is whole days,
// so 2880 is the due date and the day after. Like due dates, spans float
// with the device's clock: the arithmetic is on wall-clock time.

public let minutesPerDay = 24 * 60

/// How long a span is when the person first asks for one, unless they set
/// otherwise (`TaskDefaults`).
public let defaultSpanMinutes = 60

/// Where a task's day or time begins: its due time, or the midnight that
/// starts its due date.
public func dueStart(_ dueDate: Day, _ dueTime: Int?) -> LocalDateTime {
    LocalDateTime(dueDate, minute: dueTime ?? 0)
}

/// Where a span ends (exclusive); nil for a task without one.
public func spanEnd(_ dueDate: Day, _ dueTime: Int?, _ duration: Int?) -> LocalDateTime? {
    guard let duration else { return nil }
    return LocalDateTime(dueDate, minute: (dueTime ?? 0) + duration)
}

/// The last day a task is on: its due date, or the day its span ends on
/// (a span ending at midnight ends the day before).
public func spanLastDay(_ dueDate: Day, _ dueTime: Int?, _ duration: Int?) -> Day {
    guard let end = spanEnd(dueDate, dueTime, duration) else { return dueDate }
    return max((end - 1).day, dueDate)
}

/// How many calendar days a task is on: 1 unless it spans midnight.
public func spanDays(_ dueDate: Day, _ dueTime: Int?, _ duration: Int?) -> Int {
    dueDate.days(to: spanLastDay(dueDate, dueTime, duration)) + 1
}

/// A span that makes sense for a task with `dueTime`: positive, and whole
/// days of two or more for an all-day task (one day is no span at all).
public func normalizeDuration(_ dueTime: Int?, _ duration: Int?) -> Int? {
    guard let duration, duration > 0 else { return nil }
    if dueTime != nil { return duration }
    let days = (duration + minutesPerDay - 1) / minutesPerDay
    return days < 2 ? nil : days * minutesPerDay
}

/// The span a task keeps when it moves between having a time and being all
/// day: the days it covered, or nothing. Same kind, same span.
public func durationForTimeChange(_ dueDate: Day, _ fromTime: Int?, _ toTime: Int?, _ duration: Int?) -> Int? {
    if (fromTime == nil) == (toTime == nil) { return duration }
    guard duration != nil, toTime == nil else { return nil }
    return normalizeDuration(nil, spanDays(dueDate, fromTime, duration) * minutesPerDay)
}

/// 上午9:00-11:00 / 上午11:30-下午12:30: the end leaves out 上午 or 下午 when
/// the start has the same.
public func timeRangeLabel(_ start: Int, _ end: Int) -> String {
    let e = floorMod(end, minutesPerDay)
    let a = timeLabel(start), b = timeLabel(e)
    return (start < 720) == (e < 720) ? "\(a)-\(b.dropFirst(2))" : "\(a)-\(b)"
}
