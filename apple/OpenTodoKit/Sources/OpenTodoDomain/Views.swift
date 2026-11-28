// What the middle pane shows, ported from `app/lib/domain/views.dart`: a
// smart list, a list of the person's own, a tag or a saved filter, and how
// its tasks are grouped into sections.
//
// Dart → Swift:
//
//     SmartViewRef(kind) …    ViewRef.smart(kind), .list(id), .tag(tag), .filter(id)
//     SectionTarget(l, s) …   GroupTarget.section(listId:sectionId:), .date(_:),
//                             .priority(_:), .list(_:), .tag(_:), .order
//     lastDueKey(t)           lastDueDay(t)        (a `Day`)
//     Comparator<Task>        TaskComparator       (negative, zero, positive)
//     list.sort(cmp)          list.sort(comparing: cmp)
//
// `now` is a `LocalDateTime` and `today` a `Day`. Records (`({...})`) are
// small structs. Where Dart turned epoch milliseconds into a local date
// (已完成 by day), the Swift function takes a `timeZone`.

import Foundation

public enum SmartKind: String, Sendable, Hashable, CaseIterable, Codable {
    case today, tomorrow, next7, inbox, completed, trash
}

public enum ViewRef: Sendable, Hashable, CustomStringConvertible {
    case smart(SmartKind)
    case list(String)
    case tag(String)
    case filter(String)

    /// `smart:today`, `list:<id>`, `tag:<tag>`, `filter:<id>`, as Dart's
    /// `toString`.
    public var description: String {
        switch self {
        case .smart(let k): "smart:\(k.rawValue)"
        case .list(let id): "list:\(id)"
        case .tag(let tag): "tag:\(tag)"
        case .filter(let id): "filter:\(id)"
        }
    }
}

/// A negative, zero or positive comparison, like a Dart `Comparator`.
public typealias TaskComparator = (TodoTask, TodoTask) -> Int

extension Array {
    /// Sorts with a Dart-style comparator (stable).
    public mutating func sort(comparing compare: (Element, Element) -> Int) {
        self = sorted(comparing: compare)
    }

    /// Sorts the positions rather than the elements: a task is a big value,
    /// and moving thousands of them around while sorting cost more than the
    /// comparing (已完成, 3500 tasks: 12 ms → see PerformanceTests). The
    /// same comparisons in the same order, so the same (stable) result.
    public func sorted(comparing compare: (Element, Element) -> Int) -> [Element] {
        if count < 2 { return self }
        let order = indices.sorted { compare(self[$0], self[$1]) < 0 }
        return order.map { self[$0] }
    }
}

public struct TaskSection: Sendable, Hashable, Identifiable {
    public var id: String
    /// Nil for a list without headers.
    public var title: String?
    public var tasks: [TodoTask]
    public var collapsedByDefault: Bool
    /// Shown in the warning colour (已过期).
    public var alert: Bool
    /// What the section's open tasks have in common, which a task dragged
    /// into it takes on; nil when nothing can be dropped in it (已过期, 以后,
    /// 已完成).
    public var target: GroupTarget?
    /// The list is in manual order (自定义), so where a task is dropped
    /// counts.
    public var manualOrder: Bool
    /// The list's section (分组) this is; nil for 未分组 and for sections
    /// that aren't a list's.
    public var listSection: ListSection?
    /// Finished (or trashed) tasks, which don't move.
    public var finished: Bool

    public init(
        id: String,
        title: String?,
        tasks: [TodoTask],
        collapsedByDefault: Bool = false,
        alert: Bool = false,
        target: GroupTarget? = nil,
        manualOrder: Bool = false,
        listSection: ListSection? = nil,
        finished: Bool = false
    ) {
        self.id = id
        self.title = title
        self.tasks = tasks
        self.collapsedByDefault = collapsedByDefault
        self.alert = alert
        self.target = target
        self.manualOrder = manualOrder
        self.listSection = listSection
        self.finished = finished
    }

    /// The day a task dropped here moves to, if this is a day's section.
    public var day: Day? {
        if case .date(let day) = target { day } else { nil }
    }
}

/// What the open tasks of a section have in common, which a task dragged
/// into the section takes on.
public enum GroupTarget: Sendable, Hashable {
    /// A section (分组) of the list `listId`; `sectionId` nil is 未分组.
    case section(listId: String, sectionId: String?)
    /// A day, each task keeping its time; nil is 无日期.
    case date(Day?)
    case priority(Priority)
    case list(String)
    /// The tasks filed under the tag, their first one; nil is 无标签.
    case tag(String?)
    /// A list shown without groups, in its own order: only where a task
    /// lands counts.
    case order

    /// Whether `t` has it already.
    public func has(_ t: TodoTask) -> Bool {
        switch self {
        case let .section(listId, sectionId): t.listId == listId && t.sectionId == sectionId
        case .date(let day): t.dueDate == day
        case .priority(let p): t.priority == p
        case .list(let listId): t.listId == listId
        case .tag(let tag): t.tags.first == tag
        case .order: true
        }
    }

    /// Whether `t` can be dropped here at all.
    public func takes(_ t: TodoTask) -> Bool {
        if case .section(let listId, _) = self { return t.listId == listId }
        return true
    }

    /// For `.tag`: a task's `tags` once it's moved here: the tag in place of
    /// the one it was filed under, or none at all for 无标签. Other targets
    /// leave the tags alone.
    public func retag(_ tags: [String]) -> [String] {
        guard case .tag(let tag) = self else { return tags }
        guard let tag else { return [] }
        return [tag] + tags.dropFirst().filter { $0 != tag }
    }
}

/// How a view groups its open tasks (分组). The raw values are the Dart
/// names, which stored preferences use.
public enum TaskGrouping: String, Sendable, Hashable, CaseIterable, Codable {
    /// The list's own sections.
    case sections
    case date
    case list
    case tag
    case priority
    case none

    public var label: String {
        switch self {
        case .sections: "自定义"
        case .date: "时间"
        case .list: "清单"
        case .tag: "标签"
        case .priority: "优先级"
        case .none: "无"
        }
    }
}

/// The groupings `view` offers, its default first; none for 已完成 and
/// 垃圾桶, which always go by day.
public func groupingsFor(_ view: ViewRef) -> [TaskGrouping] {
    switch view {
    case .list, .smart(.inbox): [.sections, .date, .tag, .priority, .none]
    case .smart(.today), .smart(.tomorrow), .smart(.next7), .filter: [.date, .list, .tag, .priority, .none]
    case .tag: [.list, .date, .priority, .none]
    case .smart(.completed), .smart(.trash): []
    }
}

/// The groupings `view`'s timeline offers for its lanes, its default first:
/// a list's lanes are always its sections; elsewhere the view's own
/// groupings, but not by date (the timeline is laid out by date already).
public func timelineGroupingsFor(_ view: ViewRef) -> [TaskGrouping] {
    arrangedListId(view) != nil ? [.sections] : groupingsFor(view).filter { $0 != .date }
}

/// 今天, 明天 and 最近7天: views of the days ahead, which only list tasks
/// with a date.
public func isDateView(_ view: ViewRef) -> Bool {
    view == .smart(.today) || view == .smart(.tomorrow) || view == .smart(.next7)
}

/// The orders `view` offers, its default first. Only a list (the inbox
/// too) can be ordered by hand.
public func sortsFor(_ view: ViewRef) -> [TaskSort] {
    if arrangedListId(view) != nil { return TaskSort.allCases }
    // 自定义 last, so the default stays 时间 (the Flutter version has no
    // 自定义 here; it falls back to its default). Dragging a task by its
    // handle switches to it (`ordersFollowing`).
    return groupingsFor(view).isEmpty ? [] : [.due, .title, .tag, .priority, .manual]
}

/// The list a view shows, if it is one the person arranges by hand: one of
/// their lists, or the inbox.
public func arrangedListId(_ view: ViewRef) -> String? {
    switch view {
    case .list(let listId): listId
    case .smart(.inbox): inboxListId
    default: nil
    }
}

/// New `sortOrder`s that put `shown` in this order (as 自定义 sorts them),
/// reusing the values they have between them, so tasks elsewhere keep
/// their places; ties are nudged apart. Only the ones that change.
public func ordersFollowing(_ shown: [TodoTask]) -> [String: Double] {
    var values = shown.map(\.sortOrder).sorted()
    for i in values.indices.dropFirst() where values[i] <= values[i - 1] { values[i] = values[i - 1] + 1 }
    var out: [String: Double] = [:]
    for (t, v) in zip(shown, values) where t.sortOrder != v { out[t.id] = v }
    return out
}

/// `shown` with the task `id` moved to `position` (its place in the
/// result), kept among the pinned or the unpinned like it, which 自定义
/// always shows first.
public func moving(_ shown: [TodoTask], _ id: String, to position: Int) -> [TodoTask] {
    guard let from = shown.firstIndex(where: { $0.id == id }) else { return shown }
    var rest = shown
    let t = rest.remove(at: from)
    let pinned = t.pinnedAt != nil
    let split = rest.firstIndex { $0.pinnedAt == nil } ?? rest.count
    let lo = pinned ? 0 : split, hi = pinned ? split : rest.count
    rest.insert(t, at: min(max(position, lo), hi))
    return rest
}

/// Manual order: smallest `sortOrder` first, newest first on a tie.
public func compareByOrder(_ a: TodoTask, _ b: TodoTask) -> Int {
    let c = compareValues(a.sortOrder, b.sortOrder)
    return c != 0 ? c : compareValues(b.createdAt, a.createdAt)
}

/// Pinned (置顶) tasks before the rest, each part in `compare`'s order.
public func pinnedFirst(_ compare: @escaping TaskComparator) -> TaskComparator {
    { a, b in
        let ap = a.pinnedAt != nil, bp = b.pinnedAt != nil
        if ap != bp { return ap ? -1 : 1 }
        return compare(a, b)
    }
}

/// How a view orders the tasks in each of its groups (排序). The raw values
/// are the Dart names.
public enum TaskSort: String, Sendable, Hashable, CaseIterable, Codable {
    case manual, due, title, tag, priority

    public var label: String {
        switch self {
        case .manual: "自定义"
        case .due: "时间"
        case .title: "标题"
        case .tag: "标签"
        case .priority: "优先级"
        }
    }

    public var compare: TaskComparator {
        let compare: TaskComparator = switch self {
        case .manual: compareByOrder
        case .due: compareByDue
        case .title: compareByTitle
        case .tag: compareByTag
        case .priority: { a, b in a.priority != b.priority ? compareValues(b.priority, a.priority) : compareByDue(a, b) }
        }
        return pinnedFirst(compare)
    }
}

/// One section of a list and its tasks; `section` nil is 未分组: tasks
/// without a section, or with one that isn't this list's (any more).
public struct ListGroup: Sendable, Hashable {
    public var section: ListSection?
    public var tasks: [TodoTask]

    public init(_ section: ListSection?, _ tasks: [TodoTask]) {
        self.section = section
        self.tasks = tasks
    }

    public var title: String { section?.name ?? "未分组" }
}

/// The tasks of a list sorted into its `sections`, each in `sort`'s order
/// (pinned ones first). 未分组 comes first, and only when it has tasks or
/// the list has no sections.
public func listGroups(_ tasks: [TodoTask], _ sections: [ListSection], sort: TaskSort = .manual) -> [ListGroup] {
    let ordered = sections.sorted(comparing: { a, b in
        let c = compareValues(a.sortOrder, b.sortOrder)
        return c != 0 ? c : compareValues(a.createdAt, b.createdAt)
    })
    var byId: [String: [TodoTask]] = [:]
    for s in ordered { byId[s.id] = [] }
    var loose: [TodoTask] = []
    for t in tasks {
        if let id = t.sectionId, byId[id] != nil { byId[id]!.append(t) } else { loose.append(t) }
    }
    let compare = sort.compare
    var out: [ListGroup] = []
    if !loose.isEmpty || ordered.isEmpty { out.append(ListGroup(nil, loose.sorted(comparing: compare))) }
    for s in ordered { out.append(ListGroup(s, byId[s.id]!.sorted(comparing: compare))) }
    return out
}

/// A column of the board: a section's open tasks in manual order, and its
/// finished ones, most recent first.
public struct BoardColumn: Sendable, Hashable {
    public var group: ListGroup
    public var done: [TodoTask]

    public init(_ group: ListGroup, _ done: [TodoTask]) {
        self.group = group
        self.done = done
    }
}

/// The board (看板) of the list `listId`: one column per section.
public func boardColumns(
    _ listId: String, _ tasks: [TodoTask], _ sections: [ListSection], sort: TaskSort = .manual
) -> [BoardColumn] {
    let inList = tasks.filter { $0.listId == listId && $0.trashedAt == nil }
    let open = listGroups(inList.filter(isOpen), sections, sort: sort)
    let done = listGroups(inList.filter(isDone), sections)
    var doneBySection: [String?: [TodoTask]] = [:]
    for g in done { doneBySection[g.section?.id] = g.tasks }
    var columns = open.map { g in
        BoardColumn(g, (doneBySection[g.section?.id] ?? []).sorted(comparing: compareCompleted))
    }
    // Finished tasks without a section get a 未分组 column too.
    if open[0].section != nil, let loose = doneBySection[nil], !loose.isEmpty {
        columns.insert(BoardColumn(ListGroup(nil, []), loose.sorted(comparing: compareCompleted)), at: 0)
    }
    return columns
}

public func isOpen(_ t: TodoTask) -> Bool { t.status == .open && t.trashedAt == nil }

/// The last day a dated task is on: its due date, or where its span ends.
/// (Dart's `lastDueKey`.) The task must have a date.
public func lastDueDay(_ t: TodoTask) -> Day {
    t.duration == nil ? t.dueDate! : spanLastDay(t.dueDate!, t.dueTime, t.duration)
}

/// Whether an open task's due moment has come: an earlier day, or today
/// once its time is reached (the minute its 准时 reminder goes off). A span
/// is due when it ends.
public func isOverdue(_ t: TodoTask, _ now: LocalDateTime) -> Bool {
    guard isOpen(t), let due = t.dueDate else { return false }
    if let end = spanEnd(due, t.dueTime, t.duration) { return !(now < end) }
    if due != now.day { return due < now.day }
    if let time = t.dueTime { return time <= now.minuteOfDay }
    return false
}

public func isDone(_ t: TodoTask) -> Bool { t.status != .open && t.trashedAt == nil }

public func listName(_ listId: String, _ lists: [String: TaskList]) -> String {
    listId == inboxListId ? "收集箱" : (lists[listId]?.name ?? "收集箱")
}

public func viewTitle(_ view: ViewRef, _ lists: [String: TaskList], _ filters: [String: TaskFilter] = [:]) -> String {
    switch view {
    case .smart(.today): "今天"
    case .smart(.tomorrow): "明天"
    case .smart(.next7): "最近7天"
    case .smart(.inbox): "收集箱"
    case .smart(.completed): "已完成"
    case .smart(.trash): "垃圾桶"
    case .list(let listId): listName(listId, lists)
    case .tag(let tag): "#\(tag)"
    case .filter(let filterId): filters[filterId]?.name ?? "过滤器"
    }
}

/// Where a task typed into a view's quick-add field goes.
public struct QuickAddDefaults: Sendable, Hashable {
    public var listId: String
    public var date: Day?
    public var tags: [String]
    public var priority: Priority?

    public init(listId: String = inboxListId, date: Day? = nil, tags: [String] = [], priority: Priority? = nil) {
        self.listId = listId
        self.date = date
        self.tags = tags
        self.priority = priority
    }
}

/// Where a task typed into this view's quick-add field goes.
public func quickAddDefaults(_ view: ViewRef, _ today: Day, _ filters: [String: FilterRule] = [:]) -> QuickAddDefaults {
    switch view {
    case .smart(.today), .smart(.next7): return QuickAddDefaults(date: today)
    case .smart(.tomorrow): return QuickAddDefaults(date: today + 1)
    case .list(let listId): return QuickAddDefaults(listId: listId)
    case .tag(let tag): return QuickAddDefaults(tags: [tag])
    case .filter(let filterId):
        guard let rule = filters[filterId] else { return QuickAddDefaults() }
        let h = rule.quickAddHints(today)
        return QuickAddDefaults(
            listId: h.listId ?? inboxListId, date: h.date, tags: h.tag.map { [$0] } ?? [], priority: h.priority
        )
    default: return QuickAddDefaults()
    }
}

/// Whether a date view lists a task due on `date`. Views that aren't about
/// dates show it regardless.
public func dateViewShows(_ view: ViewRef, _ date: Day, _ today: Day) -> Bool {
    let d = today.days(to: date)
    switch view {
    case .smart(.today): return d <= 0
    case .smart(.tomorrow): return d == 1
    case .smart(.next7): return d <= 6
    default: return true
    }
}

public func canQuickAdd(_ view: ViewRef) -> Bool {
    switch view {
    case .smart(.completed), .smart(.trash): false
    default: true
    }
}

/// Dated tasks first by date and time (all-day before timed), then by
/// priority, then newest first.
public func compareByDue(_ a: TodoTask, _ b: TodoTask) -> Int {
    let ad = a.dueDate, bd = b.dueDate
    if ad != bd {
        guard let ad else { return 1 }
        guard let bd else { return -1 }
        return compareValues(ad, bd)
    }
    let at = a.dueTime ?? -1, bt = b.dueTime ?? -1
    if at != bt { return compareValues(at, bt) }
    return compareByPriority(a, b)
}

/// A to Z in pinyin (Chinese and Latin together), untitled last; the same
/// title in manual order.
public func compareByTitle(_ a: TodoTask, _ b: TodoTask) -> Int {
    let at = a.title.dartTrimmed, bt = b.title.dartTrimmed
    if at.isEmpty != bt.isEmpty { return at.isEmpty ? 1 : -1 }
    let c = comparePinyin(at, bt)
    return c != 0 ? c : compareByOrder(a, b)
}

/// By first tag, A to Z in pinyin, untagged last; then by date.
public func compareByTag(_ a: TodoTask, _ b: TodoTask) -> Int {
    let at = a.tags.first, bt = b.tags.first
    if at != bt {
        guard let at else { return 1 }
        guard let bt else { return -1 }
        let c = comparePinyin(at, bt)
        if c != 0 { return c }
    }
    return compareByDue(a, b)
}

public func compareByPriority(_ a: TodoTask, _ b: TodoTask) -> Int {
    if a.priority != b.priority { return compareValues(b.priority, a.priority) }
    return compareValues(b.createdAt, a.createdAt)
}

private func compareCompleted(_ a: TodoTask, _ b: TodoTask) -> Int {
    compareValues(b.completedAt ?? 0, a.completedAt ?? 0)
}

/// A test for the tasks `view` lists as of `now`, finished ones included.
/// A filter that isn't in `filters` (deleted, or not loaded yet) lists
/// nothing.
public func viewMatcher(_ view: ViewRef, _ now: LocalDateTime, _ filters: [String: FilterRule] = [:]) -> (TodoTask) -> Bool {
    if case .filter(let filterId) = view {
        return filters[filterId]?.matcher(now) ?? { _ in false }
    }
    let today = now.day
    return { matchesView($0, view, today, today + 1, today + 6) }
}

private func matchesView(_ t: TodoTask, _ view: ViewRef, _ today: Day, _ tomorrow: Day, _ weekEnd: Day) -> Bool {
    if t.trashedAt != nil { return view == .smart(.trash) }
    switch view {
    case .smart(.today): return t.dueDate.map { $0 <= today } ?? false
    case .smart(.tomorrow): return t.dueDate.map { $0 <= tomorrow && lastDueDay(t) >= tomorrow } ?? false
    case .smart(.next7): return t.dueDate.map { $0 <= weekEnd } ?? false
    case .smart(.inbox): return t.listId == inboxListId
    case .smart(.completed): return isDone(t)
    case .smart(.trash): return false
    case .list(let listId): return t.listId == listId
    case .tag(let tag): return t.tags.contains(tag)
    case .filter: return false // see viewMatcher
    }
}

/// Where to show a task opened from elsewhere, such as a notification: the
/// current view if it lists the task, else 今天 for one due by today, else
/// its list.
public func viewForTask(_ t: TodoTask, _ current: ViewRef, _ now: LocalDateTime, _ filters: [String: FilterRule] = [:]) -> ViewRef {
    if viewMatcher(current, now, filters)(t) { return current }
    if t.trashedAt != nil { return .smart(.trash) }
    if t.status != .open { return .smart(.completed) }
    if let due = t.dueDate, due <= now.day { return .smart(.today) }
    return t.listId == inboxListId ? .smart(.inbox) : .list(t.listId)
}

/// Number shown next to a view in the sidebar: its open tasks.
public func openCount(_ view: ViewRef, _ tasks: [TodoTask], _ now: LocalDateTime, _ filters: [String: FilterRule] = [:]) -> Int {
    let matches = viewMatcher(view, now, filters)
    return tasks.count(where: { isOpen($0) && matches($0) })
}

/// The sidebar's numbers for every view at once: what `openCount` gives
/// each one, worked out in one pass over the open tasks instead of a pass
/// over every task per view.
public struct OpenCounts: Sendable, Hashable {
    public var smart: [SmartKind: Int] = [:]
    public var lists: [String: Int] = [:]
    public var tags: [String: Int] = [:]
    public var filters: [String: Int] = [:]

    public init() {}

    /// `openCount(view, …)`.
    public subscript(view: ViewRef) -> Int {
        switch view {
        case .smart(let k): smart[k] ?? 0
        case .list(let id): lists[id] ?? 0
        case .tag(let tag): tags[tag] ?? 0
        case .filter(let id): filters[id] ?? 0
        }
    }
}

/// Every view's open-task count as of `now` (see `OpenCounts`).
public func openCounts(_ tasks: [TodoTask], _ now: LocalDateTime, _ filters: [String: FilterRule] = [:]) -> OpenCounts {
    let open = tasks.filter(isOpen)
    let today = now.day, tomorrow = today + 1, weekEnd = today + 6
    var c = OpenCounts()
    var todayN = 0, tomorrowN = 0, next7N = 0, inboxN = 0
    for t in open {
        if let due = t.dueDate {
            if due <= today { todayN += 1 }
            if due <= tomorrow && lastDueDay(t) >= tomorrow { tomorrowN += 1 }
            if due <= weekEnd { next7N += 1 }
        }
        if t.listId == inboxListId { inboxN += 1 }
        c.lists[t.listId, default: 0] += 1
        // A tag counts a task once, however often it's written.
        if t.tags.count == 1 {
            c.tags[t.tags[0], default: 0] += 1
        } else if !t.tags.isEmpty {
            for tag in Set(t.tags) { c.tags[tag, default: 0] += 1 }
        }
    }
    // 已完成 and 垃圾桶 never list an open task.
    c.smart = [.today: todayN, .tomorrow: tomorrowN, .next7: next7N, .inbox: inboxN, .completed: 0, .trash: 0]
    for (id, rule) in filters {
        let matches = rule.matcher(now)
        c.filters[id] = open.count(where: matches)
    }
    return c
}

/// The sections of `view`: its open tasks grouped by `grouping` and in
/// `sort`'s order within each group (the view's defaults when nil or not
/// one it offers), then 已完成. `timeZone` turns completion times into the
/// days 已完成 lists them under.
public func buildSections(
    view: ViewRef,
    tasks: [TodoTask],
    lists: [String: TaskList],
    now: LocalDateTime,
    filters: [String: FilterRule] = [:],
    sectionsByList: [String: [ListSection]] = [:],
    grouping: TaskGrouping? = nil,
    sort: TaskSort? = nil,
    timeZone: TimeZone = .current
) -> [TaskSection] {
    let today = now.day
    var inView = tasks.filter(viewMatcher(view, now, filters))

    if view == .smart(.trash) {
        inView.sort(comparing: { a, b in compareValues(b.trashedAt ?? 0, a.trashedAt ?? 0) })
        return inView.isEmpty ? [] : [TaskSection(id: "trash", title: nil, tasks: inView, finished: true)]
    }

    if view == .smart(.completed) {
        inView.sort(comparing: compareCompleted)
        var days: [Day] = []
        var byDay: [Day: [TodoTask]] = [:]
        for t in inView {
            let day = localDay(t.completedAt ?? t.updatedAt, timeZone)
            if byDay[day] == nil { days.append(day) }
            byDay[day, default: []].append(t)
        }
        return days.map { d in
            TaskSection(id: "done-\(d.key)", title: daySectionTitle(d, today: today), tasks: byDay[d]!, finished: true)
        }
    }

    let dateView = isDateView(view)
    let groupings = groupingsFor(view)
    let groupBy = grouping.flatMap { groupings.contains($0) ? $0 : nil } ?? groupings[0]
    let sorts = sortsFor(view)
    let order = sort.flatMap { sorts.contains($0) ? $0 : nil } ?? sorts[0]
    let manual = order == .manual
    let open = inView.filter(isOpen).sorted(comparing: order.compare)
    // A date view lists finished tasks from its own days, not every task
    // ever finished that was due in the past.
    let done = inView
        .filter { isDone($0) && (!dateView || lastDueDay($0) >= today) }
        .sorted(comparing: compareCompleted)

    let sections: [TaskSection]
    switch groupBy {
    case .sections:
        let listId = arrangedListId(view)!
        sections = bySection(open, listId, sectionsByList[listId] ?? [], order)
    case .date where dateView:
        sections = byViewDay(open, today, days: view == .smart(.next7) ? 7 : 1,
                             first: view == .smart(.tomorrow) ? today + 1 : today, manual: manual)
    case .date: sections = byDate(open, today, manual)
    case .list: sections = byList(open, lists, manual)
    case .tag: sections = byTag(open, manual)
    case .priority: sections = byPriority(open, manual)
    case .none:
        sections = open.isEmpty ? [] : [
            TaskSection(id: "all", title: nil, tasks: open, target: manual ? .order : nil, manualOrder: manual),
        ]
    }
    guard !done.isEmpty else { return sections }
    let collapsed = if case .smart = view { false } else { true }
    return sections + [
        TaskSection(id: "done", title: "已完成", tasks: done, collapsedByDefault: collapsed, finished: true),
    ]
}

/// The calendar day epoch milliseconds `ms` fall on in `timeZone`: what
/// `Day(Date(timeIntervalSince1970: ms / 1000), in: timeZone)` gives, from
/// the zone's offset at that instant instead of a calendar (several times
/// faster, for 已完成's thousands of tasks).
func localDay(_ ms: Int, _ timeZone: TimeZone) -> Day {
    let seconds = floorDiv(ms, 1000)
    let offset = timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(seconds)))
    return Day(julianDay: unixEpochJulianDay + floorDiv(seconds + offset, 86_400))
}

/// 1970-01-01.
private let unixEpochJulianDay = Day(1970, 1, 1).julianDay

/// A list's own sections (分组).
private func bySection(_ open: [TodoTask], _ listId: String, _ listSections: [ListSection], _ order: TaskSort) -> [TaskSection] {
    listGroups(open, listSections, sort: order)
        // A list without sections has no headers, and nothing at all when
        // it's empty (so the empty state shows).
        .filter { !listSections.isEmpty || !$0.tasks.isEmpty }
        .map { g in
            TaskSection(
                id: g.section.map { "section-\($0.id)" } ?? "section-none",
                title: listSections.isEmpty ? nil : g.title,
                tasks: g.tasks,
                target: .section(listId: listId, sectionId: g.section?.id),
                manualOrder: order == .manual,
                listSection: g.section
            )
        }
}

/// 今天 / 明天 / 最近7天 by day: 已过期, then each of the view's `days` days
/// from `first`.
private func byViewDay(_ open: [TodoTask], _ today: Day, days: Int, first: Day, manual: Bool = false) -> [TaskSection] {
    let overdue = open.filter { lastDueDay($0) < today }
    // A span that began earlier shows once, on the view's first day.
    var keys: [Day] = []
    var byDay: [Day: [TodoTask]] = [:]
    for t in open where lastDueDay(t) >= today {
        let key = max(t.dueDate!, first)
        if byDay[key] == nil { keys.append(key) }
        byDay[key, default: []].append(t)
    }
    // With an open task to drag, every day of the view is there, empty or
    // not, so it can be dropped onto it (out of 已过期, say).
    if !open.isEmpty { keys = (0..<days).map { first + $0 } }
    var out: [TaskSection] = []
    if !overdue.isEmpty { out.append(TaskSection(id: "overdue", title: "已过期", tasks: overdue, alert: true)) }
    for key in keys {
        out.append(TaskSection(
            id: "day-\(key.key)",
            title: daySectionTitle(key, today: today),
            tasks: byDay[key] ?? [],
            target: .date(key),
            manualOrder: manual
        ))
    }
    return out
}

/// By date: 已过期, each of the next seven days, 以后, 无日期.
private func byDate(_ open: [TodoTask], _ today: Day, _ manual: Bool) -> [TaskSection] {
    enum Key: Hashable, Comparable {
        case overdue
        case day(Day)
        case later
        case none
    }
    let weekEnd = today + 6
    var byKey: [Key: [TodoTask]] = [:]
    for t in open {
        let key: Key
        if let due = t.dueDate {
            if lastDueDay(t) < today {
                key = .overdue
            } else if due > weekEnd {
                key = .later
            } else {
                key = .day(max(due, today))
            }
        } else {
            key = .none
        }
        byKey[key, default: []].append(t)
    }
    return byKey.keys.sorted().map { k in
        switch k {
        case .overdue: TaskSection(id: "overdue", title: "已过期", tasks: byKey[k]!, alert: true)
        case .later: TaskSection(id: "later", title: "以后", tasks: byKey[k]!)
        case .none: TaskSection(id: "none", title: "无日期", tasks: byKey[k]!, target: .date(nil), manualOrder: manual)
        case .day(let d):
            TaskSection(
                id: "day-\(d.key)",
                title: daySectionTitle(d, today: today),
                tasks: byKey[k]!,
                target: .date(d),
                manualOrder: manual
            )
        }
    }
}

/// `tasks` in groups by `grouping`, for the lanes of a timeline: by list,
/// first tag or priority, or all together (for `.none`, and the groupings
/// a timeline doesn't offer). Each group keeps the order `tasks` come in;
/// finished ones go with the rest.
public func groupForTimeline(_ tasks: [TodoTask], _ grouping: TaskGrouping, _ lists: [String: TaskList]) -> [TaskSection] {
    switch grouping {
    case .list: byList(tasks, lists)
    case .tag: byTag(tasks, false)
    case .priority: byPriority(tasks, false)
    default: [TaskSection(id: "all", title: nil, tasks: tasks)]
    }
}

/// By list, in the sidebar's order (收集箱 first).
private func byList(_ open: [TodoTask], _ lists: [String: TaskList], _ manual: Bool = false) -> [TaskSection] {
    var ids: [String] = []
    var byList: [String: [TodoTask]] = [:]
    for t in open {
        if byList[t.listId] == nil { ids.append(t.listId) }
        byList[t.listId, default: []].append(t)
    }
    // A list that's gone (deleted on another device, say) goes last.
    func rank(_ id: String) -> (Int, Double, Int) {
        if id == inboxListId { return (0, 0, 0) }
        guard let l = lists[id] else { return (2, 0, 0) }
        return (1, l.sortOrder, l.createdAt)
    }
    ids.sort(comparing: { a, b in
        let ra = rank(a), rb = rank(b)
        var c = compareValues(ra.0, rb.0)
        if c == 0 { c = compareValues(ra.1, rb.1) }
        return c != 0 ? c : compareValues(ra.2, rb.2)
    })
    return ids.map { id in
        TaskSection(
            id: "list-\(id)",
            title: listName(id, lists),
            tasks: byList[id]!,
            target: id == inboxListId || lists[id] != nil ? .list(id) : nil,
            manualOrder: manual
        )
    }
}

/// By each task's first tag, A to Z in pinyin, then 无标签.
private func byTag(_ open: [TodoTask], _ manual: Bool) -> [TaskSection] {
    var byTag: [String?: [TodoTask]] = [:]
    for t in open { byTag[t.tags.first, default: []].append(t) }
    var tags: [String?] = byTag.keys.compactMap { $0 }.sorted(comparing: comparePinyin)
    if byTag[nil] != nil { tags.append(nil) }
    return tags.map { tag in
        TaskSection(
            id: "tag-\(tag ?? "")",
            title: tag ?? "无标签",
            tasks: byTag[tag]!,
            target: .tag(tag),
            manualOrder: manual
        )
    }
}

/// High priority first, 无优先级 last.
private func byPriority(_ open: [TodoTask], _ manual: Bool) -> [TaskSection] {
    [Priority.high, .medium, .low, .none].compactMap { p in
        let tasks = open.filter { $0.priority == p }
        if tasks.isEmpty { return nil }
        return TaskSection(
            id: "priority-\(p.rawValue)",
            title: priorityName(p),
            tasks: tasks,
            target: .priority(p),
            manualOrder: manual
        )
    }
}

public func priorityName(_ priority: Priority) -> String {
    switch priority {
    case .high: "高优先级"
    case .medium: "中优先级"
    case .low: "低优先级"
    case .none: "无优先级"
    }
}
