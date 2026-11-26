// The focus screens' logic, apart from the views so it can be tested: which
// buttons the timer shows, what the ring says, records by day, a record
// typed in by hand, and the ranges of the charts.

import Foundation
import OpenTodoDomain

/// A button under the timer ring.
enum FocusControl: Hashable {
    case start
    case startBreak
    case pause
    case resume
    /// 放弃: ends without finishing.
    case abandon
    /// 结束: a stopwatch's end, or a pomodoro finished early.
    case finish
    case skipBreak

    var title: String {
        switch self {
        case .start: "开始专注"
        case .startBreak: "开始休息"
        case .pause: "暂停"
        case .resume: "继续"
        case .abandon: "放弃"
        case .finish: "结束"
        case .skipBreak: "跳过休息"
        }
    }

    var symbol: String {
        switch self {
        case .start: "play.fill"
        case .startBreak: "cup.and.saucer.fill"
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .abandon: "xmark"
        case .finish: "stop.fill"
        case .skipBreak: "forward.end.fill"
        }
    }
}

/// The buttons for the timer's state: the main one first.
func focusControls(_ t: FocusTimer) -> [FocusControl] {
    switch t.phase {
    case .idle: t.upNext.isBreak ? [.startBreak, .skipBreak] : [.start]
    case .focusing: t.mode == .stopwatch ? [.pause, .finish] : [.pause, .abandon]
    case .paused: t.mode == .stopwatch ? [.resume, .finish] : [.resume, .abandon]
    case .resting: [.skipBreak]
    }
}

/// Applies a button to the timer at `now`; returns the session it recorded.
func applyFocusControl(_ c: FocusControl, to t: inout FocusTimer, at now: Int) -> FocusSession? {
    switch c {
    case .start: t.start(at: now)
    case .startBreak: t.startBreak(at: now)
    case .pause: t.pause(at: now)
    case .resume: t.resume(at: now)
    case .abandon: return t.abandon(at: now)
    case .finish: return t.complete(at: now)
    case .skipBreak: t.skipBreak(at: now)
    }
    return nil
}

/// Over the clock: 专注 / 专注中 / 已暂停 / 短休息 / 长休息 / 休息一下.
func focusPhaseTitle(_ t: FocusTimer) -> String {
    switch t.phase {
    case .idle: t.upNext.isBreak ? "休息一下" : (t.mode == .stopwatch ? "正计时" : "番茄专注")
    case .focusing: "专注中"
    case .paused: "已暂停"
    case .resting(let s): s == .longBreak ? "长休息" : "短休息"
    }
}

/// The ring's number: what's left (or, counting up, what's gone by).
func focusClockSeconds(_ t: FocusTimer, at now: Int) -> Int {
    t.remaining(at: now) ?? t.elapsed(at: now)
}

/// Pomodoros toward the next long break, as dots: done, then to go.
func focusCycleDots(_ t: FocusTimer) -> (done: Int, total: Int) {
    let total = max(t.settings.longBreakEvery, 1)
    return (min(t.cycleCount, total), total)
}

// MARK: - Records

/// Sessions by the day they started, latest day first, each latest first.
func focusRecordDays(_ sessions: [FocusSession], in tz: TimeZone) -> [(day: Day, sessions: [FocusSession])] {
    let live = sessions.filter { $0.deletedAt == nil }
    let byDay = Dictionary(grouping: live) { $0.day(in: tz) }
    return byDay.keys.sorted(by: >).map { d in
        (d, byDay[d]!.sorted { $0.startedAt > $1.startedAt })
    }
}

/// 09:00–09:25.
func focusTimeRange(_ s: FocusSession, in tz: TimeZone) -> String {
    func hm(_ t: LocalDateTime) -> String { (t.hour < 10 ? "0" : "") + "\(t.hour):" + (t.minute < 10 ? "0" : "") + "\(t.minute)" }
    return "\(hm(s.start(in: tz)))–\(hm(s.end(in: tz)))"
}

/// A record typed in by hand (补记): `minutes` from `start` on `day`.
func manualFocusSession(
    day: Day, startMinute: Int, minutes: Int, kind: FocusKind, taskId: String?, note: String,
    in tz: TimeZone, now: Int
) -> FocusSession {
    let start = Int(LocalDateTime(day, minute: startMinute).date(in: tz).timeIntervalSince1970) * 1000
    let m = max(minutes, 1)
    return FocusSession(
        startedAt: start, endedAt: start + m * 60_000, duration: m * 60, kind: kind, completed: true,
        taskId: taskId, note: note, createdAt: now, updatedAt: now
    )
}

/// The session with its tombstone set.
func deletedSession(_ s: FocusSession, now: Int) -> FocusSession {
    var s = s
    s.deletedAt = now
    s.updatedAt = now
    s.dirty = true
    return s
}

// MARK: - Charts

/// The days a focus chart covers: the last 7 days, 8 weeks or 6 months up
/// to `today`.
func focusChartRange(_ bucket: FocusBucket, today: Day) -> (from: Day, through: Day) {
    switch bucket {
    case .day: (today - 6, today)
    case .week: (today.startOfWeek - 7 * 7, today)
    case .month: (today.startOfMonth.addingMonths(-5), today)
    }
}

/// A bar's label: 11/20, 11/16 (a week's Monday), 11月.
func focusBarLabel(_ start: Day, _ bucket: FocusBucket) -> String {
    switch bucket {
    case .day, .week: "\(start.month)/\(start.day)"
    case .month: "\(start.month)月"
    }
}

/// A slice of the distribution with its name.
struct FocusSlice: Hashable, Identifiable {
    var id: String
    var name: String
    var seconds: Int
}

/// Focus per task or per list with names; small ones past the first five
/// go together under 其他.
func focusSlices(_ shares: [FocusShare], name: (String?) -> String, keep: Int = 5) -> [FocusSlice] {
    var out = shares.prefix(keep).map { FocusSlice(id: $0.id ?? "-", name: name($0.id), seconds: $0.seconds) }
    let rest = shares.dropFirst(keep).reduce(0) { $0 + $1.seconds }
    if rest > 0 { out.append(FocusSlice(id: "+", name: "其他", seconds: rest)) }
    return out
}
