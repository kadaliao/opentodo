// 自定义重复: `_CustomRepeatState` in `app/lib/ui/schedule_dialog.dart` as a
// value type. The view binds to the fields and shows `rule` as it changes.

import OpenTodoDomain

public struct CustomRepeatEditor: Hashable {
    public enum End: Hashable, CaseIterable {
        case never, until, count

        public var title: String {
            switch self {
            case .never: "永不"
            case .until: "截止日期"
            case .count: "重复次数"
            }
        }
    }

    /// The task's date: it fills in what the rule leaves out.
    public let date: Day
    /// The task's date in the lunar calendar; nil outside its table.
    public let lunarDate: LunarDate?

    public var from: RepeatFrom
    public var freq: Freq
    /// Every `interval` days / weeks / months / years; 1–999 to be valid.
    public var interval: Int
    /// WEEKLY: the days, 1 = Monday … 7 = Sunday. Never empty.
    public private(set) var weekdays: Set<Int>
    /// MONTHLY and YEARLY: by the lunar calendar. Change it with `setLunar(_:)`.
    public private(set) var lunar: Bool
    /// Monday to Friday as China's holiday schedule shifts them.
    public var holidays: Bool
    /// MONTHLY: by the nth weekday instead of the day of the month.
    public var byWeekday: Bool
    /// MONTHLY: the day of the month (lunar or not), -1 the last.
    public private(set) var monthDay: Int
    /// MONTHLY by weekday: which one (1–5, -1 the last) …
    public private(set) var nth: Int
    /// … of which weekday.
    public private(set) var nthDay: Int
    public var end: End
    public var until: Day
    /// Occurrences, the current one included; 1 or more to be valid.
    public var count: Int

    public init(date: Day, rule: RepeatRule, repeatFrom: RepeatFrom) {
        self.date = date
        lunarDate = toLunar(date)
        from = repeatFrom
        freq = rule.freq
        interval = rule.interval
        weekdays = Set(rule.weekdays.isEmpty ? [date.weekday] : rule.weekdays)
        lunar = rule.lunar && lunarDate != nil
        holidays = rule.chinaHolidays
        byWeekday = rule.nthWeekday != nil
        monthDay = 0
        nth = rule.nthWeekday?.n ?? Self.nth(of: date)
        nthDay = rule.nthWeekday?.weekday ?? date.weekday
        end = rule.until != nil ? .until : (rule.count != nil ? .count : .never)
        until = rule.until ?? Day(date.year, date.month + 1, date.day)
        count = rule.count ?? 10
        monthDay = rule.monthDays.first ?? dayOfMonth
    }

    /// The nth of its weekday `d` is in its month, -1 if it's the last.
    static func nth(of d: Day) -> Int {
        d.day + 7 > d.daysInMonth ? -1 : (d.day - 1) / 7 + 1
    }

    /// The task's day of the month, lunar or not.
    public var dayOfMonth: Int { lunar ? lunarDate!.day : date.day }

    public var byDate: Bool { from == .dueDate }

    /// Monday to Friday exactly.
    public var isMonToFri: Bool { weekdays.count == 5 && weekdays.allSatisfy { $0 <= 5 } }

    // MARK: What the form shows

    /// The seven day buttons (weekly, by the due date).
    public var showsWeekdays: Bool { byDate && freq == .weekly }

    /// 按法定节假日调休: weekly on Monday to Friday, every week.
    public var showsHolidays: Bool { showsWeekdays && isMonToFri && interval == 1 }

    /// 按农历: monthly or yearly, by the due date, for a date in the table.
    public var showsLunar: Bool { byDate && lunarDate != nil && (freq == .monthly || freq == .yearly) }

    /// 农历每月 [初一…三十 / 最后一天].
    public var showsLunarMonthDay: Bool { byDate && freq == .monthly && lunar }

    /// 按日期 / 按星期.
    public var showsMonthly: Bool { byDate && freq == .monthly && !lunar }

    // MARK: Changes

    /// At least one day stays on.
    public mutating func toggleWeekday(_ wd: Int) {
        if weekdays.contains(wd) {
            if weekdays.count > 1 { weekdays.remove(wd) }
        } else {
            weekdays.insert(wd)
        }
    }

    public mutating func setLunar(_ on: Bool) {
        lunar = on
        monthDay = dayOfMonth
    }

    /// 按日期: picking a day also switches to it.
    public mutating func setMonthDay(_ d: Int) {
        monthDay = d
        byWeekday = false
    }

    /// 按星期: picking either part also switches to it.
    public mutating func setNth(_ n: Int) {
        nth = n
        byWeekday = true
    }

    public mutating func setNthDay(_ wd: Int) {
        nthDay = wd
        byWeekday = true
    }

    // MARK: Result

    /// The rule as set; nil while a number is out of range.
    public var rule: RepeatRule? {
        guard (1...999).contains(interval) else { return nil }
        if end == .count && count < 1 { return nil }
        let lunar = byDate && self.lunar && (freq == .monthly || freq == .yearly)
        return RepeatRule(
            freq,
            interval: interval,
            weekdays: byDate && freq == .weekly ? weekdays.sorted() : [],
            monthDays: byDate && freq == .monthly && (!byWeekday || lunar)
                ? [monthDay]
                : (lunar ? [lunarDate!.day] : []),
            nthWeekday: byDate && freq == .monthly && byWeekday && !lunar ? NthWeekday(n: nth, weekday: nthDay) : nil,
            month: lunar && freq == .yearly ? lunarDate!.month : nil,
            until: end == .until ? until : nil,
            count: end == .count ? count : nil,
            lunar: lunar,
            chinaHolidays: byDate && holidays && freq == .weekly && interval == 1 && isMonToFri
        )
    }

    /// The preview under the form.
    public var summary: String {
        rule.map { describeRepeat($0, date, repeatFrom: from) } ?? "请填写有效的数字"
    }

    // MARK: Choices

    public static let freqs: [(Freq, String)] = [(.daily, "天"), (.weekly, "周"), (.monthly, "个月"), (.yearly, "年")]

    /// 一 … 日, for weekdays 1 … 7.
    public static let weekdayShort = ["一", "二", "三", "四", "五", "六", "日"]

    /// 1日 … 31日, then 最后一天 (-1).
    public static let monthDays: [(Int, String)] = (1...31).map { ($0, "\($0)日") } + [(-1, "最后一天")]

    /// 初一 … 三十, then 最后一天 (-1).
    public static let lunarMonthDays: [(Int, String)] = (1...30).map { ($0, lunarDayName($0)) } + [(-1, "最后一天")]

    /// 第1个 … 第5个, 最后一个.
    public static let nths: [(Int, String)] = [1, 2, 3, 4, 5, -1].map { ($0, $0 == -1 ? "最后一个" : "第\($0)个") }
}
