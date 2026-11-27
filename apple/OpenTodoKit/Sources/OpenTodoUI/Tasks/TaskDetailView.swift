// A task's details (task_detail.dart): the right column on macOS and iPad,
// a pushed screen on iPhone. A grouped form like the system apps' info
// screens: title, tags and notes; when (the date row opens the date
// dialog); where and how (list, priority, pinned); the checklist. A task in
// the trash is read-only and offers 恢复 / 永久删除.
//
// Title and notes save 0.4 s after typing stops and when the field is
// left, as in the Flutter version; while a field has focus, changes from
// elsewhere don't overwrite it.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    var taskId: String

    var body: some View {
        if let task = model.task(taskId) {
            TaskDetailForm(task: task)
                .id(task.id)
        } else {
            EmptyState.noTaskSelected
        }
    }
}

/// Where a task's detail keeps its 更多 menu when it is a pane beside
/// something else (the Mac's list, board, timeline and calendar) instead of
/// a screen of its own: in its title row, with a close button if the pane
/// can be put away. The window's toolbar and title stay the other side's.
struct TaskDetailChrome {
    var onClose: (@MainActor () -> Void)?
}

extension EnvironmentValues {
    /// Nil: the detail is its own screen (更多 in the toolbar, the list's
    /// name as the title).
    @Entry var taskDetailChrome: TaskDetailChrome? = nil
}

private struct TaskDetailForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.taskDetailChrome) private var chrome
    var task: TodoTask

    @State private var title = ""
    @State private var notes = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var editingSchedule = false
    @FocusState private var focus: Field?
    @Environment(\.uiScale) private var s

    private enum Field: Hashable { case title, notes }

    private var finished: Bool { task.status != .open }
    private var trashed: Bool { task.trashedAt != nil }

    var body: some View {
        Form {
            if trashed { trashSection }
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10 * s) {
                    Text(verbatim: "我").uiFont(.title3, weight: .semibold).hidden()
                        .frame(width: PriorityCheckbox.defaultSize * s)
                        .overlay {
                            PriorityCheckbox(checked: finished, priority: task.priority, action: trashed ? nil : {
                                model.run { await model.setDone(task, !finished) }
                            })
                        }
                    TextField("标题", text: $title, prompt: Text("准备做什么？"), axis: .vertical)
                        .uiFont(.title3, weight: .semibold)
                        .focused($focus, equals: .title)
                        .onSubmit(save)
                        .foregroundStyle(finished ? .secondary : .primary)
                        .strikethrough(finished, color: .secondary)
                        .labelsHidden()
                        // The hidden label doesn't reach VoiceOver (nor UI tests).
                        .accessibilityLabel("标题")
                        .disabled(trashed)
                    if let chrome { paneButtons(chrome) }
                }
                if !task.tags.isEmpty || !trashed { tagsRow }
                TextField("描述", text: $notes, prompt: Text("描述"), axis: .vertical)
                    .lineLimit(3...20)
                    .focused($focus, equals: .notes)
                    .labelsHidden()
                    .accessibilityLabel("描述")
                    .disabled(trashed)
            }

            Section { scheduleRows }

            Section {
                Picker(selection: Binding(get: { task.listId }, set: { id in
                    model.run { try await model.repo.moveToList(task.id, id) }
                })) {
                    Text("📥 收集箱").tag(inboxListId)
                    ForEach(model.lists) { l in
                        Text("\(l.emoji ?? "📋") \(l.name)").tag(l.id)
                    }
                } label: {
                    Label("清单", systemImage: "folder")
                }
                Picker(selection: Binding(get: { task.priority }, set: { p in
                    model.run { try await model.repo.setPriority(task.id, p) }
                })) {
                    ForEach(Priority.allCases.reversed(), id: \.self) { p in
                        Text(priorityName(p)).tag(p)
                    }
                } label: {
                    Label {
                        Text("优先级")
                    } icon: {
                        Image(systemName: task.priority == .none ? "flag" : "flag.fill")
                            .foregroundStyle(Palette.priority(task.priority))
                    }
                }
                if !finished {
                    Toggle(isOn: Binding(get: { task.pinnedAt != nil }, set: { pinned in
                        model.run { try await model.repo.setPinned(task.id, pinned) }
                    })) {
                        Label("置顶", systemImage: "pin")
                    }
                }
            }
            .disabled(trashed)

            ChecklistSection(taskId: task.id, readOnly: trashed)

            Section {
            } footer: {
                Text("创建于 \(stamp(task.createdAt))" + (finished ? " · 完成于 \(stamp(task.completedAt ?? task.updatedAt))" : ""))
                    .uiFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            title = task.title
            notes = task.content
        }
        // Take changes made elsewhere unless the person is typing there.
        .onChange(of: task.title) { _, new in if focus != .title { title = new } }
        .onChange(of: task.content) { _, new in if focus != .notes { notes = new } }
        .onChange(of: title) { scheduleSave() }
        .onChange(of: notes) { scheduleSave() }
        .onChange(of: focus) { save() }
        .onDisappear(perform: save)
        .modifier(ScreenChrome(task: task, enabled: chrome == nil))
    }

    // MARK: Parts

    /// 更多 and 关闭 at the end of the title row (`TaskDetailChrome`).
    private func paneButtons(_ chrome: TaskDetailChrome) -> some View {
        HStack(spacing: 10 * s) {
            Menu {
                TaskMenu(task: task)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20 * s, height: 20 * s)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
            .accessibilityLabel("更多")
            if let close = chrome.onClose {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .frame(width: 20 * s, height: 20 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("关闭详情")
                .accessibilityLabel("关闭详情")
            }
        }
        .foregroundStyle(.secondary)
    }

    private var trashSection: some View {
        Section {
            Label("这个任务在垃圾桶里", systemImage: "trash")
                .foregroundStyle(.secondary)
            HStack {
                Button("恢复", systemImage: "arrow.uturn.backward") { model.run { await model.restore(task) } }
                Spacer()
                Button("永久删除", systemImage: "trash.slash", role: .destructive) { model.run { await model.purge(task) } }
            }
            .buttonStyle(.borderless)
        }
    }

    private var tagsRow: some View {
        HStack(spacing: 6 * s) {
            ForEach(task.tags, id: \.self) { tag in
                Button {
                    model.run { await model.toggleTag(task, tag) }
                } label: {
                    HStack(spacing: 3 * s) {
                        Text(tag)
                        if !trashed { Image(systemName: "xmark").uiFont(.caption2, weight: .bold) }
                    }
                    .uiFont(.callout)
                    .padding(.horizontal, 8 * s)
                    .padding(.vertical, 2 * s)
                    .background(.tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .disabled(trashed)
                .accessibilityLabel("标签 \(tag)")
                .accessibilityHint("轻点以移除")
            }
            if !trashed {
                Button {
                    model.askNewTag(task)
                } label: {
                    Label(task.tags.isEmpty ? "添加标签" : "添加", systemImage: "number")
                        .uiFont(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var scheduleRows: some View {
        let overdue = isOverdue(task, model.now)
        Button {
            editingSchedule = true
        } label: {
            LabeledContent {
                if let due = task.dueDate {
                    HStack(spacing: 4 * s) {
                        Text(fullDueLabel(due, task.dueTime, today: model.today, duration: task.duration))
                        if !task.reminders.isEmpty { Image(systemName: "bell").accessibilityLabel("有提醒") }
                        if task.repeatRule != nil { Image(systemName: "repeat").accessibilityLabel("重复") }
                    }
                    .foregroundStyle(overdue ? AnyShapeStyle(Palette.overdue) : AnyShapeStyle(.tint))
                } else {
                    Text("设置日期").foregroundStyle(.secondary)
                }
            } label: {
                Label("日期", systemImage: "calendar")
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(trashed)
        .scheduleEditor(isPresented: $editingSchedule, schedule: ScheduleDraft(task: task),
                        defaults: model.settings.settings.defaults,
                        notificationsAllowed: model.notificationsAllowed,
                        openNotificationSettings: model.openNotificationSettings) { draft in
            model.run { await model.setSchedule(task.id, draft) }
        }
        if let due = task.dueDate, let rule = RepeatRule.tryParse(task.repeatRule) {
            LabeledContent {
                Text(describeRepeat(rule, due, repeatFrom: task.repeatFrom)).foregroundStyle(.secondary)
            } label: {
                Label("重复", systemImage: "repeat")
            }
        }
        if task.dueDate != nil, !task.reminders.isEmpty {
            LabeledContent {
                Text(remindersSummary(task.reminders, allDay: task.dueTime == nil)).foregroundStyle(.secondary)
            } label: {
                Label("提醒", systemImage: "bell")
            }
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        saveTask?.cancel()
        saveTask = nil
        let id = task.id, repo = model.repo
        if title != task.title {
            let t = title
            model.run { try await repo.setTitle(id, t) }
        }
        if notes != task.content {
            let n = notes
            model.run { try await repo.setContent(id, n) }
        }
    }

    private func stamp(_ ms: Int) -> String {
        let t = LocalDateTime(Date(timeIntervalSince1970: Double(ms) / 1000), in: model.timeZone)
        return "\(dateLabel(t.day, today: model.today)) \(timeLabel(t.minuteOfDay))"
    }
}

/// 子任务: tick, rename (on return or leaving the field), delete, drag to
/// reorder, add.
private struct ChecklistSection: View {
    @Environment(AppModel.self) private var model
    var taskId: String
    var readOnly: Bool

    @State private var newItem = ""
    @FocusState private var adding: Bool
    @Environment(\.uiScale) private var s

    var body: some View {
        let items = model.checklist(of: taskId)
        Section {
            ForEach(items) { item in
                ChecklistRow(item: item, readOnly: readOnly)
            }
            .onMove(perform: readOnly ? nil : { from, to in
                guard let i = from.first else { return }
                let item = items[i]
                model.run { await model.moveChecklistItem(item, to: to) }
            })
            .onDelete(perform: readOnly ? nil : { offsets in
                for i in offsets {
                    let id = items[i].id
                    model.run { try await model.repo.deleteChecklistItem(id) }
                }
            })
            if !readOnly {
                HStack(spacing: 8 * s) {
                    Image(systemName: "plus")
                        .foregroundStyle(.tint)
                        .frame(width: PriorityCheckbox.defaultSize * s)
                    TextField("添加子任务", text: $newItem)
                        .focused($adding)
                        .labelsHidden()
                        .onSubmit(add)
                }
            }
        } header: {
            Group {
                if !items.isEmpty {
                    Text("子任务 \(items.count(where: \.done))/\(items.count)")
                } else {
                    Text("子任务")
                }
            }
            .uiDefaultFont(.headline)
        }
    }

    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = taskId
        model.run { _ = try await model.repo.addChecklistItem(id, text) }
        newItem = ""
        adding = true
    }
}

private struct ChecklistRow: View {
    @Environment(AppModel.self) private var model
    var item: ChecklistItem
    var readOnly: Bool

    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var hovering = false
    @Environment(\.uiScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            PriorityCheckbox(checked: item.done, priority: .none, size: PriorityCheckbox.defaultSize - 2,
                             action: readOnly ? nil : {
                                 model.run { try await model.repo.updateChecklistItem(item.id, done: !item.done) }
                             })
                .frame(width: PriorityCheckbox.defaultSize * s)
            TextField("子任务", text: $text)
                .labelsHidden()
                .focused($focused)
                .foregroundStyle(item.done ? .secondary : .primary)
                .strikethrough(item.done, color: .secondary)
                .disabled(readOnly)
                .onSubmit(rename)
            #if os(macOS)
            if !readOnly {
                Button("删除子任务", systemImage: "xmark") {
                    model.run { try await model.repo.deleteChecklistItem(item.id) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering || focused ? 1 : 0)
                .help("删除子任务")
            }
            #endif
        }
        .onHover { hovering = $0 }
        .onAppear { text = item.title }
        .onChange(of: item.title) { _, new in if !focused { text = new } }
        .onChange(of: focused) { _, now in if !now { rename() } }
        .contextMenu {
            if !readOnly {
                Button("删除子任务", systemImage: "trash", role: .destructive) {
                    model.run { try await model.repo.deleteChecklistItem(item.id) }
                }
            }
        }
    }

    private func rename() {
        guard text != item.title else { return }
        let t = text, id = item.id
        model.run { try await model.repo.updateChecklistItem(id, title: t) }
    }
}

/// The detail as a screen of its own: the list's name as the title, 更多 in
/// the toolbar.
private struct ScreenChrome: ViewModifier {
    @Environment(AppModel.self) private var model
    var task: TodoTask
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationTitle(listName(task.listId, model.listsById))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem {
                        Menu {
                            TaskMenu(task: task)
                        } label: {
                            Label("更多", systemImage: "ellipsis")
                        }
                        .help("更多")
                    }
                }
        } else {
            content
        }
    }
}
