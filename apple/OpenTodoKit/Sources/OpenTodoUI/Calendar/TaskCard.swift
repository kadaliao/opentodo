// The card of a task clicked on the calendar (when the caller asks for
// cards, `CalendarOptions.taskTap == .card`): its checkbox and title, when
// it is, its list, the start of its notes, and 完成 / 打开详情. A popover on
// a Mac, a half sheet on a phone. New in the Swift version (路线图).

import OpenTodoDomain
import SwiftUI

struct TaskCard: View {
    let task: TodoTask
    let ctx: CalendarContext

    var body: some View {
        let done = task.status != .open
        let tint = ctx.color(of: task)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PriorityCheckbox(checked: done, priority: task.priority, size: 18) {
                    ctx.actions.setDone(task.id, !done)
                }
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                Text(task.title.isEmpty ? "无标题" : task.title)
                    .font(.title3.weight(.semibold))
                    .strikethrough(done)
                    .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let due = task.dueDate {
                    Label(fullDueLabel(due, task.dueTime, today: ctx.today, duration: task.duration), systemImage: "calendar")
                        .foregroundStyle(isOverdue(task, ctx.now) && !done ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                }
                if let rule = RepeatRule.tryParse(task.repeatRule), let due = task.dueDate {
                    Label(describeRepeat(rule, due, repeatFrom: task.repeatFrom), systemImage: "repeat")
                        .foregroundStyle(.secondary)
                }
                Label {
                    Text(ctx.listName(task.listId))
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(tint).imageScale(.small)
                }
                .foregroundStyle(.secondary)
                if task.priority != .none {
                    Label(["", "低优先级", "中优先级", "高优先级"][task.priority.rawValue], systemImage: "flag.fill")
                        .foregroundStyle(Palette.priority(task.priority))
                }
            }
            .font(.subheadline)
            let note = notePreview(task.content)
            if !note.isEmpty {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button {
                    ctx.actions.setDone(task.id, !done)
                    ctx.model.closeCard()
                } label: {
                    Label(done ? "标记为未完成" : "完成", systemImage: done ? "arrow.uturn.backward" : "checkmark")
                }
                Spacer()
                Button {
                    ctx.model.closeCard()
                    ctx.actions.openTask(task.id)
                } label: {
                    Label("打开详情", systemImage: "info.circle")
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(maxWidth: ctx.compact ? .infinity : 340, alignment: .leading)
        // In a phone's sheet: at the top, not centred under a gap.
        .frame(maxHeight: ctx.compact ? .infinity : nil, alignment: .top)
        .fixedSize(horizontal: !ctx.compact, vertical: false)
    }

    /// The first few lines of the notes.
    private func notePreview(_ content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(4)
            .joined(separator: "\n")
    }
}
