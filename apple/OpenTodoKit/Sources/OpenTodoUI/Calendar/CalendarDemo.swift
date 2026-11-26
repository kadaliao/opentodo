// The calendar on demo data, for screenshots and trying it out without a
// database: `-OTOpen calendar-demo:<state>` in a Debug build (see
// DebugLaunch). The host keeps the tasks in memory and carries out what the
// calendar asks (moves, ticks, new tasks), the way the app will through
// TaskRepo. The clock stands at Wednesday 18 November 2026, 10:30.

import OpenTodoDomain
import SwiftUI

/// What the demo opens on.
public enum CalendarDemoState: String, CaseIterable, Sendable {
    case month, week, day, threeDays, multiWeek, year, agenda
    /// The month with two tasks picked (多选).
    case picking
    /// The week with a task's card open.
    case card
    /// The month with a new task started on a day.
    case new
    /// The month with the 安排任务 panel open.
    case arrange
    /// The card and the new-task panel laid out in the window (a Mac
    /// screenshot of the window leaves popovers out).
    case panels
}

enum CalendarDemoData {
    static let now = LocalDateTime(2026, 11, 18, 10, 30)
    static var today: Day { now.day }

    static let lists = [
        TaskList(id: "work", name: "工作", color: 0xFF3E8BFF, sortOrder: 1),
        TaskList(id: "life", name: "生活", color: 0xFFF2A516, sortOrder: 2),
        TaskList(id: "study", name: "学习", color: 0xFFAF52DE, sortOrder: 3),
    ]

    static func tasks() -> [TodoTask] {
        var seq = 0
        func t(_ title: String, _ list: String = inboxListId, due: String? = nil, time: Int? = nil, duration: Int? = nil,
               priority: Priority = .none, status: TaskStatus = .open, repeat rule: String? = nil, content: String = "") -> TodoTask {
            seq += 1
            return TodoTask(
                id: "demo-\(seq)", listId: list, title: title, content: content, priority: priority,
                dueDate: due.map { Day($0)! }, dueTime: time, duration: duration, status: status,
                completedAt: status == .open ? nil : 1, repeatRule: rule, sortOrder: Double(seq), createdAt: seq
            )
        }
        return [
            t("晨会", "work", due: "2026-11-18", time: 9 * 60, duration: 30, priority: .high, content: "过一遍本周的上线计划\n带上电脑"),
            t("午餐会", "work", due: "2026-11-18", time: 12 * 60, duration: 60),
            t("和设计对稿", "work", due: "2026-11-18", time: 12 * 60 + 30, duration: 45, priority: .medium),
            t("写周报", "work", due: "2026-11-18", time: 15 * 60, duration: 90),
            t("晨跑", "life", due: "2026-11-18", time: 7 * 60, duration: 40, repeat: "FREQ=DAILY"),
            t("报销", "work", due: "2026-11-16", priority: .medium),
            t("健身", "life", due: "2026-11-17", time: 18 * 60, duration: 60, status: .done),
            t("交房租", "life", due: "2026-11-20", priority: .high),
            t("夜班", "work", due: "2026-11-19", time: 22 * 60, duration: 10 * 60),
            t("出差上海", "work", due: "2026-11-23", duration: 3 * 1440, priority: .medium),
            t("项目评审", "work", due: "2026-11-24", time: 14 * 60, duration: 60, priority: .high),
            t("读完一本书", "study", due: "2026-11-25"),
            t("买机票", "life", due: "2026-11-26"),
            t("洗车", "life", due: "2026-11-21"),
            t("取快递", "life", due: "2026-11-21", time: 10 * 60),
            t("买菜", "life", due: "2026-11-21", time: 17 * 60),
            t("打扫卫生", "life", due: "2026-11-21"),
            t("给妈妈打电话", inboxListId, due: "2026-11-21", time: 20 * 60),
            t("英语课", "study", due: "2026-11-16", time: 19 * 60, duration: 90, repeat: "FREQ=WEEKLY;BYDAY=MO,TH"),
            t("看牙医", "life", due: "2026-12-02", time: 10 * 60),
            t("年终总结", "work", due: "2026-12-28", duration: 4 * 1440),
            t("整理照片", "life"),
            t("学 SwiftUI 动画", "study", priority: .medium),
            t("换手机壳"),
            t("约体检", "life", priority: .high),
        ]
    }
}

/// The calendar on demo data, in the frame the app will give it: a split
/// view with the sidebar on a Mac or iPad, a navigation stack on a phone.
public struct CalendarDemoHost: View {
    @State private var model: CalendarModel
    @State private var tasks: [TodoTask]
    @State private var openTask: String?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    private let cards: Bool
    private let panels: Bool

    public init(state: CalendarDemoState) {
        let model = CalendarModel(anchor: CalendarDemoData.today)
        let tasks = CalendarDemoData.tasks()
        switch state {
        case .month, .picking, .new, .arrange, .panels: model.mode = .month
        case .week, .card: model.mode = .week
        case .day: model.mode = .day
        case .threeDays: model.mode = .threeDays
        case .multiWeek: model.mode = .multiWeek
        case .year: model.mode = .year
        case .agenda: model.mode = .agenda
        }
        if state == .picking { model.selection.selectAll(["demo-1", "demo-8"]) }
        if state == .card { model.openCard("demo-1", at: "demo-1@2026-11-18") }
        if state == .new { model.newTask = CalendarNewTask(date: Day(2026, 11, 27), time: nil, place: .cell(Day(2026, 11, 27))) }
        if state == .arrange { model.showsArrangePanel = true }
        _model = State(initialValue: model)
        _tasks = State(initialValue: tasks)
        cards = state == .card
        panels = state == .panels
    }

    public var body: some View {
        let calendar = CalendarView(
            model: model, tasks: tasks, lists: CalendarDemoData.lists, now: CalendarDemoData.now,
            actions: CalendarActions(
                openTask: { openTask = $0; model.openTaskId = $0 },
                move: apply,
                setDuration: { id, minutes in update(id) { $0.duration = minutes } },
                setDone: { id, done in update(id) { $0.status = done ? .done : .open } }
            ),
            options: CalendarOptions(
                taskTap: cards ? .card : nil,
                quickAdd: { request, done in AnyView(DemoQuickAdd(request: request) { title in add(title, request); done() }) },
                taskMenu: { task in
                    AnyView(Group {
                        Button("完成", systemImage: "checkmark") { update(task.id) { $0.status = .done } }
                        Button("删除", systemImage: "trash", role: .destructive) { tasks.removeAll { $0.id == task.id } }
                    })
                },
                filtersInToolbar: compact
            )
        )
        if panels {
            DemoPanels(model: model, tasks: tasks)
        } else if compact {
            NavigationStack { calendar }
        } else {
            NavigationSplitView {
                CalendarSidebar(model: model, tasks: tasks, lists: CalendarDemoData.lists, now: CalendarDemoData.now)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            } detail: {
                calendar
            }
        }
    }

    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private func update(_ id: String, _ change: (inout TodoTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[i])
    }

    private func apply(_ moves: [CalendarMove]) {
        for m in moves {
            update(m.id) { t in
                t.duration = durationForTimeChange(t.dueDate ?? m.date, t.dueTime, m.time, t.duration)
                t.dueDate = m.date
                t.dueTime = m.time
            }
        }
    }

    private func add(_ text: String, _ request: CalendarNewTask) {
        let parsed = parseQuickAdd(text, now: CalendarDemoData.now)
        guard !parsed.title.isEmpty else { return }
        tasks.append(TodoTask(
            id: "new-\(tasks.count)", title: parsed.title, dueDate: parsed.date ?? request.date,
            dueTime: parsed.time ?? (parsed.date == nil ? request.time : nil), duration: parsed.duration,
            tags: parsed.tags, createdAt: 1000 + tasks.count
        ))
    }
}

/// Stands in for the app's quick-add field.
private struct DemoQuickAdd: View {
    let request: CalendarNewTask
    let add: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("准备做什么？回车创建", text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { add(text) }
            .onAppear { focused = true }
    }
}

/// The card of 晨会 and the panel of a new task at 14:00, side by side.
private struct DemoPanels: View {
    let model: CalendarModel
    let tasks: [TodoTask]

    var body: some View {
        let ctx = CalendarContext(
            model: model, tasks: tasks, lists: Dictionary(uniqueKeysWithValues: CalendarDemoData.lists.map { ($0.id, $0) }),
            filters: [], now: CalendarDemoData.now, actions: CalendarActions(),
            options: CalendarOptions(quickAdd: { request, done in AnyView(DemoQuickAdd(request: request) { _ in done() }) }),
            compact: false
        )
        HStack(alignment: .top, spacing: 24) {
            TaskCard(task: tasks[0], ctx: ctx)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
            NewTaskPanel(ctx: ctx, request: CalendarNewTask(date: Day(2026, 11, 19), time: 14 * 60))
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.1))
    }
}
