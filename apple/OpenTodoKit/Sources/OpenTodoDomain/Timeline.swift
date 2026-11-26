// The timeline (时间线) of a list or another view, ported from
// `app/lib/domain/timeline.dart`: its dated tasks as bars along the days
// they cover, one lane per section (or group), packed into as few rows as
// fit.

/// How much time a screen of the timeline takes in: how wide a day is. The
/// raw values are the Dart names, which stored options use.
public enum TimelineScale: String, Sendable, Hashable, CaseIterable, Codable {
    case day, week, month

    public var label: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }

    /// How many days a bar takes up in its row at the least, with its title
    /// beside it when the bar itself is too narrow to hold it.
    public var minDays: Int {
        switch self {
        case .day: 1
        case .week: 4
        case .month: 10
        }
    }

    /// The scale stored as `name`; nil for anything else.
    public static func byName(_ name: Any?) -> TimelineScale? {
        (name as? String).flatMap(TimelineScale.init(rawValue:))
    }
}

/// A task on the timeline, from the first day it is on to the last.
public struct TimelineBar: Sendable, Hashable, CustomStringConvertible {
    public let task: TodoTask
    public let start: Day
    public let last: Day

    /// `task` must have a date.
    public init(_ task: TodoTask) {
        self.task = task
        start = task.dueDate!
        last = spanLastDay(task.dueDate!, task.dueTime, task.duration)
    }

    public var days: Int { start.days(to: last) + 1 }

    public var done: Bool { task.status != .open }

    /// Whether any of it is on the days from `from` to `to`, both included.
    public func overlaps(_ from: Day, _ to: Day) -> Bool { last >= from && start <= to }

    public var description: String { "\(task.title) \(start.key)..\(last.key)" }
}

/// One lane of the timeline: a section of the list, or a group of the
/// view's tasks (a list, a tag, a priority), and its dated tasks.
public struct TimelineLane: Sendable, Hashable, Identifiable {
    /// Tells the lanes apart (which ones are folded).
    public var id: String
    /// Its header; nil for none (a list without sections, a view that isn't
    /// grouped).
    public var title: String?
    /// What a task dragged into the lane takes on (a section, a list, a tag,
    /// a priority); nil: only its dates change.
    public var target: GroupTarget?
    /// By first day; on the same day open before finished, then in the
    /// view's order.
    public var bars: [TimelineBar]

    public init(_ id: String, _ title: String?, _ target: GroupTarget?, _ bars: [TimelineBar]) {
        self.id = id
        self.title = title
        self.target = target
        self.bars = bars
    }
}

/// The open tasks without a date of one group (a section, a list…).
public struct UndatedGroup: Sendable, Hashable {
    public var title: String?
    public var tasks: [TodoTask]

    public init(_ title: String?, _ tasks: [TodoTask]) {
        self.title = title
        self.tasks = tasks
    }
}

/// What a timeline shows.
public struct Timeline: Sendable, Hashable {
    /// At least one.
    public var lanes: [TimelineLane]
    /// Open tasks without a date by group, in the view's order, leaving out
    /// groups without any; they wait beside the timeline (无日期) to be
    /// dragged onto it.
    public var undated: [UndatedGroup]
    /// Whether the view can have tasks without a date at all, so 无日期
    /// shows: not 今天, 明天 or 最近7天.
    public var takesUndated: Bool

    public init(_ lanes: [TimelineLane], _ undated: [UndatedGroup], takesUndated: Bool = true) {
        self.lanes = lanes
        self.undated = undated
        self.takesUndated = takesUndated
    }

    public var undatedTasks: [TodoTask] { undated.flatMap(\.tasks) }

    /// The lanes have headers.
    public var titled: Bool { lanes.contains { $0.title != nil } }
}

/// Bars by first day; on the same day open before finished, then in
/// `compare`'s order.
private func bars(_ tasks: [TodoTask], _ compare: TaskComparator) -> [TimelineBar] {
    tasks.filter { $0.dueDate != nil }.map(TimelineBar.init).sorted(comparing: { a, b in
        let c = compareValues(a.start, b.start)
        if c != 0 { return c }
        if a.done != b.done { return a.done ? 1 : -1 }
        return compare(a.task, b.task)
    })
}

/// Whether `t` shows on a timeline: open, or finished with a date when
/// `showDone`.
private func shows(_ t: TodoTask, _ showDone: Bool) -> Bool {
    t.trashedAt == nil && (isOpen(t) || (showDone && isDone(t) && t.dueDate != nil))
}

/// The timeline of the list `listId`: a lane per section. Finished tasks
/// show only with `showDone`, and only those with a date.
public func buildTimeline(
    _ listId: String,
    _ tasks: [TodoTask],
    _ sections: [ListSection],
    sort: TaskSort = .manual,
    showDone: Bool = false
) -> Timeline {
    let shown = tasks.filter { $0.listId == listId && shows($0, showDone) }
    let groups = listGroups(shown, sections, sort: sort)
    let compare = sort.compare
    return Timeline(
        groups
            .filter { g in g.section != nil || sections.isEmpty || g.tasks.contains { $0.dueDate != nil } }
            .map { g in
                TimelineLane(
                    g.section?.id ?? "",
                    sections.isEmpty ? nil : g.title,
                    .section(listId: listId, sectionId: g.section?.id),
                    bars(g.tasks, compare)
                )
            },
        groups.compactMap { g in
            let undated = g.tasks.filter { $0.dueDate == nil }
            return undated.isEmpty ? nil : UndatedGroup(g.title, undated)
        }
    )
}

/// The timeline of any view but 已完成 and 垃圾桶: a list's (the inbox's)
/// lanes are its sections, as `buildTimeline`; elsewhere the view's tasks go
/// in a lane per group of `grouping` (the view's first timeline grouping
/// when it doesn't offer that one), one for each group with any task, so an
/// undated task can be dragged on without leaving its group.
public func buildViewTimeline(
    _ view: ViewRef,
    _ tasks: [TodoTask],
    now: LocalDateTime,
    lists: [String: TaskList] = [:],
    filters: [String: FilterRule] = [:],
    sectionsByList: [String: [ListSection]] = [:],
    grouping: TaskGrouping? = nil,
    sort: TaskSort? = nil,
    showDone: Bool = false
) -> Timeline {
    let sorts = sortsFor(view)
    let order = sort.flatMap { sorts.contains($0) ? $0 : nil } ?? sorts.first ?? .due
    if let listId = arrangedListId(view) {
        return buildTimeline(listId, tasks, sectionsByList[listId] ?? [], sort: order, showDone: showDone)
    }
    let matches = viewMatcher(view, now, filters)
    let compare = order.compare
    let shown = tasks.filter { matches($0) && shows($0, showDone) }.sorted(comparing: compare)
    let groupings = timelineGroupingsFor(view)
    let by = grouping.flatMap { groupings.contains($0) ? $0 : nil } ?? groupings.first ?? TaskGrouping.none
    let groups = groupForTimeline(shown, by, lists)
    let takesUndated = !isDateView(view)
    let lanes = groups.map { g in
        TimelineLane(g.id, by == .none ? nil : g.title, g.target, bars(g.tasks, compare))
    }
    return Timeline(
        lanes.isEmpty ? [TimelineLane("all", nil, nil, [])] : lanes,
        !takesUndated ? [] : groups.compactMap { g in
            let undated = g.tasks.filter { $0.dueDate == nil && isOpen($0) }
            return undated.isEmpty ? nil : UndatedGroup(g.title, undated)
        },
        takesUndated: takesUndated
    )
}

/// What a task added on a lane of a timeline starts with.
public struct LaneNewTask: Sendable, Hashable {
    public var listId: String
    public var sectionId: String?
    public var tags: [String]
    public var priority: Priority?

    public init(listId: String, sectionId: String? = nil, tags: [String] = [], priority: Priority? = nil) {
        self.listId = listId
        self.sectionId = sectionId
        self.tags = tags
        self.priority = priority
    }
}

/// What a task added on a lane of `view`'s timeline starts with: what the
/// view gives new tasks, and what the lane (`target`) stands for.
public func laneNewTask(
    _ view: ViewRef,
    _ target: GroupTarget?,
    _ today: Day,
    _ filters: [String: FilterRule] = [:]
) -> LaneNewTask {
    let d = quickAddDefaults(view, today, filters)
    switch target {
    case let .section(listId, sectionId)?:
        return LaneNewTask(listId: listId, sectionId: sectionId, tags: d.tags, priority: d.priority)
    case .list(let listId)?:
        return LaneNewTask(listId: listId, tags: d.tags, priority: d.priority)
    case .tag?:
        return LaneNewTask(listId: d.listId, tags: target!.retag(d.tags), priority: d.priority)
    case .priority(let p)?:
        return LaneNewTask(listId: d.listId, tags: d.tags, priority: p)
    default:
        return LaneNewTask(listId: d.listId, tags: d.tags, priority: d.priority)
    }
}

/// Packs `bars` (by first day) into rows, each bar in the first row with
/// room for it. A bar takes `minDays` days at the least, for its title.
public func packRows(_ bars: [TimelineBar], minDays: Int = 1) -> [[TimelineBar]] {
    var rows: [[TimelineBar]] = []
    var ends: [Day] = []
    for b in bars {
        let end = b.days >= minDays ? b.last : b.start + (minDays - 1)
        if let row = ends.firstIndex(where: { $0 < b.start }) {
            rows[row].append(b)
            ends[row] = end
        } else {
            rows.append([b])
            ends.append(end)
        }
    }
    return rows
}

/// How long `t` lasts once its right edge is dragged to `lastDay` (never
/// before its first day). An all-day task covers whole days (one day is no
/// span). A timed one ends at the same time of day as before, on the new
/// last day; one that can't (it ended at midnight, or it is back on its
/// first day and ended after midnight) ends with that day, or has no span
/// on its first. `t` must have a date.
public func resizedDuration(_ t: TodoTask, _ lastDay: Day) -> Int? {
    let start = t.dueDate!
    let k = max(start.days(to: lastDay), 0)
    guard let time = t.dueTime else { return normalizeDuration(nil, (k + 1) * minutesPerDay) }
    func lastIndex(_ d: Int?) -> Int { start.days(to: spanLastDay(start, time, d)) }
    let was = lastIndex(t.duration)
    if k == was { return t.duration }
    let d = (t.duration ?? 0) + (k - was) * minutesPerDay
    if d > 0 && lastIndex(d) == k { return d }
    return k == 0 ? nil : (k + 1) * minutesPerDay - time
}

/// Where `t` starts, and how long it lasts, once its left edge is dragged to
/// `firstDay` (never after its last day): it still ends when it did. An
/// all-day task covers whole days to its last (one day is no span). A timed
/// one keeps its time of day; when that's no longer before its end (it's on
/// its last day now, which it reached after midnight), it has no span. `t`
/// must have a date.
public func restartedSchedule(_ t: TodoTask, _ firstDay: Day) -> (date: Day, duration: Int?) {
    let start = t.dueDate!
    let last = spanLastDay(start, t.dueTime, t.duration)
    let first = min(firstDay, last)
    guard let time = t.dueTime else {
        return (first, normalizeDuration(nil, (first.days(to: last) + 1) * minutesPerDay))
    }
    // On the wall clock, from the old first day's midnight.
    let end = time + (t.duration ?? 0)
    let d = end - (start.days(to: first) * minutesPerDay + time)
    return (first, normalizeDuration(time, d))
}

/// The month a timeline shows from `day`: 2026年11月.
public func timelineMonthLabel(_ day: Day) -> String { "\(day.year)年\(day.month)月" }
