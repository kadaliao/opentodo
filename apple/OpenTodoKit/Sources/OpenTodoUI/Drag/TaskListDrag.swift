// Dragging in the task list (`TaskListView`), as task_drag.dart does it
// there: rows drag (the picked ones together), and land on a group's
// header (first in it) or on a row's top or bottom half (before or after
// it, a line shows where) — in a list's own sections, on a day of 今天 /
// 明天 / 最近7天 (the time stays; 已过期 can be dragged out of but not
// into), in a list / tag / priority group (the task takes it on). Out of
// manual order only the group counts: it lights up instead of a line. A
// list's section headers drag the section and take other sections above
// or below them. Near the list's ends it scrolls.
//
//     List { … header.taskListDragHeader(section) … row.taskListDragRow(task, in: section) … }
//         .taskListDragSpace(sections)
//
// Drops go to TaskRepo through the model (`dropTasks`, `perform(.reorder)`).

import OpenTodoDomain
import SwiftUI

extension View {
    /// The task list's drag space, over `sections` (as shown).
    func taskListDragSpace(_ sections: [TaskSection]) -> some View {
        modifier(TaskListDragSpace(sections: sections))
    }

    /// A row of `section`: dragged (unless finished), and a place to drop.
    func taskListDragRow(_ task: TodoTask, in section: TaskSection) -> some View {
        modifier(TaskListDragRow(task: task, section: section))
    }

    /// A group's header: a place to drop (first in the group); a list's
    /// section header also drags its section and takes others.
    func taskListDragHeader(_ section: TaskSection) -> some View {
        modifier(TaskListDragHeader(section: section))
    }
}

/// The open tasks picked (多选), in the order shown: they drag together.
extension EnvironmentValues {
    @Entry var dragPicked: [TodoTask] = []
}

/// The rows of `sections` in the order shown (folded groups' rows aren't
/// there), for scrolling.
func shownRowIds(_ sections: [TaskSection], folded: (TaskSection) -> Bool) -> [String] {
    sections.flatMap { s in s.title != nil && folded(s) ? [] : s.tasks.map(\.id) }
}

/// The picked open tasks, in the order `sections` show them; those in
/// folded groups stay behind (as Flutter's `picked`).
func pickedTasks(_ sections: [TaskSection], _ ids: Set<String>,
                 folded: (TaskSection) -> Bool = { _ in false }) -> [TodoTask] {
    guard !ids.isEmpty else { return [] }
    return sections.filter { !$0.finished && !($0.title != nil && folded($0)) }
        .flatMap { $0.tasks.filter { ids.contains($0.id) } }
}

private struct TaskListDragSpace: ViewModifier {
    let sections: [TaskSection]
    @Environment(AppModel.self) private var model
    @State private var drag = DragController()

    func body(content: Content) -> some View {
        let folded = { (s: TaskSection) in model.taskList.isFolded(s, in: model.view) }
        let rows = shownRowIds(sections, folded: folded)
        content
            .environment(\.dragPicked, pickedTasks(sections, model.selection.ids, folded: folded))
            .dragAutoScroll("task-list", rows: rows)
            .dragSpace(drag)
            .onAppear {
                drag.onDrop = { [weak model] outcome in
                    guard let model else { return }
                    switch outcome {
                    case .tasks(let plan): model.run { await model.dropTasks(plan) }
                    case .sections(let orders): model.run { await model.perform(.reorder(orders)) }
                    }
                }
            }
    }
}

private struct TaskListDragRow: ViewModifier {
    let task: TodoTask
    let section: TaskSection
    @Environment(AppModel.self) private var model
    @Environment(DragController.self) private var drag: DragController?
    @Environment(\.dragPicked) private var picked

    func body(content: Content) -> some View {
        let group = GroupDrop(section)
        let lit = group.map { drag?.highlights($0.target) == true } ?? false
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .taskDragSource(task, picked: picked, isEnabled: !section.finished && task.trashedAt == nil) {
                // Values only: the dragged copy is drawn outside the window.
                DragRowPreview(task: task, now: model.now, list: model.listsById[task.listId],
                               checklist: model.checklistProgress(of: task.id))
            }
            .opacity(drag?.isDragged(task.id) == true ? 0.3 : 1)
            .listRowBackground(lit ? Color.accentColor.opacity(0.1) : nil)
            .modifier(OptionalDropSlot(
                id: "row-\(task.id)",
                kind: group.map { g in .taskRow(g, index: section.tasks.firstIndex { $0.id == task.id } ?? 0) }
            ))
    }
}

private struct TaskListDragHeader: ViewModifier {
    let section: TaskSection
    @Environment(AppModel.self) private var model
    @Environment(DragController.self) private var drag: DragController?

    func body(content: Content) -> some View {
        let group = GroupDrop(section)
        let lit = group.map { drag?.highlights($0.target) == true } ?? false
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if lit {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.12))
                }
            }
            .modifier(OptionalDropSlot(id: "head-\(section.id)", kind: group.map { .taskArea($0, index: 0) }))
            .modifier(SectionHeaderDrag(section: section.listSection,
                                        among: section.listSection.map { model.sectionsByList[$0.listId] ?? [] } ?? []))
    }
}

/// A list section's header drags the section and takes another of the
/// list's above (top half) or below (bottom half) it.
private struct SectionHeaderDrag: ViewModifier {
    let section: ListSection?
    let among: [ListSection]

    func body(content: Content) -> some View {
        if let section {
            let ordered = among.sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.createdAt < $1.createdAt }
            content
                .dropSlot("section-\(section.id)", .section(section, among: ordered, axis: .vertical))
                .sectionDragSource(section) {
                    Text(section.name)
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(width: 240, alignment: .leading)
                        .background(BoardStyle.cardFill, in: .rect(cornerRadius: 10))
                }
        } else {
            content
        }
    }
}

private struct OptionalDropSlot: ViewModifier {
    let id: String
    let kind: DropSlotKind?

    func body(content: Content) -> some View {
        if let kind { content.dropSlot(id, kind) } else { content }
    }
}

/// The dragged copy of a list row.
private struct DragRowPreview: View {
    let task: TodoTask
    let now: LocalDateTime
    let list: TaskList?
    let checklist: (done: Int, total: Int)

    var body: some View {
        TaskRow(task, now: now, list: list, showList: false, checklist: checklist) {}
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(width: 320, alignment: .leading)
            .background(BoardStyle.cardFill, in: .rect(cornerRadius: 10))
    }
}
