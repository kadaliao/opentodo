// The timeline on demo data, for the debug routes `timeline:<state>`
// (DebugLaunch.swift) and previews. Edits change the tasks in memory the
// way TaskRepo would, so dragging can be tried by hand.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

public struct TimelineDemo: View {
    /// What the route opens.
    public enum Scene: String, CaseIterable, Sendable {
        /// A list with sections, by day (the 无日期 tray as the width has it).
        case day
        case week
        case month
        /// Lanes for the list's sections, with the 无日期 tray open.
        case tray
        /// 今天, in a lane per list.
        case today
        /// The inbox: no sections, so no lane headers.
        case inbox
        /// Two tasks picked (多选).
        case picked
        /// Finished tasks shown.
        case done
        /// Two picked tasks dragged together into 下周, two days on.
        case dragging
        /// The left edge of 出差上海 dragged two days earlier.
        case resizing
    }

    let scene: Scene
    let now: LocalDateTime
    @State private var tasks: [TodoTask]
    @State private var prefs: TimelinePrefs
    @State private var selection = TaskSelection()
    @State private var openTask: String?

    public init(scene: Scene, now: LocalDateTime = .now()) {
        self.scene = scene
        self.now = now
        let tasks = Self.tasks(today: now.day)
        _tasks = State(initialValue: tasks)
        var prefs = TimelinePrefs()
        switch scene {
        case .week: prefs.scale = .week
        case .month: prefs.scale = .month
        case .tray: prefs.trayOpen = true
        case .done: prefs.showDone = true
        default: break
        }
        _prefs = State(initialValue: prefs)
        if scene == .picked || scene == .dragging {
            _selection = State(initialValue: TaskSelection(["评审", "出差"], anchor: "出差"))
        }
    }

    private var view: ViewRef {
        switch scene {
        case .today: .smart(.today)
        case .inbox: .smart(.inbox)
        default: .list("w")
        }
    }

    static let lists = [
        "w": TaskList(id: "w", name: "工作", sortOrder: 1),
        "home": TaskList(id: "home", name: "生活", sortOrder: 2),
    ]

    static let sections = ["w": [
        ListSection(id: "s1", listId: "w", name: "本周", sortOrder: 1),
        ListSection(id: "s2", listId: "w", name: "下周", sortOrder: 2),
    ]]

    public var body: some View {
        let timeline = buildViewTimeline(
            view, tasks, now: now, lists: Self.lists, sectionsByList: Self.sections,
            grouping: scene == .today ? .list : nil, showDone: prefs.showDone
        )
        NavigationStack {
            TimelineView(
                timeline: timeline,
                view: view,
                now: now,
                selectedTaskId: openTask,
                prefs: $prefs,
                selection: selection,
                onTap: { id, modifiers, order in
                    if let open = tapTask(id, selection: &selection, order: order, current: openTask,
                                          modifiers: modifiers, touch: TimelineStyle.touch) {
                        openTask = open
                    }
                },
                onSetDone: { t, done in update(t.id) { $0.status = done ? .done : .open } },
                onEdit: apply,
                onNewTask: { day, target in
                    let n = laneNewTask(view, target, now.day)
                    tasks.append(TodoTask(
                        id: "new-\(tasks.count)", listId: n.listId, sectionId: n.sectionId, title: "新任务",
                        priority: n.priority ?? .none, dueDate: day, tags: n.tags, sortOrder: -Double(tasks.count)
                    ))
                }
            ) { task in
                Button("打开") { openTask = task.id }
                Button(task.status == .open ? "完成" : "标记为未完成") {
                    update(task.id) { $0.status = $0.status == .open ? .done : .open }
                }
                Button("多选") { selection.start(task.id) }
                Divider()
                Button("删除", role: .destructive) { tasks.removeAll { $0.id == task.id } }
            }
            .staged(staged)
            .navigationTitle(viewTitle(view, Self.lists))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var staged: TimelineStagedDrag? {
        switch scene {
        case .dragging: TimelineStagedDrag(taskId: "出差", kind: .move(toLane: 1), days: 2)
        case .resizing: TimelineStagedDrag(taskId: "出差", kind: .start, days: -2)
        default: nil
        }
    }

    private func update(_ id: String, _ change: (inout TodoTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[i])
    }

    /// What TaskRepo does with each edit.
    private func apply(_ edit: TimelineEdit) {
        switch edit {
        case .place(let p):
            for id in p.ids {
                update(id) { t in
                    if let due = t.dueDate {
                        t.dueDate = due + p.days
                    } else {
                        t.dueDate = p.day
                        t.dueTime = nil
                    }
                    switch p.target {
                    case let .section(listId, sectionId)?:
                        t.listId = listId
                        t.sectionId = sectionId
                    case .list(let listId)?:
                        if t.listId != listId { t.sectionId = nil }
                        t.listId = listId
                    case .tag?: t.tags = p.target!.retag(t.tags)
                    case .priority(let pr)?: t.priority = pr
                    default: break
                    }
                }
            }
        case .unschedule(let ids):
            for id in ids {
                update(id) {
                    $0.dueDate = nil
                    $0.dueTime = nil
                    $0.duration = nil
                }
            }
        case let .setStart(id, date, duration):
            update(id) {
                $0.dueDate = date
                $0.duration = normalizeDuration($0.dueTime, duration)
            }
        case let .setDuration(id, duration):
            update(id) { $0.duration = normalizeDuration($0.dueTime, duration) }
        }
    }

    /// A week of work around `today`, some in the inbox and the 生活 list.
    static func tasks(today: Day) -> [TodoTask] {
        var n = 0
        func t(
            _ id: String, _ title: String, list: String = "w", section: String? = nil, _ day: Int?,
            time: Int? = nil, duration: Int? = nil, priority: Priority = .none, done: Bool = false, tags: [String] = []
        ) -> TodoTask {
            n += 1
            return TodoTask(
                id: id, listId: list, sectionId: section, title: title, priority: priority,
                dueDate: day.map { today + $0 }, dueTime: time, duration: duration, tags: tags,
                status: done ? .done : .open, completedAt: done ? 1 : nil, sortOrder: Double(n), createdAt: n
            )
        }
        let day = minutesPerDay
        return [
            t("汇报", "准备季度汇报", section: "s1", -2, duration: 6 * day, priority: .high),
            t("评审", "需求评审", section: "s1", 0, time: 10 * 60, duration: 90, priority: .medium),
            t("周报", "写周报", section: "s1", 2),
            t("出差", "出差上海", section: "s1", 3, duration: 3 * day, tags: ["出差"]),
            t("修复", "修复登录问题", section: "s1", -1, done: true),
            t("对齐", "和设计对齐", section: "s1", 1, time: 15 * 60, priority: .low),
            t("重构", "代码重构", section: "s2", 7, duration: 4 * day),
            t("走查", "设计稿走查", section: "s2", 8, priority: .low),
            t("发布", "版本发布", section: "s2", 10, duration: 2 * day, priority: .high),
            t("复盘", "发布复盘", section: "s2", 12),
            t("整理", "整理文档", section: "s1", nil),
            t("调研", "调研竞品", section: "s2", nil, priority: .medium),
            t("想法", "想法：自动排期", nil),
            t("房租", "交房租", list: inboxListId, -3, priority: .high),
            t("买菜", "买菜", list: inboxListId, 0),
            t("体检", "体检", list: inboxListId, 5, time: 8 * 60 + 30),
            t("快递", "取快递", list: inboxListId, nil),
            t("健身", "健身", list: "home", 0, time: 19 * 60, duration: 60),
            t("看房", "周末看房", list: "home", 4, duration: 2 * day),
        ]
    }
}

#Preview("时间线") {
    TimelineDemo(scene: .day)
        .frame(width: 1000, height: 600)
}
