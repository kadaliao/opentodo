// A task's right-click (macOS) / long-press (iOS) menu and its swipe
// actions, as `showTaskMenu` in task_actions.dart: 完成, the date
// shortcuts (今天 / 明天 / 下周一 / 选择日期… / 清除日期 / 跳过此次), the
// priorities, 置顶, 移到清单, 标签, 创建副本, 删除. A trashed task offers
// 恢复 and 永久删除 only. The same menu is the detail's “更多”.

import OpenTodoDomain
import SwiftUI

struct TaskMenu: View {
    @Environment(AppModel.self) private var model
    var task: TodoTask

    var body: some View {
        if task.trashedAt != nil {
            Button("恢复", systemImage: "arrow.uturn.backward") { model.run { await model.restore(task) } }
            Button("永久删除", systemImage: "trash.slash", role: .destructive) { model.run { await model.purge(task) } }
        } else {
            let open = task.status == .open
            Button(open ? "完成" : "标记为未完成", systemImage: open ? "checkmark.circle" : "circle") {
                model.run { await model.setDone(task, open) }
            }
            StartFocusButton(task: task)
            Section {
                ControlGroup {
                    Button("今天", systemImage: "sun.max") { model.run { await model.setQuickDate(task, .today) } }
                    Button("明天", systemImage: "sunrise") { model.run { await model.setQuickDate(task, .tomorrow) } }
                    Button("下周一", systemImage: "calendar.badge.plus") { model.run { await model.setQuickDate(task, .nextWeek) } }
                }
                Button("选择日期…", systemImage: "calendar") { model.present.schedule = ScheduleRequest(taskId: task.id) }
                if task.dueDate != nil {
                    Button("清除日期", systemImage: "calendar.badge.minus") { model.run { await model.setQuickDate(task, .none) } }
                }
                if task.repeatRule != nil && task.dueDate != nil && open {
                    Button("跳过此次", systemImage: "forward.end") { model.run { await model.skip(task) } }
                }
            }
            Section {
                Menu("优先级", systemImage: "flag") {
                    Picker("优先级", selection: Binding(get: { task.priority }, set: { p in
                        model.run { try await model.repo.setPriority(task.id, p) }
                    })) {
                        ForEach(Priority.allCases.reversed(), id: \.self) { p in
                            Text(priorityName(p)).tag(p)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Menu("移到清单", systemImage: "folder") {
                    Picker("移到清单", selection: Binding(get: { task.listId }, set: { id in
                        model.run { try await model.repo.moveToList(task.id, id) }
                    })) {
                        Text("📥 收集箱").tag(inboxListId)
                        ForEach(model.lists) { l in
                            listMenuLabel(l).tag(l.id)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Menu("标签", systemImage: "number") {
                    ForEach(Array(Set(model.tags + task.tags)).sorted(), id: \.self) { tag in
                        Toggle(tag, isOn: Binding(get: { task.tags.contains(tag) }, set: { _ in
                            model.run { await model.toggleTag(task, tag) }
                        }))
                    }
                    Divider()
                    Button("新标签…", systemImage: "plus") { model.askNewTag(task) }
                }
                if open {
                    Button(task.pinnedAt == nil ? "置顶" : "取消置顶", systemImage: task.pinnedAt == nil ? "pin" : "pin.slash") {
                        model.run { try await model.repo.setPinned(task.id, task.pinnedAt == nil) }
                    }
                }
            }
            Section {
                Button("多选", systemImage: "checklist") { model.selection.start(task.id) }
                Button("创建副本", systemImage: "plus.square.on.square") { model.run { await model.duplicate(task) } }
                Button("删除", systemImage: "trash", role: .destructive) { model.run { await model.trash(task) } }
            }
        }
    }
}

/// iOS swipes: from the leading edge 完成 (or 恢复 in the trash); from the
/// trailing edge 删除 (永久删除), 置顶 and 明天.
struct TaskSwipeActions: ViewModifier {
    @Environment(AppModel.self) private var model
    var task: TodoTask

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .swipeActions(edge: .leading) {
                if task.trashedAt != nil {
                    Button("恢复", systemImage: "arrow.uturn.backward") { model.run { await model.restore(task) } }
                        .tint(Palette.accent)
                } else {
                    let open = task.status == .open
                    Button(open ? "完成" : "未完成", systemImage: open ? "checkmark" : "arrow.uturn.backward") {
                        model.run { await model.setDone(task, open) }
                    }
                    .tint(Palette.accent)
                }
            }
            .swipeActions(edge: .trailing) {
                if task.trashedAt != nil {
                    Button("永久删除", systemImage: "trash.slash", role: .destructive) { model.run { await model.purge(task) } }
                } else {
                    Button("删除", systemImage: "trash", role: .destructive) { model.run { await model.trash(task) } }
                    if task.status == .open {
                        Button(task.pinnedAt == nil ? "置顶" : "取消置顶", systemImage: task.pinnedAt == nil ? "pin" : "pin.slash") {
                            model.run { try await model.repo.setPinned(task.id, task.pinnedAt == nil) }
                        }
                        .tint(.orange)
                        Button("明天", systemImage: "sunrise") { model.run { await model.setQuickDate(task, .tomorrow) } }
                            .tint(.indigo)
                    }
                }
            }
        #else
        content
        #endif
    }
}
