// What the calendar shows: which days each mode covers, which tasks land on
// them (a repeating task on its later dates too, a span on every day it
// covers), and how timed tasks that overlap share a day's column. Ported
// from `app/lib/domain/calendar.dart`, plus the pure parts of
// `app/lib/state/calendar_providers.dart` (the page's order for Shift-click
// and 全选, the picked tasks a drag takes along).
//
// Dart → Swift: records became structs (`CalendarSlot` for dropTarget's
// `({date, time})`, `CalendarMove`, `DayNote`); `entriesByDay` gives a
// dictionary by `Day`; `DateTime` days are `Day`s.

public enum CalendarMode: String, Sendable, Hashable, CaseIterable, Codable {
    // The raw values are the Dart enum's names, as stored in `calendar.prefs`.
    case day, threeDays, week, month, agenda
    /// Swift version only: twelve small months, each day shaded by how many
    /// tasks it has. (The Flutter version reads the name as unknown and
    /// opens the month.)
    case year
    /// Swift version only: 2 to 6 weeks of month-style rows
    /// (`CalendarPrefs.weeks`), from the anchor's week on.
    case multiWeek

    public var label: String {
        switch self {
        case .day: "日"
        case .threeDays: "3天"
        case .week: "周"
        case .month: "月"
        case .agenda: "日程"
        case .year: "年"
        case .multiWeek: "多周"
        }
    }

    /// Day, 3-day and week are hour grids.
    public var isTimeGrid: Bool { self == .day || self == .threeDays || self == .week }

    /// Nil for a name this version doesn't know.
    public static func byName(_ name: String?) -> CalendarMode? { name.flatMap(CalendarMode.init(rawValue:)) }
}

/// Calendar days from `start` up to, not including, `end`.
public struct DayRange: Sendable, Hashable, CustomStringConvertible, Sequence {
    public let start: Day
    public let end: Day

    public init(_ start: Day, _ end: Day) {
        self.start = start
        self.end = end
    }

    public var length: Int { start.days(to: end) }
    public var days: [Day] { Array(start..<end) }
    public func contains(_ d: Day) -> Bool { d >= start && d < end }
    public func makeIterator() -> Range<Day>.Iterator { (start..<Swift.max(start, end)).makeIterator() }

    public var description: String { "\(start.key)..\(end.key)" }
}

/// Whole weeks (Monday first) covering a month: what the month grid shows.
public func monthGrid(_ year: Int, _ month: Int) -> DayRange {
    let first = Day(year, month, 1)
    let last = first.endOfMonth
    return DayRange(first.startOfWeek, last.startOfWeek + 7)
}

/// How many weeks the multi-week view can show, and shows unless the
/// person picks otherwise.
public let multiWeekRange = 2...6
public let defaultMultiWeeks = 4

/// The days `mode` shows around `anchor`, the day the person is looking at.
/// `weeks` is the multi-week view's length (clamped to `multiWeekRange`).
public func visibleRange(_ mode: CalendarMode, _ anchor: Day, weeks: Int = defaultMultiWeeks) -> DayRange {
    let a = anchor
    switch mode {
    case .year: return DayRange(Day(a.year, 1, 1), Day(a.year + 1, 1, 1))
    case .multiWeek: return DayRange(a.startOfWeek, a.startOfWeek + 7 * clampWeeks(weeks))
    case .day: return DayRange(a, a + 1)
    case .threeDays: return DayRange(a, a + 3)
    case .week: return DayRange(a.startOfWeek, a.startOfWeek + 7)
    case .month: return monthGrid(a.year, a.month)
    case .agenda: return DayRange(a.startOfMonth, a.endOfMonth + 1)
    }
}

/// The anchor one page on (or back, for a negative `pages`). Month pages
/// keep the day of the month where they can (31 Jan → 28 Feb), year pages
/// likewise (29 Feb → 28 Feb); a multi-week page is `weeks` weeks.
public func shiftAnchor(_ mode: CalendarMode, _ anchor: Day, _ pages: Int, weeks: Int = defaultMultiWeeks) -> Day {
    switch mode {
    case .year: anchor.addingMonths(12 * pages)
    case .multiWeek: anchor + 7 * clampWeeks(weeks) * pages
    case .day: anchor + pages
    case .threeDays: anchor + 3 * pages
    case .week: anchor + 7 * pages
    case .month, .agenda: anchor.addingMonths(pages)
    }
}

/// 2026年11月; a week running into the next month, 2026年11月–12月; the
/// year view 2026年; the multi-week view the months its weeks run across.
public func calendarTitle(_ mode: CalendarMode, _ anchor: Day, weeks: Int = defaultMultiWeeks) -> String {
    switch mode {
    case .year: return "\(anchor.year)年"
    case .multiWeek: return spanTitle(visibleRange(mode, anchor, weeks: weeks))
    case _ where mode.isTimeGrid: return spanTitle(visibleRange(mode, anchor))
    default: return "\(anchor.year)年\(anchor.month)月"
    }
}

func clampWeeks(_ weeks: Int) -> Int { min(max(weeks, multiWeekRange.lowerBound), multiWeekRange.upperBound) }

/// The months a range of days runs across: 2026年11月, 2026年11月–12月,
/// 2026年12月–2027年1月.
func spanTitle(_ r: DayRange) -> String {
    func ym(_ d: Day) -> String { "\(d.year)年\(d.month)月" }
    let first = r.start, last = r.end - 1
    if first.year == last.year && first.month == last.month { return ym(first) }
    if first.year == last.year { return "\(ym(first))–\(last.month)月" }
    return "\(ym(first))–\(ym(last))"
}

/// One task on one day of the calendar. A task that spans days has an
/// entry on each of them.
public struct CalendarEntry: Sendable, Hashable, Identifiable, CustomStringConvertible {
    public let task: TodoTask

    /// The day this entry is on.
    public let date: Day

    /// The day this occurrence of the task starts: `date`, unless it is a
    /// later day of a span.
    public let occurrence: Day

    /// A later date of a repeating task, shown ahead of time. Only the
    /// task's own date is real: a projected one can't be ticked off or moved.
    public let projected: Bool

    public init(_ task: TodoTask, _ date: Day, projected: Bool = false, occurrence: Day? = nil) {
        self.task = task
        self.date = date
        self.projected = projected
        self.occurrence = occurrence ?? date
    }

    /// Which day of its span this is; 0 for the first.
    public var dayIndex: Int { occurrence.days(to: date) }

    public var allDay: Bool { task.dueTime == nil }
    public var done: Bool { task.status != .open }

    /// Minutes after midnight where the task starts on this day: its time
    /// on its first day, midnight on the days a span runs on into. Nil all
    /// day.
    public var time: Int? { allDay ? nil : (dayIndex == 0 ? task.dueTime : 0) }

    /// Where a timed span stops on this day (exclusive, at most midnight);
    /// nil for a task at one moment.
    public var endTime: Int? {
        guard !allDay, let d = task.duration, let t = task.dueTime else { return nil }
        return min(t + d - dayIndex * minutesPerDay, minutesPerDay)
    }

    /// Unique within a calendar page: a span's later days, and the days
    /// where occurrences of a repeating span overlap, are told apart by
    /// `dayIndex`.
    public var key: String { "\(task.id)@\(date.key)\(dayIndex == 0 ? "" : "+\(dayIndex)")" }
    public var id: String { key }

    public var description: String { key + (projected ? "*" : "") }
}

/// What the person chose to see.
public struct CalendarFilter: Sendable, Hashable {
    public var showCompleted: Bool
    /// Show every later date of a repeating task, not just the next one.
    public var showRepeats: Bool
    /// Lists (by id, `inboxListId` included) left off the calendar.
    public var hiddenLists: Set<String>

    public init(showCompleted: Bool = true, showRepeats: Bool = true, hiddenLists: Set<String> = []) {
        self.showCompleted = showCompleted
        self.showRepeats = showRepeats
        self.hiddenLists = hiddenLists
    }
}

/// A daily task looked at decades ahead stops here.
private let maxProjected = 20000

/// The tasks on the days of `range`, in display order. A span shows on
/// each day it covers.
///
/// A repeating task also shows on the dates it will move to, which are all
/// after `today`: finishing an overdue one skips the dates already passed
/// (see `advanceRepeat`), and one counted from completion starts again from
/// the day it's done.
public func calendarEntries(
    _ tasks: some Sequence<TodoTask>,
    _ range: DayRange,
    today: Day,
    filter: CalendarFilter = CalendarFilter()
) -> [CalendarEntry] {
    var out: [CalendarEntry] = []
    for t in tasks {
        guard let dueDate = t.dueDate, t.trashedAt == nil, !filter.hiddenLists.contains(t.listId) else { continue }
        let open = t.status == .open
        if !open && !filter.showCompleted { continue }
        // Wall-clock spans cover as many days wherever they start.
        let days = spanDays(dueDate, t.dueTime, t.duration)
        func addOccurrence(_ start: Day, projected: Bool = false) {
            for i in 0..<days {
                let d = start + i
                if range.contains(d) { out.append(CalendarEntry(t, d, projected: projected, occurrence: start)) }
            }
        }

        addOccurrence(dueDate)
        if !open || !filter.showRepeats || dueDate >= range.end { continue }
        guard let rule = RepeatRule.tryParse(t.repeatRule) else { continue }
        let from = t.repeatFrom == .completion && dueDate < today ? today : dueDate
        let reach = range.start + (1 - days)
        var steps = 0
        for d in occurrencesAfter(rule, from) {
            steps += 1
            if d >= range.end || steps > maxProjected { break }
            if d > today && d >= reach { addOccurrence(d, projected: true) }
        }
    }
    return out.sorted { compareEntries($0, $1) < 0 }
}

/// By day; within a day open before finished, all-day before timed (spans
/// that began earlier first), then by time and priority.
public func compareEntries(_ a: CalendarEntry, _ b: CalendarEntry) -> Int {
    if a.date != b.date { return a.date < b.date ? -1 : 1 }
    if a.done != b.done { return a.done ? 1 : -1 }
    let at = a.time ?? -1, bt = b.time ?? -1
    if at != bt { return at < bt ? -1 : 1 }
    if a.dayIndex != b.dayIndex { return b.dayIndex < a.dayIndex ? -1 : 1 }
    return compareByPriority(a.task, b.task)
}

/// Entries by day, each day's in display order (the order they came in).
public func entriesByDay(_ entries: some Sequence<CalendarEntry>) -> [Day: [CalendarEntry]] {
    var out: [Day: [CalendarEntry]] = [:]
    for e in entries { out[e.date, default: []].append(e) }
    return out
}

/// Where a timed entry sits in its day's column.
public struct TimedPlacement: Sendable, Hashable, CustomStringConvertible {
    public let entry: CalendarEntry
    /// Minutes after midnight; `end` is exclusive.
    public let start: Int
    public let end: Int
    /// Side by side with `columns` - 1 others it overlaps, in slot `column`.
    public let column: Int
    public let columns: Int

    public var description: String { "\(entry.task.title) \(start)-\(end) \(column)/\(columns)" }
}

/// Lays out one day's timed entries. A span runs to its end on this day; a
/// task at one moment takes `span` minutes (cut short at midnight). Entries
/// that overlap share the width, each in the first free slot, as in most
/// calendars; anything shorter than `span` still takes that much room, as
/// it is drawn no smaller.
public func layoutTimed(_ entries: some Sequence<CalendarEntry>, span: Int = 30) -> [TimedPlacement] {
    let timed = entries.filter { $0.time != nil }.sorted { a, b in
        if a.time! != b.time! { return a.time! < b.time! }
        return compareEntries(a, b) < 0
    }
    var out: [TimedPlacement] = []
    var cluster: [(entry: CalendarEntry, start: Int, end: Int, column: Int)] = []
    var slotEnds: [Int] = []
    var clusterEnd = -1

    func flush() {
        for c in cluster {
            out.append(TimedPlacement(entry: c.entry, start: c.start, end: c.end, column: c.column, columns: slotEnds.count))
        }
        cluster = []
        slotEnds = []
    }

    for e in timed {
        let start = min(max(e.time!, 0), minutesPerDay - 1)
        let end = min(max(e.endTime ?? start + span, start + 1), minutesPerDay)
        let room = min(max(end, start + span), minutesPerDay)
        if start >= clusterEnd { flush() }
        let column: Int
        if let free = slotEnds.firstIndex(where: { $0 <= start }) {
            column = free
            slotEnds[free] = room
        } else {
            column = slotEnds.count
            slotEnds.append(room)
        }
        cluster.append((e, start, end, column))
        clusterEnd = max(clusterEnd, room)
    }
    flush()
    return out
}

/// Where a task starts: a day, at a time or all day (nil).
public struct CalendarSlot: Sendable, Hashable, CustomStringConvertible {
    public let date: Day
    public let time: Int?

    public init(date: Day, time: Int?) {
        self.date = date
        self.time = time
    }

    public var description: String { date.key + (time.map { " " + clockLabel($0) } ?? "") }
}

/// Where the task behind `e` starts once the entry is dropped on `day`: in
/// the all-day row (`allDay`), at `minute` on an hour grid, or else on a
/// month cell, which keeps its time. A span moves as a whole: dropping its
/// second day on Friday starts it on Thursday, and a timed one moves by as
/// many minutes as the dropped part did.
public func dropTarget(_ e: CalendarEntry, _ day: Day, minute: Int? = nil, allDay: Bool = false) -> CalendarSlot {
    let shifted = day - e.dayIndex
    if allDay { return CalendarSlot(date: shifted, time: nil) }
    guard let minute else { return CalendarSlot(date: shifted, time: e.task.dueTime) }
    guard let dueTime = e.task.dueTime, let time = e.time else { return CalendarSlot(date: day, time: minute) }
    let delta = e.date.days(to: day) * minutesPerDay + minute - time
    let start = LocalDateTime(e.occurrence, minute: dueTime + delta)
    return CalendarSlot(date: start.day, time: start.minuteOfDay)
}

/// Where a task goes: the day it starts on, at a time or all day (nil).
public struct CalendarMove: Sendable, Hashable, CustomStringConvertible {
    public let id: String
    public let date: Day
    public let time: Int?

    public init(id: String, date: Day, time: Int?) {
        self.id = id
        self.date = date
        self.time = time
    }

    public var description: String { "\(id) \(date.key)" + (time.map { " " + clockLabel($0) } ?? "") }
}

/// Where tasks dragged together (多选) go when the one under the pointer,
/// `lead`, is dropped on `day` as in `dropTarget`: `lead` first, then each
/// of `others` that is open and has a date. They all move by as many days
/// as `lead` does. Those of `lead`'s kind (timed, or all day) also do what
/// it does: into the all-day row they lose their time, onto the hour grid
/// a timed one moves by as many minutes and an all-day one takes the time
/// it's dropped at. The rest keep their time, or stay all day; on a month
/// cell everyone does.
public func dropTargets(
    _ lead: CalendarEntry,
    _ others: some Sequence<TodoTask>,
    _ day: Day,
    minute: Int? = nil,
    allDay: Bool = false
) -> [CalendarMove] {
    let to = dropTarget(lead, day, minute: minute, allDay: allDay)
    let days = lead.occurrence.days(to: to.date)
    // On the wall clock, as dropTarget counts.
    let minutes = lead.allDay || to.time == nil ? 0 : days * minutesPerDay + to.time! - lead.task.dueTime!
    var out = [CalendarMove(id: lead.task.id, date: to.date, time: to.time)]
    for t in others {
        guard t.id != lead.task.id, let date = t.dueDate, t.status == .open, t.trashedAt == nil else { continue }
        let shifted = date + days
        let sameKind = (t.dueTime == nil) == lead.allDay
        if !sameKind || (minute == nil && !allDay) {
            out.append(CalendarMove(id: t.id, date: shifted, time: t.dueTime))
        } else if allDay || lead.allDay {
            // Into the all-day row, or onto the hour at `minute` with an
            // all-day lead.
            out.append(CalendarMove(id: t.id, date: shifted, time: to.time))
        } else {
            let start = LocalDateTime(date, minute: t.dueTime! + minutes)
            out.append(CalendarMove(id: t.id, date: start.day, time: start.minuteOfDay))
        }
    }
    return out
}

/// The tasks behind `entries` in the order shown, each once and leaving out
/// the later dates of repeating ones: what Shift-click ranges and 全选 on
/// the calendar go by.
public func entryOrder(_ entries: some Sequence<CalendarEntry>) -> [String] {
    var seen = Set<String>()
    return entries.compactMap { e in !e.projected && seen.insert(e.task.id).inserted ? e.task.id : nil }
}

/// The order for Shift-click and 全选 on a calendar page showing `range` in
/// `mode` (Dart's `calendarOrderProvider`): in the agenda only the days it
/// shows, from `agendaFrom` on.
public func calendarOrder(_ entries: [CalendarEntry], mode: CalendarMode, range: DayRange, today: Day) -> [String] {
    guard mode == .agenda else { return entryOrder(entries) }
    let from = agendaFrom(range, today)
    return entryOrder(entries.filter { $0.date >= from })
}

/// The picked tasks (多选) a drag on the calendar takes along: the open
/// ones with a date (Dart's `calendarPickedProvider`), in `tasks`' order.
public func calendarPicked(_ tasks: some Sequence<TodoTask>, ids: Set<String>) -> [TodoTask] {
    if ids.isEmpty { return [] }
    return tasks.filter { ids.contains($0.id) && $0.dueDate != nil && $0.status == .open && $0.trashedAt == nil }
}

/// The first day the agenda shows of `range`: today in the current month,
/// else the month's first day. The agenda looks ahead.
public func agendaFrom(_ range: DayRange, _ today: Day) -> Day {
    range.contains(today) ? today : range.start
}

/// What a day on the calendar says beside its number: a festival's name or
/// else the lunar day (`special` for a festival), and whether the holiday
/// schedule has it off (休, true) or worked (班, false).
public struct DayNote: Sendable, Hashable {
    public let label: String
    public let special: Bool
    public let off: Bool?

    public init(label: String, special: Bool, off: Bool?) {
        self.label = label
        self.special = special
        self.off = off
    }
}

public func dayNote(_ date: Day) -> DayNote {
    let solar: String? = switch (date.month, date.day) {
    case (1, 1): "元旦"
    case (5, 1): "劳动节"
    case (10, 1): "国庆节"
    default: nil
    }
    let festival = lunarFestival(date) ?? solar
    let lunar = toLunar(date)
    return DayNote(
        label: festival ?? lunar.map(lunarCalendarLabel) ?? "",
        special: festival != nil,
        off: holidayOn(date)?.off
    )
}

/// Rounds `minutes` down to a whole `step` that still fits in the day.
public func snapMinutes(_ minutes: Double, step: Int = 15) -> Int {
    let m = Int((minutes / Double(step)).rounded(.down)) * step
    return min(max(m, 0), minutesPerDay - step)
}

/// 09:00.
public func clockLabel(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return (h < 10 ? "0" : "") + "\(h):" + (m < 10 ? "0" : "") + "\(m)"
}
