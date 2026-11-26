// Focus (番茄专注 / 正计时): the record of a session, the timer as a pure
// state machine, the settings, and the statistics. New in the Swift version
// (roadmap M5); the conventions are written up in `docs/apple.md` (效率模块).
//
// Moments are epoch milliseconds (`Int`), like every timestamp in the
// models; durations are whole seconds. The timer never reads the clock: each
// call takes `now`. It stores when the running stretch began and how much
// focus came before it, not "seconds left", so it can be saved, the app
// killed, and the state read back later to carry on where the clock says it
// is (`tick(at:)` catches up with whatever finished meanwhile).
//
// Statistics put a session on the calendar day it started on, in the time
// zone passed in, so the same records give the same charts on any machine.

import Foundation

/// Namespace of `FocusSession` ids (UUID v5 of the start in milliseconds).
public let focusSessionNamespace = "ea7df1ed-2a57-4a2e-82ef-89138b88d69e"

/// Focus shorter than this (abandoned, or finished early) isn't recorded.
/// A pomodoro that runs its full length is, however short it was set.
public let focusMinimumSeconds = 5 * 60

// MARK: - Model

public enum FocusKind: Int, Sendable, Hashable, Codable, CaseIterable {
    /// Counts down a set length (番茄).
    case pomodoro = 0
    /// Counts up until stopped (正计时).
    case stopwatch = 1

    /// Unknown numbers read as `pomodoro`.
    public init(from decoder: any Decoder) throws {
        self = FocusKind(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .pomodoro
    }
}

/// One stretch of focus, as recorded when it ends.
public struct FocusSession: Sendable, Hashable, Codable, Identifiable {
    /// `FocusSession.id(startedAt:)`.
    public var id: String
    /// Epoch milliseconds.
    public var startedAt: Int
    public var endedAt: Int
    /// Seconds of actual focus: `endedAt - startedAt` without the pauses.
    public var duration: Int
    public var kind: FocusKind
    /// For a pomodoro: whether it ran its length (or was finished on
    /// purpose) rather than being abandoned. Only those count as 番茄.
    /// Always true for a stopwatch.
    public var completed: Bool
    /// The task focused on, if any.
    public var taskId: String?
    /// The habit focused on, if any.
    public var habitId: String?
    public var note: String

    public var createdAt: Int
    public var updatedAt: Int
    public var deletedAt: Int?
    public var serverVersion: Int
    public var dirty: Bool

    /// `id` defaults to the one worked out from `startedAt`.
    public init(
        id: String? = nil,
        startedAt: Int = 0,
        endedAt: Int = 0,
        duration: Int = 0,
        kind: FocusKind = .pomodoro,
        completed: Bool = true,
        taskId: String? = nil,
        habitId: String? = nil,
        note: String = "",
        createdAt: Int = 0,
        updatedAt: Int = 0,
        deletedAt: Int? = nil,
        serverVersion: Int = 0,
        dirty: Bool = true
    ) {
        self.id = id ?? FocusSession.id(startedAt: startedAt)
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.kind = kind
        self.completed = completed
        self.taskId = taskId
        self.habitId = habitId
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.dirty = dirty
    }

    /// UUID v5 of the start (milliseconds) in `focusSessionNamespace`: one
    /// timer run is one record, however often its end is saved (the app
    /// killed between writing the record and saving the timer).
    public static func id(startedAt: Int) -> String {
        uuidV5(namespace: focusSessionNamespace, name: String(startedAt))
    }

    /// Counts as a 番茄 in the statistics.
    public var isPomodoro: Bool { kind == .pomodoro && completed }
}

/// The focus settings, kept on this device (`key_values`, key
/// `focus.settings`). Missing or unreadable fields take the defaults.
public struct FocusSettings: Sendable, Hashable, Codable {
    public static let storageKey = "focus.settings"

    public var pomodoroMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    /// A long break after every this many pomodoros.
    public var longBreakEvery: Int
    /// Start the break when a pomodoro ends, and the next pomodoro when a
    /// break ends, without waiting for a tap.
    public var autoStartNext: Bool
    /// Play a sound when a pomodoro or a break ends.
    public var endSound: Bool

    public init(
        pomodoroMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        longBreakEvery: Int = 4,
        autoStartNext: Bool = false,
        endSound: Bool = true
    ) {
        self.pomodoroMinutes = pomodoroMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.longBreakEvery = longBreakEvery
        self.autoStartNext = autoStartNext
        self.endSound = endSound
    }

    public static let standard = FocusSettings()

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FocusSettings.standard
        func int(_ k: CodingKeys, _ def: Int) -> Int {
            ((try? c.decodeIfPresent(Int.self, forKey: k)) ?? nil).flatMap { $0 > 0 ? $0 : nil } ?? def
        }
        pomodoroMinutes = int(.pomodoroMinutes, d.pomodoroMinutes)
        shortBreakMinutes = int(.shortBreakMinutes, d.shortBreakMinutes)
        longBreakMinutes = int(.longBreakMinutes, d.longBreakMinutes)
        longBreakEvery = int(.longBreakEvery, d.longBreakEvery)
        autoStartNext = ((try? c.decodeIfPresent(Bool.self, forKey: .autoStartNext)) ?? nil) ?? d.autoStartNext
        endSound = ((try? c.decodeIfPresent(Bool.self, forKey: .endSound)) ?? nil) ?? d.endSound
    }

    /// The JSON text, or the defaults if it can't be read.
    public static func decode(_ json: String?) -> FocusSettings {
        guard let data = json?.data(using: .utf8),
              let s = try? JSONDecoder().decode(FocusSettings.self, from: data)
        else { return .standard }
        return s
    }

    public var json: String {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return String(decoding: try! e.encode(self), as: UTF8.self)
    }

    func seconds(of step: FocusStep) -> Int {
        switch step {
        case .focus: pomodoroMinutes * 60
        case .shortBreak: shortBreakMinutes * 60
        case .longBreak: longBreakMinutes * 60
        }
    }
}

// MARK: - Timer

/// A stretch the pomodoro cycle goes through.
public enum FocusStep: Int, Sendable, Hashable, Codable {
    case focus = 0
    case shortBreak = 1
    case longBreak = 2

    public var isBreak: Bool { self != .focus }
}

public enum FocusPhase: Sendable, Hashable, Codable {
    case idle
    case focusing
    case paused
    /// A short or a long break.
    case resting(FocusStep)
}

/// The focus timer. A plain value: save it as JSON (`Codable`) whenever it
/// changes, read it back on launch, and call `tick(at:)` to catch up.
///
/// Pomodoro mode: idle → `start` → focusing ⇄ `pause` / `resume` → (the
/// length runs out, `tick`) a session is recorded → a break (started at once
/// with `autoStartNext`, otherwise waiting for `startBreak`) → `skipBreak`
/// or the break runs out → the next pomodoro (again automatic or a tap).
/// Every `longBreakEvery`-th pomodoro is followed by the long break.
/// Stopwatch mode: `start` → focusing ⇄ paused → `complete` records it.
/// `abandon` stops either, recording it if it reached `focusMinimumSeconds`.
public struct FocusTimer: Sendable, Hashable, Codable {
    public var settings: FocusSettings
    public var mode: FocusKind
    public private(set) var phase: FocusPhase
    /// What `start` / `startBreak` would begin from idle, and what follows
    /// the current stretch otherwise.
    public private(set) var upNext: FocusStep
    /// Pomodoros finished since the last long break.
    public private(set) var cycleCount: Int
    /// When the current focus began (epoch ms); nil when not focusing.
    public private(set) var startedAt: Int?
    /// When the running stretch (focus or break) last started or resumed;
    /// nil while idle or paused.
    public private(set) var runningSince: Int?
    /// Focus before `runningSince`, milliseconds (the parts before pauses).
    public private(set) var banked: Int
    public var taskId: String?
    public var habitId: String?

    public init(settings: FocusSettings = .standard, mode: FocusKind = .pomodoro) {
        self.settings = settings
        self.mode = mode
        phase = .idle
        upNext = .focus
        cycleCount = 0
        startedAt = nil
        runningSince = nil
        banked = 0
    }

    // MARK: Derived values for the screen

    /// Seconds of the current stretch so far: focus without pauses, or the
    /// break. 0 when idle.
    public func elapsed(at now: Int) -> Int {
        switch phase {
        case .idle: 0
        case .paused: banked / 1000
        case .focusing, .resting: (banked + max(now - (runningSince ?? now), 0)) / 1000
        }
    }

    /// The length of the current (or, idle, the next) stretch in seconds;
    /// nil for a stopwatch focus, which has none.
    public var length: Int? {
        switch phase {
        case .resting(let step): settings.seconds(of: step)
        case .idle: mode == .stopwatch && upNext == .focus ? nil : settings.seconds(of: upNext)
        case .focusing, .paused: mode == .stopwatch ? nil : settings.seconds(of: .focus)
        }
    }

    /// Seconds left of a pomodoro or a break; nil for a stopwatch.
    public func remaining(at now: Int) -> Int? {
        length.map { max($0 - elapsed(at: now), 0) }
    }

    /// How far through the pomodoro or the break, 0…1; nil for a stopwatch.
    public func progress(at now: Int) -> Double? {
        guard let len = length, len > 0 else { return nil }
        return min(Double(elapsed(at: now)) / Double(len), 1)
    }

    /// When the running pomodoro or break will run out (epoch ms), for a
    /// notification; nil when paused, idle or counting up.
    public func endsAt(at now: Int) -> Int? {
        guard let since = runningSince, let len = length else { return nil }
        return since + len * 1000 - banked
    }

    public var isRunning: Bool {
        switch phase {
        case .focusing, .resting: true
        case .idle, .paused: false
        }
    }

    // MARK: Events

    /// Starts focusing (from idle; otherwise nothing happens). A break that
    /// was due is skipped.
    public mutating func start(at now: Int, taskId: String? = nil, habitId: String? = nil) {
        guard phase == .idle else { return }
        if upNext == .longBreak { cycleCount = 0 }
        if taskId != nil || habitId != nil {
            self.taskId = taskId
            self.habitId = habitId
        }
        beginFocus(at: now)
    }

    /// Starts the break that's due (idle after a pomodoro, without
    /// `autoStartNext`).
    public mutating func startBreak(at now: Int) {
        guard phase == .idle, upNext.isBreak else { return }
        beginBreak(upNext, at: now)
    }

    public mutating func pause(at now: Int) {
        guard phase == .focusing, let since = runningSince else { return }
        banked += max(now - since, 0)
        runningSince = nil
        phase = .paused
    }

    public mutating func resume(at now: Int) {
        guard phase == .paused else { return }
        runningSince = now
        phase = .focusing
    }

    /// Stops the focus without finishing it (放弃). It's recorded, as not
    /// completed, if it reached `focusMinimumSeconds`. During a break this is
    /// `skipBreak`.
    @discardableResult
    public mutating func abandon(at now: Int) -> FocusSession? {
        switch phase {
        case .focusing, .paused:
            let s = record(at: now, completed: false, force: false)
            reset(upNext: .focus)
            return s
        case .resting:
            skipBreak(at: now)
            return nil
        case .idle:
            return nil
        }
    }

    /// Finishes the focus now: a stopwatch's end, or a pomodoro finished
    /// early on purpose (which counts as a 番茄 if it reached
    /// `focusMinimumSeconds`). Too short to keep, it ends unrecorded.
    @discardableResult
    public mutating func complete(at now: Int) -> FocusSession? {
        guard phase == .focusing || phase == .paused else { return nil }
        let s = record(at: now, completed: true, force: false)
        if mode == .pomodoro && s != nil {
            finishPomodoro(at: now)
        } else {
            reset(upNext: .focus)
        }
        return s
    }

    /// Ends the break (or drops the one that's due) and moves on to the
    /// next pomodoro, started at once with `autoStartNext`.
    public mutating func skipBreak(at now: Int) {
        let skipping: FocusStep
        switch phase {
        case .resting(let step): skipping = step
        case .idle where upNext.isBreak: skipping = upNext
        default: return
        }
        endBreak(skipping, at: now)
    }

    /// Catches up with the clock: a pomodoro or a break that has run out
    /// ends at the moment it ran out, and with `autoStartNext` the next one
    /// starts right then, so a timer left alone keeps cycling. Returns the
    /// sessions recorded on the way (save them, then save the timer).
    public mutating func tick(at now: Int) -> [FocusSession] {
        var out: [FocusSession] = []
        for _ in 0..<1000 {
            guard let since = runningSince, let len = length else { break }
            let endsAt = since + len * 1000 - banked
            guard endsAt <= now else { break }
            switch phase {
            case .focusing:
                if let s = record(at: endsAt, completed: true, force: true) { out.append(s) }
                finishPomodoro(at: endsAt)
            case .resting(let step):
                endBreak(step, at: endsAt)
            default:
                return out
            }
        }
        return out
    }

    /// Switches between pomodoro and stopwatch while idle.
    public mutating func setMode(_ mode: FocusKind) {
        guard phase == .idle else { return }
        self.mode = mode
        upNext = .focus
    }

    // MARK: Private

    private mutating func beginFocus(at now: Int) {
        phase = .focusing
        upNext = mode == .pomodoro ? nextBreak : .focus
        startedAt = now
        runningSince = now
        banked = 0
    }

    private var nextBreak: FocusStep {
        cycleCount + 1 >= max(settings.longBreakEvery, 1) ? .longBreak : .shortBreak
    }

    private mutating func beginBreak(_ step: FocusStep, at now: Int) {
        if step == .longBreak { cycleCount = 0 }
        phase = .resting(step)
        upNext = .focus
        startedAt = nil
        runningSince = now
        banked = 0
    }

    private mutating func finishPomodoro(at end: Int) {
        let brk = nextBreak
        cycleCount += 1
        if settings.autoStartNext {
            beginBreak(brk, at: end)
        } else {
            reset(upNext: brk)
        }
    }

    private mutating func endBreak(_ step: FocusStep, at end: Int) {
        if step == .longBreak { cycleCount = 0 }
        if settings.autoStartNext {
            phase = .idle
            beginFocus(at: end)
        } else {
            reset(upNext: .focus)
        }
    }

    private mutating func reset(upNext next: FocusStep) {
        phase = .idle
        upNext = next
        startedAt = nil
        runningSince = nil
        banked = 0
    }

    private func record(at end: Int, completed: Bool, force: Bool) -> FocusSession? {
        guard let start = startedAt else { return nil }
        let ms = banked + (runningSince.map { max(end - $0, 0) } ?? 0)
        let seconds = ms / 1000
        guard force || seconds >= focusMinimumSeconds else { return nil }
        return FocusSession(
            startedAt: start, endedAt: max(end, start), duration: seconds, kind: mode,
            completed: mode == .stopwatch || completed, taskId: taskId, habitId: habitId,
            createdAt: end, updatedAt: end
        )
    }
}

// MARK: - Statistics

/// Focus time and pomodoros over some stretch.
public struct FocusSummary: Sendable, Hashable {
    public var seconds: Int
    public var pomodoros: Int
    public var sessions: Int

    public init(seconds: Int = 0, pomodoros: Int = 0, sessions: Int = 0) {
        self.seconds = seconds
        self.pomodoros = pomodoros
        self.sessions = sessions
    }
}

extension FocusSession {
    /// The wall-clock start in `timeZone`.
    public func start(in timeZone: TimeZone) -> LocalDateTime { localTime(startedAt, timeZone) }
    public func end(in timeZone: TimeZone) -> LocalDateTime { localTime(endedAt, timeZone) }
    /// The day it counts on: the one it started on.
    public func day(in timeZone: TimeZone) -> Day { start(in: timeZone).day }
}

private func localTime(_ ms: Int, _ tz: TimeZone) -> LocalDateTime {
    LocalDateTime(Date(timeIntervalSince1970: Double(floorDiv(ms, 1000))), in: tz)
}

private func live(_ sessions: [FocusSession]) -> [FocusSession] { sessions.filter { $0.deletedAt == nil } }

/// Totals of `sessions` (deleted ones left out) started from `from` through
/// `through` in `timeZone`; both nil for all time.
public func focusSummary(
    _ sessions: [FocusSession], from: Day? = nil, through: Day? = nil, in timeZone: TimeZone
) -> FocusSummary {
    var s = FocusSummary()
    for x in live(sessions) {
        let d = x.day(in: timeZone)
        if let from, d < from { continue }
        if let through, d > through { continue }
        s.seconds += x.duration
        s.sessions += 1
        if x.isPomodoro { s.pomodoros += 1 }
    }
    return s
}

/// Today's totals.
public func focusSummary(_ sessions: [FocusSession], on day: Day, in timeZone: TimeZone) -> FocusSummary {
    focusSummary(sessions, from: day, through: day, in: timeZone)
}

public enum FocusBucket: Sendable, Hashable {
    case day
    /// Weeks from Monday.
    case week
    case month

    func start(_ d: Day) -> Day {
        switch self {
        case .day: d
        case .week: d.startOfWeek
        case .month: d.startOfMonth
        }
    }

    func next(_ d: Day) -> Day {
        switch self {
        case .day: d + 1
        case .week: d + 7
        case .month: d.addingMonths(1)
        }
    }
}

/// One bar of a focus chart.
public struct FocusBar: Sendable, Hashable {
    /// The first day of the bucket (the day, the Monday, the 1st).
    public var start: Day
    public var seconds: Int
    public var pomodoros: Int

    public init(start: Day, seconds: Int = 0, pomodoros: Int = 0) {
        self.start = start
        self.seconds = seconds
        self.pomodoros = pomodoros
    }
}

/// Focus per day, week or month for a bar chart: one bar for every bucket
/// that `from`…`through` touches, empty ones included, oldest first. A
/// session counts on the day it started.
public func focusSeries(
    _ sessions: [FocusSession], from: Day, through: Day, by bucket: FocusBucket, in timeZone: TimeZone
) -> [FocusBar] {
    guard from <= through else { return [] }
    var bars: [FocusBar] = []
    var index: [Day: Int] = [:]
    var b = bucket.start(from)
    while b <= through {
        index[b] = bars.count
        bars.append(FocusBar(start: b))
        b = bucket.next(b)
    }
    for x in live(sessions) {
        let d = x.day(in: timeZone)
        guard d >= from, d <= through, let i = index[bucket.start(d)] else { continue }
        bars[i].seconds += x.duration
        if x.isPomodoro { bars[i].pomodoros += 1 }
    }
    return bars
}

/// A slice of the focus pie: a task or a list (nil: no task), and its time.
public struct FocusShare: Sendable, Hashable {
    public var id: String?
    public var seconds: Int

    public init(id: String?, seconds: Int) {
        self.id = id
        self.seconds = seconds
    }
}

private func shares(_ sessions: [FocusSession], _ key: (FocusSession) -> String?) -> [FocusShare] {
    var by: [String?: Int] = [:]
    for x in live(sessions) { by[key(x), default: 0] += x.duration }
    return by.map { FocusShare(id: $0.key, seconds: $0.value) }.sorted { a, b in
        a.seconds != b.seconds ? a.seconds > b.seconds : (a.id ?? "") < (b.id ?? "")
    }
}

/// Focus time per task, most first; sessions without a task under nil.
/// Filter `sessions` to the period first.
public func focusByTask(_ sessions: [FocusSession]) -> [FocusShare] {
    shares(sessions) { $0.taskId }
}

/// Focus time per list of the task focused on, most first; sessions with no
/// task (or one not in `tasks`) under nil.
public func focusByList(_ sessions: [FocusSession], tasks: [TodoTask]) -> [FocusShare] {
    let listOf = Dictionary(tasks.map { ($0.id, $0.listId) }, uniquingKeysWith: { a, _ in a })
    return shares(sessions) { $0.taskId.flatMap { listOf[$0] } }
}

/// The sessions started from `from` through `through` in `timeZone`.
public func focusSessions(
    _ sessions: [FocusSession], from: Day, through: Day, in timeZone: TimeZone
) -> [FocusSession] {
    live(sessions).filter { let d = $0.day(in: timeZone); return d >= from && d <= through }
}

/// A block on the day's focus timeline.
public struct FocusTimelineItem: Sendable, Hashable {
    public var session: FocusSession
    /// Minutes after the day's midnight, clipped to the day (0…1440).
    public var startMinute: Int
    public var endMinute: Int

    public init(session: FocusSession, startMinute: Int, endMinute: Int) {
        self.session = session
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

/// The sessions that overlap `day` in `timeZone` as blocks from when they
/// started to when they ended (pauses included), clipped to the day; one
/// that runs past midnight shows on both days. Earliest first.
public func focusTimeline(_ sessions: [FocusSession], on day: Day, in timeZone: TimeZone) -> [FocusTimelineItem] {
    let dayStart = LocalDateTime(day)
    return live(sessions).compactMap { x -> FocusTimelineItem? in
        let s = x.start(in: timeZone) - dayStart
        let e = max(x.end(in: timeZone) - dayStart, s)
        guard s < minutesPerDay, e > 0 || (s == 0 && e == 0) else { return nil }
        return FocusTimelineItem(session: x, startMinute: max(s, 0), endMinute: min(e, minutesPerDay))
    }.sorted { a, b in
        a.startMinute != b.startMinute ? a.startMinute < b.startMinute : a.session.id < b.session.id
    }
}
