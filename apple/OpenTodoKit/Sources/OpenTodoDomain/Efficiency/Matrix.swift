// The four quadrants (四象限): open tasks sorted by importance and urgency.
// New in the Swift version (roadmap M5); see `docs/apple.md` (效率模块).
//
// Each quadrant is a name and a filter rule (`Filters.swift`). By default
// they go by priority: high, medium, low, none. The person can change any
// quadrant's rule; the four are kept on this device in `key_values` under
// `matrix.prefs`, each rule as the same JSON text a saved filter stores.

import Foundation

/// One quadrant: its name and which tasks it gathers.
public struct MatrixQuadrant: Sendable, Hashable, Codable {
    public var name: String
    /// The rule's JSON text, as `TaskFilter.rule` stores it.
    public var rule: String

    public init(name: String, rule: String) {
        self.name = name
        self.rule = rule
    }

    public init(name: String, rule: FilterRule) {
        self.init(name: name, rule: rule.encode())
    }

    public var filterRule: FilterRule { FilterRule.parse(rule) }
}

/// The four quadrants, top left, top right, bottom left, bottom right.
public struct MatrixPrefs: Sendable, Hashable, Codable {
    public static let storageKey = "matrix.prefs"

    /// Always four.
    public var quadrants: [MatrixQuadrant]

    public init(quadrants: [MatrixQuadrant] = MatrixPrefs.defaultQuadrants) {
        self.quadrants = MatrixPrefs.fill(quadrants)
    }

    public static let defaultQuadrants: [MatrixQuadrant] = [
        MatrixQuadrant(name: "重要且紧急", rule: FilterRule(conditions: [FilterCondition(.priority, ["high"])])),
        MatrixQuadrant(name: "重要不紧急", rule: FilterRule(conditions: [FilterCondition(.priority, ["medium"])])),
        MatrixQuadrant(name: "不重要但紧急", rule: FilterRule(conditions: [FilterCondition(.priority, ["low"])])),
        MatrixQuadrant(name: "不重要不紧急", rule: FilterRule(conditions: [FilterCondition(.priority, ["none"])])),
    ]

    public static let standard = MatrixPrefs()

    /// Missing quadrants take the defaults; extra ones are dropped.
    private static func fill(_ qs: [MatrixQuadrant]) -> [MatrixQuadrant] {
        (0..<4).map { i in i < qs.count ? qs[i] : defaultQuadrants[i] }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let qs = (try? c.decodeIfPresent([Lenient].self, forKey: .quadrants)) ?? nil
        self.init(quadrants: (qs ?? []).enumerated().map { i, q in
            let d = i < 4 ? MatrixPrefs.defaultQuadrants[i] : MatrixQuadrant(name: "", rule: "{}")
            return MatrixQuadrant(name: q.name ?? d.name, rule: q.rule ?? d.rule)
        })
    }

    /// A quadrant with whatever fields could be read.
    private struct Lenient: Decodable {
        var name: String?
        var rule: String?

        private enum Keys: String, CodingKey { case name, rule }

        init(from decoder: any Decoder) throws {
            let c = try? decoder.container(keyedBy: Keys.self)
            name = (try? c?.decodeIfPresent(String.self, forKey: .name)) ?? nil
            rule = (try? c?.decodeIfPresent(String.self, forKey: .rule)) ?? nil
        }
    }

    /// The JSON text, or the defaults if it can't be read.
    public static func decode(_ json: String?) -> MatrixPrefs {
        guard let data = json?.data(using: .utf8),
              let p = try? JSONDecoder().decode(MatrixPrefs.self, from: data)
        else { return .standard }
        return p
    }

    public var json: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! e.encode(self), as: UTF8.self)
    }
}

/// One quadrant's tasks, as the screen shows them.
public struct MatrixCell: Sendable, Hashable {
    /// 0–3: top left, top right, bottom left, bottom right.
    public var index: Int
    public var name: String
    public var tasks: [TodoTask]

    public init(index: Int, name: String, tasks: [TodoTask]) {
        self.index = index
        self.name = name
        self.tasks = tasks
    }
}

/// The open tasks (not finished, not in the trash, not deleted) in the four
/// quadrants as of `now`. A task that fits several goes in the first; one
/// that fits none isn't shown. Each quadrant is ordered like a list by
/// date: pinned ones first, then by date and time, priority, newest.
public func matrixCells(_ tasks: [TodoTask], prefs: MatrixPrefs = .standard, now: LocalDateTime) -> [MatrixCell] {
    let tests = prefs.quadrants.map { $0.filterRule.matcher(now) }
    var buckets: [[TodoTask]] = Array(repeating: [], count: prefs.quadrants.count)
    for t in tasks where t.deletedAt == nil && isOpen(t) {
        if let i = tests.firstIndex(where: { $0(t) }) { buckets[i].append(t) }
    }
    let compare = TaskSort.due.compare
    return prefs.quadrants.enumerated().map { i, q in
        MatrixCell(index: i, name: q.name, tasks: buckets[i].sorted(comparing: compare))
    }
}

/// The task after being dragged into `quadrant`: it takes the list, date,
/// tag and priority the quadrant's rule asks for, where it asks for exactly
/// one (the same hints a filter's quick-add field uses). Dropped on a
/// different day it keeps its time and span. Nothing else changes; the
/// caller stamps `updatedAt`. If the rule can't be met this way the task
/// may not end up in that quadrant.
public func movedIntoQuadrant(_ task: TodoTask, _ quadrant: MatrixQuadrant, today: Day) -> TodoTask {
    let h = quadrant.filterRule.quickAddHints(today)
    var t = task
    if let p = h.priority { t.priority = p }
    if let list = h.listId, list != t.listId {
        t.listId = list
        t.sectionId = nil
    }
    if let tag = h.tag, !t.tags.contains(tag) { t.tags.append(tag) }
    if let date = h.date { t.dueDate = date }
    return t
}
