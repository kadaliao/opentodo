// The filter editor's state and every change the form can make, apart from
// the views so it can be tested: the Dart version's `_FilterEditorState`
// and `_ValuePicker` (`app/lib/ui/filter_editor.dart`).

import Foundation
import OpenTodoDomain

/// What the editor saves: the name (trimmed) and the rule to store with
/// `rule.encode()`.
public struct FilterEditorResult: Sendable, Hashable {
    public var name: String
    public var rule: FilterRule
}

public struct FilterEditorModel: Sendable, Hashable {
    /// Nil when adding a new filter.
    public let filterId: String?
    public var name: String
    public private(set) var rule: FilterRule
    /// The 高级 form (several conditions, 不包含, 满足任一) rather than 普通.
    public private(set) var advanced: Bool
    /// Stable ids for the advanced rows, parallel to the conditions, so a
    /// row keeps its text field when a row above it goes.
    public private(set) var rowKeys: [Int]
    private var nextKey: Int

    /// Editing `filter`, or adding one when nil. A stored rule that the
    /// simple form can't show opens in 高级.
    public init(filter: TaskFilter? = nil) {
        self.init(rule: filter.map { FilterRule.parse($0.rule) } ?? FilterRule(), name: filter?.name ?? "", filterId: filter?.id)
    }

    /// Editing a rule on its own (`FilterRuleEditor`), or with a name.
    public init(rule: FilterRule, name: String = "", filterId: String? = nil) {
        self.filterId = filterId
        self.name = name
        self.rule = rule
        advanced = !rule.isSimple
        rowKeys = Array(rule.conditions.indices)
        nextKey = rule.conditions.count
    }

    public var title: String { filterId == nil ? "添加过滤器" : "编辑过滤器" }

    /// 保存 waits for a name.
    public var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether 普通 can show what's there; when not, it's greyed out.
    public var canSimple: Bool { rule.tidy().isSimple }

    /// Switches between 普通 and 高级. Going to 高级 with nothing yet gives
    /// one empty 清单 row; going back drops the rows with nothing chosen.
    public mutating func setAdvanced(_ on: Bool) {
        if on == advanced { return }
        if on {
            if rule.conditions.isEmpty { setConditions([FilterCondition(.list, [])]) }
        } else {
            guard canSimple else { return }
            setConditions(rule.tidy().conditions)
        }
        advanced = on
    }

    private mutating func setConditions(_ conditions: [FilterCondition], keys: [Int]? = nil) {
        rule = rule.copy(conditions: conditions)
        if let keys {
            rowKeys = keys
        } else {
            rowKeys = conditions.indices.map { nextKey + $0 }
            nextKey += conditions.count
        }
    }

    // MARK: 普通

    /// The values the simple form shows for `field`.
    public func simpleValues(_ field: FilterField) -> [String] { rule.valuesOf(field) }

    public mutating func setSimpleValues(_ field: FilterField, _ values: [String]) {
        rule = rule.withValues(field, values)
    }

    /// 内容包含: the keyword as typed; blank removes the row.
    public var simpleKeyword: String { rule.valuesOf(.keyword).first ?? "" }

    public mutating func setSimpleKeyword(_ text: String) {
        setSimpleValues(.keyword, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [text])
    }

    /// The priority chips: 所有 clears them, the others toggle, kept in
    /// 高中低无 order.
    public mutating func setPriority(_ key: String, on: Bool) {
        let chosen = simpleValues(.priority)
        let next = priorityChoices.map(\.key).filter { $0 == key ? on : chosen.contains($0) }
        setSimpleValues(.priority, next)
    }

    // MARK: 高级

    public mutating func setMatchAll(_ all: Bool) {
        rule = rule.copy(matchAll: all)
    }

    /// Another field starts the row afresh (keeping 包含 / 不包含).
    public mutating func setField(at i: Int, _ field: FilterField) {
        let c = rule.conditions[i]
        guard c.field != field else { return }
        replace(at: i, FilterCondition(field, [], exclude: c.exclude))
    }

    public mutating func setExclude(at i: Int, _ exclude: Bool) {
        guard rule.conditions[i].isKnown else { return }
        replace(at: i, rule.conditions[i].copy(exclude: exclude))
    }

    public mutating func setValues(at i: Int, _ values: [String]) {
        guard rule.conditions[i].isKnown else { return }
        replace(at: i, rule.conditions[i].copy(values: values))
    }

    /// A keyword row's text.
    public mutating func setKeyword(at i: Int, _ text: String) {
        setValues(at: i, [text])
    }

    private mutating func replace(at i: Int, _ c: FilterCondition) {
        var conditions = rule.conditions
        conditions[i] = c
        setConditions(conditions, keys: rowKeys)
    }

    public mutating func removeCondition(at i: Int) {
        var conditions = rule.conditions
        var keys = rowKeys
        conditions.remove(at: i)
        keys.remove(at: i)
        setConditions(conditions, keys: keys)
    }

    /// 添加条件: a row for the first field not used yet (清单 when all are).
    public mutating func addCondition() {
        let used = Set(rule.conditions.compactMap(\.field))
        let field = FilterField.allCases.first { !used.contains($0) } ?? .list
        setConditions(rule.conditions + [FilterCondition(field, [])], keys: rowKeys + [nextKey])
        nextKey += 1
    }

    // MARK: Result

    /// What to save, or nil without a name: rows with nothing chosen left
    /// out, keyword text trimmed.
    public func result() -> FilterEditorResult? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return FilterEditorResult(name: name, rule: savedRule)
    }

    /// The rule as it's saved: rows with nothing chosen left out, keyword
    /// text trimmed.
    public var savedRule: FilterRule {
        let conditions = rule.tidy().conditions.map { c in
            c.field == .keyword
                ? c.copy(values: c.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                : c
        }
        return FilterRule(matchAll: rule.matchAll, conditions: conditions)
    }

    /// How many open tasks the rule takes right now.
    public func matchingCount(_ tasks: [TodoTask], now: LocalDateTime) -> Int {
        let matches = rule.tidy().matcher(now)
        return tasks.count { isOpen($0) && matches($0) }
    }

    public static func countText(_ count: Int) -> String {
        count == 0 ? "现在没有符合条件的未完成任务" : "现在有 \(count) 个未完成任务符合条件"
    }
}

/// One choice in a value picker.
public struct FilterValueOption: Sendable, Hashable, Identifiable {
    public var value: String
    public var label: String
    public var id: String { value }
}

/// The choices for `field`: 收集箱 and the lists, 无标签 and the tags, the
/// date choices, the priorities. Something chosen earlier that's gone now
/// (a deleted list shows as 已删除的清单, a tag no task uses, a value from a
/// newer version) stays at the end so it can be unticked. A date
/// condition's custom range isn't among them: the picker shows it apart.
public func filterValueOptions(
    _ field: FilterField,
    values: [String],
    lists: [TaskList],
    tags: [String]
) -> [FilterValueOption] {
    var options: [FilterValueOption] = switch field {
    case .list:
        [FilterValueOption(value: inboxListId, label: "收集箱")]
            + lists.filter { $0.deletedAt == nil }.map { FilterValueOption(value: $0.id, label: listLabel($0)) }
    case .tag:
        [FilterValueOption(value: noTag, label: "无标签")] + tags.map { FilterValueOption(value: $0, label: $0) }
    case .date:
        DateChoice.allCases.map { FilterValueOption(value: $0.rawValue, label: $0.label) }
    case .priority:
        priorityChoices.map { FilterValueOption(value: $0.key, label: $0.label) }
    case .keyword:
        []
    }
    let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    for v in values where !options.contains(where: { $0.value == v }) {
        if field == .date && FilterDateRange(value: v) != nil { continue }
        options.append(FilterValueOption(value: v, label: describeValues(field, [v], lists: byId.filter { $0.value.deletedAt == nil })))
    }
    return options
}

/// `values` with `value` ticked or unticked, in the options' order; values
/// not among the options (a custom range) stay at the end.
public func toggling(_ value: String, in values: [String], options: [FilterValueOption]) -> [String] {
    let on = !values.contains(value)
    let listed = options.map(\.value).filter { $0 == value ? on : values.contains($0) }
    let rest = values.filter { v in !options.contains { $0.value == v } }
    return listed + rest
}

/// `💼 工作`, or just the name.
func listLabel(_ l: TaskList) -> String {
    "\(l.textEmoji ?? "") \(l.name)".trimmingCharacters(in: .whitespaces)
}

/// The view to show after filter `id` is deleted (here or by a sync): 今天
/// if it was the one showing, else what was.
public func viewAfterDeletingFilter(_ id: String, selected: ViewRef) -> ViewRef {
    selected == .filter(id) ? .smart(.today) : selected
}
