// Countdowns and anniversaries (倒数纪念日): the record and the pure logic
// for the next date, the days to go or gone, the ways to show them, ages,
// the order of the list and what shows on 今天. New in the Swift version
// (roadmap M5); the conventions are written up in `docs/apple.md` (效率模块).
//
// `date` is the event's own (Gregorian) date: the day counted to, or the
// day it all began (a birthday, the day two people met). A lunar one
// repeats on that day's lunar month and day, the way a lunar repeating task
// does (`Recurrence.swift`): yearly on the ordinary month (a date in a leap
// month repeats in the month it repeats), a thirtieth the month hasn't got
// falls on its 29th. Gregorian ones keep the day of the month and, in a
// month too short for it, take the month's last day (a 2月29日 birthday is
// on the 28th in other years; 每月31日 is on the 30th in a 30-day month).
//
// "Today" is passed in; nothing here depends on the clock or the time zone.

/// What kind of day it is; it decides how the card counts.
public enum CountdownKind: Int, Sendable, Hashable, Codable, CaseIterable {
    /// 倒数日: counts down to the date (and the days since, once it's past).
    case countdown = 0
    /// 纪念日: counts up from the date, once it has come.
    case anniversary = 1
    /// 生日: counts down to the next one, with the age it brings.
    case birthday = 2
    /// 节日: counts down to the next one.
    case holiday = 3

    /// Unknown numbers read as `countdown`.
    public init(from decoder: any Decoder) throws {
        self = CountdownKind(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .countdown
    }

    public var name: String {
        switch self {
        case .countdown: "倒数日"
        case .anniversary: "纪念日"
        case .birthday: "生日"
        case .holiday: "节日"
        }
    }
}

public enum CountdownRepeat: Int, Sendable, Hashable, Codable, CaseIterable {
    case none = 0
    case yearly = 1
    case monthly = 2

    /// Unknown numbers read as `none`.
    public init(from decoder: any Decoder) throws {
        self = CountdownRepeat(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .none
    }
}

/// A countdown or anniversary (倒数日 / 纪念日 / 生日 / 节日).
public struct Countdown: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var title: String
    public var kind: CountdownKind
    /// The event's date (Gregorian, even for a lunar one).
    public var date: Day
    /// Repeats by the lunar calendar (农历).
    public var lunar: Bool
    public var repeats: CountdownRepeat
    public var emoji: String?
    /// ARGB, as `TaskList.color`.
    public var color: Int?
    /// Shown in the 今天 smart list on its day.
    public var showInToday: Bool
    /// Minutes from the midnight that starts the day (the next occurrence),
    /// like an all-day task's reminders: `-1440 + 540` is the day before at
    /// 9:00. See `countdownReminder(daysBefore:minute:)`.
    public var reminders: [Int]
    /// When it was pinned (置顶), epoch milliseconds; nil if it isn't.
    public var pinnedAt: Int?
    public var sortOrder: Double

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    public init(
        id: String,
        title: String = "",
        kind: CountdownKind = .countdown,
        date: Day = Day(2000, 1, 1),
        lunar: Bool = false,
        repeats: CountdownRepeat = .none,
        emoji: String? = nil,
        color: Int? = nil,
        showInToday: Bool = false,
        reminders: [Int] = [],
        pinnedAt: Int? = nil,
        sortOrder: Double = 0,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.date = date
        self.lunar = lunar
        self.repeats = repeats
        self.emoji = emoji
        self.color = color
        self.showInToday = showInToday
        self.reminders = reminders
        self.pinnedAt = pinnedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }
}

/// A reminder `daysBefore` days ahead at `minute` (minutes after midnight),
/// as `Countdown.reminders` stores it.
public func countdownReminder(daysBefore: Int, minute: Int) -> Int { -daysBefore * minutesPerDay + minute }

/// The days ahead and the time of day of a stored reminder.
public func countdownReminderParts(_ offset: Int) -> (daysBefore: Int, minute: Int) {
    (-floorDiv(offset, minutesPerDay), floorMod(offset, minutesPerDay))
}

// MARK: - Dates

/// The occurrence the card is about as of `today`: the date itself while
/// it's still ahead (or a one-off's, ever after); for a repeating one, the
/// first occurrence on or after today. Nil when a lunar date is outside the
/// table (1900–2100).
public func countdownTarget(_ c: Countdown, today: Day) -> Day? {
    if c.date >= today || c.repeats == .none { return c.lunar && toLunar(c.date) == nil ? nil : c.date }
    return c.lunar ? lunarOccurrence(c, onOrAfter: today) : solarOccurrence(c, onOrAfter: today)
}

/// The occurrences of a repeating countdown from `from` on, in order, up to
/// `limit` of them (fewer when it doesn't repeat, or past the lunar table).
public func countdownOccurrences(_ c: Countdown, from: Day, limit: Int) -> [Day] {
    var out: [Day] = []
    var d = max(from, c.date)
    while out.count < limit {
        guard let next = d == c.date ? (c.lunar && toLunar(d) == nil ? nil : d)
            : (c.lunar ? lunarOccurrence(c, onOrAfter: d) : solarOccurrence(c, onOrAfter: d))
        else { break }
        out.append(next)
        if c.repeats == .none { break }
        d = next + 1
    }
    return out
}

private func solarOccurrence(_ c: Countdown, onOrAfter from: Day) -> Day? {
    let (_, month, day) = c.date.parts
    switch c.repeats {
    case .none:
        return nil
    case .yearly:
        for y in from.year...from.year + 1 {
            let d = Day(y, month, min(day, Day.daysIn(year: y, month: month)))
            if d >= from { return d }
        }
    case .monthly:
        for k in 0...1 {
            let first = Day(from.year, from.month + k, 1)
            let d = Day(first.year, first.month, min(day, first.daysInMonth))
            if d >= from { return d }
        }
    }
    return nil
}

private func lunarOccurrence(_ c: Countdown, onOrAfter from: Day) -> Day? {
    guard let l = toLunar(c.date), let start = toLunar(from) else { return nil }
    switch c.repeats {
    case .none:
        return nil
    case .yearly:
        // The ordinary month, a missing thirtieth on the 29th.
        for y in start.year...start.year + 1 {
            if let d = fromLunar(y, l.month, l.day, clampDay: true), d >= from { return d }
        }
    case .monthly:
        // Every month, leap ones included.
        for y in start.year...start.year + 1 {
            for m in lunarMonths(y) {
                let d = m.start + (min(l.day, m.length) - 1)
                if d >= from { return d }
            }
        }
    }
    return nil
}

/// What a card shows: the days, and whether they're still to go.
public struct CountdownStatus: Sendable, Hashable {
    /// The day counted to (or from, for one that counts up).
    public var target: Day
    /// Days between today and `target`, never negative.
    public var days: Int
    /// The days are gone by (已经 / 已过) rather than to go (还有).
    public var past: Bool

    public init(target: Day, days: Int, past: Bool) {
        self.target = target
        self.days = days
        self.past = past
    }
}

/// How the card counts as of `today`. An anniversary counts up from its
/// date once that has come (已经 N 天); everything else counts down to its
/// next occurrence (还有 N 天), and a one-off that has gone by counts the
/// days since. Nil outside the lunar table.
public func countdownStatus(_ c: Countdown, today: Day) -> CountdownStatus? {
    if c.kind == .anniversary && c.date <= today {
        return CountdownStatus(target: c.date, days: c.date.days(to: today), past: true)
    }
    guard let t = countdownTarget(c, today: today) else { return nil }
    return CountdownStatus(target: t, days: abs(today.days(to: t)), past: t < today)
}

/// Days from today to the target: positive ahead, negative gone by.
public func countdownDays(_ c: Countdown, today: Day) -> Int? {
    countdownStatus(c, today: today).map { $0.past ? -$0.days : $0.days }
}

// MARK: - Display

/// The ways a card can show the time.
public enum CountdownFormat: String, Sendable, Hashable, Codable, CaseIterable {
    /// 83天
    case days
    /// 1年2个月3天
    case yearsMonthsDays
    /// 11周6天
    case weeksDays
}

/// Whole years, months and days from `a` to `b` (either order): months are
/// counted by the day of the month, clamped like `Day.addingMonths` (1月31日
/// to 2月28日 is one month).
public func calendarSpan(_ a: Day, _ b: Day) -> (years: Int, months: Int, days: Int) {
    let (from, to) = a <= b ? (a, b) : (b, a)
    var months = (to.year - from.year) * 12 + to.month - from.month
    if from.addingMonths(months) > to { months -= 1 }
    let days = from.addingMonths(months).days(to: to)
    return (months / 12, months % 12, days)
}

/// The time between `today` and `target` in `format`, zero parts left
/// out: 83天, 2个月23天, 1年3天, 11周6天, 3周. The same day is 今天.
public func countdownText(from today: Day, to target: Day, format: CountdownFormat) -> String {
    let n = abs(today.days(to: target))
    if n == 0 { return "今天" }
    switch format {
    case .days:
        return "\(n)天"
    case .weeksDays:
        let (w, d) = (n / 7, n % 7)
        return (w > 0 ? "\(w)周" : "") + (d > 0 ? "\(d)天" : "")
    case .yearsMonthsDays:
        let (y, m, d) = calendarSpan(today, target)
        return (y > 0 ? "\(y)年" : "") + (m > 0 ? "\(m)个月" : "") + (d > 0 ? "\(d)天" : "")
    }
}

/// The card's number in `format` as of `today`; nil outside the lunar table.
public func countdownText(_ c: Countdown, today: Day, format: CountdownFormat) -> String? {
    countdownStatus(c, today: today).map { countdownText(from: today, to: $0.target, format: format) }
}

/// The age (周岁) on `day` of someone born on `c.date`, by the calendar the
/// countdown uses: a birthday on the lunar calendar adds a year on the
/// lunar birthday. Nil before the birth or outside the lunar table.
public func countdownAge(_ c: Countdown, on day: Day) -> Int? {
    guard day >= c.date else { return nil }
    if c.lunar {
        guard let born = toLunar(c.date), let now = toLunar(day),
              let birthday = fromLunar(now.year, born.month, born.day, clampDay: true)
        else { return nil }
        return now.year - born.year - (day < birthday && now.year > born.year ? 1 : 0)
    }
    let (y, m, d) = c.date.parts
    let birthday = Day(day.year, m, min(d, Day.daysIn(year: day.year, month: m)))
    return day.year - y - (day < birthday ? 1 : 0)
}

// MARK: - Lists

/// The countdowns page in order: deleted ones left out, pinned ones first;
/// in each part those still ahead (soonest first), then those gone by (most
/// recent first); then by `sortOrder`.
public func sortCountdowns(_ cs: [Countdown], today: Day) -> [Countdown] {
    let keyed = cs.filter { $0.deletedAt == nil }.map { c in
        (c, countdownStatus(c, today: today))
    }
    return keyed.sorted { a, b in
        let ap = a.0.pinnedAt != nil, bp = b.0.pinnedAt != nil
        if ap != bp { return ap }
        // Ahead before gone by; outside the table last.
        let ar = a.1.map { $0.past ? 1 : 0 } ?? 2, br = b.1.map { $0.past ? 1 : 0 } ?? 2
        if ar != br { return ar < br }
        let ad = a.1?.days ?? 0, bd = b.1?.days ?? 0
        if ad != bd { return ad < bd }
        if a.0.sortOrder != b.0.sortOrder { return a.0.sortOrder < b.0.sortOrder }
        return a.0.id < b.0.id
    }.map(\.0)
}

/// The countdowns 今天 shows: those marked for it whose day is today.
public func todayCountdowns(_ cs: [Countdown], today: Day) -> [Countdown] {
    sortCountdowns(cs.filter { $0.showInToday && countdownTarget($0, today: today) == today }, today: today)
}

/// The reminders of the next occurrence still ahead of `now`, earliest
/// first. A repeating countdown whose reminders for this occurrence have all
/// gone off reminds of the next one.
public func countdownReminderTimes(_ c: Countdown, now: LocalDateTime) -> [LocalDateTime] {
    guard !c.reminders.isEmpty else { return [] }
    for occurrence in countdownOccurrences(c, from: now.day, limit: 3) {
        let times = c.reminders.map { LocalDateTime(occurrence, minute: $0) }.filter { $0 > now }.sorted()
        if !times.isEmpty { return times }
    }
    return []
}
