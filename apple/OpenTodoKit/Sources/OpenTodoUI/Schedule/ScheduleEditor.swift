// What the date dialog holds while the person edits, and how each choice
// changes the rest: `_ScheduleDialogState` in `app/lib/ui/schedule_dialog.dart`,
// as a value type so it can be tested without a view. The views only call
// the mutating methods here and read the derived values.

import Foundation
import OpenTodoDomain

public struct ScheduleEditor: Hashable {
    /// The person's defaults: reminders for a new time or all-day task, and
    /// how long a new span is.
    public let defaults: TaskDefaults
    /// The moment the dialog opened, wall clock. A span starts at the next
    /// hour of it.
    public let now: LocalDateTime

    /// The date, or the start of a span.
    public var date: Day
    /// Minutes after midnight; nil all day. Change it with `setTime(_:)`,
    /// which also starts the reminders over.
    public private(set) var time: Int?
    /// Sorted offsets.
    public private(set) var reminders: [Int]
    public private(set) var repeatRule: RepeatRule?
    public private(set) var repeatFrom: RepeatFrom

    /// 时间段: a start and an end instead of one date.
    public private(set) var isSpan: Bool

    /// Minutes from the start to the end while picking a span; it may be
    /// zero or less while the end is set before the start. All day, whole
    /// days, and nil is the one day.
    public private(set) var duration: Int?

    public var today: Day { now.day }

    public init(_ initial: ScheduleDraft, defaults: TaskDefaults = .standard, now: LocalDateTime) {
        self.defaults = defaults
        self.now = now
        date = initial.dueDate ?? now.day
        time = initial.dueTime
        // A task without a date starts with the defaults for an all-day one,
        // which is what it becomes.
        reminders = sortedReminders(initial.dueDate == nil ? defaults.allDayReminders : initial.reminders)
        repeatRule = initial.repeatRule
        repeatFrom = initial.repeatFrom
        isSpan = initial.dueDate != nil && initial.duration != nil
        duration = initial.duration
    }

    public var isAllDay: Bool { time == nil }

    /// A span ends after it starts: by a day or more all day, by a minute
    /// or more with times.
    public var isSpanValid: Bool {
        !isSpan || (isAllDay ? (duration ?? minutesPerDay) >= minutesPerDay : (duration ?? 0) > 0)
    }

    /// The last day of an all-day span (at midnight), or the end of a timed one.
    public var end: LocalDateTime {
        if isAllDay {
            let days = Int((Double(duration ?? minutesPerDay) / Double(minutesPerDay)).rounded(.up))
            return LocalDateTime(date + (days - 1))
        }
        return LocalDateTime(date, minute: time! + (duration ?? 0))
    }

    /// Wall-clock minutes from the start to `end`.
    private func minutes(to end: LocalDateTime) -> Int {
        end - LocalDateTime(date, minute: time ?? 0)
    }

    // MARK: Date and time

    public mutating func setDate(_ day: Day) { date = day }

    /// Reminders mean different things with and without a time, so switching
    /// starts them over with the defaults: out of the box 准时 for a timed
    /// task, none for an all-day one.
    public mutating func setTime(_ newTime: Int?) {
        if (newTime == nil) != (time == nil) {
            reminders = sortedReminders(defaults.remindersFor(allDay: newTime == nil))
        }
        time = newTime
    }

    /// What the time picker starts on when there's no time yet (the Dart
    /// version's picker opened on 9:00).
    public static let defaultPickedTime = 9 * 60

    // MARK: Span

    public mutating func setSpan(_ on: Bool) {
        isSpan = on
        guard on else { return }
        if isAllDay && duration == nil {
            // A span is usually a few hours: start at the next hour today, or
            // in the morning another day.
            let start = date == now.day && now.hour < 23 ? (now.hour + 1) * 60 : 9 * 60
            setTime(start)
        }
        if !isAllDay && duration == nil { duration = defaults.spanMinutes }
    }

    /// The span's 全天 switch: all day keeps the days it touches, back to
    /// times starts at 9:00 for the default length.
    public mutating func setSpanAllDay(_ allDay: Bool) {
        guard allDay != isAllDay else { return }
        if allDay {
            let e = end
            let days = date.days(to: e.day) + (e.minuteOfDay == 0 ? 0 : 1)
            setTime(nil)
            duration = max(days, 1) * minutesPerDay
        } else {
            setTime(9 * 60)
            duration = defaults.spanMinutes
        }
    }

    /// The start's date; the span keeps its length.
    public mutating func setStartDay(_ day: Day) { date = day }

    /// The start's time; the span keeps its length (the Dart version picked
    /// the start time with the same picker as a single date's time).
    public mutating func setStartTime(_ minute: Int) { setTime(minute) }

    public mutating func setEndDay(_ day: Day) {
        let e = end
        duration = isAllDay
            ? (date.days(to: day) + 1) * minutesPerDay
            : minutes(to: LocalDateTime(day, minute: e.minuteOfDay))
    }

    public mutating func setEndTime(_ minute: Int) {
        duration = minutes(to: LocalDateTime(end.day, minute: minute))
    }

    // MARK: Reminders

    public mutating func setReminders(_ offsets: some Sequence<Int>) { reminders = sortedReminders(offsets) }

    public mutating func clearReminders() { reminders = [] }

    /// 准时 / 提前30分钟、当天 09:00 …; nil without reminders.
    public var remindersText: String? {
        reminders.isEmpty ? nil : remindersSummary(reminders, allDay: isAllDay)
    }

    // MARK: Repeat

    /// The repeat menu for the current date.
    public var repeatPresets: [RepeatPreset] { RepeatPreset.all(for: date) }

    /// A preset from the menu (nil: 不重复). Presets count from the due date.
    public mutating func setRepeat(_ rule: RepeatRule?) {
        repeatRule = rule
        repeatFrom = .dueDate
    }

    /// The 艾宾浩斯 preset picked again keeps the round the series is on.
    public mutating func choose(_ preset: RepeatPreset) {
        if preset.isEbbinghaus && repeatRule?.ebbinghausRound != nil && repeatFrom == .dueDate { return }
        setRepeat(preset.rule)
    }

    /// From 自定义重复.
    public mutating func setCustomRepeat(_ rule: RepeatRule, from: RepeatFrom) {
        repeatRule = rule
        repeatFrom = from
    }

    public mutating func clearRepeat() { setRepeat(nil) }

    /// Whether the rule is one the menu doesn't list (or counts from
    /// completion): 自定义… gets the check.
    public var isCustomRepeat: Bool {
        guard let rule = repeatRule else { return false }
        return repeatFrom != .dueDate || !repeatPresets.contains { $0.matches(rule) }
    }

    /// Whether `preset` gets the check in the menu.
    public func isChosen(_ preset: RepeatPreset) -> Bool {
        guard !isCustomRepeat else { return false }
        guard let rule = repeatRule else { return preset.rule == nil }
        return preset.matches(rule)
    }

    /// 每天 / 每2周的周一、三（按完成日期）…; nil without a repeat.
    public var repeatText: String? {
        repeatRule.map { describeRepeat($0, date, repeatFrom: repeatFrom) }
    }

    /// What 自定义… opens on: the current rule, or weekly.
    public var customRepeatEditor: CustomRepeatEditor {
        CustomRepeatEditor(date: date, rule: repeatRule ?? .weekly, repeatFrom: repeatFrom)
    }

    // MARK: Quick dates

    public var quickDates: [QuickDate] { QuickDate.all(today: today) }

    // MARK: Result

    /// What 确定 gives; nil while the span ends before it starts.
    public var result: ScheduleDraft? {
        guard isSpanValid else { return nil }
        return ScheduleDraft(
            dueDate: date,
            dueTime: time,
            duration: isSpan ? normalizeDuration(time, duration) : nil,
            reminders: reminders,
            repeatRule: repeatRule,
            repeatFrom: repeatFrom
        )
    }
}

/// The shortcuts above the month: 今天, 明天, 下周一, 下个月.
public struct QuickDate: Hashable, Identifiable {
    public let title: String
    public let symbol: String
    public let day: Day
    public var id: String { title }

    public static func all(today: Day) -> [QuickDate] {
        [
            QuickDate(title: "今天", symbol: "sun.max", day: today),
            QuickDate(title: "明天", symbol: "sunrise", day: today + 1),
            QuickDate(title: "下周一", symbol: "calendar.badge.plus", day: today.startOfWeek + 7),
            // Same day next month, rolling over like Dart's DateTime
            // (1月31日 → 3月3日).
            QuickDate(title: "下个月", symbol: "calendar", day: Day(today.year, today.month + 1, today.day)),
        ]
    }
}

/// One line of the repeat menu, its words filled in from the task's date.
public struct RepeatPreset: Hashable, Identifiable {
    public let title: String
    /// Nil: 不重复.
    public let rule: RepeatRule?
    public var id: String { title }

    public var isEbbinghaus: Bool { rule?.ebbinghausRound != nil }

    /// Any 艾宾浩斯 round counts as the 艾宾浩斯 line.
    public func matches(_ other: RepeatRule) -> Bool {
        if isEbbinghaus { return other.ebbinghausRound != nil }
        return rule == other
    }

    public static func all(for date: Day) -> [RepeatPreset] {
        var out = [
            RepeatPreset(title: "不重复", rule: nil),
            RepeatPreset(title: "每天", rule: .daily),
            RepeatPreset(title: "每周（\(weekdayName(date))）", rule: .weekly),
            RepeatPreset(title: "每月（\(date.day)日）", rule: .monthly),
            RepeatPreset(title: "每年（\(date.month)月\(date.day)日）", rule: .yearly),
            RepeatPreset(title: "工作日（周一至周五）", rule: .workdays),
            RepeatPreset(title: "法定工作日（按节假日调休）", rule: .statutoryWorkdays),
        ]
        if let l = toLunar(date) {
            out.append(RepeatPreset(title: "农历每年（\(lunarMonthName(l.month))\(lunarDayName(l.day))）",
                                    rule: RepeatRule.lunarYearlyOn(date)))
            out.append(RepeatPreset(title: "农历每月（\(lunarDayName(l.day))）", rule: RepeatRule.lunarMonthlyOn(date)))
        }
        // Not in the Dart menu (it came later, with the Swift version).
        out.append(RepeatPreset(title: "艾宾浩斯记忆法", rule: .ebbinghaus))
        return out
    }
}
