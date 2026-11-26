// Habits (效率模块). New in the Swift version, no Dart counterpart.
// 2026-11-16 is a Monday.

import Foundation
import Testing
@testable import OpenTodoDomain

private func done(_ h: Habit, _ days: Day...) -> [HabitCheckin] {
    days.map { HabitCheckin(habitId: h.id, day: $0, value: 1, status: .done) }
}

@Suite("UUID v5")
struct UUIDv5Tests {
    @Test func matchesTheStandardVectors() {
        // RFC 9562 / Python's uuid.uuid5(NAMESPACE_DNS, "python.org").
        #expect(uuidV5(namespace: "6ba7b810-9dad-11d1-80b4-00c04fd430c8", name: "python.org")
            == "886313e1-3b8a-5372-9b90-0c9aee199e5d")
        // Non-ASCII names hash their UTF-8 bytes, as Dart's uuid package does.
        #expect(uuidV5(namespace: "b3e0b216-dc4f-4498-98bb-c1e895f8613a", name: "任务/2026-11-15")
            == "184269d4-d65e-5290-a6ff-eef39ee7feb2")
    }

    @Test func sha1() {
        func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(OpenTodoDomain.sha1([])) == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        // Several blocks.
        #expect(hex(OpenTodoDomain.sha1(Array(repeating: 0x61, count: 1000))) == "291e9a6c66994949b57ba5e650361e98fc36b1ba")
    }
}

@Suite("Habit model")
struct HabitModelTests {
    @Test func frequencyRules() {
        #expect(HabitFrequency.daily.rule == "FREQ=DAILY")
        #expect(HabitFrequency.weekdays([5, 1, 3, 3, 9]).rule == "FREQ=WEEKLY;BYDAY=MO,WE,FR")
        #expect(HabitFrequency.timesPerWeek(3).rule == "FREQ=WEEKLY;TIMES=3")
        for f in [HabitFrequency.daily, .weekdays([6, 7]), .timesPerWeek(2)] {
            #expect(HabitFrequency(rule: f.rule) == f)
        }
        #expect(HabitFrequency(rule: "freq=weekly; byday=tu,th") == .onWeekdays([2, 4]))
    }

    @Test func oddFrequenciesFallBack() {
        #expect(HabitFrequency(rule: "") == .daily)
        #expect(HabitFrequency(rule: "FREQ=MONTHLY") == .daily)
        #expect(HabitFrequency(rule: "FREQ=WEEKLY;BYDAY=XX") == .daily)
        #expect(HabitFrequency(rule: "FREQ=WEEKLY") == .daily)
        #expect(HabitFrequency(rule: "FREQ=WEEKLY;TIMES=9") == .daily)
        #expect(HabitFrequency(rule: "FREQ=WEEKLY;TIMES=0") == .timesPerWeek(1))
        #expect(HabitFrequency.weekdays(1...7) == .daily)
        #expect(HabitFrequency.weekdays([]) == .daily)
    }

    @Test func jsonUsesSimpleTypes() throws {
        let h = Habit(
            id: "h", name: "喝水", emoji: "💧", goalKind: .count, goal: 8, unit: "杯",
            frequency: .weekdays([1, 2, 3, 4, 5]), reminders: [540, 900], startDate: Day(2026, 11, 1),
            section: .morning
        )
        let data = try JSONEncoder().encode(h)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["frequency"] as? String == "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
        #expect(obj["startDate"] as? String == "2026-11-01")
        #expect(obj["goalKind"] as? Int == 1)
        #expect(obj["section"] as? Int == 1)
        #expect(try JSONDecoder().decode(Habit.self, from: data) == h)
    }

    @Test func unknownNumbersReadAsDefaults() throws {
        struct Box: Decodable { var g: HabitGoalKind; var s: HabitSection; var c: CheckinStatus }
        let b = try JSONDecoder().decode(Box.self, from: Data(#"{"g":7,"s":9,"c":5}"#.utf8))
        #expect(b.g == .once && b.s == .anytime && b.c == .partial)
    }

    @Test func checkinIdComesFromHabitAndDay() {
        let a = HabitCheckin(habitId: "h1", day: Day(2026, 11, 15))
        #expect(a.id == "5de93b98-aaee-566e-85ce-8e8a4f8b1e8a")
        #expect(a.id == HabitCheckin(habitId: "h1", day: Day("2026-11-15")!, value: 3).id)
        #expect(a.id != HabitCheckin(habitId: "h1", day: Day(2026, 11, 16)).id)
        #expect(a.id != HabitCheckin(habitId: "h2", day: Day(2026, 11, 15)).id)
    }

    @Test func sectionsShowMorningFirstAnytimeLast() {
        #expect(HabitSection.displayOrder == [.morning, .afternoon, .evening, .anytime])
    }
}

@Suite("Checking in")
struct CheckInTests {
    let day = Day(2026, 11, 15)

    @Test func onceIsDoneAtOnce() {
        let h = Habit(id: "h")
        let c = checkIn(h, on: day, existing: nil, now: 100)
        #expect(c.status == .done && c.value == 1)
        #expect(c.id == HabitCheckin.id(habitId: "h", day: day))
        #expect(c.createdAt == 100 && c.updatedAt == 100 && c.dirty)
        // Again: still once.
        #expect(checkIn(h, on: day, existing: c, now: 200).value == 1)
    }

    @Test func countAddsUpToTheGoal() {
        let h = Habit(id: "h", goalKind: .count, goal: 3, step: 1, unit: "杯")
        var c = checkIn(h, on: day, existing: nil, now: 1)
        #expect(c.status == .partial && c.value == 1)
        c = checkIn(h, on: day, existing: c, now: 2)
        #expect(c.status == .partial && c.value == 2)
        c = checkIn(h, on: day, existing: c, now: 3)
        #expect(c.status == .done && c.value == 3)
        #expect(c.createdAt == 1 && c.updatedAt == 3)
        c = checkIn(h, on: day, existing: c, amount: 2.5, now: 4)
        #expect(c.status == .done && c.value == 5.5)
    }

    @Test func setValueCanTakeItBack() {
        let h = Habit(id: "h", goalKind: .count, goal: 2)
        let c = setCheckinValue(h, on: day, existing: checkIn(h, on: day, existing: nil, amount: 2, now: 1), value: 1, now: 2)
        #expect(c.status == .partial && c.value == 1)
        #expect(setCheckinValue(h, on: day, existing: c, value: -4, now: 3).value == 0)
    }

    @Test func abandonKeepsTheAmount() {
        let h = Habit(id: "h", goalKind: .count, goal: 8)
        let c = abandonDay(h, on: day, existing: checkIn(h, on: day, existing: nil, now: 1), now: 2)
        #expect(c.status == .abandoned && c.value == 1)
        // Checking in afterwards takes it back.
        #expect(checkIn(h, on: day, existing: c, amount: 7, now: 3).status == .done)
    }

    @Test func aTombstoneComesBackUnderTheSameId() {
        let h = Habit(id: "h", goalKind: .count, goal: 8)
        var old = HabitCheckin(habitId: "h", day: day, value: 5, status: .partial, createdAt: 1, updatedAt: 2, deletedAt: 2, serverVersion: 7, dirty: false)
        old.id = HabitCheckin.id(habitId: "h", day: day)
        let c = checkIn(h, on: day, existing: old, now: 10)
        #expect(c.id == old.id)
        #expect(c.deletedAt == nil && c.value == 1 && c.serverVersion == 7 && c.dirty)
    }
}

@Suite("Habit days")
struct HabitDayTests {
    let today = Day(2026, 11, 18) // Wednesday

    @Test func dueFromTheStartOnItsWeekdays() {
        let h = Habit(id: "h", frequency: .weekdays([1, 3, 5]), startDate: Day(2026, 11, 17))
        #expect(!isDue(h, on: Day(2026, 11, 16))) // Monday, before the start
        #expect(!isDue(h, on: Day(2026, 11, 17))) // Tuesday
        #expect(isDue(h, on: Day(2026, 11, 18)))
        #expect(isDue(h, on: Day(2026, 11, 20)))
        #expect(!isDue(h, on: Day(2026, 11, 22)))
        let w = Habit(id: "w", frequency: .timesPerWeek(3), startDate: Day(2026, 11, 1))
        #expect((Day(2026, 11, 16)...Day(2026, 11, 22)).allSatisfy { isDue(w, on: $0) })
    }

    @Test func states() {
        let h = Habit(id: "h", goalKind: .count, goal: 4, frequency: .weekdays([1, 2, 3, 4, 5]), startDate: Day(2026, 11, 10))
        func s(_ d: Day, _ c: HabitCheckin? = nil) -> HabitDayState { dayState(h, on: d, checkin: c, today: today) }
        #expect(s(Day(2026, 11, 9)) == .beforeStart)
        #expect(s(Day(2026, 11, 15)) == .notDue) // Sunday
        #expect(s(Day(2026, 11, 16)) == .missed)
        #expect(s(today) == .pending)
        #expect(s(Day(2026, 11, 19)) == .future)
        #expect(s(Day(2026, 11, 16), HabitCheckin(habitId: "h", day: Day(2026, 11, 16), value: 1)) == .partial(0.25))
        #expect(s(Day(2026, 11, 16), HabitCheckin(habitId: "h", day: Day(2026, 11, 16), value: 0)) == .missed)
        #expect(s(Day(2026, 11, 16), HabitCheckin(habitId: "h", day: Day(2026, 11, 16), status: .abandoned)) == .abandoned)
        // A record wins over the schedule: done on a Sunday, or before the start.
        #expect(s(Day(2026, 11, 15), HabitCheckin(habitId: "h", day: Day(2026, 11, 15), value: 4, status: .done)) == .done)
        #expect(s(Day(2026, 11, 2), HabitCheckin(habitId: "h", day: Day(2026, 11, 2), value: 4, status: .done)) == .done)
        // Deleted rows don't count.
        #expect(s(Day(2026, 11, 16), HabitCheckin(habitId: "h", day: Day(2026, 11, 16), status: .done, deletedAt: 1)) == .missed)
    }

    @Test func aWeeklyCountHabitDoesNotMissSingleDays() {
        let h = Habit(id: "h", frequency: .timesPerWeek(2), startDate: Day(2026, 11, 1))
        #expect(dayState(h, on: Day(2026, 11, 16), checkin: nil, today: today) == .notDue)
        #expect(dayState(h, on: today, checkin: nil, today: today) == .pending)
    }

    @Test func dayStatesAcrossTheEndOfTheMonth() {
        let h = Habit(id: "h", startDate: Day(2026, 1, 1))
        let all = dayStates(h, checkins: done(h, Day(2026, 1, 31), Day(2026, 2, 1)) + [HabitCheckin(habitId: "other", day: Day(2026, 1, 30), status: .done)],
                            from: Day(2026, 1, 30), through: Day(2026, 2, 2), today: Day(2026, 2, 2))
        #expect(all.map(\.day) == [Day(2026, 1, 30), Day(2026, 1, 31), Day(2026, 2, 1), Day(2026, 2, 2)])
        #expect(all.map(\.state) == [.missed, .done, .done, .pending])
        #expect(dayStates(h, checkins: [], from: Day(2026, 2, 2), through: Day(2026, 2, 1), today: today).isEmpty)
    }
}

@Suite("Habit streaks")
struct HabitStreakTests {
    @Test func dailyTodayStillOpenDoesNotBreak() {
        let h = Habit(id: "h", startDate: Day(2026, 11, 1))
        let cs = done(h, Day(2026, 11, 15), Day(2026, 11, 16), Day(2026, 11, 17))
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 18)) == HabitStreak(current: 3, longest: 3, unit: .days))
        #expect(streak(h, checkins: cs + done(h, Day(2026, 11, 18)), today: Day(2026, 11, 18)).current == 4)
        // Yesterday missed: back to 0 (today open).
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 19)) == HabitStreak(current: 0, longest: 3, unit: .days))
    }

    @Test func missedAndAbandonedDaysBreak() {
        let h = Habit(id: "h", startDate: Day(2026, 11, 1))
        let cs = done(h, Day(2026, 11, 1), Day(2026, 11, 2), Day(2026, 11, 3), Day(2026, 11, 5), Day(2026, 11, 7))
            + [HabitCheckin(habitId: "h", day: Day(2026, 11, 6), value: 1, status: .abandoned)]
        let s = streak(h, checkins: cs, today: Day(2026, 11, 7))
        #expect(s.current == 1 && s.longest == 3)
    }

    @Test func partialDaysBreak() {
        let h = Habit(id: "h", goalKind: .count, goal: 8, startDate: Day(2026, 11, 1))
        let cs = done(h, Day(2026, 11, 1)) + [HabitCheckin(habitId: "h", day: Day(2026, 11, 2), value: 5)] + done(h, Day(2026, 11, 3))
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 3)) == HabitStreak(current: 1, longest: 1, unit: .days))
    }

    @Test func daysOffDoNotBreakAndCountWhenCheckedIn() {
        // Weekdays only; Friday 11-20 to Monday 11-23 across a weekend.
        let h = Habit(id: "h", frequency: .weekdays(1...5), startDate: Day(2026, 11, 1))
        let cs = done(h, Day(2026, 11, 19), Day(2026, 11, 20), Day(2026, 11, 23))
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 23)).current == 3)
        #expect(streak(h, checkins: cs + done(h, Day(2026, 11, 22)), today: Day(2026, 11, 23)).current == 4)
        // On Sunday the streak is still alive.
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 22)).current == 2)
    }

    @Test func acrossTheNewYearAndALeapDay() {
        let h = Habit(id: "h", startDate: Day(2027, 12, 1))
        let cs = (Day(2027, 12, 30)...Day(2028, 1, 2)).map { HabitCheckin(habitId: "h", day: $0, status: .done) }
        #expect(streak(h, checkins: cs, today: Day(2028, 1, 2)).current == 4)
        let leap = Habit(id: "h", startDate: Day(2028, 2, 1))
        let ls = done(leap, Day(2028, 2, 28), Day(2028, 2, 29), Day(2028, 3, 1))
        #expect(streak(leap, checkins: ls, today: Day(2028, 3, 1)).current == 3)
        // Skipping the leap day breaks it.
        #expect(streak(leap, checkins: done(leap, Day(2028, 2, 28), Day(2028, 3, 1)), today: Day(2028, 3, 1)).current == 1)
    }

    @Test func futureAndOtherHabitsCheckinsAreIgnored() {
        let h = Habit(id: "h", startDate: Day(2026, 11, 1))
        let cs = done(h, Day(2026, 11, 17), Day(2026, 11, 19)) + [HabitCheckin(habitId: "x", day: Day(2026, 11, 16), status: .done)]
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 17)) == HabitStreak(current: 1, longest: 1, unit: .days))
    }

    @Test func nothingYet() {
        let h = Habit(id: "h", startDate: Day(2026, 12, 1))
        #expect(streak(h, checkins: [], today: Day(2026, 11, 18)) == HabitStreak(current: 0, longest: 0, unit: .days))
        let w = Habit(id: "w", frequency: .timesPerWeek(3), startDate: Day(2026, 12, 1))
        #expect(streak(w, checkins: [], today: Day(2026, 11, 18)).unit == .weeks)
    }

    @Test func weeklyCountsWholeWeeksFromMonday() {
        // Three times a week, from Monday 2026-11-02.
        let h = Habit(id: "h", frequency: .timesPerWeek(3), startDate: Day(2026, 11, 2))
        let cs = done(h, Day(2026, 11, 2), Day(2026, 11, 4), Day(2026, 11, 8)) // week 1: 3, ending on Sunday
            + done(h, Day(2026, 11, 9), Day(2026, 11, 10), Day(2026, 11, 11)) // week 2: 3
            + done(h, Day(2026, 11, 16)) // this week: 1 so far
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 18)) == HabitStreak(current: 2, longest: 2, unit: .weeks))
        let more = cs + done(h, Day(2026, 11, 17), Day(2026, 11, 18))
        #expect(streak(h, checkins: more, today: Day(2026, 11, 18)).current == 3)
        // Next Monday the short week is over: broken.
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 23)) == HabitStreak(current: 0, longest: 2, unit: .weeks))
    }

    @Test func weeklyFirstWeekNeedsOnlyTheDaysItHad() {
        // Starts on Saturday: two days left in its first week, needs 2 of 3.
        let h = Habit(id: "h", frequency: .timesPerWeek(3), startDate: Day(2026, 11, 7))
        let cs = done(h, Day(2026, 11, 7), Day(2026, 11, 8)) + done(h, Day(2026, 11, 9), Day(2026, 11, 10), Day(2026, 11, 12))
        #expect(streak(h, checkins: cs, today: Day(2026, 11, 16)).current == 2)
        // Weeks across the new year: Monday 2029-12-31.
        let y = Habit(id: "y", frequency: .timesPerWeek(1), startDate: Day(2029, 12, 24))
        let ys = done(y, Day(2029, 12, 24), Day(2030, 1, 6))
        #expect(streak(y, checkins: ys, today: Day(2030, 1, 7)).current == 2)
    }

    @Test func totals() {
        let h = Habit(id: "h")
        let cs = done(h, Day(2026, 1, 1), Day(2026, 1, 2))
            + [HabitCheckin(habitId: "h", day: Day(2026, 1, 3), value: 1),
               HabitCheckin(habitId: "h", day: Day(2026, 1, 4), status: .done, deletedAt: 5),
               HabitCheckin(habitId: "x", day: Day(2026, 1, 5), status: .done)]
        #expect(totalCheckins(h, checkins: cs) == 2)
    }
}

@Suite("Habit month rate")
struct HabitRateTests {
    @Test func dailyInALeapFebruary() {
        let h = Habit(id: "h", startDate: Day(2028, 1, 1))
        let cs = (Day(2028, 2, 1)...Day(2028, 2, 29)).filter { $0.day % 2 == 1 }.map { HabitCheckin(habitId: "h", day: $0, status: .done) }
        #expect(monthCompletionRate(h, checkins: cs, year: 2028, month: 2, today: Day(2028, 3, 5)) == 15.0 / 29.0)
        // Mid-month counts through today only.
        #expect(monthCompletionRate(h, checkins: cs, year: 2028, month: 2, today: Day(2028, 2, 4)) == 2.0 / 4.0)
    }

    @Test func fromTheStartAndNilBeforeIt() {
        let h = Habit(id: "h", startDate: Day(2026, 11, 20))
        let cs = done(h, Day(2026, 11, 20), Day(2026, 11, 21), Day(2026, 11, 3))
        #expect(monthCompletionRate(h, checkins: cs, year: 2026, month: 11, today: Day(2026, 11, 30)) == 2.0 / 11.0)
        #expect(monthCompletionRate(h, checkins: cs, year: 2026, month: 10, today: Day(2026, 11, 30)) == nil)
        #expect(monthCompletionRate(h, checkins: cs, year: 2026, month: 12, today: Day(2026, 11, 30)) == nil)
    }

    @Test func weekdaysIgnoreDaysOff() {
        // December 2026: 23 weekdays.
        let h = Habit(id: "h", frequency: .weekdays(1...5), startDate: Day(2026, 1, 1))
        let cs = done(h, Day(2026, 12, 1), Day(2026, 12, 5), Day(2026, 12, 6))
        #expect(monthCompletionRate(h, checkins: cs, year: 2026, month: 12, today: Day(2027, 1, 1)) == 1.0 / 23.0)
    }

    @Test func weeklyCountsPerWeek() {
        // Twice a week in February 2026 (starts on a Sunday, 4 more full weeks ending 3-1).
        let h = Habit(id: "h", frequency: .timesPerWeek(2), startDate: Day(2026, 1, 1))
        let cs = done(h, Day(2026, 2, 1)) // week of 1-26: 1 day in February, wants 1
            + done(h, Day(2026, 2, 2), Day(2026, 2, 3), Day(2026, 2, 4)) // 3 of 2: capped
            + done(h, Day(2026, 2, 10)) // 1 of 2
        // Weeks: 2-1 (1 day, want 1), 2-2, 2-9, 2-16, 2-23 (want 2 each, 2-23..28 has 6 days) = 9.
        #expect(monthCompletionRate(h, checkins: cs, year: 2026, month: 2, today: Day(2026, 3, 1)) == 4.0 / 9.0)
    }
}

@Suite("Today's habits")
struct TodayHabitsTests {
    let today = Day(2026, 11, 18) // Wednesday

    @Test func bySectionInOrder() {
        let hs = [
            Habit(id: "a", section: .anytime, sortOrder: 1),
            Habit(id: "b", section: .evening, sortOrder: 2),
            Habit(id: "c", section: .morning, sortOrder: 3),
            Habit(id: "d", section: .morning, sortOrder: 1),
            Habit(id: "e", section: .evening, archivedAt: 1),
            Habit(id: "f", section: .evening, deletedAt: 1),
            Habit(id: "g", startDate: Day(2026, 11, 19)),
            Habit(id: "h", frequency: .weekdays([1, 2])),
        ]
        let groups = todayHabits(hs, checkins: [], today: today)
        #expect(groups.map(\.section) == [.morning, .evening, .anytime])
        #expect(groups.map { $0.habits.map(\.id) } == [["d", "c"], ["b"], ["a"]])
    }

    @Test func weeklyCountHabitsLeaveOnceTheWeekIsDone() {
        let h = Habit(id: "w", frequency: .timesPerWeek(2))
        #expect(todayHabits([h], checkins: done(h, Day(2026, 11, 16)), today: today).count == 1)
        #expect(todayHabits([h], checkins: done(h, Day(2026, 11, 16), Day(2026, 11, 17)), today: today).isEmpty)
        // Last week's don't count.
        #expect(todayHabits([h], checkins: done(h, Day(2026, 11, 14), Day(2026, 11, 15)), today: today).count == 1)
        // Checked in today: stays, to show it done.
        #expect(todayHabits([h], checkins: done(h, Day(2026, 11, 16), Day(2026, 11, 18)), today: today).count == 1)
    }
}

@Suite("Habit day completion")
struct HabitDayCompletionTests {
    @Test func countsDueHabitsDone() {
        let a = Habit(id: "a"), b = Habit(id: "b", frequency: .weekdays([1])), c = Habit(id: "c", archivedAt: 1)
        let d = Day(2026, 11, 16) // Monday
        let cs = done(a, d) + done(c, d)
        #expect(dayCompletion([a, b, c], checkins: cs, on: d) == (1, 2))
        #expect(dayCompletion([a, b, c], checkins: cs, on: d + 1) == (0, 1))
        #expect(dayCompletion([], checkins: [], on: d) == (0, 0))
    }
}
