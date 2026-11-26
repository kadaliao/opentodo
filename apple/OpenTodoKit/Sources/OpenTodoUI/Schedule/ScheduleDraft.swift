// The date dialog's input and output: a task's date, time, span, reminders
// and repeat as one value (Dart: `Schedule` in `app/lib/ui/schedule_dialog.dart`).
//
// Callers (the task detail, context menus, batch actions, the calendar)
// build one from the task, show `ScheduleEditorView` (or the
// `.scheduleEditor(isPresented:…)` modifier) and hand what comes back to
// `TaskRepo`; the dialog itself never writes anything.

import OpenTodoDomain

public struct ScheduleDraft: Sendable, Hashable {
    /// Nil: no date. Coming out of the dialog it means the person pressed
    /// 清除, which clears everything else with it.
    public var dueDate: Day?
    /// Minutes after midnight; nil for an all-day task.
    public var dueTime: Int?
    /// Minutes from the start to the end of a span (时间段); nil for one day
    /// or one moment. See `Dates.swift`.
    public var duration: Int?
    /// Offsets in minutes (`Reminders.swift`), sorted.
    public var reminders: [Int]
    public var repeatRule: RepeatRule?
    public var repeatFrom: RepeatFrom

    public init(
        dueDate: Day?,
        dueTime: Int? = nil,
        duration: Int? = nil,
        reminders: [Int] = [],
        repeatRule: RepeatRule? = nil,
        repeatFrom: RepeatFrom = .dueDate
    ) {
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.duration = duration
        self.reminders = reminders
        self.repeatRule = repeatRule
        self.repeatFrom = repeatFrom
    }

    /// What 清除 gives: no date, and with it no time, span, reminders or repeat.
    public static let cleared = ScheduleDraft(dueDate: nil)

    /// The task's current schedule (its RRULE text parsed; text this app
    /// can't read counts as no repeat, as in the Dart version).
    public init(task: TodoTask) {
        self.init(
            dueDate: task.dueDate,
            dueTime: task.dueTime,
            duration: task.duration,
            reminders: task.reminders,
            repeatRule: RepeatRule.tryParse(task.repeatRule),
            repeatFrom: task.repeatFrom
        )
    }

    /// Whether this is the 清除 result.
    public var isCleared: Bool { dueDate == nil }

    /// The RRULE text to store in `TodoTask.repeatRule`.
    public var repeatRuleText: String? { repeatRule?.description }

    /// The task with this schedule, for callers that write whole rows. A
    /// cleared draft leaves no date, time, span, reminders or repeat behind.
    public func applied(to task: TodoTask) -> TodoTask {
        var t = task
        if let dueDate {
            t.dueDate = dueDate
            t.dueTime = dueTime
            t.duration = duration
            t.reminders = reminders
            t.repeatRule = repeatRuleText
            t.repeatFrom = repeatFrom
        } else {
            t.dueDate = nil
            t.dueTime = nil
            t.duration = nil
            t.reminders = []
            t.repeatRule = nil
            t.repeatFrom = .dueDate
        }
        return t
    }
}
