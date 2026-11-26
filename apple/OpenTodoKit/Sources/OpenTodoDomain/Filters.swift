// Saved filters (过滤器), ported from `app/lib/domain/filters.dart`: rules
// that gather tasks from every list, such as "high priority this week in
// 工作".
//
// A rule is a set of conditions joined by 且 (all must hold) or 或 (any
// may). Each condition looks at one field of a task and lists the values it
// accepts; it can be turned around to exclude them instead. A condition
// with no values is left out, so an empty rule matches every task.
//
// Stored as JSON in `TaskFilter.rule` and synced as is:
//
//     {"match": "all", "conditions": [
//       {"field": "list", "values": ["inbox", "<list id>"]},
//       {"field": "date", "values": ["today", "overdue"]},
//       {"field": "tag", "values": ["工作", ""], "exclude": true},
//       {"field": "priority", "values": ["high"]},
//       {"field": "keyword", "values": ["周报"]}
//     ]}
//
// The tag value `""` stands for a task without tags. Conditions on a field
// this version doesn't know (written by a newer one) are kept as they are
// and left out when matching. `encode()` writes exactly what the Dart
// version's `jsonEncode` does (see `JSONValue.swift`).

public enum FilterField: String, Sendable, Hashable, CaseIterable, Codable {
    case list, tag, date, priority, keyword

    public var label: String {
        switch self {
        case .list: "清单"
        case .tag: "标签"
        case .date: "日期"
        case .priority: "优先级"
        case .keyword: "内容"
        }
    }

    /// Its place in the form (Dart's `index`).
    var index: Int { Self.allCases.firstIndex(of: self)! }
}

/// The date choices a filter offers.
public enum DateChoice: String, Sendable, Hashable, CaseIterable, Codable {
    case overdue, today, tomorrow, thisWeek, next7, nextWeek, thisMonth, none

    public var label: String {
        switch self {
        case .overdue: "已过期"
        case .today: "今天"
        case .tomorrow: "明天"
        case .thisWeek: "本周"
        case .next7: "最近7天"
        case .nextWeek: "下周"
        case .thisMonth: "本月"
        case .none: "无日期"
        }
    }
}

/// Priority values as a filter stores them, highest first.
public let priorityChoices: [(key: String, priority: Priority, label: String)] = [
    ("high", .high, "高"),
    ("medium", .medium, "中"),
    ("low", .low, "低"),
    ("none", .none, "无"),
]

private func priorityKey(_ p: Priority) -> String {
    (priorityChoices.first { $0.priority == p } ?? priorityChoices[priorityChoices.count - 1]).key
}

/// The tag value that stands for "no tags".
public let noTag = ""

public struct FilterCondition: Sendable, Hashable {
    /// Nil for a condition from a newer version; see `raw`.
    public let field: FilterField?
    public let values: [String]
    /// Keeps the tasks that *don't* match instead (不包含).
    public let exclude: Bool
    /// A condition this version can't read, kept so saving doesn't drop it.
    public let raw: JSONObject?

    public init(_ field: FilterField, _ values: [String], exclude: Bool = false) {
        self.field = field
        self.values = values
        self.exclude = exclude
        raw = nil
    }

    private init(unknown raw: JSONObject) {
        field = nil
        values = []
        exclude = false
        self.raw = raw
    }

    /// Reads one condition of a stored rule; one it can't read is kept raw.
    public init(json j: JSONObject) {
        guard let name = j["field"]?.string, let field = FilterField(rawValue: name),
              let values = j["values"]?.array
        else {
            self.init(unknown: j)
            return
        }
        self.init(field, values.compactMap(\.string), exclude: j["exclude"] == .bool(true))
    }

    public var isKnown: Bool { field != nil }

    /// Whether it takes part in matching.
    public var isActive: Bool {
        isKnown && values.contains { field != .keyword || !$0.dartTrimmed.isEmpty }
    }

    /// A copy with some parts changed (Dart's `copyWith`); always a known
    /// condition.
    public func copy(field: FilterField? = nil, values: [String]? = nil, exclude: Bool? = nil) -> FilterCondition {
        FilterCondition(field ?? self.field!, values ?? self.values, exclude: exclude ?? self.exclude)
    }

    public func toJSON() -> JSONValue {
        if let raw { return .object(raw) }
        var o: JSONObject = ["field": .string(field!.rawValue), "values": .array(values.map(JSONValue.string))]
        if exclude { o["exclude"] = .bool(true) }
        return .object(o)
    }
}

public struct FilterRule: Sendable, Hashable {
    /// 且 (true) or 或.
    public var matchAll: Bool
    public var conditions: [FilterCondition]

    public init(matchAll: Bool = true, conditions: [FilterCondition] = []) {
        self.matchAll = matchAll
        self.conditions = conditions
    }

    public init(json j: JSONObject) {
        let conditions = j["conditions"]?.array ?? []
        self.init(
            matchAll: j["match"] != .string("any"),
            conditions: conditions.compactMap { $0.object.map(FilterCondition.init(json:)) }
        )
    }

    /// Reads the stored text; anything unreadable is an empty rule.
    public static func parse(_ text: String) -> FilterRule {
        guard let o = JSONValue(parsing: text)?.object else { return FilterRule() }
        return FilterRule(json: o)
    }

    public func toJSON() -> JSONValue {
        .object(["match": .string(matchAll ? "all" : "any"), "conditions": .array(conditions.map { $0.toJSON() })])
    }

    /// The text to store, as the Dart version writes it.
    public func encode() -> String { toJSON().encoded() }

    public func copy(matchAll: Bool? = nil, conditions: [FilterCondition]? = nil) -> FilterRule {
        FilterRule(matchAll: matchAll ?? self.matchAll, conditions: conditions ?? self.conditions)
    }

    /// Whether the simple form (one row per field, everything 包含, joined by
    /// 且) can show this rule.
    public var isSimple: Bool {
        if !matchAll { return false }
        var seen = Set<FilterField>()
        for c in conditions {
            guard let field = c.field else { return false }
            if !c.isActive { continue }
            if c.exclude || !seen.insert(field).inserted { return false }
            if field == .keyword && c.values.count > 1 { return false }
        }
        return true
    }

    /// The values the simple form shows for `field`.
    public func valuesOf(_ field: FilterField) -> [String] {
        conditions.filter { $0.field == field && $0.isActive && !$0.exclude }.flatMap(\.values)
    }

    /// Replaces `field`'s row in the simple form; no values removes it.
    /// (Like the Dart version, the result is joined by 且.)
    public func withValues(_ field: FilterField, _ values: [String]) -> FilterRule {
        var out: [FilterCondition] = []
        var placed = false
        for c in conditions {
            if c.field != field {
                out.append(c)
            } else if !placed && !values.isEmpty {
                out.append(FilterCondition(field, values))
                placed = true
            }
        }
        if !placed && !values.isEmpty { out.append(FilterCondition(field, values)) }
        // Keep the rows in the order the form shows them.
        let end = FilterField.allCases.count
        out.sort { ($0.field?.index ?? end) < ($1.field?.index ?? end) }
        return FilterRule(conditions: out)
    }

    /// Leaves out conditions with nothing chosen.
    public func tidy() -> FilterRule {
        copy(conditions: conditions.filter { $0.isActive || !$0.isKnown })
    }

    /// A test for tasks as of `now`. Trashed tasks never match.
    public func matcher(_ now: LocalDateTime) -> (TodoTask) -> Bool {
        let tests = conditions.filter(\.isActive).map { conditionTest($0, now) }
        if tests.isEmpty { return { $0.trashedAt == nil } }
        return matchAll
            ? { t in t.trashedAt == nil && tests.allSatisfy { $0(t) } }
            : { t in t.trashedAt == nil && tests.contains { $0(t) } }
    }

    /// Where a task typed into the filter's quick-add field goes: into the
    /// list, tag, day and priority the rule asks for, when it asks for one.
    public func quickAddHints(_ today: Day) -> FilterQuickAddHints {
        if !matchAll { return FilterQuickAddHints() }
        func only(_ f: FilterField) -> String? {
            let c = conditions.filter { $0.field == f && $0.isActive && !$0.exclude }
            return c.count == 1 && c[0].values.count == 1 ? c[0].values[0] : nil
        }
        let tag = conditions
            .filter { $0.field == .tag && $0.isActive && !$0.exclude }
            .flatMap(\.values)
            .first { $0 != noTag }
        let date: Day? = switch only(.date) {
        case "today"?: today
        case "tomorrow"?: today + 1
        default: nil
        }
        let p = only(.priority)
        return FilterQuickAddHints(
            listId: only(.list),
            date: date,
            tag: tag,
            priority: p.flatMap { p in priorityChoices.first { $0.key == p }?.priority }
        )
    }
}

/// What `FilterRule.quickAddHints` gives a new task; nil where the rule
/// doesn't say.
public struct FilterQuickAddHints: Sendable, Hashable {
    public var listId: String?
    public var date: Day?
    public var tag: String?
    public var priority: Priority?

    public init(listId: String? = nil, date: Day? = nil, tag: String? = nil, priority: Priority? = nil) {
        self.listId = listId
        self.date = date
        self.tag = tag
        self.priority = priority
    }
}

private func conditionTest(_ c: FilterCondition, _ now: LocalDateTime) -> (TodoTask) -> Bool {
    let values = Set(c.values)
    let test: (TodoTask) -> Bool = switch c.field! {
    case .list: { values.contains($0.listId) }
    case .tag: { t in t.tags.isEmpty ? values.contains(noTag) : t.tags.contains(where: values.contains) }
    case .priority: { values.contains(priorityKey($0.priority)) }
    case .keyword: keywordTest(c.values)
    case .date: dateTest(values, now)
    }
    return c.exclude ? { !test($0) } : test
}

private func keywordTest(_ values: [String]) -> (TodoTask) -> Bool {
    let words = values.map(\.dartTrimmed).filter { !$0.isEmpty }.map { $0.lowercased() }
    return { t in
        let title = t.title.lowercased(), content = t.content.lowercased()
        return words.contains { utf16Contains(title, $0) || utf16Contains(content, $0) }
    }
}

private func dateTest(_ values: Set<String>, _ now: LocalDateTime) -> (TodoTask) -> Bool {
    let today = now.day
    let weekStart = today.startOfWeek
    // Inclusive ranges of days.
    var ranges: [ClosedRange<Day>] = []
    for v in values {
        switch DateChoice(rawValue: v) {
        case .today: ranges.append(today...today)
        case .tomorrow: ranges.append(today + 1...today + 1)
        case .thisWeek: ranges.append(weekStart...weekStart + 6)
        case .next7: ranges.append(today...today + 6)
        case .nextWeek: ranges.append(weekStart + 7...weekStart + 13)
        case .thisMonth: ranges.append(today.startOfMonth...today.endOfMonth)
        case .overdue?, DateChoice.none?: break
        case nil:
            // A custom range (Swift version); anything else is from a newer
            // version and left out, as the Dart version does.
            if let r = FilterDateRange(value: v) { ranges.append(r.start...r.end) }
        }
    }
    let none = values.contains(DateChoice.none.rawValue)
    let overdue = values.contains(DateChoice.overdue.rawValue)
    return { t in
        guard let first = t.dueDate else { return none }
        if overdue && isOverdue(t, now) { return true }
        // A span is on every day it covers.
        let last = lastDueDay(t)
        return ranges.contains { first <= $0.upperBound && last >= $0.lowerBound }
    }
}

/// What the picker shows for the chosen values, e.g. `今天、明天`.
/// With `today`, a custom range in this year leaves the year out.
public func describeValues(_ field: FilterField, _ values: [String], lists: [String: TaskList], today: Day? = nil) -> String {
    if values.isEmpty { return "所有" }
    func one(_ v: String) -> String {
        switch field {
        case .list: v == inboxListId ? "收集箱" : (lists[v]?.name ?? "已删除的清单")
        case .tag: v == noTag ? "无标签" : v
        case .date: DateChoice(rawValue: v)?.label ?? FilterDateRange(value: v)?.label(today: today) ?? v
        case .priority: priorityChoices.first { $0.key == v }?.label ?? v
        case .keyword: "“\(v)”"
        }
    }
    return values.map(one).joined(separator: "、")
}

// MARK: - Swift version only

/// A date condition's custom range (自定义范围): from `start` to `end`, both
/// days included. Stored among the condition's values as
/// `"2026-11-01~2026-11-30"`. The Dart version reads a date value it doesn't
/// know as nothing (it leaves it out when matching, shows it as written in
/// the picker, and keeps it when saving), so older versions don't fail on
/// it: they just don't match on the range.
public struct FilterDateRange: Sendable, Hashable {
    public let start: Day
    public let end: Day

    /// The two days in either order.
    public init(_ a: Day, _ b: Day) {
        start = min(a, b)
        end = max(a, b)
    }

    /// Reads a stored value; nil for anything else (the `DateChoice` names).
    public init?(value: String) {
        let parts = value.split(separator: "~", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 10, parts[1].count == 10,
              let a = Day(parts[0]), let b = Day(parts[1])
        else { return nil }
        self.init(a, b)
    }

    public var value: String { "\(start.key)~\(end.key)" }

    public func contains(_ day: Day) -> Bool { start <= day && day <= end }

    /// `11月1日–11月30日`, `11月3日` for one day; years shown when not
    /// `today`'s (always without `today`).
    public func label(today: Day? = nil) -> String {
        let thisYear = today.map { start.year == $0.year && end.year == $0.year } ?? false
        func text(_ d: Day, year: Bool) -> String { (year ? "\(d.year)年" : "") + "\(d.month)月\(d.day)日" }
        if start == end { return text(start, year: !thisYear) }
        let endYear = !thisYear && end.year != start.year
        return text(start, year: !thisYear) + "–" + text(end, year: endYear)
    }
}

extension FilterCondition {
    /// The custom range among a date condition's values, if there is one.
    public var dateRange: FilterDateRange? {
        field == .date ? values.lazy.compactMap(FilterDateRange.init(value:)).first : nil
    }

    /// The values with the custom range set to `range` (nil takes it out);
    /// it replaces any range already there, keeping its place.
    public func values(settingRange range: FilterDateRange?) -> [String] {
        var out: [String] = []
        var placed = false
        for v in values {
            if FilterDateRange(value: v) != nil {
                if !placed, let range { out.append(range.value) }
                placed = true
            } else {
                out.append(v)
            }
        }
        if !placed, let range { out.append(range.value) }
        return out
    }
}

/// Filters in the order the sidebar shows them: by `sortOrder`, then
/// `createdAt` (as `TaskRepo.watchFilters` reads them); deleted ones left out.
public func sortedFilters(_ filters: [TaskFilter]) -> [TaskFilter] {
    filters.filter { $0.deletedAt == nil }.sorted {
        $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.createdAt < $1.createdAt
    }
}

/// Dragging filter `movingId` in the sidebar so it lands at `index` of the
/// filters as shown (counting it where it was): the new `sortOrder`s to
/// save, usually just the moved filter's (see `planMove`). Empty when it
/// doesn't move or isn't there.
public func planFilterMove(_ filters: [TaskFilter], moving movingId: String, to index: Int) -> [String: Double] {
    let shown = sortedFilters(filters)
    let ids = shown.map(\.id)
    guard let from = ids.firstIndex(of: movingId) else { return [:] }
    if index == from || index == from + 1 { return [:] }
    let byId = Dictionary(shown.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { a, _ in a })
    let plan = planMove(ids, movingId, index) { byId[$0]! }
    return plan.filter { byId[$0.key] != $0.value }
}

extension String {
    /// Dart's `String.trim()`: leading and trailing whitespace off.
    var dartTrimmed: String {
        let s = unicodeScalars
        guard let a = s.firstIndex(where: { !$0.properties.isWhitespace }),
              let b = s.lastIndex(where: { !$0.properties.isWhitespace })
        else { return "" }
        return String(s[a...b])
    }
}
