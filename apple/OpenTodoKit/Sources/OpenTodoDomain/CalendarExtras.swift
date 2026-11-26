// Calendar additions of the Swift version (路线图“日历补充”), with no Flutter
// counterpart: the year view's small months and how busy each day is, the
// rows of a month or multi-week grid with tasks that span days drawn as one
// bar, and the 安排任务 panel of tasks without a date to drag onto the
// calendar. The year and multi-week ranges themselves are `CalendarMode`
// cases (`Calendar.swift`).

// MARK: - Year view

/// The twelve month grids of `year`, January first (`monthGrid` each: whole
/// weeks, so a small month shows its neighbours' days dimmed or blank).
public func yearMonths(_ year: Int) -> [DayRange] { (1...12).map { monthGrid(year, $0) } }

/// How many tasks each day has: distinct tasks among `entries` (a span
/// counts on each day it covers; a projected repeat counts like a real
/// one). Days without any are left out. Pass the year's
/// `calendarEntries`, already filtered by the person's choices.
public func dayDensity(_ entries: some Sequence<CalendarEntry>) -> [Day: Int] {
    var ids: [Day: Set<String>] = [:]
    for e in entries { ids[e.date, default: []].insert(e.task.id) }
    return ids.mapValues(\.count)
}

/// A shade for a day of the year view: 0 none, 1 one task, 2 two or three,
/// 3 four or five, 4 six or more (like the shading of a contribution
/// calendar).
public func densityLevel(_ count: Int) -> Int {
    switch count {
    case ...0: 0
    case 1: 1
    case 2...3: 2
    case 4...5: 3
    default: 4
    }
}

// MARK: - Bars across a week row

/// The weeks of a grid range (a month grid, the multi-week view), one per
/// row, Monday first. A range that isn't whole weeks ends with a short row.
public func weekRows(_ range: DayRange) -> [DayRange] {
    stride(from: 0, to: range.length, by: 7).map { i in
        DayRange(range.start + i, min(range.start + i + 7, range.end))
    }
}

/// One task's place in a week row of the month grid: the columns it covers
/// and the line it sits on. A task on several days of the row is one bar
/// (`isBar`); one on a single day a line in that day's cell.
public struct WeekItem: Sendable, Hashable, CustomStringConvertible {
    /// The task's entry on the first day of the row it covers.
    public let entry: CalendarEntry
    /// 0 for Monday (the row's first day).
    public let column: Int
    /// How many days of the row it covers, 1 or more.
    public let columns: Int
    /// The line in the row, 0 at the top.
    public let line: Int
    /// The span began before this row (draw its left end open).
    public let continuesBefore: Bool
    /// The span goes on after this row (draw its right end open).
    public let continuesAfter: Bool

    /// Drawn as a bar across days rather than a line in one cell.
    public var isBar: Bool { columns > 1 || continuesBefore || continuesAfter }

    /// The columns it covers.
    public var columnRange: Range<Int> { column..<(column + columns) }

    public var description: String {
        "\(entry.task.title) \(column)+\(columns) @\(line)\(continuesBefore ? " <" : "")\(continuesAfter ? " >" : "")"
    }
}

/// One occurrence's days in a week row, while `weekLayout` gathers them.
private struct RowOccurrence {
    var first: CalendarEntry
    var lastDay: Day
}

/// An occurrence placed in a week row, before it gets its line.
private struct RowCandidate {
    let entry: CalendarEntry
    let column: Int
    let columns: Int
    let before: Bool
    let after: Bool
    var isBar: Bool { columns > 1 || before || after }
}

/// Lays out one week row of the month (or multi-week) grid, the way common
/// calendar apps do: each occurrence of a task that spans days becomes one
/// bar across the days it covers in the row, the bars first (earlier
/// start, then longer, then display order) and the single-day tasks after
/// them in display order (`compareEntries`), each on the topmost line
/// that is free on all its days. `entries` may include other days; only
/// `week`'s are laid out.
public func weekLayout(_ entries: some Sequence<CalendarEntry>, week: DayRange) -> [WeekItem] {
    // One group per occurrence: a span's days in the row.
    var order: [String] = []
    var groups: [String: RowOccurrence] = [:]
    for e in entries where week.contains(e.date) {
        let key = "\(e.task.id)@\(e.occurrence.key)\(e.projected ? "*" : "")"
        if var g = groups[key] {
            if e.date < g.first.date { g.first = e }
            g.lastDay = max(g.lastDay, e.date)
            groups[key] = g
        } else {
            order.append(key)
            groups[key] = RowOccurrence(first: e, lastDay: e.date)
        }
    }
    let candidates = order.map { key -> RowCandidate in
        let g = groups[key]!
        let t = g.first.task
        let last = g.first.occurrence + (spanDays(t.dueDate ?? g.first.occurrence, t.dueTime, t.duration) - 1)
        return RowCandidate(
            entry: g.first,
            column: week.start.days(to: g.first.date),
            columns: g.first.date.days(to: g.lastDay) + 1,
            before: g.first.occurrence < week.start,
            after: last >= week.end
        )
    }.sorted { a, b in
        if a.isBar != b.isBar { return a.isBar }
        if a.isBar {
            if a.column != b.column { return a.column < b.column }
            if a.columns != b.columns { return a.columns > b.columns }
        }
        return compareEntries(a.entry, b.entry) < 0
    }

    // taken[line][column]
    var taken: [[Bool]] = []
    var out: [WeekItem] = []
    let width = max(week.length, 1)
    for c in candidates {
        let cols = c.column..<min(c.column + c.columns, width)
        var line = 0
        while line < taken.count && cols.contains(where: { taken[line][$0] }) { line += 1 }
        if line == taken.count { taken.append(Array(repeating: false, count: width)) }
        for col in cols { taken[line][col] = true }
        out.append(WeekItem(
            entry: c.entry, column: c.column, columns: c.columns, line: line,
            continuesBefore: c.before, continuesAfter: c.after
        ))
    }
    return out
}

/// For each day of a week row laid out by `weekLayout`, how many of its
/// items don't fit when the cell has room for `lines` lines: those on line
/// `lines` or below (a bar counts on every day it covers). The UI shows
/// "+N" for them; to keep a line for that label, pass one line less.
public func hiddenCounts(_ items: [WeekItem], lines: Int, days: Int = 7) -> [Int] {
    var out = Array(repeating: 0, count: days)
    for item in items where item.line >= lines {
        for col in item.columnRange where col < days { out[col] += 1 }
    }
    return out
}

// MARK: - 安排任务

/// The tasks the 安排任务 panel lists, to be dragged onto the calendar: open,
/// without a date, not in the trash; only `listId`'s when it is given
/// (`inboxListId` for 收集箱). Higher priority first, newer first among
/// equals (`compareByPriority`).
public func unscheduledTasks(_ tasks: some Sequence<TodoTask>, listId: String? = nil) -> [TodoTask] {
    tasks.filter {
        $0.dueDate == nil && $0.status == .open && $0.trashedAt == nil && $0.deletedAt == nil
            && (listId == nil || $0.listId == listId)
    }.sorted { compareByPriority($0, $1) < 0 }
}

/// Where a task from the 安排任务 panel goes when dropped on `day`: at
/// `minute` on an hour grid, all day on a month cell or the all-day row.
/// (A dated task's entry goes by `dropTarget` instead.)
public func scheduleTarget(_ task: TodoTask, _ day: Day, minute: Int? = nil) -> CalendarMove {
    CalendarMove(id: task.id, date: day, time: minute)
}
