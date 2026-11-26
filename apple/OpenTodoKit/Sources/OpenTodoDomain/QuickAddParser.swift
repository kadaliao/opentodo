// Parses the quick-add line: 明天下午3点开会 #工作 !高 becomes the title 开会,
// tomorrow at 15:00, tag 工作 and high priority; 每周一9点例会 repeats;
// 下午3点到5点 is a span. Matched spans are returned so the input field can
// highlight them as the person types. Ported from
// `app/lib/domain/quick_add_parser.dart`.
//
// Positions: a token's `start` / `end` are **UTF-16 offsets** into the
// input, exactly the numbers the Dart version gives (Dart strings are
// UTF-16). That is what `NSRange`, `NSAttributedString`, `UITextView` /
// `NSTextView` and `TextField` selection bridging use, so the UI can
// highlight with `token.nsRange` directly; for Swift string slicing use
// `token.range(in: input)`, a `Range<String.Index>`. Tokens never split a
// character: they start and end where a regex match does.
//
// The patterns run on `NSRegularExpression` (ICU), which matches on UTF-16
// like Dart's `RegExp`. Where ICU and JavaScript regexes differ the
// patterns spell out the JavaScript meaning: `[0-9]` for `\d` (ICU's `\d`
// also takes full-width digits) and `(?![A-Za-z0-9_])` for the `\b` after
// am/pm (ICU counts 汉字 as word characters).

import Foundation

public enum QuickAddTokenKind: String, Sendable, Hashable {
    case date, time, tag, priority, `repeat`
}

public struct QuickAddToken: Sendable, Hashable, CustomStringConvertible {
    /// UTF-16 offset of the first unit, as in Dart.
    public let start: Int
    /// UTF-16 offset just past the last unit.
    public let end: Int
    public let kind: QuickAddTokenKind

    public init(_ start: Int, _ end: Int, _ kind: QuickAddTokenKind) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    /// The same span as an `NSRange` (UTF-16), for attributed strings.
    public var nsRange: NSRange { NSRange(location: start, length: end - start) }

    /// The span in `input` (the string that was parsed) as string indices.
    public func range(in input: String) -> Range<String.Index> {
        String.Index(utf16Offset: start, in: input)..<String.Index(utf16Offset: end, in: input)
    }

    public var description: String { "\(kind)[\(start),\(end))" }
}

public struct QuickAddResult: Sendable, Hashable {
    public let title: String
    /// For a repeating task without a date of its own, its first occurrence.
    public let date: Day?
    /// Minutes after midnight.
    public let time: Int?
    /// Minutes from `time` to the end of a span (下午3点到5点: 120).
    public let duration: Int?
    public let tags: [String]
    public let priority: Priority?
    /// In the order they appear in the input.
    public let tokens: [QuickAddToken]
    public let `repeat`: RepeatRule?
}

// MARK: - Regex plumbing

/// A compiled pattern. `NSRegularExpression` is immutable and safe to share
/// across threads.
private struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func allMatches(_ s: String) -> [Match] {
        let ns = s as NSString
        return regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { Match(result: $0, text: ns) }
    }

    func firstMatch(_ s: String) -> Match? {
        let ns = s as NSString
        return regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)).map { Match(result: $0, text: ns) }
    }

    /// A match starting exactly at `from` (Dart's `matchAsPrefix`); the
    /// pattern still sees the text around it.
    func matchAsPrefix(_ s: String, _ from: Int) -> Match? {
        let ns = s as NSString
        guard from <= ns.length else { return nil }
        return regex.firstMatch(
            in: s, options: [.anchored, .withTransparentBounds, .withoutAnchoringBounds],
            range: NSRange(location: from, length: ns.length - from)
        ).map { Match(result: $0, text: ns) }
    }

    func hasMatch(_ s: String) -> Bool { firstMatch(s) != nil }

    func replacingAll(_ s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }
}

private struct Match {
    let result: NSTextCheckingResult
    let text: NSString

    var start: Int { result.range.location }
    var end: Int { result.range.location + result.range.length }

    /// Group `i`, nil if it didn't take part (Dart's `m[i]`).
    subscript(_ i: Int) -> String? {
        let r = result.range(at: i)
        return r.location == NSNotFound ? nil : text.substring(with: r)
    }
}

// MARK: - Numbers and dates

private let num = "(?:[0-9]{1,2}|[零〇一二两三四五六七八九十]{1,3})"
private let period = "凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜晚|早|晚"

private let cnDigits: [Character: Int] = [
    "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
    "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
]

/// 3 / 十一 / 二十三 / 两 → Int.
public func parseNumber(_ s: String) -> Int? {
    if let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return n }
    if s.isEmpty { return nil }
    guard let i = s.firstIndex(of: "十") else { return s.count == 1 ? cnDigits[s.first!] : nil }
    let head = s[..<i], rest = s[s.index(after: i)...]
    let tens = head.isEmpty ? 1 : (head.count == 1 ? cnDigits[head.first!] : nil)
    let ones = rest.isEmpty ? 0 : (rest.count == 1 ? cnDigits[rest.first!] : nil)
    guard let tens, let ones else { return nil }
    return tens * 10 + ones
}

private func weekdayNumber(_ s: String) -> Int {
    switch s {
    case "一", "1": 1
    case "二", "2": 2
    case "三", "3": 3
    case "四", "4": 4
    case "五", "5": 5
    case "六", "6": 6
    default: 7 // 日 / 天 / 7
    }
}

/// A date found in the text, plus what it says about the time of day.
private struct DateHit {
    let match: Match
    let date: Day
    var periodHint: String? = nil
    var defaultTime: Int? = nil
}

/// 正 / 八 / 十一 / 冬 / 腊 (the 月 follows).
private let lunarMonthPattern = "十一|十二|正|一|二|三|四|五|六|七|八|九|十|冬|腊"

/// 初五 / 十五 / 二十 / 廿三 / 三十.
private let lunarDayPattern = "初[一二三四五六七八九十]|十[一二三四五六七八九]|二十|廿[一二三四五六七八九]|三十"

/// The next 农历 `month`/`day` from `today` on (its last day for a 三十 the
/// month hasn't got).
private func nextLunar(_ month: Int, _ day: Int, _ today: Day) -> Day {
    firstOccurrence(RepeatRule(.yearly, monthDays: [day], month: month, lunar: true), today)
}

private typealias DateRule = @Sendable (Match, Day) -> DateHit?

private let dateRules: [(Pattern, DateRule)] = [
    // 农历八月十五 / 除夕: the next one. Before 八月十五 is read as August.
    (Pattern("农历(\(lunarMonthPattern))月(\(lunarDayPattern))"), { m, today in
        DateHit(match: m, date: nextLunar(lunarMonthNumber(m[1]!)!, lunarDayNumber(m[2]!)!, today))
    }),
    (Pattern("除夕"), { m, today in DateHit(match: m, date: nextLunar(12, 30, today)) }),
    // 2026年11月18日 / 2026-11-18 / 2026/11/18
    (Pattern("([0-9]{4})\\s*[年/\\-.]\\s*([0-9]{1,2})\\s*[月/\\-.]\\s*([0-9]{1,2})\\s*[日号]?"), { m, _ in
        Day.valid(Int(m[1]!)!, Int(m[2]!)!, Int(m[3]!)!).map { DateHit(match: m, date: $0) }
    }),
    // 11月18日 / 十一月十八号: this year, or next year if already past.
    (Pattern("(\(num))\\s*月\\s*(\(num))\\s*[日号]?"), { m, today in
        guard let mo = parseNumber(m[1]!), let day = parseNumber(m[2]!) else { return nil }
        var d = Day.valid(today.year, mo, day)
        if let x = d, x < today { d = Day.valid(today.year + 1, mo, day) }
        return d.map { DateHit(match: m, date: $0) }
    }),
    // 11/18
    (Pattern("(?<![0-9/])([0-9]{1,2})/([0-9]{1,2})(?![0-9/])"), { m, today in
        let mo = Int(m[1]!)!, day = Int(m[2]!)!
        var d = Day.valid(today.year, mo, day)
        if let x = d, x < today { d = Day.valid(today.year + 1, mo, day) }
        return d.map { DateHit(match: m, date: $0) }
    }),
    (Pattern("大后天|后天|明天|明日|明儿|今天|今日|今晚|今早|明晚|明早"), { m, today in
        switch m[0]! {
        case "今晚": DateHit(match: m, date: today, periodHint: "晚上", defaultTime: 20 * 60)
        case "今早": DateHit(match: m, date: today, periodHint: "早上", defaultTime: 8 * 60)
        case "明晚": DateHit(match: m, date: today + 1, periodHint: "晚上", defaultTime: 20 * 60)
        case "明早": DateHit(match: m, date: today + 1, periodHint: "早上", defaultTime: 8 * 60)
        case "明天", "明日", "明儿": DateHit(match: m, date: today + 1)
        case "后天": DateHit(match: m, date: today + 2)
        case "大后天": DateHit(match: m, date: today + 3)
        default: DateHit(match: m, date: today)
        }
    }),
    // 周五 / 下周一 / 这周三 / 下下周二 / 星期天
    (Pattern("(下下|下个?|这个?|本|上个?)?(?:周|星期|礼拜)([一二三四五六日天1-7])"), { m, today in
        let wd = weekdayNumber(m[2]!)
        let monday = today.startOfWeek
        let d: Day = switch m[1] {
        case nil: today + floorMod(wd - today.weekday, 7)
        case "这", "这个", "本": monday + (wd - 1)
        case "下下": monday + (14 + wd - 1)
        case "上", "上个": monday + (-7 + wd - 1)
        default: monday + (7 + wd - 1)
        }
        return DateHit(match: m, date: d)
    }),
    // 3天后 / 两周后 / 1个月以后
    (Pattern("(\(num))\\s*(天|个?星期|周|个?月)\\s*(?:后|之后|以后)"), { m, today in
        guard let n = parseNumber(m[1]!) else { return nil }
        let unit = m[2]!
        if unit.hasSuffix("月") {
            // Rolls over like Dart's DateTime(y, m + n, d): 1月31日 + 1 → 3月3日.
            return DateHit(match: m, date: Day(today.year, today.month + n, today.day))
        }
        return DateHit(match: m, date: today + (unit == "天" ? n : n * 7))
    }),
    // 周末 / 下周末 → Saturday
    (Pattern("(下个?)?周末"), { m, today in
        let sat = today.startOfWeek + 5
        if m[1] != nil { return DateHit(match: m, date: sat + 7) }
        // On a Sunday, 周末 is today.
        return DateHit(match: m, date: sat < today ? today : sat)
    }),
    // 下周 alone → next Monday
    (Pattern("下个?(?:周|星期|礼拜)(?![一二三四五六日天1-7末])"), { m, today in
        DateHit(match: m, date: today.startOfWeek + 7)
    }),
    // 20号: this month, or next month if already past.
    (Pattern("(?<![0-9])([0-9]{1,2})\\s*号"), { m, today in
        let day = Int(m[1]!)!
        var d = Day.valid(today.year, today.month, day)
        if let x = d, x < today {
            // The next month that has the day; December rolls into January.
            // (The Dart version doesn't roll over, so in December it finds
            // no date there.)
            func inMonth(_ k: Int) -> Day? {
                let first = Day(today.year, today.month + k, 1)
                return Day.valid(first.year, first.month, day)
            }
            d = inMonth(1) ?? inMonth(2)
        }
        return d.map { DateHit(match: m, date: $0) }
    }),
]

// MARK: - Repeats

private let weekdayChars = "一二三四五六日天1-7"
private let weekdayChar = Pattern("[\(weekdayChars)]")

private typealias RepeatRuleMaker = @Sendable (Match) -> RepeatRule?

/// 每天 / 每3天 / 每周一、三 / 每两周 / 工作日 / 每月15号 / 每月最后一天 / 每年3月8日 …
private let repeatRules: [(Pattern, RepeatRuleMaker)] = [
    // 艾宾浩斯 / 按艾宾浩斯记忆法 / 记忆曲线 / 遗忘曲线 (Swift version only;
    // see `ebbinghausReviewDays`). 复习 after it stays in the title.
    (Pattern("(?:按照?)?(?:艾宾浩斯(?:记忆法|遗忘曲线|记忆曲线|曲线)?|记忆曲线|遗忘曲线)"), { _ in .ebbinghaus }),
    // By the lunar calendar, before 每年 and 每月 take the words.
    (Pattern("(?:每年农历|农历每年)(\(lunarMonthPattern))月(\(lunarDayPattern))"), { m in
        RepeatRule(.yearly, monthDays: [lunarDayNumber(m[2]!)!], month: lunarMonthNumber(m[1]!), lunar: true)
    }),
    (Pattern("每年除夕"), { _ in RepeatRule(.yearly, monthDays: [30], month: 12, lunar: true) }),
    (Pattern("(?:每月农历|农历每月)(\(lunarDayPattern))"), { m in
        RepeatRule(.monthly, monthDays: [lunarDayNumber(m[1]!)!], lunar: true)
    }),
    // Always with 每, so 工作日志 or 天天向上 stay plain words.
    (Pattern("每个?法定工作日"), { _ in .statutoryWorkdays }),
    (Pattern("每天|每日"), { _ in .daily }),
    (Pattern("每(\(num))天"), { m in
        parseNumber(m[1]!).flatMap { $0 > 0 ? RepeatRule(.daily, interval: $0) : nil }
    }),
    (Pattern("每个?工作日"), { _ in .workdays }),
    (Pattern("每个?周末"), { _ in .weekends }),
    // 每周一 / 每周一三五 / 每周二、四 / 每个星期六
    (Pattern("每个?(?:周|星期|礼拜)([\(weekdayChars)](?:[、,，和及与]?[\(weekdayChars)])*)"), { m in
        let days = Set(m[1]!.map(String.init).filter(weekdayChar.hasMatch).map(weekdayNumber)).sorted()
        return RepeatRule(.weekly, weekdays: days)
    }),
    (Pattern("每(\(num))个?(?:周|星期|礼拜)"), { m in
        parseNumber(m[1]!).flatMap { $0 > 0 ? RepeatRule(.weekly, interval: $0) : nil }
    }),
    (Pattern("每个?(?:周|星期|礼拜)"), { _ in .weekly }),
    (Pattern("每个?月(?:的)?最后一天"), { _ in RepeatRule(.monthly, monthDays: [-1]) }),
    (Pattern("每个?月(?:的)?(\(num))\\s*[号日]"), { m in
        parseNumber(m[1]!).flatMap { (1...31).contains($0) ? RepeatRule(.monthly, monthDays: [$0]) : nil }
    }),
    (Pattern("每(\(num))个月"), { m in
        parseNumber(m[1]!).flatMap { $0 > 0 ? RepeatRule(.monthly, interval: $0) : nil }
    }),
    (Pattern("每个?月"), { _ in .monthly }),
    (Pattern("每年(?:的)?(\(num))\\s*月\\s*(\(num))\\s*[日号]?"), { m in
        guard let mo = parseNumber(m[1]!), let day = parseNumber(m[2]!), Day.valid(2028, mo, day) != nil else { return nil }
        return RepeatRule(.yearly, monthDays: [day], month: mo)
    }),
    (Pattern("每年"), { _ in .yearly }),
]

// MARK: - Times

private enum TimeRule: CaseIterable {
    case amPm, colon, dian

    var pattern: Pattern {
        switch self {
        case .amPm: timeAmPm
        case .colon: timeColon
        case .dian: timeDian
        }
    }
}

private let timeColon = Pattern("(\(period))?\\s*([0-9]{1,2})\\s*[:：]\\s*([0-9]{2})")
private let timeDian = Pattern(
    "(\(period))?\\s*(\(num))\\s*[点时](?![点儿])(?:\\s*(半|一刻|三刻|([0-9]{1,2})\\s*分?|([零一二三四五六七八九十]{1,3})\\s*分))?"
)
private let timeAmPm = Pattern("([0-9]{1,2})(?::([0-9]{2}))?\\s*(am|pm)(?![A-Za-z0-9_])", caseInsensitive: true)
private let rangeJoin = Pattern("\\s*(?:到|至|-|~|～|—|－)\\s*")
private let tagPattern = Pattern("(?<!\\S)#([^\\s#]+)")
private let priorityPattern = Pattern("(?<!\\S)[!！](高|中|低|[1-3])(?!\\S)")
private let whitespaceRun = Pattern("\\s+")
private let edgePunctuation = Pattern("^[\\s,，、;；]+|[\\s,，、;；]+$")

private func hour24(_ hour: Int, _ period: String?) -> Int? {
    var h = hour
    switch period {
    case "下午", "傍晚", "晚上", "夜里", "夜晚", "晚":
        if h < 12 { h += 12 }
    case "中午":
        if h < 6 { h += 12 }
    case "凌晨":
        if h == 12 { h = 0 }
    case "上午", "早上", "早晨", "早":
        break
    default:
        // No period: 3点开会 means the afternoon.
        if h >= 1 && h <= 6 { h += 12 }
    }
    return h >= 0 && h <= 23 ? h : nil
}

private struct ReadTime {
    let hour: Int
    let minute: Int
    /// What the match named; `ampm` for am/pm, already applied.
    let period: String?
}

/// The hour and minute a time match says, before 上午/下午 is applied.
private func readTime(_ rule: TimeRule, _ m: Match) -> ReadTime? {
    switch rule {
    case .amPm:
        let h = Int(m[1]!)!
        if h > 12 { return nil }
        let pm = m[3]!.lowercased() == "pm"
        return ReadTime(hour: h % 12 + (pm ? 12 : 0), minute: m[2].map { Int($0)! } ?? 0, period: "ampm")
    case .colon:
        return ReadTime(hour: Int(m[2]!)!, minute: Int(m[3]!)!, period: m[1])
    case .dian:
        let raw = parseNumber(m[2]!)
        let min: Int? = switch m[3] {
        case nil: 0
        case "半": 30
        case "一刻": 15
        case "三刻": 45
        default: m[4] != nil ? Int(m[4]!)! : parseNumber(m[5]!)
        }
        guard let raw, let min else { return nil }
        return ReadTime(hour: raw, minute: min, period: m[1])
    }
}

/// The end of 3点到5点, right after the start's match: minutes from the
/// start, and where the text ends. Without 上午/下午 the end is the first
/// reading after the start (上午11点到1点 ends at 13:00); one earlier than
/// the start runs past midnight (晚上10点到凌晨2点).
private func spanEnd(_ masked: String, _ from: Int, _ start: Int) -> (duration: Int, end: Int)? {
    guard let join = rangeJoin.matchAsPrefix(masked, from) else { return nil }
    for rule in TimeRule.allCases {
        guard let m = rule.pattern.matchAsPrefix(masked, join.end) else { continue }
        guard let t = readTime(rule, m), t.minute >= 0, t.minute <= 59 else { return nil }
        let hour: Int? = switch t.period {
        case "ampm": t.hour
        case nil: t.hour <= 23 ? t.hour : nil
        case let p: hour24(t.hour, p)
        }
        guard var h = hour else { return nil }
        if t.period == nil && h < 12 && h * 60 + t.minute <= start { h += 12 }
        var end = h * 60 + t.minute
        if end <= start { end += 24 * 60 }
        let duration = end - start
        if duration <= 0 || duration > 24 * 60 { return nil }
        return (duration, m.end)
    }
    return nil
}

// MARK: - Parsing

/// Reads the quick-add line typed at `now`.
public func parseQuickAdd(_ input: String, now: LocalDateTime) -> QuickAddResult {
    let today = now.day
    var tokens: [QuickAddToken] = []
    var masked = input

    func consume(_ start: Int, _ end: Int, _ kind: QuickAddTokenKind) {
        tokens.append(QuickAddToken(start, end, kind))
        masked = (masked as NSString).replacingCharacters(
            in: NSRange(location: start, length: end - start),
            with: String(repeating: "\u{0}", count: end - start)
        )
    }

    // Tags and priority first, so their text isn't read as a date.
    var tags: [String] = []
    for m in tagPattern.allMatches(masked) {
        tags.append(m[1]!)
        consume(m.start, m.end, .tag)
    }
    var priority: Priority?
    if let pm = priorityPattern.firstMatch(masked) {
        priority = switch pm[1] {
        case "高", "3": .high
        case "中", "2": .medium
        default: .low
        }
        consume(pm.start, pm.end, .priority)
    }

    // Repeats before dates, so 每周一 isn't read as 周一.
    var repeatRule: RepeatRule?
    search: for (pattern, make) in repeatRules {
        for m in pattern.allMatches(masked) {
            if let r = make(m) {
                repeatRule = r
                consume(m.start, m.end, .repeat)
                break search
            }
        }
    }

    var dateHit: DateHit?
    search: for (pattern, rule) in dateRules {
        for m in pattern.allMatches(masked) {
            if let hit = rule(m, today) {
                dateHit = hit
                break search
            }
        }
    }
    if let dateHit { consume(dateHit.match.start, dateHit.match.end, .date) }

    var time: Int?, duration: Int?
    let periodHint = dateHit?.periodHint
    for rule in TimeRule.allCases {
        guard let m = rule.pattern.firstMatch(masked) else { continue }
        let t = readTime(rule, m)
        let h = t.flatMap { $0.period == "ampm" ? $0.hour : hour24($0.hour, $0.period ?? periodHint) }
        if let h, let t, t.minute >= 0, t.minute < 60 {
            let start = h * 60 + t.minute
            time = start
            var end = m.end
            if let span = spanEnd(masked, m.end, start) {
                duration = span.duration
                end = span.end
            }
            consume(m.start, end, .time)
            break
        }
    }

    if time == nil { time = dateHit?.defaultTime }
    var date: Day? = dateHit?.date ?? repeatRule.map { firstOccurrence($0, today) } ?? (time != nil ? today : nil)
    // 每天8点吃药 typed at 10:00 starts tomorrow, not overdue.
    if dateHit == nil, let repeatRule, let time, date == today, time <= now.minuteOfDay {
        date = nextOccurrence(repeatRule, today) ?? date
    }

    tokens.sort { $0.start < $1.start }
    let ns = input as NSString
    var buf = ""
    var pos = 0
    for t in tokens {
        buf += ns.substring(with: NSRange(location: pos, length: t.start - pos))
        buf += " "
        pos = t.end
    }
    buf += ns.substring(from: pos)
    let title = edgePunctuation.replacingAll(whitespaceRun.replacingAll(buf, with: " "), with: "")

    return QuickAddResult(
        title: title,
        date: date,
        time: time,
        duration: duration,
        tags: tags,
        priority: priority,
        tokens: tokens,
        repeat: repeatRule
    )
}
