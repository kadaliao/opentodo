// A view's tasks as a list, in its groups (`AppModel.sections(for:)`):
// headers fold, a list's own sections have a ⋯ menu (重命名, 上移, 下移,
// 删除分组), empty days of 今天 / 最近7天 show without a count. Rows select
// (wide) or push (phone) the task; the checkbox completes it; right-click /
// long-press and swipes have the everyday actions. On macOS and iPad the
// quick-add field heads the list; the trash ends with a note.
//
// The list's selection is `model.selection` (one task now; a set later,
// for multi-select).

import OpenTodoData
import OpenTodoDomain
import SwiftUI

struct TaskListView: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    var view: ViewRef

    var body: some View {
        let sections = model.sections(for: view)
        let compact = model.width == .compact
        let trash = view == .smart(.trash)
        List(selection: compact && !model.selection.isPicking ? nil : model.listSelection(in: view)) {
            if !compact && canQuickAdd(view) {
                QuickAddField(focusRequests: model.taskList.quickAddRequests)
                    .padding(.vertical, 6 * s)
                    .selectionDisabled()
            }
            if view == .smart(.today) { TodayCountdownsRow() }
            ForEach(sections) { section in
                if let title = section.title {
                    let folded = model.taskList.isFolded(section, in: view)
                    Section {
                        if !folded { rows(section) }
                    } header: {
                        header(section, title: title, folded: folded)
                    }
                } else {
                    Section { rows(section) }
                }
            }
            if trash && !sections.isEmpty {
                Text("垃圾桶里的任务可以恢复；清空后无法找回。")
                    .uiFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        #else
        .listStyle(.plain)
        #endif
        .taskListDragSpace(sections)
        .overlay {
            if model.loaded && sections.isEmpty {
                EmptyState.forView(view)
            }
        }
        .animation(.snappy, value: sections.map(\.id))
    }

    private func header(_ section: TaskSection, title: String, folded: Bool) -> some View {
        HStack(spacing: 4 * s) {
            GroupHeader(title,
                        // An empty day (there to drop onto) shows no 0.
                        count: section.day != nil && section.tasks.isEmpty ? nil : section.tasks.count,
                        alert: section.alert,
                        dimmed: section.day != nil && section.tasks.isEmpty,
                        collapsed: Binding(get: { folded }, set: { model.taskList.setFolded($0, section, in: view) }))
            if let listSection = section.listSection {
                GroupSectionMenu(section: listSection)
            }
        }
        .taskListDragHeader(section)
    }

    @ViewBuilder
    private func rows(_ section: TaskSection) -> some View {
        ForEach(section.tasks) { task in
            TaskRow(task, now: model.now, list: model.listsById[task.listId], showList: model.showsList(in: view),
                    checklist: model.checklistProgress(of: task.id)) {
                model.run { await model.setDone(task, task.status == .open) }
            }
            .tag(task.id)
            .modifier(OpenOnTap(compact: model.width == .compact && !model.selection.isPicking) {
                model.open(taskId: task.id)
            })
            .contextMenu { TaskMenu(task: task) }
            .modifier(TaskSwipeActions(task: task))
            .taskListDragRow(task, in: section)
        }
    }
}

/// A list section's ⋯: 重命名, 上移, 下移, 删除分组 (section_actions.dart).
private struct GroupSectionMenu: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    var section: ListSection

    var body: some View {
        let siblings = model.sectionsByList[section.listId] ?? []
        let index = siblings.firstIndex { $0.id == section.id } ?? -1
        Menu {
            Button("重命名", systemImage: "pencil") { model.askRenameSection(section) }
            if index > 0 {
                Button("上移", systemImage: "arrow.up") { model.run { await model.moveSection(section, by: -1) } }
            }
            if index >= 0 && index < siblings.count - 1 {
                Button("下移", systemImage: "arrow.down") { model.run { await model.moveSection(section, by: 1) } }
            }
            Divider()
            Button("删除分组", systemImage: "trash", role: .destructive) { model.askDeleteSection(section) }
        } label: {
            Image(systemName: "ellipsis")
                .uiFont(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24 * s, height: 20 * s)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("分组操作")
        .accessibilityLabel("分组操作")
    }
}

/// On a phone a tap on the row pushes the task (the list has no selection
/// there); elsewhere the list's selection does it.
private struct OpenOnTap: ViewModifier {
    var compact: Bool
    var open: () -> Void

    func body(content: Content) -> some View {
        if compact {
            content
                .onTapGesture(perform: open)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "打开", open)
        } else {
            content
        }
    }
}
