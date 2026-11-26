// Habit and countdown reminders, in one budget with the tasks'.

import Testing
@testable import OpenTodoDomain

private let effNow = LocalDateTime(2026, 11, 16, 10) // Monday 10:00
private let effMonday = Day(2026, 11, 16)

private func shape(_ es: [ReminderEvent]) -> [String] {
    es.map { "\($0.kind.rawValue) \($0.title) \($0.at)" }
}

@Suite struct EfficiencyRemindersTests {
    @Test("a habit reminds on the days it is due, from its start, not once done or given up")
    func habits() {
        let run = Habit(id: "run", name: "跑步", emoji: "🏃", frequency: .onWeekdays([1, 3]), reminders: [7 * 60, 20 * 60],
                        startDate: Day(2026, 11, 1))
        let late = Habit(id: "late", name: "读书", reminders: [21 * 60], startDate: Day(2026, 11, 18))
        let archived = Habit(id: "a", name: "旧的", reminders: [21 * 60], startDate: Day(2026, 11, 1), archivedAt: 1)
        let gone = Habit(id: "g", name: "删了", reminders: [21 * 60], startDate: Day(2026, 11, 1), deletedAt: 1)
        let events = habitReminders([run, late, archived, gone], checkins: [], now: effNow)
        #expect(shape(events) == [
            "habit 🏃 跑步 2026-11-16T20:00", // 07:00 has gone by
            "habit 🏃 跑步 2026-11-18T07:00", "habit 🏃 跑步 2026-11-18T20:00",
            "habit 读书 2026-11-18T21:00", "habit 读书 2026-11-19T21:00", "habit 读书 2026-11-20T21:00",
            "habit 读书 2026-11-21T21:00", "habit 读书 2026-11-22T21:00",
        ])
        #expect(events.first?.body == "该打卡了")

        // Done today, given up on Wednesday; a partial count still reminds.
        let water = Habit(id: "w", name: "喝水", goalKind: .count, goal: 8, unit: "杯", reminders: [15 * 60], startDate: Day(2026, 11, 1))
        let checkins = [
            HabitCheckin(habitId: "run", day: effMonday, value: 1, status: .done),
            HabitCheckin(habitId: "run", day: effMonday + 2, status: .abandoned),
            HabitCheckin(habitId: "w", day: effMonday, value: 3, status: .partial),
            HabitCheckin(habitId: "w", day: effMonday + 1, value: 8, status: .done, deletedAt: 5), // taken back
        ]
        let after = habitReminders([run, water], checkins: checkins, now: effNow, days: 3)
        #expect(shape(after) == ["habit 喝水 2026-11-16T15:00", "habit 喝水 2026-11-17T15:00", "habit 喝水 2026-11-18T15:00"])
        #expect(after.first?.body == "今天的目标：8杯")
    }

    @Test("每周 N 次 stops reminding once the week has its N")
    func timesPerWeek() {
        let gym = Habit(id: "gym", name: "健身", frequency: .timesPerWeek(2), reminders: [18 * 60], startDate: Day(2026, 11, 1))
        let twice = [
            HabitCheckin(habitId: "gym", day: effMonday - 7, value: 1, status: .done), // last week's don't count
            HabitCheckin(habitId: "gym", day: effMonday, value: 1, status: .done),
        ]
        #expect(habitReminders([gym], checkins: twice, now: effNow).count == 6) // Tue–Sun, and next Monday… within 7 days
        let full = twice + [HabitCheckin(habitId: "gym", day: effMonday + 1, value: 1, status: .done)]
        // This week is done (Mon, Tue): only next Monday, the 7th day.
        #expect(shape(habitReminders([gym], checkins: full, now: effNow)) == [])
        #expect(shape(habitReminders([gym], checkins: full, now: effNow, days: 8)) == ["habit 健身 2026-11-23T18:00"])
    }

    @Test("a countdown reminds before its next occurrence")
    func countdowns() {
        let birthday = Countdown(id: "b", title: "妈妈生日", kind: .birthday, date: Day(1960, 11, 18), repeats: .yearly,
                                 emoji: "🎂", reminders: [countdownReminder(daysBefore: 1, minute: 9 * 60), 8 * 60])
        let events = countdownReminders([birthday], now: effNow)
        #expect(shape(events) == ["countdown 🎂 妈妈生日 2026-11-17T09:00", "countdown 🎂 妈妈生日 2026-11-18T08:00"])
        #expect(events.map(\.body) == ["还有1天 · 11月18日", "就是今天 · 11月18日"])
        // Once this year's have gone off: next year's.
        let later = countdownReminders([birthday], now: LocalDateTime(2026, 11, 18, 9))
        #expect(shape(later) == ["countdown 🎂 妈妈生日 2027-11-17T09:00", "countdown 🎂 妈妈生日 2027-11-18T08:00"])
        // A one-off that has gone by, or one without reminders: nothing.
        let past = Countdown(id: "p", title: "考试", date: Day(2026, 11, 1), reminders: [540])
        #expect(countdownReminders([past, Countdown(id: "n", date: effMonday + 3)], now: effNow).isEmpty)
    }

    @Test("one budget of the soonest for tasks, habits and countdowns; ids never meet")
    func together() {
        let task = TodoTask(id: "x", title: "开会", dueDate: effMonday, dueTime: 15 * 60, reminders: [0])
        let habit = Habit(id: "x", name: "喝水", reminders: [15 * 60, 16 * 60], startDate: effMonday)
        let cd = Countdown(id: "x", title: "生日", date: effMonday + 1, reminders: [15 * 60 - 1440])
        let all = upcomingReminders(tasks: [task], habits: [habit], checkins: [], countdowns: [cd], now: effNow, limit: 3)
        #expect(shape(all) == ["task 开会 2026-11-16T15:00", "habit 喝水 2026-11-16T15:00", "countdown 生日 2026-11-16T15:00"])
        // Same id, same minute, three kinds: three notification ids. A task's
        // is the number the Dart version gave it.
        #expect(Set(all.map { $0.id() }).count == 3)
        #expect(all[0].id() == notificationId("x", all[0].at))
        // Tasks alone: as before.
        #expect(upcomingReminders(tasks: [task], now: effNow) == upcomingReminders([task], effNow))
    }
}
