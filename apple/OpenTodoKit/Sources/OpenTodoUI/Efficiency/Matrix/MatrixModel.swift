// The four quadrants' screen logic, apart from the views so it can be
// tested: what a drop changes, what quick add fills in, the simple
// priority-only rule editor, and each quadrant's look.

import OpenTodoDomain
import SwiftUI

/// A task dropped (or moved by menu) into quadrant `index`: the task as it
/// was and as it should be saved. Nil when there's nothing to change: an
/// unknown task, the quadrant it's already in, or a rule that asks for
/// nothing a drop can set.
func matrixDrop(
    taskId: String, into index: Int, tasks: [TodoTask], prefs: MatrixPrefs, now: LocalDateTime
) -> (old: TodoTask, new: TodoTask)? {
    guard prefs.quadrants.indices.contains(index), let t = tasks.first(where: { $0.id == taskId }) else { return nil }
    if matrixQuadrantIndex(of: t, prefs: prefs, now: now) == index { return nil }
    let moved = movedIntoQuadrant(t, prefs.quadrants[index], today: now.day)
    return moved == t ? nil : (t, moved)
}

/// The quadrant a task shows in, if any.
func matrixQuadrantIndex(of t: TodoTask, prefs: MatrixPrefs, now: LocalDateTime) -> Int? {
    matrixCells([t], prefs: prefs, now: now).first { !$0.tasks.isEmpty }?.index
}

/// Where a task typed into quadrant `index` goes: the list, day, tag and
/// priority its rule asks for, like a filter's quick-add field.
func matrixQuickAddDefaults(_ index: Int, prefs: MatrixPrefs, today: Day) -> QuickAddDefaults {
    guard prefs.quadrants.indices.contains(index) else { return QuickAddDefaults() }
    let h = prefs.quadrants[index].filterRule.quickAddHints(today)
    return QuickAddDefaults(listId: h.listId ?? inboxListId, date: h.date, tags: h.tag.map { [$0] } ?? [], priority: h.priority)
}

// MARK: - Simple rule editor

/// The priorities a rule asks for, as the simple editor shows them.
func rulePriorities(_ rule: FilterRule) -> Set<Priority> {
    Set(rule.valuesOf(.priority).compactMap { key in priorityChoices.first { $0.key == key }?.priority })
}

/// The rule with its priority condition replaced (the other conditions
/// kept); none chosen drops the condition.
func ruleWithPriorities(_ rule: FilterRule, _ ps: Set<Priority>) -> FilterRule {
    let keys = priorityChoices.filter { ps.contains($0.priority) }.map(\.key)
    return rule.withValues(.priority, keys)
}

/// A one-line summary of a rule: 高优先级, 高、中优先级, or 自定义条件.
func ruleSummary(_ rule: FilterRule) -> String {
    let active = rule.conditions.filter(\.isActive)
    if active.isEmpty { return "所有任务" }
    if active.count == 1, active[0].field == .priority, !active[0].exclude {
        let labels = priorityChoices.filter { rulePriorities(rule).contains($0.priority) }.map(\.label)
        return labels == ["无"] ? "无优先级" : labels.joined(separator: "、") + "优先级"
    }
    return "自定义条件"
}

// MARK: - Look

/// Each quadrant's colour and symbol, by position.
enum MatrixStyle {
    static func tint(_ i: Int) -> Color { [Color.red, .orange, .blue, .green][i % 4] }
    static func symbol(_ i: Int) -> String { ["\(i + 1).circle.fill"][0] }
}

func priorityTint(_ p: Priority) -> Color {
    switch p {
    case .high: Color(argb: 0xFFE5484D)
    case .medium: Color(argb: 0xFFF2A516)
    case .low: Color(argb: 0xFF3E8BFF)
    case .none: .secondary
    }
}
