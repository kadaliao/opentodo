// One task in a list: the priority checkbox, the title (two lines at
// most), and a line of small details under it — the date (red when
// overdue, with repeat / alarm glyphs), the list it is in (in views that
// gather several lists), checklist progress, tags. A pinned task has a pin
// at the end. A finished task is greyed; a trashed one has no checkbox
// action.
//
// It takes only the task and plain values, so any screen can use it:
//
//     TaskRow(task, now: model.now, list: model.listsById[task.listId],
//             showList: true, checklist: model.checklistProgress(of: task.id)) {
//         model.setDone(task, task.status == .open)
//     }
//
// Selection, swipe actions and context menus belong to the list that
// holds the rows.

import OpenTodoDomain
import SwiftUI

public struct TaskRow: View {
    public var task: TodoTask
    public var now: LocalDateTime
    /// The task's list (nil for 收集箱), shown when `showList`.
    public var list: TaskList?
    public var showList: Bool
    /// (done, total) of the checklist; nothing shows when total is 0.
    public var checklist: (done: Int, total: Int)
    public var onToggle: (() -> Void)?
    @Environment(\.uiScale) private var s

    public init(_ task: TodoTask, now: LocalDateTime, list: TaskList? = nil, showList: Bool = false,
                checklist: (done: Int, total: Int) = (0, 0), onToggle: (() -> Void)? = nil) {
        self.task = task
        self.now = now
        self.list = list
        self.showList = showList
        self.checklist = checklist
        self.onToggle = onToggle
    }

    private var finished: Bool { task.status != .open }
    private var trashed: Bool { task.trashedAt != nil }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.gap * s) {
            // A hidden copy of the title's first line gives the checkbox
            // its baseline, so it sits on the first line however many lines
            // the title wraps to.
            Text(verbatim: "我")
                .uiFont(Metrics.titleFont)
                .hidden()
                .frame(width: PriorityCheckbox.defaultSize * s)
                .overlay {
                    PriorityCheckbox(checked: finished, priority: task.priority, action: trashed ? nil : onToggle)
                }
            VStack(alignment: .leading, spacing: Metrics.lineGap * s) {
                Text(task.title.isEmpty ? "无标题" : task.title)
                    .uiFont(Metrics.titleFont)
                    .foregroundStyle(finished || task.title.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                if hasDetails { details }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if task.pinnedAt != nil && !finished {
                Image(systemName: "pin.fill")
                    .uiFont(.caption2)
                    .foregroundStyle(.orange)
                    .rotationEffect(.degrees(45))
                    .accessibilityLabel("已置顶")
            }
        }
        .padding(.vertical, Metrics.rowPadding * s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var hasDetails: Bool {
        task.dueDate != nil || showList || checklist.total > 0 || !task.tags.isEmpty
    }

    private var details: some View {
        HStack(spacing: Metrics.detailGap * s) {
            if let due = DueLabel(task, now: now) {
                due.layoutPriority(2)
            }
            if showList {
                HStack(spacing: 3 * s) {
                    if let e = list?.emoji, !e.isEmpty { Text(e).uiFont(.caption2) }
                    Text(list?.name ?? "收集箱")
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            }
            if checklist.total > 0 {
                Text("\(Image(systemName: "checklist")) \(checklist.done)/\(checklist.total)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityLabel("子任务完成 \(checklist.done) 个，共 \(checklist.total) 个")
            }
            ForEach(task.tags.prefix(3), id: \.self) { TagLabel($0) }
        }
        .uiFont(Metrics.detailFont)
        .opacity(finished ? 0.7 : 1)
    }

    /// At 标准; all of them grow with 界面大小 (`uiScale`).
    enum Metrics {
        #if os(macOS)
        static let titleFont = Font.TextStyle.body
        static let detailFont = Font.TextStyle.subheadline
        static let gap: CGFloat = 8
        static let lineGap: CGFloat = 2
        static let detailGap: CGFloat = 8
        static let rowPadding: CGFloat = 4
        #else
        static let titleFont = Font.TextStyle.body
        static let detailFont = Font.TextStyle.subheadline
        static let gap: CGFloat = 12
        static let lineGap: CGFloat = 3
        static let detailGap: CGFloat = 10
        static let rowPadding: CGFloat = 4
        #endif
    }
}

#Preview {
    let now = LocalDateTime(2026, 11, 26, 9, 41)
    List {
        TaskRow(TodoTask(id: "a", title: "写第四季度工作总结", priority: .high, dueDate: Day(2026, 11, 26), dueTime: 900,
                         tags: ["工作"], reminders: [-30]), now: now, checklist: (2, 5)) {}
        TaskRow(TodoTask(id: "b", title: "评审设计稿", priority: .medium, dueDate: Day(2026, 11, 24)), now: now,
                list: TaskList(id: "w", name: "工作", emoji: "💼"), showList: true) {}
        TaskRow(TodoTask(id: "c", title: "做幻灯片", dueDate: Day(2026, 11, 27), repeatRule: "FREQ=WEEKLY", pinnedAt: 1),
                now: now) {}
        TaskRow(TodoTask(id: "d", title: "晨跑", status: .done), now: now) {}
    }
}
