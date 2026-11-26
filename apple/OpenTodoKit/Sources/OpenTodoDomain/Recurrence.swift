// Repeat rules: the part of iCalendar's RRULE (RFC 5545) a to-do app needs.
// Ported from `app/lib/domain/recurrence.dart`.
//
// A repeating task is one row whose date moves forward each time it is
// completed; the rule says where it moves to. Rules are stored as RRULE
// text (`FREQ=WEEKLY;BYDAY=MO,WE`) so they can be exported to calendars
// later. Parts the rule leaves out (which weekday, which day of the month)
// come from the task's current date, as DTSTART does in iCalendar.
//
// Two Chinese additions: lunar dates, as RFC 7529's `RSCALE=CHINESE`
// (农历每年八月十五), and China's working days, `X-HOLIDAYS=CN` on a
// Monday-to-Friday rule (法定工作日), which an older app reads as plain
// weekdays.
//
// One addition of the Swift version, not in the Dart one: 艾宾浩斯记忆法
// (spaced review by the forgetting curve), `X-EBBINGHAUS`; see
// `ebbinghausReviewDays` below.
//
// Dart → Swift: `RepeatRule.tryParse(text)` keeps its name; `toString()` is
// `description` (the RRULE text); `copyWith` is plain mutation of a copy
// (the fields are `var`s); `RepeatFrom` is the enum in `Models.swift`.

public enum Freq: String, Sendable, Hashable, CaseIterable {
    case daily, weekly, monthly, yearly
}

/// The nth weekday of a month (n = -1 for the last), such as the second
/// Tuesday. Dart's `({int n, int weekday})`.
public struct NthWeekday: Sendable, Hashable {
    public var n: Int
    /// 1 = Monday … 7 = Sunday.
    public var weekday: Int

    public init(n: Int, weekday: Int) {
        self.n = n
        self.weekday = weekday
    }
}

private let dayCodes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
private let workdayNumbers = [1, 2, 3, 4, 5]
private let weekendNumbers = [6, 7]

public struct RepeatRule: Sendable, Hashable, CustomStringConvertible {
    public var freq: Freq

    /// Every `interval` days / weeks / months / years.
    public var interval: Int

    /// WEEKLY: 1 = Monday … 7 = Sunday, sorted. Empty: the task's weekday.
    public var weekdays: [Int]

    /// MONTHLY / YEARLY: days of the month, -1 for the last. Empty: the
    /// task's day. Months without that day are skipped, as in iCalendar.
    public var monthDays: [Int]

    /// MONTHLY / YEARLY: the nth weekday of the month.
    public var nthWeekday: NthWeekday?

    /// YEARLY: 1–12. Nil: the task's month.
    public var month: Int?

    /// Last date the series may land on, inclusive.
    public var until: Day?

    /// Occurrences left, the current one included. Each completion uses one up.
    public var count: Int?

    /// MONTHLY / YEARLY by the lunar calendar: `month` and `monthDays` are
    /// lunar, leap months count as months for MONTHLY, and a thirtieth in a
    /// month of 29 days falls back to the 29th (SKIP=BACKWARD), so 腊月三十
    /// is always 除夕.
    public var lunar: Bool

    /// Monday to Friday as China's holiday schedule shifts them: holidays
    /// skipped, weekend days worked in exchange added (`Holidays.swift`).
    public var chinaHolidays: Bool

    /// 艾宾浩斯记忆法: how many sessions of the series are done before the
    /// task's current date (0: the current one is the first study, k ≥ 1:
    /// it is the kth review). Nil for every other rule. Make one with
    /// `RepeatRule.ebbinghaus(round:)`, which keeps `freq`, `interval` and
    /// `count` in step with it; see `ebbinghausReviewDays`.
    public var ebbinghausRound: Int?

    public init(
        _ freq: Freq,
        interval: Int = 1,
        weekdays: [Int] = [],
        monthDays: [Int] = [],
        nthWeekday: NthWeekday? = nil,
        month: Int? = nil,
        until: Day? = nil,
        count: Int? = nil,
        lunar: Bool = false,
        chinaHolidays: Bool = false,
        ebbinghausRound: Int? = nil
    ) {
        self.freq = freq
        self.interval = interval
        self.weekdays = weekdays
        self.monthDays = monthDays
        self.nthWeekday = nthWeekday
        self.month = month
        self.until = until
        self.count = count
        self.lunar = lunar
        self.chinaHolidays = chinaHolidays
        self.ebbinghausRound = ebbinghausRound
    }

    public static let daily = RepeatRule(.daily)
    public static let weekly = RepeatRule(.weekly)
    public static let monthly = RepeatRule(.monthly)
    public static let yearly = RepeatRule(.yearly)
    public static let workdays = RepeatRule(.weekly, weekdays: workdayNumbers)
    public static let weekends = RepeatRule(.weekly, weekdays: weekendNumbers)
    public static let statutoryWorkdays = RepeatRule(.weekly, weekdays: workdayNumbers, chinaHolidays: true)

    /// 艾宾浩斯记忆法 from the first study on.
    public static let ebbinghaus = RepeatRule.ebbinghaus(round: 0)

    /// 艾宾浩斯记忆法 with `round` sessions done (clamped to the series).
    /// The RRULE an older app reads as plain FREQ=DAILY: the INTERVAL to
    /// the next review and a COUNT of the sessions left, current included.
    public static func ebbinghaus(round: Int) -> RepeatRule {
        let k = min(max(round, 0), ebbinghausReviewDays.count)
        return RepeatRule(
            .daily,
            interval: ebbinghausGap(k) ?? 1,
            count: ebbinghausReviewDays.count + 1 - k,
            ebbinghausRound: k
        )
    }

    /// 农历每年 on `date`'s lunar month and day; nil outside the lunar table.
    public static func lunarYearlyOn(_ date: Day) -> RepeatRule? {
        toLunar(date).map { RepeatRule(.yearly, monthDays: [$0.day], month: $0.month, lunar: true) }
    }

    /// 农历每月 on `date`'s lunar day.
    public static func lunarMonthlyOn(_ date: Day) -> RepeatRule? {
        toLunar(date).map { RepeatRule(.monthly, monthDays: [$0.day], lunar: true) }
    }

    /// Nil for empty or unusable text (an unknown FREQ, say, from a newer
    /// app). Parts it doesn't know are ignored.
    public static func tryParse(_ text: String?) -> RepeatRule? {
        guard let text else { return nil }
        var s = trimmed(text)
        if s.uppercased().hasPrefix("RRULE:") { s = String(s.dropFirst(6)) }
        if s.isEmpty { return nil }
        var parts: [String: String] = [:]
        for p in s.split(separator: ";", omittingEmptySubsequences: false) {
            if let i = p.firstIndex(of: "="), i > p.startIndex {
                parts[trimmed(p[..<i]).uppercased()] = trimmed(p[p.index(after: i)...])
            }
        }
        let freq: Freq? = switch parts["FREQ"]?.uppercased() {
        case "DAILY": .daily
        case "WEEKLY": .weekly
        case "MONTHLY": .monthly
        case "YEARLY": .yearly
        default: nil
        }
        guard let freq else { return nil }
        // Everything else in an Ebbinghaus rule follows from its round; one
        // that isn't a round of the series is ignored, leaving the rule an
        // older app would read.
        if let k = parseInt(parts["X-EBBINGHAUS"] ?? ""), (0...ebbinghausReviewDays.count).contains(k) {
            return .ebbinghaus(round: k)
        }
        let interval = parseInt(parts["INTERVAL"] ?? "") ?? 1
        let count = parseInt(parts["COUNT"] ?? "").flatMap { $0 > 0 ? $0 : nil }
        let until = parseUntil(parts["UNTIL"])
        let rscale = parts["RSCALE"]?.uppercased()
        // Another calendar (Hebrew, say) would put the dates elsewhere.
        if let rscale, rscale != "GREGORIAN", rscale != "CHINESE" { return nil }
        let lunar = rscale == "CHINESE" && (freq == .monthly || freq == .yearly)
        if parts["X-HOLIDAYS"]?.uppercased() == "CN" {
            return RepeatRule(.weekly, weekdays: workdayNumbers, until: until, count: count, chinaHolidays: true)
        }

        var weekdays = Set<Int>()
        var nth: NthWeekday?
        for d in (parts["BYDAY"] ?? "").split(separator: ",", omittingEmptySubsequences: false) {
            let code = trimmed(d).uppercased()
            guard code.count >= 2, let wd = dayCodes.firstIndex(of: String(code.suffix(2))).map({ $0 + 1 }) else { continue }
            let prefix = code.dropLast(2)
            if prefix.isEmpty {
                weekdays.insert(wd)
                continue
            }
            // [+-]?\d{1,2}
            let digits = prefix.first == "+" || prefix.first == "-" ? prefix.dropFirst() : prefix
            guard (1...2).contains(digits.count), digits.allSatisfy(\.isASCIIDigitChar), let n = Int(prefix) else { continue }
            if n != 0 && n >= -5 && n <= 5 && nth == nil { nth = NthWeekday(n: n, weekday: wd) }
        }
        var monthDays = Set<Int>()
        for d in (parts["BYMONTHDAY"] ?? "").split(separator: ",", omittingEmptySubsequences: false) {
            if let n = parseInt(trimmed(d)), n != 0, n >= -1, n <= (lunar ? 30 : 31) { monthDays.insert(n) }
        }
        // A leap month (6L) is taken as the month it repeats.
        let firstMonth = (parts["BYMONTH"]?.split(separator: ",", omittingEmptySubsequences: false).first).map(String.init) ?? ""
        let month = parseInt(firstMonth.uppercased().replacingOccurrences(of: "L", with: ""))
        let byMonthDay = freq == .monthly || freq == .yearly
        return RepeatRule(
            freq,
            interval: max(interval, 1),
            weekdays: freq == .weekly ? weekdays.sorted() : [],
            monthDays: byMonthDay ? monthDays.sorted(by: monthDayOrder) : [],
            nthWeekday: byMonthDay && !lunar ? nth : nil,
            month: freq == .yearly ? month.flatMap { (1...12).contains($0) ? $0 : nil } : nil,
            until: until,
            count: count,
            lunar: lunar
        )
    }

    /// `YYYYMMDD` at the start of UNTIL (a time after it is ignored); the
    /// parts roll over like Dart's `DateTime`.
    private static func parseUntil(_ s: String?) -> Day? {
        guard let s else { return nil }
        let digits = s.prefix(8)
        guard digits.count == 8, digits.allSatisfy(\.isASCIIDigitChar) else { return nil }
        let a = Array(digits)
        return Day(Int(String(a[0..<4]))!, Int(String(a[4..<6]))!, Int(String(a[6..<8]))!)
    }

    /// RRULE text, parts in a fixed order so equal rules give equal text.
    public var description: String {
        if let k = ebbinghausRound {
            let r = RepeatRule.ebbinghaus(round: k)
            return "FREQ=DAILY" + (r.interval > 1 ? ";INTERVAL=\(r.interval)" : "")
                + ";X-EBBINGHAUS=\(r.ebbinghausRound!);COUNT=\(r.count!)"
        }
        var parts = lunar ? ["RSCALE=CHINESE"] : []
        parts.append("FREQ=\(freq.rawValue.uppercased())")
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if let month { parts.append("BYMONTH=\(month)") }
        if !monthDays.isEmpty { parts.append("BYMONTHDAY=" + monthDays.map(String.init).joined(separator: ",")) }
        if !weekdays.isEmpty {
            parts.append("BYDAY=" + weekdays.map { dayCodes[$0 - 1] }.joined(separator: ","))
        } else if let nth = nthWeekday {
            parts.append("BYDAY=\(nth.n)\(dayCodes[nth.weekday - 1])")
        }
        if chinaHolidays { parts.append("X-HOLIDAYS=CN") }
        if lunar { parts.append("SKIP=BACKWARD") }
        if let until { parts.append("UNTIL=" + until.key.replacingOccurrences(of: "-", with: "")) }
        if let count { parts.append("COUNT=\(count)") }
        return parts.joined(separator: ";")
    }

    /// Equal rules are those with the same text.
    public static func == (lhs: RepeatRule, rhs: RepeatRule) -> Bool { lhs.description == rhs.description }
    public func hash(into hasher: inout Hasher) { hasher.combine(description) }

    /// The rule without its end (until / count).
    public var open: RepeatRule {
        var r = self
        r.until = nil
        r.count = nil
        return r
    }

    /// The same series one session on: an Ebbinghaus rule's next round.
    /// Other rules count down (`count`) instead.
    fileprivate var nextRound: RepeatRule {
        ebbinghausRound.map { .ebbinghaus(round: $0 + 1) } ?? self
    }

    fileprivate var usesTaskDate: Bool {
        if chinaHolidays { return false }
        if ebbinghausRound != nil { return true }
        return switch freq {
        case .daily: true
        case .weekly: weekdays.isEmpty
        case .monthly, .yearly: monthDays.isEmpty && nthWeekday == nil
        }
    }
}

// MARK: - 艾宾浩斯记忆法

/// When an Ebbinghaus series reviews, in days after the first study: the
/// schedule usually given for the forgetting curve (艾宾浩斯遗忘曲线) at the
/// scale of days, 第1、2、4、7、15天, 一个月, 三个月, 半年. After the last
/// review the series ends.
///
/// Stored as `FREQ=DAILY;INTERVAL=<gap>;X-EBBINGHAUS=<rounds done>;COUNT=<left>`
/// (`FREQ=DAILY;X-EBBINGHAUS=0;COUNT=9` for a new one). The Dart version
/// ignores parts it doesn't know, so it reads this as a daily rule whose
/// next date is the next review and which ends after as many sessions; on
/// completing it there, it writes back a plain daily rule (it doesn't keep
/// `X-EBBINGHAUS`), and the series goes on from there as that.
public let ebbinghausReviewDays = [1, 2, 4, 7, 15, 30, 90, 180]

/// Days from session `round` (0 the study, k the kth review) to the next;
/// nil after the last review.
func ebbinghausGap(_ round: Int) -> Int? {
    guard round >= 0, round < ebbinghausReviewDays.count else { return nil }
    return ebbinghausReviewDays[round] - (round == 0 ? 0 : ebbinghausReviewDays[round - 1])
}

/// -1 (the last day) after every other day.
private func monthDayOrder(_ a: Int, _ b: Int) -> Bool { (a < 0 ? 99 : a) < (b < 0 ? 99 : b) }

/// Whitespace trimmed from both ends, as Dart's `String.trim`.
private func trimmed(_ s: some StringProtocol) -> String {
    String(s).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// An optionally signed decimal integer, surrounding whitespace allowed;
/// what `int.tryParse` accepts in RRULE text.
private func parseInt(_ s: String) -> Int? { Int(trimmed(s)) }

extension Character {
    fileprivate var isASCIIDigitChar: Bool { ("0"..."9").contains(self) }
}

/// Days in `month` of `year`; `month` may be outside 1–12 and rolls over.
public func daysInMonth(_ year: Int, _ month: Int) -> Int { Day(year, month, 1).daysInMonth }

/// The `n`th `weekday` of a month (n = -1 for the last), or nil if the
/// month hasn't got one (a fifth Monday, say).
public func nthWeekdayOfMonth(_ year: Int, _ month: Int, _ n: Int, _ weekday: Int) -> Day? {
    let lastDay = daysInMonth(year, month)
    if n > 0 {
        let first = Day(year, month, 1)
        let d = 1 + floorMod(weekday - first.weekday, 7) + (n - 1) * 7
        return d <= lastDay ? Day(year, month, d) : nil
    }
    let last = Day(year, month, lastDay)
    let d = lastDay - floorMod(last.weekday - weekday, 7) + (n + 1) * 7
    return d >= 1 ? Day(year, month, d) : nil
}

/// Dates the rule allows in one month, in order. `anchor` fills in whatever
/// the rule leaves out. `month` may overflow (13 is next January).
private func monthCandidates(_ r: RepeatRule, _ year: Int, _ month: Int, _ anchor: Day) -> [Day] {
    let ym = Day(year, month, 1)
    let (y, m, _) = ym.parts
    if let nth = r.nthWeekday {
        return nthWeekdayOfMonth(y, m, nth.n, nth.weekday).map { [$0] } ?? []
    }
    let last = ym.daysInMonth
    let days = r.monthDays.isEmpty ? [anchor.day] : r.monthDays
    return days.compactMap { d -> Day? in
        if d == -1 { return Day(y, m, last) }
        return d <= last ? Day(y, m, d) : nil
    }.sorted()
}

/// The day `d` of a lunar month: -1 or a thirtieth it hasn't got is its
/// last.
private func lunarDay(_ m: LunarMonth, _ d: Int) -> Day {
    m.start + ((d == -1 || d > m.length ? m.length : d) - 1)
}

private func lunarStepAfter(_ r: RepeatRule, _ anchor: Day) -> Day? {
    guard let from = toLunar(anchor) else { return nil }
    let days = r.monthDays.isEmpty ? [from.day] : r.monthDays
    if r.freq == .monthly {
        // The lunar months from `from`'s on, leap months included, to the
        // end of the table.
        var started = false
        var i = 0
        var y = from.year
        while true {
            let months = lunarMonths(y)
            if months.isEmpty { return nil }
            for m in months {
                started = started || (m.month == from.month && m.leap == from.leap)
                guard started else { continue }
                defer { i += 1 }
                if i % r.interval != 0 { continue }
                for d in days.map({ lunarDay(m, $0) }).sorted() where d > anchor { return d }
            }
            y += 1
        }
    }
    let month = r.month ?? from.month
    var y = from.year
    while true {
        guard let m = lunarMonths(y).first(where: { $0.month == month && !$0.leap }) else { return nil } // past the table
        for d in days.map({ lunarDay(m, $0) }).sorted() where d > anchor { return d }
        y += r.interval
    }
}

/// The first date after `anchor` the rule lands on, ignoring its end. The
/// anchor also fixes the phase: with an interval of two, which weeks count.
private func stepAfter(_ r: RepeatRule, _ anchor: Day) -> Day? {
    if let k = r.ebbinghausRound { return ebbinghausGap(k).map { anchor + $0 } }
    if r.chinaHolidays {
        var d = anchor + 1
        for _ in 0..<400 {
            if isWorkday(d) { return d }
            d += 1
        }
        return nil
    }
    if r.lunar { return lunarStepAfter(r, anchor) }
    switch r.freq {
    case .daily:
        return anchor + r.interval
    case .weekly:
        let days = r.weekdays.isEmpty ? [anchor.weekday] : r.weekdays
        let monday = anchor.startOfWeek
        for weeks in [0, r.interval] {
            for wd in days {
                let d = monday + (weeks * 7 + wd - 1)
                if d > anchor { return d }
            }
        }
        return nil
    case .monthly:
        // A bound in case the rule names a day no month has.
        for k in stride(from: 0, through: 1200, by: r.interval) {
            for d in monthCandidates(r, anchor.year, anchor.month + k, anchor) where d > anchor { return d }
        }
        return nil
    case .yearly:
        let month = r.month ?? anchor.month
        for k in stride(from: 0, through: 400, by: r.interval) {
            // monthCandidates skips Feb 29 in other years, as iCalendar does.
            for d in monthCandidates(r, anchor.year + k, month, anchor) where d.year == anchor.year + k && d > anchor {
                return d
            }
        }
        return nil
    }
}

/// The occurrence after `date`, or nil when the series has ended there.
public func nextOccurrence(_ rule: RepeatRule, _ date: Day) -> Day? {
    if let count = rule.count, count <= 1 { return nil }
    guard let next = stepAfter(rule, date) else { return nil }
    if let until = rule.until, next > until { return nil }
    return next
}

/// The occurrences after `date`, in order, as long as the series runs: the
/// dates a calendar shows ahead of a repeating task. `rule`'s count
/// includes `date` itself. Lazy, and possibly long (a daily rule runs for
/// centuries): take what you need with `prefix`.
public func occurrencesAfter(_ rule: RepeatRule, _ date: Day) -> some Sequence<Day> {
    AnySequence { () -> AnyIterator<Day> in
        var left = rule.count
        var at = date
        var current = rule
        return AnyIterator {
            if let l = left, l <= 1 { return nil }
            guard let next = stepAfter(current, at) else { return nil }
            if let until = rule.until, next > until { return nil }
            if let l = left { left = l - 1 }
            at = next
            current = current.nextRound
            return next
        }
    }
}

/// Where a repeating task goes when one occurrence is done or skipped.
public struct RepeatAdvance: Sendable, Hashable {
    /// The task's new date.
    public let date: Day
    /// The rule to store with it: its count, if it has one, is used up by
    /// the occurrences passed over.
    public let rule: RepeatRule

    public init(_ date: Day, _ rule: RepeatRule) {
        self.date = date
        self.rule = rule
    }
}

/// The next date for a repeating task finished (or skipped) on `today`.
///
/// Counting from the due date, the task lands on the first occurrence after
/// both its date and today, so finishing an overdue daily task doesn't
/// leave another overdue copy behind. Counting from completion, the rule
/// restarts from today. Nil when the series is over.
///
/// An Ebbinghaus series moves one round per completion whichever way it
/// counts, since a review missed still has to be done: the next review is
/// the gap after the due date, or after today when that is later (a review
/// done late counts from the day it was done).
public func advanceRepeat(_ rule: RepeatRule, _ due: Day, today: Day, repeatFrom: RepeatFrom = .dueDate) -> RepeatAdvance? {
    if let k = rule.ebbinghausRound {
        guard let gap = ebbinghausGap(k) else { return nil }
        return RepeatAdvance(max(due, today) + gap, rule.nextRound)
    }
    var left = rule.count
    var date = repeatFrom == .completion ? today : due
    // Generous bound: a daily task years overdue still gets there.
    for _ in 0..<100_000 {
        if let l = left, l <= 1 { return nil }
        guard let next = stepAfter(rule, date) else { return nil }
        if let until = rule.until, next > until { return nil }
        if let l = left { left = l - 1 }
        date = next
        if date > today && date > due {
            var r = rule
            r.count = left
            return RepeatAdvance(date, r)
        }
    }
    return nil
}

/// The first date on or after `from` the rule lands on: where a new task
/// typed as 每周一 starts.
public func firstOccurrence(_ rule: RepeatRule, _ from: Day) -> Day {
    if rule.usesTaskDate { return from }
    return stepAfter(rule.open, from - 1) ?? from
}

// MARK: - Words

private let cnWeekday = ["一", "二", "三", "四", "五", "六", "日"]

private func weekdayList(_ days: [Int]) -> String { days.map { cnWeekday[$0 - 1] }.joined(separator: "、") }

private func nthLabel(_ n: Int) -> String { n == -1 ? "最后一个" : "第\(n)个" }

private func monthDayLabel(_ d: Int) -> String { d == -1 ? "最后一天" : "\(d)日" }

private func sameDays(_ a: [Int], _ b: [Int]) -> Bool { a.count == b.count && a.allSatisfy(b.contains) }

/// 每天 / 每2周的周一、三 / 工作日 / 每月最后一天 / 每年11月15日 …
/// `date` is the task's date, which fills in what the rule leaves out.
public func describeRepeat(_ r: RepeatRule, _ date: Day, repeatFrom: RepeatFrom = .dueDate) -> String {
    let n = r.interval
    let lunarDate = toLunar(date)
    func lunarDays() -> String {
        (r.monthDays.isEmpty ? [lunarDate?.day ?? 1] : r.monthDays)
            .map { $0 == -1 ? "最后一天" : lunarDayName($0) }
            .joined(separator: "、")
    }
    func nthWeekday(_ nth: NthWeekday) -> String { "\(nthLabel(nth.n))周\(cnWeekday[nth.weekday - 1])" }

    if let k = r.ebbinghausRound {
        let total = ebbinghausReviewDays.count
        return k == 0 ? "艾宾浩斯记忆法，复习\(total)次" : "艾宾浩斯记忆法，第\(k)次复习（共\(total)次）"
    }
    let base: String
    if r.chinaHolidays {
        base = "法定工作日"
    } else if r.freq == .monthly && r.lunar {
        base = n == 1 ? "农历每月\(lunarDays())" : "每\(n)个月的农历\(lunarDays())"
    } else if r.freq == .yearly && r.lunar {
        let which = lunarMonthName(r.month ?? lunarDate?.month ?? 1) + lunarDays()
        base = n == 1 ? "农历每年\(which)" : "每\(n)年的农历\(which)"
    } else {
        switch r.freq {
        case .daily:
            base = n == 1 ? "每天" : "每\(n)天"
        case .weekly where n == 1 && sameDays(r.weekdays, workdayNumbers):
            base = "工作日"
        case .weekly where n == 1 && sameDays(r.weekdays, weekendNumbers):
            base = "周末"
        case .weekly where n == 1 && r.weekdays.count == 7:
            base = "每天"
        case .weekly:
            let days = "周" + weekdayList(r.weekdays.isEmpty ? [date.weekday] : r.weekdays)
            base = n == 1 ? "每\(days)" : "每\(n)周的\(days)"
        case .monthly:
            let which = r.nthWeekday.map(nthWeekday)
                ?? (r.monthDays.isEmpty ? [date.day] : r.monthDays).map(monthDayLabel).joined(separator: "、")
            base = n == 1 ? "每月\(which)" : "每\(n)个月的\(which)"
        case .yearly:
            let m = r.month ?? date.month
            let which = r.nthWeekday.map { "\(m)月\(nthWeekday($0))" }
                ?? "\(m)月" + (r.monthDays.isEmpty ? [date.day] : r.monthDays).map(monthDayLabel).joined(separator: "、")
            base = n == 1 ? "每年\(which)" : "每\(n)年的\(which)"
        }
    }
    let from = repeatFrom == .completion ? "（按完成日期）" : ""
    let end = if let u = r.until {
        "，至\(u.year)年\(u.month)月\(u.day)日"
    } else if let c = r.count {
        "，还剩\(c)次"
    } else {
        ""
    }
    return base + from + end
}
