// The reminder list and 自定义提醒: `_ReminderPicker` and `_CustomReminder`
// in `app/lib/ui/schedule_dialog.dart`, as value types.

import OpenTodoDomain

/// The reminders on offer and which are on. The list is fixed when it
/// opens (the presets plus whatever the task has), so turning one off
/// doesn't make it disappear; custom ones join it.
public struct ReminderChoices: Hashable {
    public let allDay: Bool
    /// Latest first, as in the Dart version: 准时, 提前5分钟 … 提前1天.
    public private(set) var options: [Int]
    public private(set) var selected: Set<Int>

    public init(allDay: Bool, selected: [Int]) {
        self.allDay = allDay
        self.selected = Set(selected)
        options = sortedReminders((allDay ? allDayReminderPresets : timedReminderPresets) + selected).reversed()
    }

    public func isOn(_ offset: Int) -> Bool { selected.contains(offset) }

    public mutating func toggle(_ offset: Int) {
        if selected.contains(offset) { selected.remove(offset) } else { selected.insert(offset) }
    }

    public mutating func clear() { selected = [] }

    /// A custom reminder, turned on.
    public mutating func add(_ offset: Int) {
        selected.insert(offset)
        if !options.contains(offset) {
            options.append(offset)
            options.sort(by: >)
        }
    }

    public func label(_ offset: Int) -> String { reminderLabel(offset, allDay: allDay) }

    /// What goes back to the task, sorted.
    public var reminders: [Int] { sortedReminders(selected) }
}

/// 提前 [n] [分钟/小时/天] for a timed task; 提前 [n] 天 at a time of day for
/// an all-day one.
public struct CustomReminder: Hashable {
    public enum Unit: Int, Hashable, CaseIterable {
        case minutes = 1, hours = 60, days = 1440

        public var title: String {
            switch self {
            case .minutes: "分钟"
            case .hours: "小时"
            case .days: "天"
            }
        }
    }

    public let allDay: Bool
    /// 0–999 to be valid.
    public var amount: Int
    /// Timed tasks only.
    public var unit: Unit = .minutes
    /// All-day tasks only: the time of day it goes off.
    public var minuteOfDay = 9 * 60

    public init(allDay: Bool) {
        self.allDay = allDay
        amount = allDay ? 1 : 10
    }

    /// The offset; nil while the amount is out of range.
    public var offset: Int? {
        guard (0...999).contains(amount) else { return nil }
        return allDay ? -amount * 1440 + minuteOfDay : -amount * unit.rawValue
    }

    /// The preview: 提前10分钟 / 提前1天 09:00.
    public var label: String? { offset.map { reminderLabel($0, allDay: allDay) } }
}
