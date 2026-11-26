// The countdown screens' logic, apart from the views so it can be tested:
// what a card says, the order of display formats, date text, and the
// editor's draft.

import Foundation
import OpenTodoDomain

/// What a card shows.
struct CountdownCardText: Equatable {
    /// The number and its units, the numbers to be drawn big: "2", "个月",
    /// "22", "天"; or just "今天".
    var runs: [TextRun]
    /// 还有 / 已经 / 已过, nil on the day itself.
    var caption: String?
    /// The day counted to, as text.
    var date: String

    struct TextRun: Equatable, Hashable {
        var text: String
        var isNumber: Bool
    }
}

/// Splits "1年2个月3天" into numbers and units.
func textRuns(_ s: String) -> [CountdownCardText.TextRun] {
    var out: [CountdownCardText.TextRun] = []
    for ch in s {
        let digit = ch.isASCII && ch.isNumber
        if let last = out.last, last.isNumber == digit {
            out[out.count - 1].text.append(ch)
        } else {
            out.append(.init(text: String(ch), isNumber: digit))
        }
    }
    return out
}

func countdownCardText(_ c: Countdown, today: Day, format: CountdownFormat) -> CountdownCardText {
    guard let s = countdownStatus(c, today: today) else {
        return CountdownCardText(runs: [.init(text: "–", isNumber: true)], caption: nil, date: "超出农历范围")
    }
    let text = countdownText(from: today, to: s.target, format: format)
    let caption: String? = s.days == 0 ? nil
        : s.past ? (c.kind == .anniversary ? "已经" : "已过")
        : "还有"
    // 今天 is the number too.
    let runs = s.days == 0 ? [CountdownCardText.TextRun(text: text, isNumber: true)] : textRuns(text)
    return CountdownCardText(runs: runs, caption: caption, date: countdownDateText(c, s.target, today: today))
}

/// The day with its weekday, and the lunar date for a lunar countdown:
/// 2027年2月6日 周六 · 正月初一.
func countdownDateText(_ c: Countdown, _ d: Day, today: Day) -> String {
    let base = dayText(d, today: today)
    guard c.lunar, let l = toLunar(d) else { return base }
    return "\(base) · \(lunarMonthName(l.month, leap: l.leap))\(lunarDayName(l.day))"
}

/// The next format when a card is tapped.
func nextFormat(_ f: CountdownFormat) -> CountdownFormat {
    let all = CountdownFormat.allCases
    return all[(all.firstIndex(of: f)! + 1) % all.count]
}

func repeatText(_ c: Countdown) -> String {
    switch c.repeats {
    case .none: "不重复"
    case .yearly: c.lunar ? "农历每年" : "每年"
    case .monthly: c.lunar ? "农历每月" : "每月"
    }
}

/// 当天 9:00 / 提前1天 9:00.
func countdownReminderText(_ offset: Int) -> String {
    let (days, minute) = countdownReminderParts(offset)
    return (days == 0 ? "当天 " : "提前\(days)天 ") + timeLabel(minute)
}

/// The SF Symbol of a kind (a badge without an emoji).
func countdownSymbol(_ k: CountdownKind) -> String {
    switch k {
    case .countdown: "hourglass"
    case .anniversary: "heart.fill"
    case .birthday: "birthday.cake.fill"
    case .holiday: "party.popper.fill"
    }
}

/// The fields of the countdown editor.
struct CountdownDraft: Hashable {
    var kind: CountdownKind
    var title = ""
    var date: Day
    var lunar = false
    var repeats: CountdownRepeat
    var emoji: String?
    var color: Int? = EfficiencyPalette.colors[0]
    var showInToday = true
    var reminders: [Int] = []
    var pinned = false

    init(kind: CountdownKind, today: Day) {
        self.kind = kind
        date = today
        repeats = kind == .countdown ? .none : .yearly
        reminders = [countdownReminder(daysBefore: kind == .countdown ? 0 : 1, minute: 9 * 60)]
    }

    init(_ c: Countdown) {
        kind = c.kind
        title = c.title
        date = c.date
        lunar = c.lunar
        repeats = c.repeats
        emoji = c.emoji
        color = c.color
        showInToday = c.showInToday
        reminders = c.reminders
        pinned = c.pinnedAt != nil
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A title is needed, and a lunar date must be inside the table.
    var canSave: Bool { !trimmedTitle.isEmpty && (!lunar || toLunar(date) != nil) }

    /// Switching kinds brings the usual repetition along, unless it was
    /// changed by hand.
    mutating func setKind(_ k: CountdownKind) {
        let usual: (CountdownKind) -> CountdownRepeat = { $0 == .countdown ? .none : .yearly }
        if repeats == usual(kind) { repeats = usual(k) }
        kind = k
    }

    func countdown(base: Countdown?, newId: String, now: Int) -> Countdown {
        var c = base ?? Countdown(id: newId, createdAt: now)
        c.kind = kind
        c.title = trimmedTitle
        c.date = date
        c.lunar = lunar
        c.repeats = repeats
        c.emoji = emoji
        c.color = color
        c.showInToday = showInToday
        c.reminders = Array(Set(reminders)).sorted()
        if pinned != (c.pinnedAt != nil) { c.pinnedAt = pinned ? now : nil }
        c.updatedAt = now
        c.dirty = true
        return c
    }
}

/// The countdown pinned or unpinned.
func togglingPin(_ c: Countdown, now: Int) -> Countdown {
    var c = c
    c.pinnedAt = c.pinnedAt == nil ? now : nil
    c.updatedAt = now
    c.dirty = true
    return c
}

func deletedCountdown(_ c: Countdown, now: Int) -> Countdown {
    var c = c
    c.deletedAt = now
    c.updatedAt = now
    c.dirty = true
    return c
}
