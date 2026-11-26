// What can be dragged around a list or a board, and what a drop does with
// it — ported from `app/lib/ui/task_drag.dart` and the moving half of
// `app/lib/ui/section_actions.dart`. Pure values: the views feed them, and
// the result goes out to whoever writes (TaskRepo.dropInto,
// TaskRepo.updateSection).

import CoreGraphics
import OpenTodoDomain

/// The tasks being dragged: the one under the pointer (`lead`) and, when
/// it is one of several picked (多选), the others with it.
public struct DraggedTasks: Sendable, Hashable {
    public var lead: TodoTask

    /// Every task dragged, in the order shown, `lead` among them; just
    /// `lead` when empty.
    public var tasks: [TodoTask]

    public init(_ lead: TodoTask, _ tasks: [TodoTask] = []) {
        self.lead = lead
        self.tasks = tasks
    }

    /// Dragging `task` when `picked` (in the order shown) are picked: all
    /// of them when it is one of them and there's more than one.
    public init(_ task: TodoTask, picked: [TodoTask]) {
        self.init(task, picked.count > 1 && picked.contains { $0.id == task.id } ? picked : [])
    }

    public var all: [TodoTask] { tasks.isEmpty ? [lead] : tasks }
    public var count: Int { all.count }

    public func contains(_ id: String) -> Bool { all.contains { $0.id == id } }
}

/// What's being dragged.
public enum DragItem: Sendable, Hashable {
    case tasks(DraggedTasks)
    /// A list's section (分组), by its header or its board column.
    case section(ListSection)
}

/// What a drop of tasks into a group comes to: give `ids` what `target`
/// stands for, and the new `sortOrder`s (often just the moved tasks'; empty
/// when only the group counts). `TaskRepo.dropInto(ids, target, orders)`.
public struct TaskDropPlan: Sendable, Hashable {
    public var ids: [String]
    public var target: GroupTarget
    public var orders: [String: Double]

    public init(ids: [String], target: GroupTarget, orders: [String: Double]) {
        self.ids = ids
        self.target = target
        self.orders = orders
    }
}

private func movable(_ t: TodoTask) -> Bool { t.status == .open && t.trashedAt == nil }

/// A group of a view's open tasks (a section of a list, a day, a
/// priority…): tasks dropped into it take on what the group stands for
/// (`target`) and, in manual order, land where they're dropped.
public struct GroupDrop: Sendable, Hashable {
    public var target: GroupTarget

    /// The group's open tasks as shown, pinned ones first.
    public var tasks: [TodoTask]

    /// The view is in manual order; otherwise a drop only changes group.
    public var manual: Bool

    public init(_ target: GroupTarget, tasks: [TodoTask] = [], manual: Bool = false) {
        self.target = target
        self.tasks = tasks
        self.manual = manual
    }

    /// The drop for a section of `buildSections`, if things can be dropped
    /// in it.
    public init?(_ section: TaskSection) {
        guard let target = section.target, !section.finished else { return nil }
        self.init(target, tasks: section.tasks, manual: section.manualOrder)
    }

    /// Whether where in the group it lands counts (a line shows where), or
    /// only which group.
    public var ordered: Bool { manual }

    /// Out of manual order, only tasks from another group.
    public func accepts(_ t: TodoTask) -> Bool {
        movable(t) && target.takes(t) && (manual || !target.has(t))
    }

    /// Takes a drag when any of its tasks can go here.
    public func accepts(_ d: DraggedTasks) -> Bool { d.all.contains(where: accepts) }

    /// Puts the dragged tasks that can go here in this group, together, at
    /// `index` among the tasks as shown (counting any of them where they
    /// are now) when `ordered`. Nil when there's nothing to do: none can
    /// go here, or they were let go where they already are.
    public func plan(_ d: DraggedTasks, at index: Int) -> TaskDropPlan? {
        let moving = d.all.filter(accepts)
        if moving.isEmpty { return nil }
        let ids = moving.map(\.id)
        var orders: [String: Double] = [:]
        if manual {
            // Pinned tasks move among the pinned ones, the rest among the rest.
            let split = tasks.firstIndex { $0.pinnedAt == nil } ?? tasks.count
            for pinned in [true, false] {
                let movers = moving.filter { ($0.pinnedAt != nil) == pinned }
                if movers.isEmpty { continue }
                let peers = tasks.filter { ($0.pinnedAt != nil) == pinned }
                let at = pinned ? min(max(index, 0), split) : min(max(index - split, 0), peers.count)
                var byId: [String: TodoTask] = [:]
                for x in peers + movers { byId[x.id] = x }
                orders.merge(
                    planMoveMany(peers.map(\.id), movers.map(\.id), at) { byId[$0]!.sortOrder },
                    uniquingKeysWith: { $1 }
                )
            }
            // Let go where they were: nothing to do.
            if orders.isEmpty && moving.allSatisfy({ t in tasks.contains { $0.id == t.id } }) { return nil }
        }
        return TaskDropPlan(ids: ids, target: target, orders: orders)
    }
}

/// The new `sortOrder`s that put the section `id` at `index` of `sections`
/// (the list's, in order; the index counts it where it is now), as
/// dragging it there does. Empty when it stays where it is.
public func planSectionMove(_ sections: [ListSection], _ id: String, to index: Int) -> [String: Double] {
    let ids = sections.map(\.id)
    guard let from = ids.firstIndex(of: id), index != from, index != from + 1 else { return [:] }
    var byId: [String: ListSection] = [:]
    for s in sections { byId[s.id] = s }
    return planMove(ids, id, index) { byId[$0]!.sortOrder }
}

/// The new `sortOrder`s that move the section `id` `delta` places among
/// `sections` (上移 / 下移, 左移 / 右移). Empty when it can't go further.
public func planSectionShift(_ sections: [ListSection], _ id: String, by delta: Int) -> [String: Double] {
    guard let from = sections.firstIndex(where: { $0.id == id }) else { return [:] }
    let to = from + delta
    guard to >= 0, to < sections.count else { return [:] }
    // The index counts the section still in place.
    return planSectionMove(sections, id, to: delta > 0 ? to + 1 : to)
}
