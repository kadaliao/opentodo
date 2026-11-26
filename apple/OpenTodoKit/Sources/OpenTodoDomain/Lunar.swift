// The Chinese lunar calendar (农历), 1900 to 2100: converting dates both
// ways, and the names a calendar shows (初五, 闰六月, 中秋). Ported from
// `app/lib/domain/lunar.dart`.

private let firstLunarYear = 1900
private let lastLunarYear = 2100

/// One entry per lunar year from 1900, copied verbatim from `lunar.dart`
/// (generated from the Chinese calendar of macOS, ICU, China time, by
/// `app/tool/lunar_table.swift`). Bits 17 and up: days from 1 January to
/// the year's 正月初一; bits 13–16: its leap month (0 for none); bits 0–12:
/// its months in order, the leap month after the month it repeats, set for
/// 30 days and clear for 29.
private let lunarYears: [Int] = [
  0x3d16d2, 0x620752, 0x4c0ea5, 0x38b64a, 0x5c064b, 0x440a9b, 0x309556, 0x56056a,
  0x400b59, 0x2a5752, 0x500752, 0x3adb25, 0x600b25, 0x480a4b, 0x32b2ab, 0x580aad,
  0x44056a, 0x2c4b69, 0x520da9, 0x3efd92, 0x640d92, 0x4c0d25, 0x36ba4d, 0x5c0a56,
  0x4602b6, 0x2e95b5, 0x5606d4, 0x400ea9, 0x2c5e92, 0x500e92, 0x3acd26, 0x5e052b,
  0x480a57, 0x32b2b6, 0x580b5a, 0x4406d4, 0x2e6ec9, 0x520749, 0x3cf693, 0x620a93,
  0x4c052b, 0x34ca5b, 0x5a0aad, 0x46056a, 0x309b55, 0x560ba4, 0x400b49, 0x2a5a93,
  0x500a95, 0x38f52d, 0x5e0536, 0x480aad, 0x34b5aa, 0x5805b2, 0x420da5, 0x2e7d4a,
  0x540d4a, 0x3d0a95, 0x600a97, 0x4c0556, 0x36cab5, 0x5a0ad5, 0x4606d2, 0x308ea5,
  0x560ea5, 0x40064a, 0x286c97, 0x4e0a9b, 0x3af55a, 0x5e056a, 0x480b69, 0x34b752,
  0x5a0b52, 0x420b25, 0x2c964b, 0x520a4b, 0x3d14ab, 0x6002ad, 0x4a056d, 0x36cb69,
  0x5c0da9, 0x460d92, 0x309d25, 0x560d25, 0x415a4d, 0x640a56, 0x4e02b6, 0x38c5b5,
  0x5e06d5, 0x480ea9, 0x34be92, 0x5a0e92, 0x440d26, 0x2c6a56, 0x500a57, 0x3d14d6,
  0x62035a, 0x4a06d5, 0x36b6c9, 0x5c0749, 0x460693, 0x2e952b, 0x54052b, 0x3e0a5b,
  0x2a555a, 0x4e056a, 0x38fb55, 0x600ba4, 0x4a0b49, 0x32ba93, 0x580a95, 0x42052d,
  0x2c8aad, 0x500ab5, 0x3d35aa, 0x6205d2, 0x4c0da5, 0x36dd4a, 0x5c0d4a, 0x460c95,
  0x30952e, 0x540556, 0x3e0ab5, 0x2a55b2, 0x5006d2, 0x38cea5, 0x5e0725, 0x48064b,
  0x32ac97, 0x560cab, 0x42055a, 0x2c6ad6, 0x520b69, 0x3d7752, 0x620b52, 0x4c0b25,
  0x36da4b, 0x5a0a4b, 0x4404ab, 0x2ea55b, 0x5405ad, 0x3e0b6a, 0x2a5b52, 0x500d92,
  0x3afd25, 0x5e0d25, 0x480a55, 0x32b4ad, 0x5804b6, 0x4005b5, 0x2c6daa, 0x520ec9,
  0x3f1e92, 0x620e92, 0x4c0d26, 0x36ca56, 0x5a0a57, 0x4404d6, 0x2e86d5, 0x540755,
  0x400749, 0x286e93, 0x4e0693, 0x38f52b, 0x5e052b, 0x460a5b, 0x32b55a, 0x58056a,
  0x420b65, 0x2c974a, 0x520b4a, 0x3d1a95, 0x620a95, 0x4a052d, 0x34caad, 0x5a0ab5,
  0x4605aa, 0x2e8ba5, 0x540da5, 0x400d4a, 0x2a7c95, 0x4e0c96, 0x38f94e, 0x5e0556,
  0x480ab5, 0x32b5b2, 0x5806d2, 0x420ea5, 0x2e8e4a, 0x50068b, 0x3b0c97, 0x6004ab,
  0x4a055b, 0x34cad6, 0x5a0b6a, 0x460752, 0x309725, 0x540b25, 0x3e0a8b, 0x28549b,
  0x4e04ab,
]

/// A day of the lunar calendar. `year` is the Gregorian year its 正月 starts
/// in.
public struct LunarDate: Sendable, Hashable, CustomStringConvertible {
    public let year: Int
    /// 1 (正月) to 12 (腊月).
    public let month: Int
    /// 1 to 30.
    public let day: Int
    /// In the leap month that repeats `month`.
    public let leap: Bool

    public init(_ year: Int, _ month: Int, _ day: Int, leap: Bool = false) {
        self.year = year
        self.month = month
        self.day = day
        self.leap = leap
    }

    public var description: String { "\(year)年\(lunarMonthName(month, leap: leap))\(lunarDayName(day))" }
}

/// A month of the lunar calendar: which, where it starts, how long it is.
public struct LunarMonth: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let leap: Bool
    public let start: Day
    public let length: Int
}

private func lunarNewYear(_ year: Int) -> Day {
    Day(year, 1, 1 + (lunarYears[year - firstLunarYear] >> 17))
}

/// The months of a lunar year in order, the leap one included.
public func lunarMonths(_ year: Int) -> [LunarMonth] {
    guard year >= firstLunarYear, year <= lastLunarYear else { return [] }
    let info = lunarYears[year - firstLunarYear]
    let leapMonth = (info >> 13) & 0xf
    var out: [LunarMonth] = []
    var start = lunarNewYear(year)
    var i = 0
    for m in 1...12 {
        for leap in m == leapMonth ? [false, true] : [false] {
            let length = (info >> i) & 1 == 1 ? 30 : 29
            i += 1
            out.append(LunarMonth(year: year, month: m, leap: leap, start: start, length: length))
            start += length
        }
    }
    return out
}

/// The lunar date of `date`; nil outside 1900–2100.
public func toLunar(_ date: Day) -> LunarDate? {
    var year = min(date.year, lastLunarYear)
    if year >= firstLunarYear && date < lunarNewYear(year) { year -= 1 }
    for m in lunarMonths(year) {
        let offset = m.start.days(to: date)
        if offset >= 0 && offset < m.length {
            return LunarDate(year, m.month, offset + 1, leap: m.leap)
        }
    }
    return nil
}

/// The Gregorian date of a lunar one, or nil if there's no such day (a
/// thirtieth in a month of 29, a leap month that year hasn't got).
/// `clampDay` takes the month's last day instead of a thirtieth it lacks,
/// as a yearly 除夕 (腊月三十) wants.
public func fromLunar(_ year: Int, _ month: Int, _ day: Int, leap: Bool = false, clampDay: Bool = false) -> Day? {
    for m in lunarMonths(year) where m.month == month && m.leap == leap {
        var day = day
        if day > m.length {
            if !clampDay { return nil }
            day = m.length
        }
        return m.start + (day - 1)
    }
    return nil
}

private let lunarMonthChars = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
private let cnDigitChars = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

/// 正月 / 闰六月 / 冬月 / 腊月.
public func lunarMonthName(_ month: Int, leap: Bool = false) -> String {
    "\(leap ? "闰" : "")\(lunarMonthChars[month - 1])月"
}

/// 初一 / 十五 / 二十 / 廿三 / 三十.
public func lunarDayName(_ day: Int) -> String {
    switch day {
    case ...10: "初\(cnDigitChars[day - 1])"
    case ..<20: "十\(cnDigitChars[day - 11])"
    case 20: "二十"
    case ..<30: "廿\(cnDigitChars[day - 21])"
    default: "三十"
    }
}

/// The month number a name like 正 / 八 / 十一 / 冬 / 腊 stands for.
public func lunarMonthNumber(_ name: String) -> Int? {
    switch name {
    case "正", "一": 1
    case "冬", "十一": 11
    case "腊", "十二": 12
    default: cnDigitChars.firstIndex(of: name).map { $0 + 1 }
    }
}

/// The day number a name like 初五 / 十五 / 廿三 / 三十 stands for.
public func lunarDayNumber(_ name: String) -> Int? {
    (1...30).first { lunarDayName($0) == name }
}

/// Under a day's number on the calendar: the month on the first of it
/// (十月), the day otherwise (初五).
public func lunarCalendarLabel(_ d: LunarDate) -> String {
    d.day == 1 ? lunarMonthName(d.month, leap: d.leap) : lunarDayName(d.day)
}

/// The traditional festivals by the lunar calendar: 春节, 元宵, 端午, 七夕,
/// 中秋, 重阳, 腊八, and 除夕 on the last day of the year.
public func lunarFestival(_ date: Day) -> String? {
    guard let d = toLunar(date), !d.leap else { return nil }
    switch (d.month, d.day) {
    case (1, 1): return "春节"
    case (1, 15): return "元宵"
    case (5, 5): return "端午"
    case (7, 7): return "七夕"
    case (8, 15): return "中秋"
    case (9, 9): return "重阳"
    case (12, 8): return "腊八"
    default: break
    }
    let next = toLunar(date + 1)
    return d.month == 12 && next?.month == 1 && next?.day == 1 ? "除夕" : nil
}
