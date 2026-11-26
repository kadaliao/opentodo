// China's public holidays and the weekend days worked in exchange (调休),
// as the State Council's General Office announces them each year
// (国务院办公厅关于××××年部分节假日安排的通知, usually in November). The
// schedule isn't a rule that can be worked out, so it ships with the app:
// when next year's notice is out, add it to `holidaySchedules` (and to the
// Dart version's `holidays.dart`) and release. Ported from
// `app/lib/domain/holidays.dart`.

/// One holiday in a notice: the days off, and the weekend days worked.
private struct Holiday {
    let name: String
    /// `MM-DD`, inclusive.
    let from: String
    let to: String
    /// `MM-DD`: weekend days worked in exchange (上班).
    let workdays: [String]

    init(_ name: String, _ from: String, _ to: String, _ workdays: [String] = []) {
        self.name = name
        self.from = from
        self.to = to
        self.workdays = workdays
    }
}

/// In year order (the Dart map's insertion order).
private let holidaySchedules: [(year: Int, holidays: [Holiday])] = [
    // 国办发明电〔2024〕12号
    (2025, [
        Holiday("元旦", "01-01", "01-01"),
        Holiday("春节", "01-28", "02-04", ["01-26", "02-08"]),
        Holiday("清明节", "04-04", "04-06"),
        Holiday("劳动节", "05-01", "05-05", ["04-27"]),
        Holiday("端午节", "05-31", "06-02"),
        Holiday("国庆节、中秋节", "10-01", "10-08", ["09-28", "10-11"]),
    ]),
    // 国办发明电〔2025〕7号
    (2026, [
        Holiday("元旦", "01-01", "01-03", ["01-04"]),
        Holiday("春节", "02-15", "02-23", ["02-14", "02-28"]),
        Holiday("清明节", "04-04", "04-06"),
        Holiday("劳动节", "05-01", "05-05", ["05-09"]),
        Holiday("端午节", "06-19", "06-21"),
        Holiday("中秋节", "09-25", "09-27"),
        Holiday("国庆节", "10-01", "10-07", ["09-20", "10-10"]),
    ]),
    // 国办发明电〔2026〕10号
    (2027, [
        Holiday("元旦", "01-01", "01-03"),
        Holiday("春节", "02-05", "02-13", ["01-31", "02-14"]),
        Holiday("清明节", "04-03", "04-05"),
        Holiday("劳动节", "05-01", "05-05", ["05-08"]),
        Holiday("端午节", "06-09", "06-09"),
        Holiday("中秋节", "09-15", "09-15"),
        Holiday("国庆节", "10-01", "10-07", ["09-26", "10-09"]),
    ]),
]

/// The years the app knows the schedule for.
public var holidayYears: [Int] { holidaySchedules.map(\.year) }

/// A day the schedule says something about: off for `name`, or a weekend
/// day worked in exchange for it.
public struct HolidayDay: Sendable, Hashable {
    public let name: String
    public let off: Bool

    public init(name: String, off: Bool) {
        self.name = name
        self.off = off
    }
}

private let holidayDays: [Day: HolidayDay] = {
    var out: [Day: HolidayDay] = [:]
    for (year, holidays) in holidaySchedules {
        func day(_ md: String) -> Day { Day("\(year)-\(md)")! }
        for h in holidays {
            for d in day(h.from)...day(h.to) {
                out[d] = HolidayDay(name: h.name, off: true)
            }
            for w in h.workdays {
                out[day(w)] = HolidayDay(name: h.name, off: false)
            }
        }
    }
    return out
}()

/// Whether `date` is a public holiday (休) or a weekend day worked (班);
/// nil for an ordinary day or a year without a schedule.
public func holidayOn(_ date: Day) -> HolidayDay? { holidayDays[date] }

/// A working day by the schedule: Monday to Friday unless it's a holiday,
/// and the weekend days worked in exchange. Years without a schedule go by
/// the weekdays alone.
public func isWorkday(_ date: Day) -> Bool {
    guard let h = holidayOn(date) else { return date.weekday <= 5 }
    return !h.off
}
