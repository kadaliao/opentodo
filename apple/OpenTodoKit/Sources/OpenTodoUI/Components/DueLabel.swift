// The small date of a task row or calendar chip: 今天 / 下午3:00 / 周三 /
// 11月20日 (`dueLabel`), with a repeat and an alarm glyph after it when the
// task repeats or reminds. Red once overdue, grey otherwise (and always
// grey for a finished task).

import OpenTodoDomain
import SwiftUI

public struct DueLabel: View {
    public var dueDate: Day
    public var dueTime: Int?
    public var duration: Int?
    public var repeats: Bool
    public var reminds: Bool
    public var overdue: Bool
    public var today: Day
    /// `.increased` in a selected row on the Mac: red wouldn't show on the
    /// accent colour, the weight still marks it overdue.
    @Environment(\.backgroundProminence) private var prominence

    public init(dueDate: Day, dueTime: Int? = nil, duration: Int? = nil, repeats: Bool = false, reminds: Bool = false,
                overdue: Bool = false, today: Day) {
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.duration = duration
        self.repeats = repeats
        self.reminds = reminds
        self.overdue = overdue
        self.today = today
    }

    /// The label for a task; nil if it has no date.
    public init?(_ task: TodoTask, now: LocalDateTime) {
        guard let due = task.dueDate else { return nil }
        let open = task.status == .open
        self.init(dueDate: due, dueTime: task.dueTime, duration: task.duration, repeats: task.repeatRule != nil,
                  reminds: open && !task.reminders.isEmpty, overdue: isOverdue(task, now), today: now.day)
    }

    public var text: String { dueLabel(dueDate, dueTime, today: today, duration: duration) }

    public var body: some View {
        let r = repeats ? Text(" \(Image(systemName: "repeat"))") : Text(verbatim: "")
        let b = reminds ? Text(" \(Image(systemName: "bell"))") : Text(verbatim: "")
        return Text("\(text)\(r)\(b)")
            .accessibilityLabel([text, repeats ? "重复" : nil, reminds ? "有提醒" : nil].compactMap { $0 }.joined(separator: "，"))
            .foregroundStyle(overdue && prominence != .increased ? AnyShapeStyle(Palette.overdue) : AnyShapeStyle(.secondary))
            .fontWeight(overdue ? .medium : nil)
            .lineLimit(1)
            .fixedSize()
    }
}
