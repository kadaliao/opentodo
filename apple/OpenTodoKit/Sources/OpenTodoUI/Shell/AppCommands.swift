// macOS menu bar commands. They act on the focused window's `AppModel`
// (published with `.focusedSceneValue(\.appModel, …)` by the root view),
// and are disabled when there's no window or nothing to act on.
//
//     文件   新建任务 ⌘N · 新建清单 ⇧⌘N
//     编辑   搜索 ⌘F            (in place of the text Find menu; ⌘A and Esc
//                               are the list's own)
//     显示   one per module ⌘1–⌘6 · tasks: 列表 / 看板 / 时间线 ⌃⌘1–3,
//            显示已完成 ⇧⌘H · calendar: 日 / 3天 / 周 / 月 / 日程 ⌃⌘1–5, 年,
//            多周 · the sidebar commands
//     前往   今天 ⇧⌘1 · 明天 ⇧⌘2 · 最近7天 ⇧⌘3 · 收集箱 ⇧⌘4 · each list ·
//            已完成 · 垃圾桶 · calendar: 回到今天 ⌃⌘T, 上一页 ⌃⌘←, 下一页 ⌃⌘→
//
// Shortcuts that two modules share (⌃⌘1–3, ⌃⌘T) are only ever enabled in
// one module at a time. The calendar's own single keys (D W M A T ← →)
// work while it has focus and aren't menu items, so typing is never taken.
//     任务   完成 ⌘↩ · 日期 (今天 ⌃⌘T, 明天 ⌃⌘M, 下周一, 选择日期… ⌘D, 清除日期)
//            · 优先级 (高 ⌥⌘1, 中 ⌥⌘2, 低 ⌥⌘3, 无 ⌥⌘0) · 置顶 ⇧⌘P · 创建副本
//            · 跳过此次 · 删除 ⌘⌫
//     清单   编辑清单… · 添加分组… · 删除清单…   (the list on screen)
//
// 任务 acts on the open task (the calendar's, in the calendar), or on the
// picked ones (完成, 优先级, 删除) while several are picked.

#if os(macOS)
import AppKit
#endif
import OpenTodoDomain
import OpenTodoData
import SwiftUI

extension FocusedValues {
    @Entry var appModel: AppModel?
}

public struct AppCommands: Commands {
    @FocusedValue(\.appModel) private var model

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建任务") { model?.requestQuickAdd() }
                .keyboardShortcut("n")
                .disabled(model == nil)
            Button("新建清单…") {
                model?.switchTo(.tasks)
                model?.present.listEditor = ListEditorRequest()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(model == nil)
        }
        CommandGroup(replacing: .textEditing) {
            Button("搜索") { model?.requestSearch() }
                .keyboardShortcut("f")
                .disabled(model == nil)
        }
        CommandGroup(before: .sidebar) {
            ForEach(AppModule.allCases) { m in
                Button(m.title) { model?.switchTo(m) }
                    .keyboardShortcut(m.shortcut)
                    .disabled(model == nil)
            }
            Divider()
            layoutCommands
            calendarModeCommands
            Divider()
        }
        CommandMenu("前往") { goCommands }
        CommandMenu("任务") { taskCommands }
        CommandMenu("清单") { listCommands }
    }

    // MARK: 显示

    @ViewBuilder private var layoutCommands: some View {
        let view = model?.view
        let offered = view.map(layouts(for:)) ?? []
        let keys: [ListLayout: KeyEquivalent] = [.list: "1", .board: "2", .timeline: "3"]
        ForEach(ListLayout.allCases, id: \.self) { l in
            Button("显示为\(l.title)") {
                if let model, let view { model.settings.setLayout(view, l) }
            }
            .keyboardShortcut(keys[l]!, modifiers: [.command, .control])
            .disabled(model?.module != .tasks || !offered.contains(l))
        }
        Button(view.map { model?.taskList.showsDone($0) == true } == true ? "隐藏已完成" : "显示已完成") {
            if let model, let view { model.taskList.setShowsDone(!model.taskList.showsDone(view), view) }
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])
        .disabled(model?.module != .tasks || view.map { groupingsFor($0).isEmpty } != false)
    }

    @ViewBuilder private var calendarModeCommands: some View {
        let inCalendar = model?.module == .calendar
        let keys: [CalendarMode: KeyEquivalent] = [.day: "1", .threeDays: "2", .week: "3", .month: "4", .agenda: "5"]
        ForEach([CalendarMode.day, .threeDays, .week, .month, .agenda, .year, .multiWeek], id: \.self) { m in
            Button("日历：\(m.label)") { model?.calendar.perform(.mode(m), today: model?.today ?? .today()) }
                .modifier(OptionalShortcut(key: keys[m], modifiers: [.command, .control]))
                .disabled(!inCalendar)
        }
    }

    // MARK: 前往

    @ViewBuilder private var goCommands: some View {
        let smart: [(SmartKind, KeyEquivalent?)] = [(.today, "1"), (.tomorrow, "2"), (.next7, "3"), (.inbox, "4")]
        ForEach(smart, id: \.0) { kind, key in
            Button(kind.title) { go(.smart(kind)) }
                .keyboardShortcut(key!, modifiers: [.command, .shift])
                .disabled(model == nil)
        }
        if let lists = model?.lists, !lists.isEmpty {
            Divider()
            ForEach(lists) { l in
                Button("\(l.emoji ?? "📋") \(l.name)") { go(.list(l.id)) }
            }
        }
        Divider()
        Button(SmartKind.completed.title) { go(.smart(.completed)) }.disabled(model == nil)
        Button(SmartKind.trash.title) { go(.smart(.trash)) }.disabled(model == nil)
        Divider()
        let inCalendar = model?.module == .calendar
        Button("日历：回到今天") { model?.calendar.perform(.today, today: model?.today ?? .today()) }
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(!inCalendar)
        Button("日历：上一页") { model?.calendar.perform(.page(-1), today: model?.today ?? .today()) }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
            .disabled(!inCalendar)
        Button("日历：下一页") { model?.calendar.perform(.page(1), today: model?.today ?? .today()) }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
            .disabled(!inCalendar)
    }

    private func go(_ view: ViewRef) {
        model?.switchTo(.tasks)
        model?.select(view)
    }

    // MARK: 任务

    @ViewBuilder private var taskCommands: some View {
        let task = commandTask
        let picked = model?.batchSelection
        let usable = task != nil && task?.trashedAt == nil
        Button(picked != nil ? "完成所选任务" : (task?.status == .open || task == nil ? "完成" : "标记为未完成")) {
            guard let model else { return }
            if let picked { model.run { await model.performBatch(picked.complete) } }
            else if let task { model.run { await model.setDone(task, task.status == .open) } }
        }
        .keyboardShortcut(.return)
        .disabled(picked == nil && !usable)

        Menu("日期") {
            Button("今天") { quickDate(.today) }
                .keyboardShortcut("t", modifiers: [.command, .control])
                .disabled(model?.module == .calendar)
            Button("明天") { quickDate(.tomorrow) }.keyboardShortcut("m", modifiers: [.command, .control])
            Button("下周一") { quickDate(.nextWeek) }
            Button("选择日期…") {
                if let task { model?.present.schedule = ScheduleRequest(taskId: task.id) }
            }
            .keyboardShortcut("d")
            Button("清除日期") { quickDate(.none) }.disabled(task?.dueDate == nil)
        }
        .disabled(!usable || picked != nil)

        Menu("优先级") {
            let keys: [Priority: KeyEquivalent] = [.high: "1", .medium: "2", .low: "3", .none: "0"]
            ForEach(Priority.allCases.reversed(), id: \.self) { p in
                Button(priorityName(p)) {
                    guard let model else { return }
                    if let picked { model.run { await model.performBatch(picked.setPriority(p)) } }
                    else if let task { model.run { try await model.repo.setPriority(task.id, p) } }
                }
                .keyboardShortcut(keys[p]!, modifiers: [.command, .option])
            }
        }
        .disabled(picked == nil && !usable)

        Button(task?.pinnedAt == nil ? "置顶" : "取消置顶") {
            if let task, let model { model.run { try await model.repo.setPinned(task.id, task.pinnedAt == nil) } }
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(!usable || picked != nil || task?.status != .open)

        Button("跳过此次") {
            if let task, let model { model.run { await model.skip(task) } }
        }
        .disabled(!usable || picked != nil || task?.repeatRule == nil || task?.dueDate == nil || task?.status != .open)

        Button("创建副本") {
            if let task, let model { model.run { await model.duplicate(task) } }
        }
        .disabled(!usable || picked != nil)

        Divider()
        Button(picked != nil ? "删除所选任务" : "删除") {
            guard let model else { return }
            // The menu sees ⌘⌫ before a text field does: while typing (the
            // title, the notes, quick add) it is the field's 删到行首, not
            // a reason to throw the open task away.
            #if os(macOS)
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
                editor.deleteToBeginningOfLine(nil)
                return
            }
            #endif
            if let picked { model.run { await model.performBatch(picked.trash) } }
            else if let task { model.run { await model.trash(task) } }
        }
        .keyboardShortcut(.delete)
        .disabled(picked == nil && !usable)
    }

    /// The task the 任务 menu acts on: the open one — in the calendar, the
    /// calendar's.
    private var commandTask: TodoTask? {
        guard let model else { return nil }
        let id = model.module == .calendar ? model.calendar.openTaskId : model.selectedTaskId
        return id.flatMap(model.task)
    }

    private func quickDate(_ d: DateShortcut) {
        if let model, let task = commandTask { model.run { await model.setQuickDate(task, d) } }
    }

    // MARK: 清单

    @ViewBuilder private var listCommands: some View {
        let list: TaskList? = if case .list(let id)? = model?.view { model?.listsById[id] } else { nil }
        let arranged = model.flatMap { arrangedListId($0.view) }
        Button("编辑清单…") { if let list { model?.present.listEditor = ListEditorRequest(list: list) } }
            .disabled(list == nil || model?.module != .tasks)
        Button("添加分组…") { if let arranged { model?.askAddSection(arranged) } }
            .disabled(arranged == nil || model?.module != .tasks)
        Divider()
        Button("删除清单…") { if let list { model?.askDeleteList(list) } }
            .disabled(list == nil || model?.module != .tasks)
    }
}

/// A shortcut when there is one.
private struct OptionalShortcut: ViewModifier {
    var key: KeyEquivalent?
    var modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let key { content.keyboardShortcut(key, modifiers: modifiers) } else { content }
    }
}
