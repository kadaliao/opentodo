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
    /// iOS: 子任务 are being put in order (each shows its ≡, `ChecklistStack`).
    @State private var sortingChecklist = false
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
                        listMenuLabel(l).tag(l.id)
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

            ChecklistSection(taskId: task.id, readOnly: trashed, sorting: $sortingChecklist)

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

/// 子任务: tick, rename (on return or leaving the field), delete, add, and
/// put in order by a handle (≡) that moves the subtask straight up or down
/// only (`ChecklistStack`; the system list's `onMove` let it drift
/// sideways). On macOS the subtasks are always that stack, the handle
/// showing while the pointer is over a row; on iOS 排序 by the section's
/// title (or in a row's long-press menu) turns them into it, with every
/// handle showing, and 完成 back into rows that swipe to delete.
private struct ChecklistSection: View {
    @Environment(AppModel.self) private var model
    var taskId: String
    var readOnly: Bool
    @Binding var sorting: Bool

    @State private var newItem = ""
    @FocusState private var adding: Bool
    @Environment(\.uiScale) private var s

    var body: some View {
        let items = model.checklist(of: taskId)
        let sortable = !readOnly && items.count > 1
        Section {
            #if os(macOS)
            if !items.isEmpty {
                ChecklistStack(items: items, readOnly: readOnly, sortable: sortable, sorting: false)
            }
            #else
            if sorting {
                ChecklistStack(items: items, readOnly: readOnly, sortable: sortable, sorting: true)
            } else {
                ForEach(items) { item in
                    ChecklistRow(item: item, among: items, readOnly: readOnly, sorting: false,
                                 sortable: sortable, startSorting: { sorting = true })
                }
                .onDelete(perform: readOnly ? nil : { offsets in
                for i in offsets {
                    let id = items[i].id
                    model.run { try await model.repo.deleteChecklistItem(id) }
                }
                })
            }
            #endif
            if !readOnly && !sorting {
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
            HStack {
                if !items.isEmpty {
                    Text("子任务 \(items.count(where: \.done))/\(items.count)")
                } else {
                    Text("子任务")
                }
                #if os(iOS)
                Spacer()
                if sortable || sorting {
                    Button(sorting ? "完成" : "排序") { sorting.toggle() }
                        .buttonStyle(.borderless)
                        .uiFont(.subheadline, weight: sorting ? .semibold : .regular)
                        .textCase(nil)
                }
                #endif
            }
            .uiDefaultFont(.headline)
        }
        .onChange(of: sortable) { _, can in if !can { sorting = false } }
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

/// The subtasks one under another, put in order by dragging a handle:
/// the subtask follows the pointer up and down only (kept within the
/// stack), the ones it passes slide out of its way, and where it's let go
/// is written. Until the database says so, the stack keeps showing the new
/// order (`pending`), so nothing jumps back for a moment.
private struct ChecklistStack: View {
    @Environment(AppModel.self) private var model
    @Environment(\.uiScale) private var s
    let items: [ChecklistItem]
    let readOnly: Bool
    let sortable: Bool
    /// iOS 排序: every handle shows, the rows don't edit.
    let sorting: Bool

    @State private var heights: [String: CGFloat] = [:]
    @State private var dragging: String?
    @State private var dy: CGFloat = 0
    @State private var pending: [String]?

    var body: some View {
        let shown = ordered
        let drag = dragState(shown)
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                let lifted = item.id == dragging
                VStack(spacing: 0) {
                    if i > 0 {
                        Divider().padding(.leading, (PriorityCheckbox.defaultSize + 8) * s)
                            .opacity(lifted || drag.map { $0.shifts(i) != 0 } == true ? 0 : 1)
                    }
                    ChecklistRow(item: item, among: shown, readOnly: readOnly, sorting: sorting,
                                 sortable: sortable, startSorting: {}) {
                        handle(item, shown)
                    }
                    .padding(.vertical, 5 * s)
                }
                .background {
                    if lifted {
                        RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                            .padding(.horizontal, -6 * s)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[item.id] = $0 }
                .offset(y: lifted ? dy : CGFloat(drag?.shifts(i) ?? 0))
                .zIndex(lifted ? 1 : 0)
                .animation(lifted ? nil : .snappy(duration: 0.18), value: drag?.position)
            }
        }
        .onChange(of: items.map(\.id)) { pending = nil }
    }

    /// The subtasks in the order to show: the one just dropped already in
    /// its new place.
    private var ordered: [ChecklistItem] {
        guard let pending else { return items }
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let known = pending.compactMap { byId[$0] }
        return known.count == items.count ? known : items
    }

    private func dragState(_ shown: [ChecklistItem]) -> ChecklistDrag? {
        guard let dragging, let from = shown.firstIndex(where: { $0.id == dragging }) else { return nil }
        return ChecklistDrag(from: from, dy: dy, heights: shown.map { heights[$0.id] ?? 0 })
    }

    private func handle(_ item: ChecklistItem, _ shown: [ChecklistItem]) -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            #if os(macOS)
            .frame(width: 18 * s, height: 18 * s)
            #else
            .foregroundStyle(.secondary)
            .frame(width: 44 * s, height: 36 * s)
            #endif
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragging == nil { dragging = item.id }
                        guard let from = shown.firstIndex(where: { $0.id == item.id }) else { return }
                        dy = ChecklistDrag.clamp(value.translation.height, from: from,
                                                 heights: shown.map { heights[$0.id] ?? 0 })
                    }
                    .onEnded { _ in drop(item, shown) }
            )
            .help("拖动排序")
            .accessibilityLabel("拖动排序")
    }

    private func drop(_ item: ChecklistItem, _ shown: [ChecklistItem]) {
        defer {
            dragging = nil
            dy = 0
        }
        guard let state = dragState(shown), let index = state.moveIndex else { return }
        var ids = shown.map(\.id)
        ids.move(fromOffsets: [state.from], toOffset: index)
        pending = ids
        model.run { await model.moveChecklistItem(item, to: index) }
    }
}

/// A subtask being dragged in a stack of rows `heights` tall (in order):
/// the one at `from`, `dy` points from its place.
struct ChecklistDrag: Equatable {
    var from: Int
    var dy: CGFloat
    var heights: [CGFloat]

    private func top(_ i: Int) -> CGFloat { heights[..<i].reduce(0, +) }
    private func center(_ i: Int) -> CGFloat { top(i) + heights[i] / 2 }

    /// The place it would take if let go now: past every row whose middle
    /// its middle has gone by.
    var position: Int {
        guard heights.indices.contains(from) else { return from }
        let mid = center(from) + dy
        var p = from
        if dy > 0 {
            for j in (from + 1)..<heights.count where mid > center(j) { p = j }
        } else if dy < 0 {
            for j in (0..<from).reversed() where mid < center(j) { p = j }
        }
        return p
    }

    /// How far the row at `i` moves to make room.
    func shifts(_ i: Int) -> CGFloat {
        guard heights.indices.contains(from) else { return 0 }
        let p = position, h = heights[from]
        if from < i && i <= p { return -h }
        if p <= i && i < from { return h }
        return 0
    }

    /// The index `moveChecklistItem` / `Array.move(toOffset:)` take (counting
    /// it where it is now); nil when it stays.
    var moveIndex: Int? {
        let p = position
        return p == from ? nil : p > from ? p + 1 : p
    }

    /// `dy` kept about within the stack: at most half the row past the
    /// first row's top or the last row's bottom (enough to get past their
    /// middles and take their places).
    static func clamp(_ dy: CGFloat, from: Int, heights: [CGFloat]) -> CGFloat {
        guard heights.indices.contains(from) else { return 0 }
        let top = heights[..<from].reduce(0, +)
        let below = heights[(from + 1)...].reduce(0, +)
        let half = heights[from] / 2
        return min(max(dy, -top - half), below + half)
    }
}

private struct ChecklistRow<Handle: View>: View {
    @Environment(AppModel.self) private var model
    var item: ChecklistItem
    /// The task's subtasks in order (for 上移 / 下移).
    var among: [ChecklistItem]
    var readOnly: Bool
    var sorting: Bool
    var sortable: Bool
    var startSorting: () -> Void
    /// macOS: what the row drags by, at its end.
    @ViewBuilder var handle: () -> Handle

    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var hovering = false
    @Environment(\.uiScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            PriorityCheckbox(checked: item.done, priority: .none, size: PriorityCheckbox.defaultSize - 2,
                             action: readOnly || sorting ? nil : {
                                 model.run { try await model.repo.updateChecklistItem(item.id, done: !item.done) }
                             })
                .frame(width: PriorityCheckbox.defaultSize * s)
            TextField("子任务", text: $text)
                .labelsHidden()
                .focused($focused)
                .foregroundStyle(item.done ? .secondary : .primary)
                .strikethrough(item.done, color: .secondary)
                .disabled(readOnly || sorting)
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
            if sortable {
                #if os(macOS)
                handle().opacity(hovering ? 1 : 0)
                #else
                if sorting { handle() }
                #endif
            }
        }
        .contentShape(Rectangle())
        .accessibilityActions {
            if sortable && !sorting, let i = among.firstIndex(where: { $0.id == item.id }) {
                if i > 0 { Button("上移") { model.run { await model.moveChecklistItem(item, to: i - 1) } } }
                if i + 1 < among.count { Button("下移") { model.run { await model.moveChecklistItem(item, to: i + 2) } } }
            }
        }
        .onHover { hovering = $0 }
        .onAppear { text = item.title }
        .onChange(of: item.title) { _, new in if !focused { text = new } }
        .onChange(of: focused) { _, now in if !now { rename() } }
        .contextMenu {
            if !readOnly && !sorting {
                #if os(iOS)
                if sortable {
                    Button("排序", systemImage: "arrow.up.arrow.down", action: startSorting)
                }
                #endif
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

extension ChecklistRow where Handle == EmptyView {
    init(item: ChecklistItem, among: [ChecklistItem], readOnly: Bool, sorting: Bool, sortable: Bool,
         startSorting: @escaping () -> Void) {
        self.init(item: item, among: among, readOnly: readOnly, sorting: sorting, sortable: sortable,
                  startSorting: startSorting, handle: { EmptyView() })
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
