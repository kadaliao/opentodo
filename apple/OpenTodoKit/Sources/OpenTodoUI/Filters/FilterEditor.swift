// Adding and editing a saved filter: a form in a sheet (a panel on macOS,
// a page sheet with its own navigation bar on iOS). 普通 has a row per
// field; 高级 has as many conditions as wanted, each 包含 or 不包含, joined
// by 全部 or 任一. When 高级 holds something 普通 can't show, 普通 is greyed
// out. A deleted list still ticked shows as 已删除的清单, a condition from a
// newer version as a line saying so (it can be removed, not edited).
//
//     .sheet(item: $editing) { request in
//         FilterEditor(
//             filter: request.filter,                 // nil to add one
//             lists: lists, tags: tags, tasks: tasks, now: .now(),
//             onSave: { result in
//                 // result.name, result.rule.encode()
//                 // new: repo.addFilter(…) and select .filter(id); else repo.updateFilter(…)
//             },
//             onCancel: {}
//         )
//     }
//
// The sheet dismisses itself after either callback. Deleting is
// `filterDeleteConfirmation` below.

import OpenTodoDomain
import SwiftUI

public struct FilterEditor: View {
    @Environment(\.uiScale) private var s
    let lists: [TaskList]
    let tags: [String]
    let tasks: [TodoTask]
    let now: LocalDateTime
    let onSave: (FilterEditorResult) -> Void
    let onCancel: () -> Void
    /// Replaces 添加过滤器 / 编辑过滤器 (the matrix edits a quadrant with it).
    var title: String? = nil

    @State private var model: FilterEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    /// `lists` are the person's lists in sidebar order, `tags` every tag in
    /// use, `tasks` all tasks (for the count of what matches now).
    public init(
        filter: TaskFilter?,
        lists: [TaskList],
        tags: [String],
        tasks: [TodoTask],
        now: LocalDateTime,
        onSave: @escaping (FilterEditorResult) -> Void,
        onCancel: @escaping () -> Void = {},
        title: String? = nil
    ) {
        self.init(model: FilterEditorModel(filter: filter), lists: lists, tags: tags, tasks: tasks, now: now, onSave: onSave, onCancel: onCancel)
        self.title = title
    }

    init(
        model: FilterEditorModel,
        lists: [TaskList],
        tags: [String],
        tasks: [TodoTask],
        now: LocalDateTime,
        onSave: @escaping (FilterEditorResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.lists = lists
        self.tags = tags
        self.tasks = tasks
        self.now = now
        self.onSave = onSave
        self.onCancel = onCancel
        _model = State(initialValue: model)
    }

    /// The count goes under the form on iOS, beside the buttons on macOS.
    private var footer: String? {
        #if os(iOS)
        FilterEditorModel.countText(model.matchingCount(tasks, now: now))
        #else
        nil
        #endif
    }

    private var context: FilterPickerContext { FilterPickerContext(lists: lists, tags: tags, today: now.day) }

    public var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            form
            Divider()
            HStack {
                Text(FilterEditorModel.countText(model.matchingCount(tasks, now: now)))
                    .uiFont(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel) { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
            .padding(16 * s)
        }
        .frame(width: 540 * s)
        .frame(minHeight: 420 * s, idealHeight: 520 * s)
        .onAppear { nameFocused = model.filterId == nil }
        #else
        NavigationStack {
            form
                .navigationTitle(title ?? model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", role: .cancel) { cancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存", role: .confirm) { save() }
                            .disabled(!model.canSave)
                    }
                }
        }
        .onAppear { nameFocused = model.filterId == nil }
        #endif
    }

    private var form: some View {
        Form {
            Section {
                FilterModePicker(model: $model)
                TextField("名称", text: $model.name, prompt: Text("过滤器名称"))
                    .focused($nameFocused)
                    .onSubmit(save)
            } header: {
                #if os(macOS)
                Text(title ?? model.title).uiFont(.headline).foregroundStyle(.primary)
                #endif
            }
            FilterRuleSections(model: $model, context: context, footer: footer)
        }
        .formStyle(.grouped)
    }

    // MARK: Actions

    private func save() {
        guard let result = model.result() else { return }
        onSave(result)
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}

extension View {
    /// Asks before deleting `filter` (set it to ask; it goes back to nil
    /// when answered). `onDelete` gets the filter to delete; afterwards
    /// show `viewAfterDeletingFilter(id, selected:)`.
    public func filterDeleteConfirmation(_ filter: Binding<TaskFilter?>, onDelete: @escaping (TaskFilter) -> Void) -> some View {
        alert(
            "删除过滤器“\(filter.wrappedValue?.name ?? "")”？",
            isPresented: Binding(get: { filter.wrappedValue != nil }, set: { if !$0 { filter.wrappedValue = nil } }),
            presenting: filter.wrappedValue
        ) { f in
            Button("删除", role: .destructive) { onDelete(f) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("只删除过滤器，里面的任务不受影响。")
        }
    }
}
