// Dragging tasks onto the sidebar (macOS): onto a list or 收集箱 moves them
// there, onto 今天 / 明天 gives them that day (each keeps its time), onto a
// tag adds the tag, onto 已完成 completes them, onto 垃圾桶 deletes them (both
// with 撤销). 最近7天 and the filters don't take a drop: they don't say one
// thing to change.
//
// The sidebar is outside the drag space the tasks come from (the list, the
// board, the timeline), so what's being dragged is handed over through the
// window's `DragHandoff`: `DragSource` writes it as a drag starts, and a
// drop on a sidebar row checks that what arrived is that drag's text (a
// stale handoff or text from another app does nothing).
//
//     row.sidebarTaskDrop(view)          // ViewsList, macOS sidebar rows

import OpenTodoDomain
import SwiftUI

/// What a window is dragging, for places outside the drag space it started
/// in. One per window (`AppModel.dragHandoff`), in the environment.
@MainActor
public final class DragHandoff {
    public private(set) var item: DragItem?
    /// What the drag carries as text (`DragToken`).
    public private(set) var text = ""

    public init() {}

    func begin(_ item: DragItem, text: String) {
        self.item = item
        self.text = text
    }

    /// The tasks of the drag that brought `strings`, if that's the drag
    /// this window started.
    public func tasks(arriving strings: [String]) -> [TodoTask]? {
        guard case .tasks(let d)? = item, strings.joined(separator: "\n") == text else { return nil }
        return d.all
    }

    /// The tasks being dragged now, whatever arrives.
    public var draggedTasks: [TodoTask]? {
        if case .tasks(let d)? = item { d.all } else { nil }
    }
}

extension EnvironmentValues {
    @Entry var dragHandoff: DragHandoff? = nil
}

/// What dropping `tasks` on the sidebar row of `view` does; nil when it
/// does nothing (a view that doesn't stand for one change, or they all
/// have it already).
public func sidebarDropAction(_ view: ViewRef, _ tasks: [TodoTask], today: Day) -> BatchAction? {
    let open = tasks.filter { $0.status == .open && $0.trashedAt == nil }
    func due(_ day: Day) -> BatchAction? {
        let changes = open.filter { $0.dueDate != day }.map { BatchDueChange(id: $0.id, date: day, time: $0.dueTime) }
        return changes.isEmpty ? nil : .setDue(changes)
    }
    func move(_ listId: String) -> BatchAction? {
        let ids = open.filter { $0.listId != listId }.map(\.id)
        return ids.isEmpty ? nil : .moveToList(ids: ids, listId: listId)
    }
    switch view {
    case .smart(.today): return due(today)
    case .smart(.tomorrow): return due(today + 1)
    case .smart(.inbox): return move(inboxListId)
    case .list(let id): return move(id)
    case .tag(let tag):
        let changes = open.filter { !$0.tags.contains(tag) }.map { BatchTagChange(id: $0.id, tags: $0.tags + [tag]) }
        return changes.isEmpty ? nil : .setTags(changes)
    case .smart(.completed): return open.isEmpty ? nil : .complete(ids: open.map(\.id))
    case .smart(.trash): return open.isEmpty ? nil : .trash(ids: open.map(\.id))
    case .smart(.next7), .filter: return nil
    }
}

extension AppModel {
    /// Drops `tasks` on the sidebar row of `view` (`sidebarDropAction`),
    /// saying where they went when they leave sight.
    public func dropOnSidebar(_ view: ViewRef, _ tasks: [TodoTask]) async {
        guard let action = sidebarDropAction(view, tasks, today: today) else { return }
        await performBatch(action)
        let name = title(of: view)
        func say(_ n: Int, _ what: String) { notices.show(n == 1 ? "已\(what)" : "已把 \(n) 个任务\(what)") }
        switch action {
        case .setDue(let changes): say(changes.count, "改到\(name)")
        case .moveToList(let ids, _): say(ids.count, "移到“\(name)”")
        case .setTags(let changes): say(changes.count, "加上标签 \(name)")
        default: break
        }
    }
}

extension View {
    /// A sidebar row that takes tasks dragged from this window (macOS).
    func sidebarTaskDrop(_ view: ViewRef) -> some View {
        modifier(SidebarTaskDrop(view: view))
    }
}

private struct SidebarTaskDrop: ViewModifier {
    let view: ViewRef
    @Environment(AppModel.self) private var model
    @Environment(\.dragHandoff) private var handoff
    @Environment(\.uiScale) private var s
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .background {
                if targeted {
                    RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                        .padding(.horizontal, -6 * s)
                        .padding(.vertical, -3 * s)
                }
            }
            .dropDestination(for: String.self) { strings, _ in
                targeted = false
                guard let handoff, let tasks = handoff.tasks(arriving: strings),
                      sidebarDropAction(view, tasks, today: model.today) != nil else { return false }
                model.run { await model.dropOnSidebar(view, tasks) }
                return true
            } isTargeted: { over in
                // Only light up where letting go would do something.
                targeted = over && handoff?.draggedTasks.flatMap { sidebarDropAction(view, $0, today: model.today) } != nil
            }
    }
}
