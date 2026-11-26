// Focus (效率模块). New in the Swift version, no Dart counterpart.

import Foundation
import Testing
@testable import OpenTodoDomain

private let t0 = 1_800_000_000_000 // some moment, epoch ms
private func mins(_ m: Int) -> Int { t0 + m * 60_000 }
private func sec(_ s: Int) -> Int { t0 + s * 1000 }

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let newYork = TimeZone(identifier: "America/New_York")!

/// Epoch ms of a wall-clock time in `tz`.
private func ms(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ tz: TimeZone = shanghai) -> Int {
    Int(LocalDateTime(y, m, d, h, mi).date(in: tz).timeIntervalSince1970) * 1000
}

private func session(_ start: Int, minutes: Int, kind: FocusKind = .pomodoro, completed: Bool = true, task: String? = nil) -> FocusSession {
    FocusSession(startedAt: start, endedAt: start + minutes * 60_000, duration: minutes * 60, kind: kind, completed: completed, taskId: task)
}

@Suite("Focus settings")
struct FocusSettingsTests {
    @Test func defaults() {
        let s = FocusSettings()
        #expect(s.pomodoroMinutes == 25 && s.shortBreakMinutes == 5 && s.longBreakMinutes == 15)
        #expect(s.longBreakEvery == 4 && !s.autoStartNext)
        #expect(FocusSettings.storageKey == "focus.settings")
    }

    @Test func jsonRoundTripAndBadFieldsFallBack() {
        let s = FocusSettings(pomodoroMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 20, longBreakEvery: 2, autoStartNext: true)
        #expect(FocusSettings.decode(s.json) == s)
        #expect(FocusSettings.decode(nil) == .standard)
        #expect(FocusSettings.decode("not json") == .standard)
        let odd = FocusSettings.decode(#"{"pomodoroMinutes":"x","shortBreakMinutes":0,"longBreakMinutes":30,"extra":1}"#)
        #expect(odd == FocusSettings(longBreakMinutes: 30))
    }
}

@Suite("Focus session")
struct FocusSessionTests {
    @Test func idComesFromTheStart() {
        #expect(FocusSession(startedAt: t0).id == FocusSession.id(startedAt: t0))
        #expect(FocusSession(startedAt: t0).id != FocusSession(startedAt: t0 + 1).id)
        #expect(FocusSession(startedAt: t0).id.count == 36)
    }

    @Test func onlyFinishedPomodorosCount() {
        #expect(session(t0, minutes: 25).isPomodoro)
        #expect(!session(t0, minutes: 25, completed: false).isPomodoro)
        #expect(!session(t0, minutes: 25, kind: .stopwatch).isPomodoro)
    }

    @Test func unknownKindReadsAsPomodoro() throws {
        struct Box: Decodable { var k: FocusKind }
        #expect(try JSONDecoder().decode(Box.self, from: Data(#"{"k":9}"#.utf8)).k == .pomodoro)
    }
}

@Suite("Focus timer")
struct FocusTimerTests {
    @Test func aPomodoroWithAPause() {
        var t = FocusTimer()
        #expect(t.phase == .idle && t.remaining(at: t0) == 1500 && t.elapsed(at: t0) == 0)
        t.start(at: t0, taskId: "task")
        #expect(t.phase == .focusing && t.isRunning)
        #expect(t.remaining(at: mins(5)) == 1200)
        #expect(t.progress(at: mins(5)) == 0.2)
        #expect(t.upNext == .shortBreak)
        t.pause(at: mins(10))
        #expect(t.phase == .paused && t.elapsed(at: mins(14)) == 600 && !t.isRunning)
        #expect(t.tick(at: mins(60)).isEmpty) // paused: the clock doesn't run out
        t.resume(at: mins(15))
        #expect(t.remaining(at: mins(20)) == 600)
        #expect(t.tick(at: sec(30 * 60 - 1)).isEmpty)
        let s = t.tick(at: mins(31))
        #expect(s.count == 1)
        #expect(s[0].startedAt == t0 && s[0].endedAt == mins(30)) // when it ran out, not when ticked
        #expect(s[0].duration == 1500 && s[0].kind == .pomodoro && s[0].completed && s[0].taskId == "task")
        #expect(s[0].id == FocusSession.id(startedAt: t0))
        #expect(t.phase == .idle && t.upNext == .shortBreak && t.cycleCount == 1)
        #expect(t.remaining(at: mins(31)) == 300)
    }

    @Test func breaksWaitForATapWithoutAutoStart() {
        var t = FocusTimer()
        t.start(at: t0)
        _ = t.tick(at: mins(25))
        t.startBreak(at: mins(26))
        #expect(t.phase == .resting(.shortBreak))
        #expect(t.remaining(at: mins(28)) == 180)
        #expect(t.progress(at: mins(27)) == 0.2)
        t.pause(at: mins(28)) // breaks don't pause
        #expect(t.phase == .resting(.shortBreak))
        #expect(t.tick(at: mins(40)).isEmpty)
        #expect(t.phase == .idle && t.upNext == .focus)
    }

    @Test func everyFourthIsFollowedByTheLongBreak() {
        var t = FocusTimer()
        var at = 0
        for i in 1...4 {
            t.start(at: mins(at))
            #expect(t.upNext == (i == 4 ? .longBreak : .shortBreak))
            #expect(t.tick(at: mins(at + 25)).count == 1)
            at += 25
            t.startBreak(at: mins(at))
            #expect(t.phase == .resting(i == 4 ? .longBreak : .shortBreak))
            _ = t.tick(at: mins(at + 30))
            at += 30
        }
        #expect(t.cycleCount == 0)
        t.start(at: mins(at))
        #expect(t.upNext == .shortBreak)
    }

    @Test func autoStartKeepsCyclingWhileAway() throws {
        var t = FocusTimer(settings: FocusSettings(autoStartNext: true))
        t.start(at: t0)
        // 4 × 25 focus + 3 × 5 short = 115, then a long break of 15: the
        // fifth pomodoro starts at 130.
        let s = t.tick(at: mins(131))
        #expect(s.map(\.startedAt) == [mins(0), mins(30), mins(60), mins(90)])
        #expect(s.allSatisfy { $0.duration == 1500 && $0.completed })
        #expect(t.phase == .focusing && t.startedAt == mins(130) && t.cycleCount == 0)
        #expect(t.remaining(at: mins(131)) == 24 * 60)
    }

    @Test func survivesBeingSavedAndReadBack() throws {
        var t = FocusTimer()
        t.start(at: t0, taskId: "x")
        t.pause(at: mins(5))
        t.resume(at: mins(10))
        let data = try JSONEncoder().encode(t)
        var back = try JSONDecoder().decode(FocusTimer.self, from: data)
        #expect(back == t)
        // The app was killed; it comes back after the pomodoro would have ended.
        let s = back.tick(at: mins(90))
        #expect(s.count == 1 && s[0].endedAt == mins(30) && s[0].duration == 1500 && s[0].taskId == "x")
    }

    @Test func abandonRecordsOnlyFromFiveMinutes() {
        var t = FocusTimer()
        t.start(at: t0)
        #expect(t.abandon(at: sec(299)) == nil)
        #expect(t.phase == .idle && t.upNext == .focus)

        t.start(at: t0)
        t.pause(at: mins(4))
        t.resume(at: mins(20))
        #expect(t.abandon(at: sec(20 * 60 + 59)) == nil) // 4:59 without the pause

        t.start(at: t0)
        t.pause(at: mins(3))
        t.resume(at: mins(10))
        let s = t.abandon(at: mins(12))
        #expect(s?.duration == 300 && s?.completed == false && s?.endedAt == mins(12))
        #expect(s?.isPomodoro == false)
        #expect(t.cycleCount == 0 && t.upNext == .focus)
    }

    @Test func completingEarly() {
        var t = FocusTimer()
        t.start(at: t0)
        let s = t.complete(at: mins(20))
        #expect(s?.duration == 1200 && s?.completed == true)
        #expect(t.phase == .idle && t.upNext == .shortBreak && t.cycleCount == 1)

        t.start(at: mins(30)) // skips the break
        #expect(t.complete(at: mins(32)) == nil)
        #expect(t.phase == .idle && t.upNext == .focus && t.cycleCount == 1)
    }

    @Test func aFullPomodoroShorterThanTheMinimumIsStillRecorded() {
        var t = FocusTimer(settings: FocusSettings(pomodoroMinutes: 2))
        t.start(at: t0)
        #expect(t.tick(at: mins(2)).first?.duration == 120)
    }

    @Test func skippingBreaks() {
        var t = FocusTimer(settings: FocusSettings(longBreakEvery: 1))
        t.start(at: t0)
        _ = t.tick(at: mins(25))
        #expect(t.upNext == .longBreak)
        t.skipBreak(at: mins(26))
        #expect(t.phase == .idle && t.upNext == .focus && t.cycleCount == 0)

        var a = FocusTimer(settings: FocusSettings(autoStartNext: true))
        a.start(at: t0)
        _ = a.tick(at: mins(26))
        #expect(a.phase == .resting(.shortBreak))
        a.skipBreak(at: mins(27))
        #expect(a.phase == .focusing && a.startedAt == mins(27))
        // Abandoning a break is skipping it.
        _ = a.tick(at: mins(52))
        #expect(a.abandon(at: mins(53)) == nil && a.phase == .focusing && a.startedAt == mins(53))
    }

    @Test func eventsOutOfPlaceAreIgnored() {
        var t = FocusTimer()
        let idle = t
        t.pause(at: t0)
        t.resume(at: t0)
        t.skipBreak(at: t0)
        t.startBreak(at: t0)
        #expect(t.complete(at: t0) == nil && t.abandon(at: t0) == nil)
        #expect(t == idle)
        t.start(at: t0)
        let running = t
        t.start(at: mins(1))
        t.resume(at: mins(1))
        t.setMode(.stopwatch)
        #expect(t == running)
    }

    @Test func stopwatch() {
        var t = FocusTimer(mode: .stopwatch)
        #expect(t.length == nil && t.remaining(at: t0) == nil && t.progress(at: t0) == nil)
        t.start(at: t0, habitId: "h")
        #expect(t.upNext == .focus)
        #expect(t.tick(at: mins(600)).isEmpty) // never runs out
        t.pause(at: mins(30))
        t.resume(at: mins(40))
        #expect(t.elapsed(at: mins(50)) == 40 * 60)
        let s = t.complete(at: mins(50))
        #expect(s?.kind == .stopwatch && s?.duration == 2400 && s?.habitId == "h" && s?.completed == true)
        #expect(s?.isPomodoro == false && t.phase == .idle && t.upNext == .focus)
        // Too short.
        t.start(at: mins(60))
        #expect(t.complete(at: mins(64)) == nil)
        // Abandoned stopwatch focus is kept from five minutes on.
        t.start(at: mins(70))
        #expect(t.abandon(at: mins(80))?.duration == 600)
    }

    @Test func switchingModes() {
        var t = FocusTimer()
        t.setMode(.stopwatch)
        #expect(t.mode == .stopwatch && t.length == nil)
        t.setMode(.pomodoro)
        #expect(t.length == 1500)
    }
}

@Suite("Focus statistics")
struct FocusStatsTests {
    @Test func todayAndTotal() {
        let s = [
            session(ms(2026, 11, 15, 9, 0), minutes: 25),
            session(ms(2026, 11, 15, 10, 0), minutes: 25, completed: false),
            session(ms(2026, 11, 15, 14, 0), minutes: 40, kind: .stopwatch),
            session(ms(2026, 11, 14, 9, 0), minutes: 25),
            FocusSession(startedAt: ms(2026, 11, 15, 16, 0), duration: 999, deletedAt: 1),
        ]
        #expect(focusSummary(s, on: Day(2026, 11, 15), in: shanghai) == FocusSummary(seconds: 90 * 60, pomodoros: 1, sessions: 3))
        #expect(focusSummary(s, in: shanghai) == FocusSummary(seconds: 115 * 60, pomodoros: 2, sessions: 4))
        #expect(focusSummary(s, on: Day(2026, 11, 16), in: shanghai) == FocusSummary())
    }

    @Test func theDayDependsOnTheZoneGivenNotTheMachine() {
        // 07:00 on the 16th in Shanghai is 18:00 on the 15th in New York.
        let s = [session(ms(2026, 11, 16, 7, 0), minutes: 25)]
        #expect(focusSummary(s, on: Day(2026, 11, 16), in: shanghai).sessions == 1)
        #expect(focusSummary(s, on: Day(2026, 11, 15), in: newYork).sessions == 1)
        #expect(s[0].start(in: newYork) == LocalDateTime(2026, 11, 15, 18, 0))
    }

    @Test func aSessionCountsOnTheDayItStarted() {
        let s = [session(ms(2026, 12, 31, 23, 50), minutes: 25)]
        #expect(focusSummary(s, on: Day(2026, 12, 31), in: shanghai).seconds == 1500)
        #expect(focusSummary(s, on: Day(2027, 1, 1), in: shanghai).seconds == 0)
    }

    @Test func seriesByDayAcrossTheEndOfAMonth() {
        let s = [
            session(ms(2028, 2, 28, 9, 0), minutes: 25),
            session(ms(2028, 2, 29, 9, 0), minutes: 25),
            session(ms(2028, 2, 29, 20, 0), minutes: 30, kind: .stopwatch),
            session(ms(2028, 3, 2, 9, 0), minutes: 25),
            session(ms(2028, 3, 9, 9, 0), minutes: 25), // outside
        ]
        let bars = focusSeries(s, from: Day(2028, 2, 28), through: Day(2028, 3, 2), by: .day, in: shanghai)
        #expect(bars.map(\.start) == [Day(2028, 2, 28), Day(2028, 2, 29), Day(2028, 3, 1), Day(2028, 3, 2)])
        #expect(bars.map(\.seconds) == [1500, 3300, 0, 1500])
        #expect(bars.map(\.pomodoros) == [1, 1, 0, 1])
        #expect(focusSeries(s, from: Day(2028, 3, 2), through: Day(2028, 3, 1), by: .day, in: shanghai).isEmpty)
    }

    @Test func seriesByWeekStartsOnMonday() {
        // 2026-12-28 is a Monday; the week runs into 2027.
        let s = [
            session(ms(2026, 12, 27, 9, 0), minutes: 10), // Sunday: the week before
            session(ms(2026, 12, 28, 9, 0), minutes: 20),
            session(ms(2027, 1, 3, 22, 0), minutes: 30), // Sunday: same week
            session(ms(2027, 1, 4, 9, 0), minutes: 40),
        ]
        let bars = focusSeries(s, from: Day(2026, 12, 27), through: Day(2027, 1, 4), by: .week, in: shanghai)
        #expect(bars.map(\.start) == [Day(2026, 12, 21), Day(2026, 12, 28), Day(2027, 1, 4)])
        #expect(bars.map(\.seconds) == [600, 3000, 2400])
    }

    @Test func seriesByMonthIncludesEmptyMonths() {
        let s = [session(ms(2026, 11, 30, 9, 0), minutes: 10), session(ms(2027, 1, 31, 9, 0), minutes: 20)]
        let bars = focusSeries(s, from: Day(2026, 11, 15), through: Day(2027, 1, 31), by: .month, in: shanghai)
        #expect(bars.map(\.start) == [Day(2026, 11, 1), Day(2026, 12, 1), Day(2027, 1, 1)])
        #expect(bars.map(\.seconds) == [600, 0, 1200])
    }

    @Test func byTaskAndByList() {
        let tasks = [TodoTask(id: "a", listId: "work"), TodoTask(id: "b", listId: "work"), TodoTask(id: "c")]
        let s = [
            session(t0, minutes: 10, task: "a"),
            session(t0 + 1, minutes: 30, task: "b"),
            session(t0 + 2, minutes: 15, task: "c"),
            session(t0 + 3, minutes: 5),
            session(t0 + 4, minutes: 5, task: "gone"),
        ]
        #expect(focusByTask(s) == [
            FocusShare(id: "b", seconds: 1800), FocusShare(id: "c", seconds: 900),
            FocusShare(id: "a", seconds: 600), FocusShare(id: nil, seconds: 300), FocusShare(id: "gone", seconds: 300),
        ])
        #expect(focusByList(s, tasks: tasks) == [
            FocusShare(id: "work", seconds: 2400), FocusShare(id: inboxListId, seconds: 900), FocusShare(id: nil, seconds: 600),
        ])
    }

    @Test func sessionsInARange() {
        let s = [session(ms(2026, 11, 14, 23, 59), minutes: 5), session(ms(2026, 11, 15, 0, 0), minutes: 5), session(ms(2026, 11, 16, 0, 0), minutes: 5)]
        #expect(focusSessions(s, from: Day(2026, 11, 15), through: Day(2026, 11, 15), in: shanghai).count == 1)
    }

    @Test func timelineClipsToTheDay() {
        let s = [
            session(ms(2026, 11, 15, 14, 0), minutes: 25),
            session(ms(2026, 11, 14, 23, 40), minutes: 40), // into the 15th
            FocusSession(startedAt: ms(2026, 11, 15, 9, 0), endedAt: ms(2026, 11, 15, 10, 0), duration: 1800), // with a pause
            session(ms(2026, 11, 15, 23, 50), minutes: 30), // into the 16th
            session(ms(2026, 11, 16, 0, 0), minutes: 25), // next day
            session(ms(2026, 11, 14, 23, 0), minutes: 60), // ends at midnight
        ]
        let items = focusTimeline(s, on: Day(2026, 11, 15), in: shanghai)
        #expect(items.map(\.startMinute) == [0, 9 * 60, 14 * 60, 23 * 60 + 50])
        #expect(items.map(\.endMinute) == [20, 10 * 60, 14 * 60 + 25, 1440])
    }
}

@Suite("Focus additions")
struct FocusAdditionsTests {
    @Test func endsAt() {
        var t = FocusTimer()
        #expect(t.endsAt(at: t0) == nil)
        t.start(at: t0)
        #expect(t.endsAt(at: t0) == mins(25))
        t.pause(at: mins(5))
        #expect(t.endsAt(at: mins(6)) == nil)
        t.resume(at: mins(10))
        #expect(t.endsAt(at: mins(10)) == mins(30))
        var s = FocusTimer(mode: .stopwatch)
        s.start(at: t0)
        #expect(s.endsAt(at: t0) == nil)
    }

    @Test func endSoundDefaultsOn() {
        #expect(FocusSettings().endSound)
        #expect(FocusSettings.decode("{}").endSound)
        #expect(!FocusSettings.decode(FocusSettings(endSound: false).json).endSound)
    }
}
