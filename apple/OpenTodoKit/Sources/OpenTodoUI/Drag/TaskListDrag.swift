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
#if os(iOS)
import UIKit
#endif

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
            .taskDragSource(task, picked: picked,
                            isEnabled: rowsDragThemselves && !section.finished && task.trashedAt == nil) {
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
    @Environment(\.uiScale) private var s
    let section: ListSection?
    let among: [ListSection]

    func body(content: Content) -> some View {
        if let section {
            let ordered = among.sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.createdAt < $1.createdAt }
            content
                .dropSlot("section-\(section.id)", .section(section, among: ordered, axis: .vertical))
                .sectionDragSource(section) {
                    Text(section.name)
                        .uiFont(.headline)
                        .padding(.horizontal, 14 * s)
                        .padding(.vertical, 10 * s)
                        .frame(width: 240 * s, alignment: .leading)
                        .background(BoardStyle.cardFill, in: .rect(cornerRadius: 10 * s))
                }
        } else {
            content
        }
    }
}

/// The rows of `section`, each made by `row`. On iOS the system list
/// drags them itself, while 排序 is on (`sorting`): the list is in edit
/// mode and each row of a group in manual order has the system's ≡ handle
/// to drag it by within the group (`onMove`), written as a drop would be.
/// A long press on a row's right end turns 排序 on (`taskRowMenu`); anywhere
/// else on the row it's the task's menu. There the drag space can't do
/// it: the `List` keeps every drag over it to itself (its `onDrop` never
/// hears of one), and an iPhone list row doesn't drag with `.draggable`
/// at all. On macOS the drag space does it (rows into other groups too,
/// picked tasks together).
struct TaskListDropRows<Row: View>: View {
    let section: TaskSection
    var sorting = false
    @ViewBuilder let row: (TodoTask) -> Row
    #if os(iOS)
    @Environment(AppModel.self) private var model
    #endif

    var body: some View {
        #if os(iOS)
        // Only while sorting: with `onMove` on, the list also lifts a row
        // on a long press anywhere, and that and the menu fight over it.
        let group = sorting ? sortableGroup(section) : nil
        ForEach(section.tasks) { row($0) }
            .onMove(perform: group.map { g in { from, to in move(from, to: to, in: g) } })
        #else
        ForEach(section.tasks) { row($0) }
        #endif
    }

    #if os(iOS)
    /// `to` counts the rows as they are, the moved one still in its place
    /// (as `GroupDrop.plan` does).
    private func move(_ from: IndexSet, to: Int, in group: GroupDrop) {
        guard let i = from.first, section.tasks.indices.contains(i),
              let plan = group.plan(DraggedTasks(section.tasks[i]), at: to) else { return }
        model.run { await model.dropTasks(plan) }
    }
    #endif
}

/// The group `section` is, when its rows can be put in order by hand.
func sortableGroup(_ section: TaskSection) -> GroupDrop? {
    guard !section.finished, let group = GroupDrop(section), group.ordered else { return nil }
    return group
}

#if os(iOS)
extension View {
    /// A row's long-press menu, and in a group in manual order its right
    /// end: a long press there turns 排序 on (`start`) instead. It goes on
    /// before the row's tap (a tap on the right end still opens the task).
    /// While sorting (`sorting`) there's neither: rows move by their handles.
    func taskRowMenu(_ task: TodoTask, in section: TaskSection, sorting: Bool, sorts: Bool,
                     start: @escaping () -> Void) -> some View {
        modifier(TaskRowMenu(task: task, sorting: sorting,
                             grip: !sorting && sorts && task.trashedAt == nil && sortableGroup(section) != nil,
                             start: start))
    }
}

private struct TaskRowMenu: ViewModifier {
    @Environment(\.uiScale) private var s
    let task: TodoTask
    let sorting: Bool
    let grip: Bool
    let start: () -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if !sorting { TaskMenu(task: task) }
            }
            .overlay(alignment: .trailing) {
                if grip {
                    LongPressArea(duration: 0.4, action: start)
                        .frame(width: 64 * s)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityActions {
                if grip { Button("排序", action: start) }
            }
    }
}

/// A long press here: `action`, and not the row's menu. The list shows a
/// row's menu for a long press anywhere on the row, so a SwiftUI gesture
/// on top got both (and a menu emptied while the finger was down still
/// came at times). UIKit's lets the others wait: every other press waits
/// for this one to fail (a tap here still opens the task, once the finger
/// lifts); scrolling doesn't.
private struct LongPressArea: UIViewRepresentable {
    var duration: TimeInterval
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.action = action
        for case let press as UILongPressGestureRecognizer in view.gestureRecognizers ?? [] {
            press.minimumPressDuration = duration
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void = {}

        @objc func pressed(_ press: UILongPressGestureRecognizer) {
            if press.state == .began { action() }
        }

        func gestureRecognizer(_ press: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            !(other is UIPanGestureRecognizer)
        }
    }
}
#endif

/// Whether list rows are dragged with `.draggable` (and the drag space):
/// on macOS; on iOS the system list does it (`TaskListDropRows`).
#if os(iOS)
private let rowsDragThemselves = false
#else
private let rowsDragThemselves = true
#endif

private struct OptionalDropSlot: ViewModifier {
    let id: String
    let kind: DropSlotKind?

    func body(content: Content) -> some View {
        if let kind { content.dropSlot(id, kind) } else { content }
    }
}

/// The dragged copy of a list row.
private struct DragRowPreview: View {
    @Environment(\.uiScale) private var s
    let task: TodoTask
    let now: LocalDateTime
    let list: TaskList?
    let checklist: (done: Int, total: Int)

    var body: some View {
        TaskRow(task, now: now, list: list, showList: false, checklist: checklist) {}
            .padding(.horizontal, 12 * s)
            .padding(.vertical, 6 * s)
            .frame(width: 320 * s, alignment: .leading)
            .background(BoardStyle.cardFill, in: .rect(cornerRadius: 10 * s))
    }
}
