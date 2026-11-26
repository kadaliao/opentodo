// The drag pieces in a plain grouped task list: how the task list hooks
// them up (debug route `board:list`). Each group (`buildSections`) gives
// its header a place at its top (`.taskArea(group, index: 0)`) and each row
// a place (`.taskRow(group, index:)`: top half before it, bottom half
// after); a list's own section headers can also be dragged and take other
// sections above or below them (`.section(_, among:, axis: .vertical)`).
// Groups that aren't in manual order light up as a whole.

import OpenTodoDomain
import SwiftUI

struct DragListDemo: View {
    @State private var store = BoardDemoStore()
    @State private var drag = DragController()
    @State private var grouping: TaskGrouping = .sections
    @State private var dialog: SectionDialog?

    private var sections: [TaskSection] {
        buildSections(
            view: .list(BoardDemoStore.listId),
            tasks: store.tasks,
            lists: [:],
            now: BoardDemoStore.now,
            sectionsByList: [BoardDemoStore.listId: store.sections],
            grouping: grouping,
            sort: store.sort
        )
    }

    var body: some View {
        let listSections = store.sections.sorted { $0.sortOrder < $1.sortOrder }
        let picked = store.tasks.filter { store.selection.picking && store.selection.picked.contains($0.id) }
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        group(section, listSections: listSections, picked: picked)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .dragAutoScroll("list", axis: .vertical)
            .dragSpace(drag)
            .navigationTitle("产品发布")
            .toolbar {
                ToolbarItem {
                    Picker("分组", selection: $grouping) {
                        Text("分组").tag(TaskGrouping.sections)
                        Text("时间").tag(TaskGrouping.date)
                        Text("优先级").tag(TaskGrouping.priority)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .sectionDialogs($dialog, perform: store.actions.section)
        .onAppear {
            drag.onDrop = { [store] outcome in
                switch outcome {
                case .tasks(let plan): store.apply(plan)
                case .sections(let orders): store.apply(.reorder(orders))
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ section: TaskSection, listSections: [ListSection], picked: [TodoTask]) -> some View {
        let drop = GroupDrop(section)
        if let title = section.title {
            header(section, title: title, drop: drop, listSections: listSections)
        }
        ForEach(Array(section.tasks.enumerated()), id: \.element.id) { i, task in
            row(task)
                .taskDragSource(task, picked: picked, isEnabled: !section.finished) {
                    row(task).frame(width: 320).background(BoardStyle.cardFill, in: .rect(cornerRadius: 10))
                }
                .opacity(drag.isDragged(task.id) ? 0.3 : 1)
                .modifier(OptionalSlot(id: "row-\(task.id)", kind: drop.map { .taskRow($0, index: i) }))
        }
    }

    private func header(_ section: TaskSection, title: String, drop: GroupDrop?, listSections: [ListSection]) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(section.alert ? .red : .primary)
            Text(section.tasks.count, format: .number).foregroundStyle(.secondary)
            Spacer()
            if let s = section.listSection {
                Menu {
                    SectionMenu(section: s, among: listSections, dialog: $dialog, perform: store.actions.section)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .background {
            if let target = drop?.target, drag.highlights(target) {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1))
            }
        }
        .modifier(OptionalSlot(id: "head-\(section.id)", kind: drop.map { .taskArea($0, index: 0) }))
        .modifier(HeaderSection(section: section.listSection, among: listSections, title: title))
    }

    private func row(_ task: TodoTask) -> some View {
        HStack(spacing: 10) {
            TaskCheckbox(done: task.status != .open, priority: task.priority) {
                store.setDone(task.id, task.status == .open)
            }
            Text(task.title).lineLimit(1)
            Spacer()
            if let due = task.dueDate {
                Text(dueLabel(due, task.dueTime, today: BoardDemoStore.now.day)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

private struct OptionalSlot: ViewModifier {
    let id: String
    let kind: DropSlotKind?

    func body(content: Content) -> some View {
        if let kind { content.dropSlot(id, kind) } else { content }
    }
}

/// A list section's header drags the section and takes another one above
/// or below it.
private struct HeaderSection: ViewModifier {
    let section: ListSection?
    let among: [ListSection]
    let title: String

    func body(content: Content) -> some View {
        if let section {
            content
                .dropSlot("section-\(section.id)", .section(section, among: among, axis: .vertical))
                .sectionDragSource(section) {
                    Text(title).font(.headline).padding(10).frame(width: 240, alignment: .leading)
                        .background(BoardStyle.cardFill, in: .rect(cornerRadius: 10))
                }
        } else {
            content
        }
    }
}
