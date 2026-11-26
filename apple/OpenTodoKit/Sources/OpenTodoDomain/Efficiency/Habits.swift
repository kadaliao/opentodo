// Habits (习惯打卡): the records and the pure logic for checking in,
// streaks, rates and the calendar. New in the Swift version (roadmap M5);
// there is no Dart code behind it. The data conventions are written up in
// `docs/apple.md` (效率模块).
//
// A `Habit` is what to keep doing and how often; a `HabitCheckin` is what
// happened on one day. A check-in's id is worked out from the habit and the
// day (`HabitCheckin.id(habitId:day:)`), so two devices that check in the
// same day offline end up with one row after syncing (the later write wins).
//
// Days are `Day`s and weeks start on Monday (`Day.startOfWeek`). "Today" is
// passed in, so nothing here depends on the clock or the time zone.

import Foundation

/// Namespace of `HabitCheckin` ids (UUID v5 of `<habitId>/<YYYY-MM-DD>`).
public let habitCheckinNamespace = "c5327d1b-9b1b-4a39-b591-86d48cf93de5"

// MARK: - Model

/// How a day counts as done.
public enum HabitGoalKind: Int, Sendable, Hashable, Codable, CaseIterable {
    /// One check-in finishes the day.
    case once = 0
    /// The day is done once the amount reaches `Habit.goal` (8 杯水).
    case count = 1

    /// Unknown numbers read as `once`.
    public init(from decoder: any Decoder) throws {
        self = HabitGoalKind(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .once
    }
}

/// Which days a habit asks for.
///
/// Stored and synced as text in the style of a task's RRULE:
/// `FREQ=DAILY`, `FREQ=WEEKLY;BYDAY=MO,WE,FR`, `FREQ=WEEKLY;TIMES=3`.
/// Text it can't read is every day.
public enum HabitFrequency: Sendable, Hashable {
    /// Every day.
    case daily
    /// On these weekdays (Monday 1 … Sunday 7). Use `weekdays(_:)`, which
    /// sorts them and drops duplicates and numbers out of range.
    case onWeekdays([Int])
    /// Any days, so many of them each week (1–7).
    case timesPerWeek(Int)

    /// `.onWeekdays` with the days tidied; no valid day means every day.
    public static func weekdays(_ days: some Sequence<Int>) -> HabitFrequency {
        let set = Set(days.filter { (1...7).contains($0) })
        return set.isEmpty || set.count == 7 ? .daily : .onWeekdays(set.sorted())
    }

    private static let codes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    public var rule: String {
        switch self {
        case .daily: "FREQ=DAILY"
        case .onWeekdays(let days): "FREQ=WEEKLY;BYDAY=" + days.map { Self.codes[$0 - 1] }.joined(separator: ",")
        case .timesPerWeek(let n): "FREQ=WEEKLY;TIMES=\(n)"
        }
    }

    public init(rule: String) {
        var parts: [String: String] = [:]
        for p in rule.uppercased().split(separator: ";") {
            let kv = p.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { parts[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces) }
        }
        guard parts["FREQ"] == "WEEKLY" else { self = .daily; return }
        if let t = parts["TIMES"], let n = Int(t) {
            self = n >= 7 ? .daily : .timesPerWeek(max(n, 1))
        } else if let byDay = parts["BYDAY"] {
            self = .weekdays(byDay.split(separator: ",").compactMap { code in
                Self.codes.firstIndex(of: code.trimmingCharacters(in: .whitespaces)).map { $0 + 1 }
            })
        } else {
            self = .daily
        }
    }
}

extension HabitFrequency: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(rule: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rule)
    }
}

/// The part of the day a habit is shown under on the check-in page.
public enum HabitSection: Int, Sendable, Hashable, Codable, CaseIterable {
    case anytime = 0
    case morning = 1
    case afternoon = 2
    case evening = 3

    /// Unknown numbers read as `anytime`.
    public init(from decoder: any Decoder) throws {
        self = HabitSection(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .anytime
    }

    /// The order the page shows them in.
    public static let displayOrder: [HabitSection] = [.morning, .afternoon, .evening, .anytime]

    public var name: String {
        switch self {
        case .anytime: "任意时间"
        case .morning: "上午"
        case .afternoon: "下午"
        case .evening: "晚上"
        }
    }
}

/// A habit (习惯).
public struct Habit: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var emoji: String?
    /// ARGB, as `TaskList.color`.
    public var color: Int?
    public var goalKind: HabitGoalKind
    /// The amount a day needs for a `.count` goal (8); 1 for `.once`.
    public var goal: Double
    /// What one tap adds for a `.count` goal.
    public var step: Double
    /// The unit of `goal` (杯, 公里); empty for `.once`.
    public var unit: String
    public var frequency: HabitFrequency
    /// Minutes after midnight, on each day the habit is due.
    public var reminders: [Int]
    /// The first day it counts from: earlier days are neither due nor missed.
    public var startDate: Day
    public var section: HabitSection
    /// When it was archived (归档), epoch milliseconds: it leaves the
    /// check-in page but keeps its history. Nil while active.
    public var archivedAt: Int?
    public var sortOrder: Double

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    public init(
        id: String,
        name: String = "",
        emoji: String? = nil,
        color: Int? = nil,
        goalKind: HabitGoalKind = .once,
        goal: Double = 1,
        step: Double = 1,
        unit: String = "",
        frequency: HabitFrequency = .daily,
        reminders: [Int] = [],
        startDate: Day = Day(2000, 1, 1),
        section: HabitSection = .anytime,
        archivedAt: Int? = nil,
        sortOrder: Double = 0,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.color = color
        self.goalKind = goalKind
        self.goal = goal
        self.step = step
        self.unit = unit
        self.frequency = frequency
        self.reminders = reminders
        self.startDate = startDate
        self.section = section
        self.archivedAt = archivedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }

    /// What a day needs: `goal` for a count, 1 for a single check-in.
    public var target: Double { goalKind == .count ? max(goal, 0) : 1 }
}

/// What a check-in says about its day.
public enum CheckinStatus: Int, Sendable, Hashable, Codable, CaseIterable {
    /// Something recorded, not (yet) done: 3 of 8 杯.
    case partial = 0
    case done = 1
    /// Given up on that day (放弃): shown as failed, counts as not done.
    case abandoned = 2

    /// Unknown numbers read as `partial`.
    public init(from decoder: any Decoder) throws {
        self = CheckinStatus(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .partial
    }
}

/// One day of one habit (打卡记录).
public struct HabitCheckin: Sendable, Hashable, Codable, Identifiable {
    /// `HabitCheckin.id(habitId:day:)`.
    public var id: String
    public var habitId: String
    public var day: Day
    /// The amount recorded that day (1 for a single check-in).
    public var value: Double
    public var status: CheckinStatus

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    /// `id` defaults to the one worked out from `habitId` and `day`.
    public init(
        id: String? = nil,
        habitId: String,
        day: Day,
        value: Double = 0,
        status: CheckinStatus = .partial,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id ?? HabitCheckin.id(habitId: habitId, day: day)
        self.habitId = habitId
        self.day = day
        self.value = value
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }

    /// The id of `habitId`'s check-in on `day`: UUID v5 of
    /// `<habitId>/<YYYY-MM-DD>` in `habitCheckinNamespace`.
    public static func id(habitId: String, day: Day) -> String {
        uuidV5(namespace: habitCheckinNamespace, name: "\(habitId)/\(day.key)")
    }

    public var isDone: Bool { deletedAt == nil && status == .done }
}

// MARK: - Checking in

/// The check-in after a tap on `day`: a single check-in is done; a count
/// adds `amount` (default `habit.step`) and is done once it reaches the
/// goal. `existing` is that day's row if there is one (a tombstone starts
/// afresh, under the same id). `now` is epoch milliseconds.
public func checkIn(
    _ habit: Habit, on day: Day, existing: HabitCheckin?, amount: Double? = nil, now: Int
) -> HabitCheckin {
    let live = existing.flatMap { $0.deletedAt == nil ? $0 : nil }
    let value = habit.goalKind == .once ? 1 : (live?.value ?? 0) + (amount ?? habit.step)
    return recorded(habit, on: day, existing: existing, value: value, now: now)
}

/// The check-in with the day's amount set to `value` (typed in, or taken
/// back to 0). Done when it reaches the target.
public func setCheckinValue(
    _ habit: Habit, on day: Day, existing: HabitCheckin?, value: Double, now: Int
) -> HabitCheckin {
    recorded(habit, on: day, existing: existing, value: max(value, 0), now: now)
}

/// The check-in that gives up on `day` (放弃), keeping what was recorded.
public func abandonDay(_ habit: Habit, on day: Day, existing: HabitCheckin?, now: Int) -> HabitCheckin {
    var c = base(habit, day, existing, now)
    c.status = .abandoned
    return c
}

private func recorded(_ habit: Habit, on day: Day, existing: HabitCheckin?, value: Double, now: Int) -> HabitCheckin {
    var c = base(habit, day, existing, now)
    c.value = value
    c.status = value > 0 && value >= habit.target ? .done : .partial
    return c
}

private func base(_ habit: Habit, _ day: Day, _ existing: HabitCheckin?, _ now: Int) -> HabitCheckin {
    if var c = existing, c.deletedAt == nil {
        c.updatedAt = now
        c.dirty = true
        return c
    }
    // A fresh row, or a tombstone brought back: same id, so sync merges.
    return HabitCheckin(
        habitId: habit.id, day: day, createdAt: existing?.createdAt ?? now, updatedAt: now,
        serverVersion: existing?.serverVersion ?? 0
    )
}

// MARK: - Days

/// Whether `day` is one the habit asks for: on or after its start, and on
/// one of its weekdays. Every day qualifies for `.timesPerWeek` (any day of
/// the week will do). Archiving doesn't change it.
public func isDue(_ habit: Habit, on day: Day) -> Bool {
    guard day >= habit.startDate else { return false }
    return isScheduled(habit.frequency, day)
}

private func isScheduled(_ f: HabitFrequency, _ day: Day) -> Bool {
    switch f {
    case .daily, .timesPerWeek: true
    case .onWeekdays(let days): days.contains(day.weekday)
    }
}

/// How one day of a habit looks on the calendar and the heat map.
public enum HabitDayState: Sendable, Hashable {
    /// Before the habit started, nothing recorded.
    case beforeStart
    /// Not one of its days (or, for `.timesPerWeek`, a past day left
    /// empty), nothing recorded.
    case notDue
    case done
    /// Some amount recorded, short of the goal; the fraction done, 0..<1.
    case partial(Double)
    case abandoned
    /// A due day gone by with nothing recorded.
    case missed
    /// Today, due, nothing yet.
    case pending
    /// After today.
    case future
}

/// The state of `day`. What was recorded wins over the schedule, so a
/// check-in on a day off still shows as done.
public func dayState(_ habit: Habit, on day: Day, checkin: HabitCheckin?, today: Day) -> HabitDayState {
    if let c = checkin, c.deletedAt == nil {
        switch c.status {
        case .done: return .done
        case .abandoned: return .abandoned
        case .partial where c.value > 0:
            let t = habit.target
            return .partial(t > 0 ? min(c.value / t, 0.999) : 0)
        case .partial: break
        }
    }
    if day < habit.startDate { return .beforeStart }
    if day > today { return .future }
    guard isScheduled(habit.frequency, day) else { return .notDue }
    if day == today { return .pending }
    if case .timesPerWeek = habit.frequency { return .notDue }
    return .missed
}

/// Every day from `from` through `through` with its state, in order (a
/// month view, a heat map). `checkins` may hold other habits' rows.
public func dayStates(
    _ habit: Habit, checkins: [HabitCheckin], from: Day, through: Day, today: Day
) -> [(day: Day, state: HabitDayState)] {
    guard from <= through else { return [] }
    let log = HabitLog(habit, checkins)
    return (from...through).map { ($0, dayState(habit, on: $0, checkin: log.byDay[$0], today: today)) }
}

/// The check-ins of one habit, live ones only, by day.
struct HabitLog {
    var byDay: [Day: HabitCheckin] = [:]

    init(_ habit: Habit, _ checkins: [HabitCheckin]) {
        for c in checkins where c.habitId == habit.id && c.deletedAt == nil {
            // Ids are per day, so at most one; keep the latest edit if not.
            if let old = byDay[c.day], old.updatedAt > c.updatedAt { continue }
            byDay[c.day] = c
        }
    }

    func isDone(_ d: Day) -> Bool { byDay[d]?.status == .done }

    /// Done days, sorted.
    var doneDays: [Day] { byDay.values.filter { $0.status == .done }.map(\.day).sorted() }

    func doneCount(_ from: Day, _ through: Day) -> Int {
        from > through ? 0 : (from...through).count(where: isDone)
    }
}

// MARK: - Streaks and totals

public enum StreakUnit: Sendable, Hashable {
    case days
    /// For `.timesPerWeek`: whole weeks that reached the count.
    case weeks
}

public struct HabitStreak: Sendable, Hashable {
    public var current: Int
    public var longest: Int
    public var unit: StreakUnit

    public init(current: Int, longest: Int, unit: StreakUnit) {
        self.current = current
        self.longest = longest
        self.unit = unit
    }
}

/// The current and the longest streak (连续打卡) as of `today`.
///
/// By day (every day, or set weekdays): a streak is a run of done days in
/// which no due day was left undone. Days off don't break it (and count when
/// checked in anyway); today doesn't break it until it's over; an abandoned
/// day breaks it like a missed one. The current streak is the run that
/// reaches today (or yesterday's, while today is still open).
///
/// By week (`.timesPerWeek(n)`): weeks from Monday, a week kept when it has
/// `n` done days (the habit's first week only needs as many as it had days
/// left). The current week doesn't break it until it's over.
public func streak(_ habit: Habit, checkins: [HabitCheckin], today: Day) -> HabitStreak {
    let log = HabitLog(habit, checkins)
    let done = log.doneDays.filter { $0 <= today }
    let first = min(habit.startDate, done.first ?? habit.startDate)
    guard first <= today else {
        return HabitStreak(current: 0, longest: 0, unit: habit.frequency.isWeekly ? .weeks : .days)
    }

    if case .timesPerWeek(let n) = habit.frequency {
        var run = 0, longest = 0
        var week = first.startOfWeek
        let thisWeek = today.startOfWeek
        while week <= thisWeek {
            let count = log.doneCount(week, min(week + 6, today))
            let needed = min(n, week + 6 - habit.startDate + 1)
            if count >= max(needed, 1) {
                run += 1
            } else if week < thisWeek && needed > 0 {
                run = 0
            }
            longest = max(longest, run)
            week += 7
        }
        return HabitStreak(current: run, longest: longest, unit: .weeks)
    }

    var run = 0, longest = 0
    for d in first...today {
        if log.isDone(d) {
            run += 1
        } else if isDue(habit, on: d) && d < today {
            run = 0
        }
        longest = max(longest, run)
    }
    return HabitStreak(current: run, longest: longest, unit: .days)
}

extension HabitFrequency {
    var isWeekly: Bool { if case .timesPerWeek = self { true } else { false } }
}

/// How many days were checked in as done, ever.
public func totalCheckins(_ habit: Habit, checkins: [HabitCheckin]) -> Int {
    HabitLog(habit, checkins).doneDays.count
}

/// The share of the month's due days that were done (0…1), counting from
/// the habit's start through `today`; nil when no day of the month counts
/// yet. Check-ins on days off don't raise it. For `.timesPerWeek(n)` each
/// week (or the part of it in the month) asks for up to `n` days.
public func monthCompletionRate(
    _ habit: Habit, checkins: [HabitCheckin], year: Int, month: Int, today: Day
) -> Double? {
    let start = max(Day(year, month, 1), habit.startDate)
    let end = min(Day(year, month, 1).endOfMonth, today)
    guard start <= end else { return nil }
    let log = HabitLog(habit, checkins)

    var wanted = 0, done = 0
    if case .timesPerWeek(let n) = habit.frequency {
        var week = start.startOfWeek
        while week <= end {
            let a = max(week, start), b = min(week + 6, end)
            let target = min(n, b - a + 1)
            wanted += target
            done += min(target, log.doneCount(a, b))
            week += 7
        }
    } else {
        for d in start...end where isDue(habit, on: d) {
            wanted += 1
            if log.isDone(d) { done += 1 }
        }
    }
    return wanted == 0 ? nil : Double(done) / Double(wanted)
}

// MARK: - Today

/// The habits of one section on the check-in page.
public struct HabitGroup: Sendable, Hashable {
    public var section: HabitSection
    public var habits: [Habit]

    public init(section: HabitSection, habits: [Habit]) {
        self.section = section
        self.habits = habits
    }
}

/// The habits to check in on `today`, by section (上午, 下午, 晚上, 任意;
/// empty sections left out), each in `sortOrder`. Left out: deleted,
/// archived, not started, not due today, and `.timesPerWeek` habits whose
/// week is already complete (unless today was one of its days).
public func todayHabits(_ habits: [Habit], checkins: [HabitCheckin], today: Day) -> [HabitGroup] {
    let shown = habits.filter { h in
        guard h.deletedAt == nil, h.archivedAt == nil, isDue(h, on: today) else { return false }
        if case .timesPerWeek(let n) = h.frequency {
            let log = HabitLog(h, checkins)
            if log.byDay[today] != nil { return true }
            return log.doneCount(today.startOfWeek, today - 1) < n
        }
        return true
    }
    return HabitSection.displayOrder.compactMap { s in
        let hs = shown.filter { $0.section == s }.sorted { a, b in
            a.sortOrder != b.sortOrder ? a.sortOrder < b.sortOrder : a.id < b.id
        }
        return hs.isEmpty ? nil : HabitGroup(section: s, habits: hs)
    }
}

/// How many of the habits due on `day` were done that day, out of how
/// many were due (deleted and archived habits left out): the rings of the
/// week strip.
public func dayCompletion(_ habits: [Habit], checkins: [HabitCheckin], on day: Day) -> (done: Int, due: Int) {
    var done = 0, due = 0
    for h in habits where h.deletedAt == nil && h.archivedAt == nil && isDue(h, on: day) {
        due += 1
        if HabitLog(h, checkins).isDone(day) { done += 1 }
    }
    return (done, due)
}
