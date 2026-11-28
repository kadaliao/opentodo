// Writes that also show something: an undo, a note, a question first, or a
// change of what's on screen. Each is the Flutter version's handler of the
// same name (`task_actions.dart`, `sidebar.dart`, `section_actions.dart`,
// `quick_add_field.dart`). Plain writes with nothing to show go straight to
// `model.repo`.
//
// They run on the main actor and await the write, so tests can `await`
// them and then read `data` once the observation has caught up.

import Foundation
import OpenTodoData
import OpenTodoDomain

extension AppModel {
    /// Runs a write; a failure shows as a note rather than vanishing.
    public func attempt(_ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            notices.show("没有成功：\(error.localizedDescription)")
        }
    }

    /// `attempt` from a button: starts the write and returns.
    public func run(_ body: @escaping @MainActor () async throws -> Void) {
        Task { await attempt(body) }
    }

    // MARK: - Tasks

    /// Ticks a task off or back on. Finishing one occurrence of a repeating
    /// task says where it went, with an undo (`setTaskDone`).
    public func setDone(_ task: TodoTask, _ done: Bool) async {
        await attempt {
            guard let result = try await repo.setCompleted(task.id, done) else { return }
            let repo = self.repo
            notices.show("已完成，下次：\(dateLabel(result.next, today: today))", undoName: "完成") {
                try? await repo.undoRepeatCompletion(result)
            }
        }
    }

    /// Moves a task to the trash, with an undo.
    public func trash(_ task: TodoTask) async {
        await attempt {
            try await repo.trashTask(task.id)
            if selectedTaskId == task.id { closeTask() }
            let repo = self.repo
            notices.show("已删除“\(task.title.isEmpty ? "无标题" : task.title)”", undoName: "删除") {
                try? await repo.restoreTask(task.id)
            }
        }
    }

    public func restore(_ task: TodoTask) async {
        await attempt { try await repo.restoreTask(task.id) }
    }

    /// 永久删除, from the trash.
    public func purge(_ task: TodoTask) async {
        await attempt {
            try await repo.purgeTask(task.id)
            if selectedTaskId == task.id { closeTask() }
        }
    }

    /// 清空 the trash, after asking.
    public func askEmptyTrash() {
        present.confirm = ConfirmRequest(title: "清空垃圾桶？", message: "垃圾桶里的任务会被永久删除，无法恢复。",
                                         action: "清空", destructive: true) { [self] in
            run { try await self.repo.emptyTrash() }
        }
    }

    /// Moves a repeating task on to its next date without finishing it.
    public func skip(_ task: TodoTask) async {
        await attempt {
            let next = try await repo.skipOccurrence(task.id)
            notices.show(next.map { "已跳过，下次：\(dateLabel($0, today: today))" } ?? "已是最后一次，任务已放弃")
        }
    }

    /// The context menu's date shortcuts, keeping the task's time.
    public func setQuickDate(_ task: TodoTask, _ choice: DateShortcut) async {
        await attempt {
            switch choice {
            case .today: try await repo.setDue(task.id, today, task.dueTime)
            case .tomorrow: try await repo.setDue(task.id, today + 1, task.dueTime)
            case .nextWeek: try await repo.setDue(task.id, today.startOfWeek + 7, task.dueTime)
            case .none: try await repo.setDue(task.id, nil, nil)
            }
        }
    }

    /// Applies what the date dialog gave back.
    public func setSchedule(_ taskId: String, _ draft: ScheduleDraft) async {
        await attempt {
            try await repo.setSchedule(taskId, date: draft.dueDate, time: draft.dueTime, duration: draft.duration,
                                       reminders: draft.reminders, repeatRule: draft.repeatRuleText,
                                       repeatFrom: draft.repeatFrom)
        }
    }

    /// Adds `tag`, or takes it off if the task has it.
    public func toggleTag(_ task: TodoTask, _ tag: String) async {
        let tags = task.tags.contains(tag) ? task.tags.filter { $0 != tag } : task.tags + [tag]
        await attempt { try await repo.setTags(task.id, tags) }
    }

    /// Asks for a tag and adds it, offering the tags already in use that
    /// the task doesn't have. One typed like an existing tag but in other
    /// case (`opentodo` for OpenTodo) is taken as that tag.
    public func askNewTag(_ task: TodoTask) {
        let known = tags
        present.textPrompt = TextPromptRequest(title: "添加标签", placeholder: "标签名称",
                                               suggestions: known.filter { !task.tags.contains($0) }) { [self] text in
            let typed = text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let tag = known.first { $0.caseInsensitiveCompare(typed) == .orderedSame } ?? typed
            guard !tag.isEmpty, !task.tags.contains(tag) else { return }
            run { try await self.repo.setTags(task.id, task.tags + [tag]) }
        }
    }

    /// 创建副本: the same task with its notes and subtasks, open beside it.
    @discardableResult
    public func duplicate(_ task: TodoTask) async -> String? {
        var newId: String?
        await attempt {
            let id = try await repo.addTask(
                title: task.title, listId: task.listId, sectionId: task.sectionId, dueDate: task.dueDate,
                dueTime: task.dueTime, duration: task.duration, tags: task.tags, priority: task.priority,
                reminders: task.reminders, repeatRule: task.repeatRule, repeatFrom: task.repeatFrom)
            if !task.content.isEmpty { try await repo.setContent(id, task.content) }
            for item in checklist(of: task.id) {
                let itemId = try await repo.addChecklistItem(id, item.title)
                if item.done { try await repo.updateChecklistItem(itemId, done: true) }
            }
            newId = id
        }
        if let newId, width == .regular { selectedTaskId = newId }
        return newId
    }

    /// Closes the open task (on a phone, pops its page).
    public func closeTask() {
        selectedTaskId = nil
        if width == .compact, case .task = phonePath.last { phonePath.removeLast() }
    }

    // MARK: - Quick add

    /// Adds a task from the quick-add text (`QuickAddField._submit`): what
    /// the text says, else `target`'s values, else the current view's
    /// defaults; a dated task gets the default reminders. Without a target
    /// the new task opens, and a note says where it went if the view won't
    /// show it. Returns the new id, nil when there's no title.
    @discardableResult
    public func quickAdd(_ text: String, target: QuickAddTarget? = nil) async -> String? {
        let parsed = parseQuickAdd(text, now: now)
        guard !parsed.title.isEmpty else { return nil }
        let view = self.view
        let defaults = target.map {
            QuickAddDefaults(listId: $0.listId, date: $0.date, tags: $0.tags, priority: $0.priority)
        } ?? quickAddDefaults(view, today, filterRules)
        let dueDate = parsed.date ?? defaults.date
        let dueTime = parsed.time ?? (parsed.date == nil ? target?.time : nil)
        var tags = defaults.tags
        for t in parsed.tags where !tags.contains(t) { tags.append(t) }
        var id: String?
        await attempt {
            id = try await repo.addTask(
                title: parsed.title, listId: defaults.listId, sectionId: target?.sectionId,
                dueDate: dueDate, dueTime: dueTime, duration: parsed.time == nil ? nil : parsed.duration,
                tags: tags,
                priority: parsed.priority ?? defaults.priority ?? .none,
                // Out of the box, a task with a time gets a reminder at that time.
                reminders: dueDate == nil ? [] : settings.settings.defaults.remindersFor(allDay: dueTime == nil),
                repeatRule: parsed.repeat?.description)
        }
        guard let id, target == nil else { return id }
        // A task dated outside a date view, or one the filter doesn't take,
        // won't show up in it; say where it went.
        if case .filter(let filterId) = view {
            if let task = try? await repo.getTask(id), let rule = filterRules[filterId], !rule.matcher(now)(task) {
                notices.show("已添加到“\(listName(task.listId, listsById))”，不符合这个过滤器的条件")
            }
        } else if let dueDate, !dateViewShows(view, dueDate, today) {
            notices.show("已添加到\(dateLabel(dueDate, today: today))")
        }
        if width == .regular { selectedTaskId = id }
        return id
    }

    // MARK: - Lists

    /// Adds a list and shows it.
    public func addList(name: String, emoji: String?, color: Int? = nil) async {
        await attempt {
            let id = try await repo.addList(name, emoji: emoji, color: color)
            select(.list(id))
        }
    }

    public func askDeleteList(_ list: TaskList) {
        present.confirm = ConfirmRequest(title: "删除清单“\(list.name)”？", message: "清单里的任务会移到垃圾桶，可以从那里恢复。",
                                         action: "删除", destructive: true) { [self] in
            run {
                try await self.repo.deleteList(list.id)
                if self.view == .list(list.id) { self.select(.smart(.inbox)) }
            }
        }
    }

    /// Puts the list at `index` of the lists (counting it where it is now),
    /// as dragging it there does.
    public func moveList(_ id: String, to index: Int) async {
        let ids = lists.map(\.id)
        let byId = listsById
        let orders = planMove(ids, id, index) { byId[$0]?.sortOrder ?? 0 }
        await attempt {
            for (listId, order) in orders { try await repo.updateList(listId, sortOrder: order) }
        }
    }

    // MARK: - Filters

    /// Asks for the filter editor (`FilterEditorSheet`; saving is
    /// `saveFilter`, Filters/FilterActions.swift).
    public func editFilter(_ filter: TaskFilter? = nil) {
        present.filterEditor = FilterEditorRequest(filter: filter)
    }

    public func askDeleteFilter(_ filter: TaskFilter) {
        present.confirm = ConfirmRequest(title: "删除过滤器“\(filter.name)”？", message: "只删除过滤器，里面的任务不受影响。",
                                         action: "删除", destructive: true) { [self] in
            run {
                try await self.repo.deleteFilter(filter.id)
                if self.view == .filter(filter.id) { self.select(.smart(.today)) }
            }
        }
    }

    // MARK: - Sections (分组)

    /// Asks for a name and adds a section at the end of the list's, then
    /// groups the view by sections so the new one shows.
    public func askAddSection(_ listId: String) {
        present.textPrompt = TextPromptRequest(title: "添加分组", placeholder: "分组名称，比如“进行中”") { [self] name in
            let name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            run {
                _ = try await self.repo.addSection(listId, name)
                let view: ViewRef = listId == inboxListId ? .smart(.inbox) : .list(listId)
                if self.prefs(for: view).groupingIn(view) != .sections { self.settings.setGrouping(view, .sections) }
            }
        }
    }

    public func askRenameSection(_ section: ListSection) {
        present.textPrompt = TextPromptRequest(title: "重命名分组", placeholder: "名称", initial: section.name) { [self] name in
            let name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            run { try await self.repo.updateSection(section.id, name: name) }
        }
    }

    public func askDeleteSection(_ section: ListSection) {
        present.confirm = ConfirmRequest(title: "删除分组“\(section.name)”？", message: "分组里的任务会留在清单里，归到“未分组”。",
                                         action: "删除", destructive: true) { [self] in
            run { try await self.repo.deleteSection(section.id) }
        }
    }

    /// Moves a section `delta` places among its list's (`moveSection`).
    public func moveSection(_ section: ListSection, by delta: Int) async {
        let sections = sectionsByList[section.listId] ?? []
        guard let from = sections.firstIndex(where: { $0.id == section.id }) else { return }
        let to = from + delta
        guard to >= 0, to < sections.count else { return }
        let byId = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0) })
        let orders = planMove(sections.map(\.id), section.id, delta > 0 ? to + 1 : to) { byId[$0]!.sortOrder }
        await attempt {
            for (id, order) in orders { try await repo.updateSection(id, sortOrder: order) }
        }
    }

    /// Before a task of `view` is dragged by its handle in a view that
    /// isn't in 自定义 order: the view's open tasks keep the order shown
    /// (`ordersFollowing`), and the view sorts 自定义 from now on.
    public func sortByHand(_ view: ViewRef) async {
        guard prefs(for: view).sortIn(view) != .manual, sortsFor(view).contains(.manual) else { return }
        let shown = sections(for: view).filter { !$0.finished }.flatMap(\.tasks)
        let orders = ordersFollowing(shown)
        if !orders.isEmpty {
            await attempt { try await repo.dropInto(Array(orders.keys), .order, orders) }
        }
        settings.setSort(view, .manual)
    }

    // MARK: - Checklist

    /// Puts the subtask at `index` (counting it where it is now).
    public func moveChecklistItem(_ item: ChecklistItem, to index: Int) async {
        let items = checklist(of: item.taskId)
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let orders = planMove(items.map(\.id), item.id, index) { byId[$0]!.sortOrder }
        await attempt {
            for (id, order) in orders { try await repo.updateChecklistItem(id, sortOrder: order) }
        }
    }
}

/// The context menu's date shortcuts.
public enum DateShortcut: Sendable, Hashable {
    case today, tomorrow, nextWeek, none
}

/// Where a task typed into a quick-add field goes when the text doesn't
/// say — a board column's section, a calendar slot's day and time, a
/// timeline lane's tag — instead of the current view's defaults. With a
/// target the new task isn't opened.
public struct QuickAddTarget: Sendable, Hashable {
    public var listId: String
    /// The list's section (a board column).
    public var sectionId: String?
    public var date: Day?
    /// Used only with `date`, and only when the text names no date.
    public var time: Int?
    /// Tags it starts with, besides those typed.
    public var tags: [String]
    /// Unless one is typed.
    public var priority: Priority?

    public init(listId: String = inboxListId, sectionId: String? = nil, date: Day? = nil, time: Int? = nil,
                tags: [String] = [], priority: Priority? = nil) {
        self.listId = listId
        self.sectionId = sectionId
        self.date = date
        self.time = time
        self.tags = tags
        self.priority = priority
    }
}

// MARK: - Notifications

extension AppModel {
    /// Whether the system lets reminders through (nil until asked): the
    /// date dialog says 系统通知已关闭 · 去开启 when false.
    var notificationsAllowed: Bool? { services?.reminders.allowed }

    /// 去开启: the system's notification settings for the app.
    func openNotificationSettings() {
        Task { await services?.reminders.openSettings() }
    }
}
