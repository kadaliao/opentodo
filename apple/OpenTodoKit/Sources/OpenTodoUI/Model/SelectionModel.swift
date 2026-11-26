// Multi-select (多选): the tasks picked at once, to change them together.
// It wraps the domain's `TaskSelection` (ids and the Shift-click anchor)
// and its `tapTask` rule, so the list, the board, the timeline and the
// calendar all pick the same way. The task open in the detail is separate:
// `AppModel.selectedTaskId`.
//
//     if let id = model.selection.tap(task.id, modifiers: mods, order: shownIds,
//                                     current: model.selectedTaskId) {
//         model.open(taskId: id)              // a plain click opens
//     }
//
// Changing view or module clears it (`AppModel.select(_:)` / `switchTo(_:)`).

import Observation
import OpenTodoDomain

@Observable
public final class SelectionModel {
    public private(set) var picked = TaskSelection()
    /// iOS: 多选 mode is on (taps pick instead of opening), even before
    /// anything is picked.
    public var isPicking = false

    public init() {}

    public var ids: Set<String> { picked.ids }
    public var anchor: String? { picked.anchor }
    /// Whether any task is picked.
    public var isActive: Bool { picked.active }
    public func contains(_ id: String) -> Bool { picked.contains(id) }

    /// What a click or tap on `id` does (`tapTask`): ⌘ toggles it, Shift
    /// picks the range in `order` (the tasks as shown), a tap while picking
    /// on a touch screen toggles; otherwise picking stops and the task is
    /// returned to open. `current` is the task open in the detail, which a
    /// first ⌘-click takes along.
    @discardableResult
    public func tap(_ id: String, modifiers: TapModifiers = [], order: [String], current: String?,
                    touch: Bool = SelectionModel.touch) -> String? {
        // 多选 mode on with nothing picked yet: a tap starts picking.
        if isPicking && !picked.active {
            picked.toggle(id)
            return nil
        }
        let open = tapTask(id, selection: &picked, order: order, current: current, modifiers: modifiers,
                           touch: touch || isPicking)
        if open != nil { isPicking = false }
        return open
    }

    /// Starts picking with `id` (a task's menu: 多选).
    public func start(_ id: String) {
        picked.start(id)
        isPicking = true
    }

    public func selectAll(_ order: [String]) { picked.selectAll(order) }

    /// Takes the picked set a system list worked out itself (its own ⌘ /
    /// Shift clicks and ⌘A follow the same rules); the anchor is the task
    /// added last.
    public func replace(with ids: Set<String>) {
        let added = ids.subtracting(picked.ids)
        picked = TaskSelection(ids, anchor: added.first ?? picked.anchor.flatMap { ids.contains($0) ? $0 : nil })
    }

    /// Picks nothing and leaves 多选 mode.
    public func clear() {
        if picked.active { picked.clear() }
        isPicking = false
    }

    #if os(iOS)
    public static let touch = true
    #else
    public static let touch = false
    #endif
}
