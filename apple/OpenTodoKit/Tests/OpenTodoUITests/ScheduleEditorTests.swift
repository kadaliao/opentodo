// The date dialog's rules, without a view. The first four suites are the
// date-dialog parts of `app/test/app_test.dart` (widget tests there; here
// the same steps on `ScheduleEditor`), the rest the edge cases of
// `app/lib/ui/schedule_dialog.dart`.

import OpenTodoDomain
import Testing
@testable import OpenTodoUI

/// Thursday 26 November 2026, 14:20.
private let now = LocalDateTime(2026, 11, 26, 14, 20)
private let today = now.day

private func editor(_ draft: ScheduleDraft, defaults: TaskDefaults = .standard) -> ScheduleEditor {
    ScheduleEditor(draft, defaults: defaults, now: now)
}

// MARK: - From app_test.dart

@Suite("desktop: the date dialog sets a time span")
struct DialogSetsATimeSpan {
    @Test func spanStartsFromTheTaskTimeAndLastsAnHour() {
        // 上午10点评审: a time comes with 准时.
        var e = editor(ScheduleDraft(dueDate: today, dueTime: 600, reminders: [0]))
        e.setSpan(true)
        #expect(e.isSpan)
        #expect(timeLabel(e.time!) == "上午10:00")
        #expect(timeLabel(e.end.minuteOfDay) == "上午11:00")
        let r = e.result!
        #expect((r.dueTime, r.duration, r.reminders) == (600, 60, [0]))
    }

    @Test func allDayKeepsTheDatesAndDropsTheTimes() {
        var e = editor(ScheduleDraft(dueDate: today, dueTime: 600, duration: 60, reminders: [0]))
        #expect(e.isSpan) // opens on 时间段
        e.setSpanAllDay(true)
        #expect(e.time == nil)
        let r = e.result!
        #expect(r.dueTime == nil)
        #expect(r.duration == nil)
        #expect(r.reminders == [])
    }

    @Test func backToOneDateDropsTheSpan() {
        // 明天下午3点到5点 培训
        var e = editor(ScheduleDraft(dueDate: today + 1, dueTime: 900, duration: 120, reminders: [0]))
        e.setSpan(false)
        let r = e.result!
        #expect(r.dueTime == 900)
        #expect(r.duration == nil)
    }
}

@Suite("desktop: default reminders from the settings")
struct DefaultRemindersFromTheSettings {
    let defaults = TaskDefaults(timedReminders: [-30], allDayReminders: [540], spanMinutes: 30)

    @Test func aTaskWithoutADateGetsThemAndASpanStartsAtTheDefaultLength() {
        var e = editor(ScheduleDraft(dueDate: nil), defaults: defaults)
        #expect(e.date == today)
        #expect(e.remindersText == "当天 09:00")
        e.setSpan(true)
        #expect(e.remindersText == "提前30分钟") // timed now
        let r = e.result!
        #expect(r.duration == 30)
        #expect(r.reminders == [-30])
    }
}

@Suite("the date dialog sets reminders and repeat")
struct DialogSetsRemindersAndRepeat {
    @Test func dailyThenRemindersThenEveryOtherDay() throws {
        var e = editor(ScheduleDraft(dueDate: today))
        #expect(e.remindersText == nil) // the row says 提醒

        let daily = try #require(e.repeatPresets.first { $0.title == "每天" })
        e.choose(daily)
        #expect(e.repeatText == "每天")

        var choices = ReminderChoices(allDay: e.isAllDay, selected: e.reminders)
        #expect(choices.options.map(choices.label).contains("当天 09:00"))
        choices.toggle(540)
        e.setReminders(choices.reminders)
        #expect(e.remindersText == "当天 09:00")

        // A custom rule: every other day.
        #expect(e.isChosen(daily))
        var custom = e.customRepeatEditor
        custom.interval = 2
        #expect(custom.summary == "每2天") // preview
        e.setCustomRepeat(try #require(custom.rule), from: custom.from)
        #expect(e.repeatText == "每2天")
        #expect(e.isCustomRepeat)

        let r = try #require(e.result)
        #expect(r.repeatRuleText == "FREQ=DAILY;INTERVAL=2")
        #expect(r.reminders == [540])
        #expect(r.dueTime == nil)
    }
}

@Suite("the date dialog repeats on statutory working days or by the lunar calendar")
struct DialogRepeatsOnWorkdaysOrLunar {
    @Test func statutoryWorkdays() throws {
        var e = editor(ScheduleDraft(dueDate: today))
        e.choose(try #require(e.repeatPresets.first { $0.title == "法定工作日（按节假日调休）" }))
        #expect(e.result?.repeatRuleText == "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;X-HOLIDAYS=CN")
    }

    @Test func lunarYearlyAndTheCustomDialogKeepsIt() throws {
        let lunar = try #require(toLunar(today))
        let yearly = "\(lunarMonthName(lunar.month))\(lunarDayName(lunar.day))"
        var e = editor(ScheduleDraft(dueDate: today))
        e.choose(try #require(e.repeatPresets.first { $0.title == "农历每年（\(yearly)）" }))
        let rule = try #require(e.repeatRule)
        #expect(rule == RepeatRule.lunarYearlyOn(today))
        #expect(describeRepeat(rule, today) == "农历每年\(yearly)")

        // The custom dialog keeps it lunar.
        let custom = e.customRepeatEditor
        #expect(custom.showsLunar)
        #expect(custom.lunar)
        #expect(custom.summary == "农历每年\(yearly)")
        e.setCustomRepeat(try #require(custom.rule), from: custom.from)
        #expect(e.repeatRule == RepeatRule.lunarYearlyOn(today))
        #expect(!e.isCustomRepeat)
    }
}

// MARK: - The dialog

@Suite struct ScheduleEditorStates {
    @Test func opensOnTheTaskOrToday() {
        let e = editor(ScheduleDraft(dueDate: Day(2027, 1, 5), dueTime: 480, reminders: [0, -60, 0]))
        #expect(e.date == Day(2027, 1, 5))
        #expect(e.reminders == [-60, 0]) // sorted, once each
        #expect(!e.isSpan)
        #expect(editor(ScheduleDraft(dueDate: nil, duration: 120)).isSpan == false)
        #expect(editor(ScheduleDraft(dueDate: nil)).date == today)
    }

    @Test func switchingBetweenTimeAndAllDayStartsTheRemindersOver() {
        var e = editor(ScheduleDraft(dueDate: today, reminders: [540, -900]))
        e.setTime(600)
        #expect(e.reminders == [0])
        e.setReminders([-5, 0])
        e.setTime(720) // still timed: kept
        #expect(e.reminders == [-5, 0])
        e.setTime(nil)
        #expect(e.reminders == [])
    }

    @Test func spanStartsAtTheNextHourTodayOrNineAnotherDay() {
        var e = editor(ScheduleDraft(dueDate: today))
        e.setSpan(true)
        #expect(e.time == 15 * 60)
        #expect(e.duration == 60)
        #expect(e.reminders == [0])

        var other = editor(ScheduleDraft(dueDate: today + 3))
        other.setSpan(true)
        #expect(other.time == 9 * 60)

        // After 23:00 today: the morning.
        var late = ScheduleEditor(ScheduleDraft(dueDate: today), now: LocalDateTime(today, minute: 23 * 60 + 10))
        late.setSpan(true)
        #expect(late.time == 9 * 60)
    }

    @Test func spanOfATimedTaskKeepsItsTime() {
        var e = editor(ScheduleDraft(dueDate: today, dueTime: 8 * 60))
        e.setSpan(true)
        #expect(e.time == 8 * 60)
        #expect(e.duration == 60)
    }

    @Test func anAllDaySpanKeepsItsDays() {
        var e = editor(ScheduleDraft(dueDate: today, duration: 3 * minutesPerDay))
        #expect(e.isSpan && e.isAllDay)
        #expect(e.end == LocalDateTime(today + 2))
        e.setSpan(false)
        e.setSpan(true) // a duration already: no time added
        #expect(e.isAllDay)
        #expect(e.result?.duration == 3 * minutesPerDay)
    }

    @Test func endAcrossMidnight() {
        var e = editor(ScheduleDraft(dueDate: today, dueTime: 22 * 60, duration: 60))
        e.setEndDay(today + 1)
        #expect(e.duration == 25 * 60)
        e.setEndTime(90) // 01:30 the next day
        #expect(e.duration == 3 * 60 + 30)
        #expect(e.end == LocalDateTime(today + 1, minute: 90))
        #expect(e.result?.duration == 210)
    }

    @Test func anEndBeforeTheStartIsNotAllowed() {
        var e = editor(ScheduleDraft(dueDate: today, dueTime: 600, duration: 60))
        e.setEndTime(9 * 60)
        #expect(e.duration == -60)
        #expect(!e.isSpanValid)
        #expect(e.result == nil)
        e.setEndTime(10 * 60) // the same minute: still not
        #expect(e.result == nil)

        var allDay = editor(ScheduleDraft(dueDate: today, duration: 2 * minutesPerDay))
        allDay.setEndDay(today - 1)
        #expect(allDay.duration == 0)
        #expect(allDay.result == nil)
        allDay.setEndDay(today) // one day: valid, but no span at all
        #expect(allDay.isSpanValid)
        #expect(allDay.result?.duration == nil)
    }

    @Test func moreThanADayToAllDayCountsTheDaysItTouches() {
        // 22:00 to 01:30 the day after: two days.
        var e = editor(ScheduleDraft(dueDate: today, dueTime: 22 * 60, duration: 210))
        e.setSpanAllDay(true)
        #expect(e.duration == 2 * minutesPerDay)
        // Ending at midnight doesn't touch the next day.
        var m = editor(ScheduleDraft(dueDate: today, dueTime: 22 * 60, duration: 120))
        m.setSpanAllDay(true)
        #expect(m.duration == minutesPerDay)
        // Back to times: 9:00 for the default length.
        m.setSpanAllDay(false)
        #expect((m.time, m.duration) == (540, 60))
        #expect(m.reminders == [0])
    }

    @Test func movingTheStartKeepsTheLength() {
        var e = editor(ScheduleDraft(dueDate: today, dueTime: 600, duration: 90))
        e.setStartDay(today + 2)
        e.setStartTime(13 * 60)
        #expect(e.end == LocalDateTime(today + 2, minute: 14 * 60 + 30))
    }

    @Test func quickDates() {
        let q = QuickDate.all(today: today)
        #expect(q.map(\.title) == ["今天", "明天", "下周一", "下个月"])
        #expect(q.map(\.day) == [today, today + 1, Day(2026, 11, 30), Day(2026, 12, 26)])
        // Rolls over like Dart's DateTime.
        #expect(QuickDate.all(today: Day(2027, 1, 31))[3].day == Day(2027, 3, 3))
    }

    @Test func clearingIsItsOwnResult() {
        let c = ScheduleDraft.cleared
        #expect(c.isCleared)
        #expect(c.reminders.isEmpty && c.repeatRule == nil && c.dueTime == nil)
        let task = TodoTask(id: "t", title: "x", dueDate: today, dueTime: 600, duration: 30,
                            reminders: [0], repeatRule: "FREQ=DAILY", repeatFrom: .completion)
        let cleared = c.applied(to: task)
        #expect(cleared.dueDate == nil && cleared.dueTime == nil && cleared.duration == nil)
        #expect(cleared.reminders.isEmpty && cleared.repeatRule == nil && cleared.repeatFrom == .dueDate)
        #expect(ScheduleDraft(task: task).applied(to: task) == task)
    }

    @Test func aTaskWithUnreadableRepeatTextHasNone() {
        let task = TodoTask(id: "t", title: "x", dueDate: today, repeatRule: "FREQ=SECONDLY")
        #expect(ScheduleDraft(task: task).repeatRule == nil)
    }
}

// MARK: - Repeat menu

@Suite struct RepeatMenu {
    @Test func presetsUseTheTaskDate() {
        let titles = RepeatPreset.all(for: Day(2026, 11, 26)).map(\.title)
        let l = toLunar(Day(2026, 11, 26))!
        #expect(titles == [
            "不重复", "每天", "每周（周四）", "每月（26日）", "每年（11月26日）",
            "工作日（周一至周五）", "法定工作日（按节假日调休）",
            "农历每年（\(lunarMonthName(l.month))\(lunarDayName(l.day))）", "农历每月（\(lunarDayName(l.day))）",
            "艾宾浩斯记忆法",
        ])
        // Outside the lunar table: no lunar lines.
        #expect(!RepeatPreset.all(for: Day(2101, 3, 1)).map(\.title).contains { $0.hasPrefix("农历") })
    }

    @Test func theCheck() throws {
        var e = editor(ScheduleDraft(dueDate: today))
        #expect(e.isChosen(e.repeatPresets[0])) // 不重复
        e.setRepeat(.weekly)
        #expect(e.isChosen(e.repeatPresets[2]))
        #expect(!e.isCustomRepeat)
        // From completion: custom even when the rule is a preset's.
        e.setCustomRepeat(.weekly, from: .completion)
        #expect(e.isCustomRepeat)
        #expect(!e.repeatPresets.contains(where: e.isChosen))
        #expect(e.repeatText == "每周四（按完成日期）")
        // A preset counts from the due date again.
        e.choose(e.repeatPresets[1])
        #expect(e.repeatFrom == .dueDate)
        e.clearRepeat()
        #expect(e.repeatRule == nil && e.repeatText == nil)
    }

    @Test func ebbinghausKeepsItsRound() throws {
        var e = editor(ScheduleDraft(dueDate: today, repeatRule: .ebbinghaus(round: 3)))
        let preset = try #require(e.repeatPresets.last)
        #expect(preset.isEbbinghaus)
        #expect(e.isChosen(preset))
        #expect(!e.isCustomRepeat)
        e.choose(preset)
        #expect(e.repeatRule == .ebbinghaus(round: 3))
        e.setRepeat(.daily)
        e.choose(preset)
        #expect(e.repeatRule == .ebbinghaus)
    }

    @Test func customOpensOnTheRuleOrWeekly() {
        var e = editor(ScheduleDraft(dueDate: today))
        #expect(e.customRepeatEditor.rule == .weekly.with(weekdays: [4]))
        e.setRepeat(.monthly)
        #expect(e.customRepeatEditor.rule == RepeatRule(.monthly, monthDays: [26]))
    }
}

private extension RepeatRule {
    func with(weekdays: [Int]) -> RepeatRule {
        var r = self
        r.weekdays = weekdays
        return r
    }
}

// MARK: - Custom repeat

@Suite struct CustomRepeat {
    @Test func weekdaysStartFromTheTaskAndOneStaysOn() {
        var c = CustomRepeatEditor(date: today, rule: .weekly, repeatFrom: .dueDate) // a Thursday
        #expect(c.weekdays == [4])
        c.toggleWeekday(4)
        #expect(c.weekdays == [4])
        c.toggleWeekday(1)
        c.toggleWeekday(4)
        #expect(c.rule?.description == "FREQ=WEEKLY;BYDAY=MO")
    }

    @Test func holidaysOnlyForMondayToFridayEveryWeek() {
        var c = CustomRepeatEditor(date: today, rule: .workdays, repeatFrom: .dueDate)
        #expect(c.showsHolidays)
        c.holidays = true
        #expect(c.rule == .statutoryWorkdays)
        c.interval = 2
        #expect(!c.showsHolidays)
        #expect(c.rule?.chinaHolidays == false)
        c.interval = 1
        c.toggleWeekday(6)
        #expect(!c.showsHolidays)
        #expect(c.rule?.chinaHolidays == false)
        #expect(CustomRepeatEditor(date: today, rule: .statutoryWorkdays, repeatFrom: .dueDate).holidays)
    }

    @Test func monthlyByDayOrByWeekday() {
        var c = CustomRepeatEditor(date: today, rule: .monthly, repeatFrom: .dueDate)
        #expect(c.showsMonthly)
        #expect(c.monthDay == 26)
        #expect(!c.byWeekday)
        #expect((c.nth, c.nthDay) == (-1, 4)) // the last Thursday
        c.setNth(2)
        #expect(c.byWeekday)
        #expect(c.rule?.description == "FREQ=MONTHLY;BYDAY=2TH")
        #expect(c.summary == "每月第2个周四")
        c.setNth(-1)
        #expect(c.summary == "每月最后一个周四")
        c.setMonthDay(-1)
        #expect(!c.byWeekday)
        #expect(c.summary == "每月最后一天")
        c.setNthDay(1)
        #expect(c.summary == "每月最后一个周一")
        // The last week of a month counts as the last.
        #expect(CustomRepeatEditor(date: Day(2026, 11, 23), rule: .monthly, repeatFrom: .dueDate).nth == 4)
        #expect(CustomRepeatEditor(date: Day(2026, 11, 8), rule: .monthly, repeatFrom: .dueDate).nth == 2)
    }

    @Test func lunarMonthly() throws {
        let l = try #require(toLunar(today))
        var c = CustomRepeatEditor(date: today, rule: .monthly, repeatFrom: .dueDate)
        #expect(c.showsLunar && !c.showsLunarMonthDay)
        c.setLunar(true)
        #expect(c.showsLunarMonthDay && !c.showsMonthly)
        #expect(c.monthDay == l.day)
        #expect(c.rule == RepeatRule.lunarMonthlyOn(today))
        c.setMonthDay(-1)
        #expect(c.summary == "农历每月最后一天")
        c.setLunar(false)
        #expect(c.monthDay == 26)
        // Daily and weekly can't be lunar.
        c.setLunar(true)
        c.freq = .daily
        #expect(!c.showsLunar)
        #expect(c.rule == .daily)
    }

    @Test func lunarYearlyUsesTheLunarMonth() throws {
        let l = try #require(toLunar(today))
        var c = CustomRepeatEditor(date: today, rule: .yearly, repeatFrom: .dueDate)
        c.setLunar(true)
        #expect(c.rule == RepeatRule(.yearly, monthDays: [l.day], month: l.month, lunar: true))
        c.interval = 2
        #expect(c.summary.hasPrefix("每2年的农历"))
    }

    @Test func outsideTheLunarTableNoLunar() {
        let c = CustomRepeatEditor(date: Day(2101, 3, 1), rule: .yearly, repeatFrom: .dueDate)
        #expect(!c.showsLunar)
    }

    @Test func fromCompletionDropsTheDays() {
        var c = CustomRepeatEditor(date: today, rule: RepeatRule(.weekly, weekdays: [1, 3]), repeatFrom: .dueDate)
        c.from = .completion
        #expect(!c.showsWeekdays)
        #expect(c.rule == .weekly)
        #expect(c.summary == "每周四（按完成日期）")
        c.freq = .monthly
        c.setLunar(true)
        #expect(c.rule == .monthly)
    }

    @Test func endsOnADateOrAfterACount() {
        var c = CustomRepeatEditor(date: today, rule: .daily, repeatFrom: .dueDate)
        #expect(c.end == .never)
        #expect(c.until == Day(2026, 12, 26))
        #expect(c.count == 10)
        c.end = .until
        #expect(c.rule?.until == Day(2026, 12, 26))
        #expect(c.summary == "每天，至2026年12月26日")
        c.end = .count
        c.count = 3
        #expect(c.summary == "每天，还剩3次")
        c.count = 0
        #expect(c.rule == nil)
        #expect(c.summary == "请填写有效的数字")
        c.end = .never
        #expect(c.rule == .daily)

        let fromRule = CustomRepeatEditor(date: today, rule: RepeatRule(.daily, until: Day(2027, 2, 1)), repeatFrom: .dueDate)
        #expect(fromRule.end == .until && fromRule.until == Day(2027, 2, 1))
        #expect(CustomRepeatEditor(date: today, rule: RepeatRule(.daily, count: 4), repeatFrom: .dueDate).count == 4)
    }

    @Test func intervalOutOfRange() {
        var c = CustomRepeatEditor(date: today, rule: .daily, repeatFrom: .dueDate)
        c.interval = 0
        #expect(c.rule == nil)
        c.interval = 1000
        #expect(c.rule == nil)
        c.interval = 999
        #expect(c.rule?.interval == 999)
    }

    @Test func unchangedItGivesBackTheRule() {
        // A rule leaving out what the date fills in comes back with it:
        // 每周 on a Thursday is 每周四.
        #expect(CustomRepeatEditor(date: today, rule: .weekly, repeatFrom: .dueDate).rule?.description
            == "FREQ=WEEKLY;BYDAY=TH")
        for rule in [RepeatRule.daily, .workdays, .statutoryWorkdays,
                     RepeatRule(.weekly, interval: 2, weekdays: [1, 3, 5], count: 10),
                     RepeatRule(.monthly, nthWeekday: NthWeekday(n: 2, weekday: 2)),
                     RepeatRule(.monthly, monthDays: [-1], until: Day(2027, 6, 1)),
                     RepeatRule.lunarMonthlyOn(today)!, RepeatRule.lunarYearlyOn(today)!] {
            #expect(CustomRepeatEditor(date: today, rule: rule, repeatFrom: .dueDate).rule == rule, "\(rule)")
        }
    }
}

// MARK: - Reminders

@Suite struct Reminders {
    @Test func optionsLatestFirstWithTheTaskOwn() {
        let timed = ReminderChoices(allDay: false, selected: [-15])
        #expect(timed.options == [0, -5, -15, -30, -60, -1440])
        #expect(timed.options.map(timed.label) == ["准时", "提前5分钟", "提前15分钟", "提前30分钟", "提前1小时", "提前1天"])
        let allDay = ReminderChoices(allDay: true, selected: [])
        #expect(allDay.options.map(allDay.label) == ["当天 09:00", "提前1天 09:00", "提前2天 09:00", "提前1周 09:00"])
    }

    @Test func turningOneOffKeepsItListedAndCustomOnesJoin() {
        var c = ReminderChoices(allDay: false, selected: [-15, 0])
        c.toggle(-15)
        #expect(c.options.contains(-15))
        #expect(c.reminders == [0])
        c.add(-120)
        #expect(c.options == [0, -5, -15, -30, -60, -120, -1440])
        #expect(c.reminders == [-120, 0])
        c.add(-5) // already listed
        #expect(c.options.count == 7)
        c.clear()
        #expect(c.reminders.isEmpty)
    }

    @Test func customReminder() {
        var t = CustomReminder(allDay: false)
        #expect(t.amount == 10)
        #expect(t.label == "提前10分钟")
        t.unit = .hours
        t.amount = 2
        #expect(t.offset == -120)
        t.unit = .days
        #expect(t.label == "提前2天")
        t.amount = 1000
        #expect(t.offset == nil)
        t.amount = -1
        #expect(t.offset == nil)

        var a = CustomReminder(allDay: true)
        #expect(a.amount == 1)
        #expect(a.label == "提前1天 09:00")
        a.minuteOfDay = 20 * 60 + 30
        a.amount = 0
        #expect(a.offset == 1230)
        #expect(a.label == "当天 20:30")
    }

    @Test func clearingReminders() {
        var e = editor(ScheduleDraft(dueDate: today, dueTime: 600, reminders: [0]))
        e.clearReminders()
        #expect(e.result?.reminders == [])
        #expect(e.remindersText == nil)
    }
}

// MARK: - Month

@Suite struct Month {
    @Test func weeksFromMondayWithOtherMonthsBlank() {
        let weeks = MonthPage(Day(2026, 11, 26)).weeks
        #expect(weeks.count == 6) // 1 November 2026 is a Sunday
        #expect(weeks[0].compactMap(\.self) == [Day(2026, 11, 1)])
        #expect(weeks[5].compactMap(\.self) == [Day(2026, 11, 30)])
        #expect(MonthPage(Day(2027, 2, 1)).weeks.count == 4) // February 2027 starts on a Monday
        #expect(MonthPage(year: 2026, month: 13) == MonthPage(Day(2027, 1, 1)))
        #expect(MonthPage(Day(2026, 1, 5)).adding(months: -1).title == "2025年12月")
    }

    @Test func dayNotes() {
        let spring = ScheduleDayNote(Day(2026, 2, 17)) // 春节, off
        #expect(spring.label == "春节" && spring.special && spring.off == true)
        let worked = ScheduleDayNote(Day(2026, 2, 14)) // a Saturday worked for it
        #expect(worked.off == false)
        #expect(!worked.special)
        #expect(ScheduleDayNote(Day(2026, 10, 1)).label == "国庆节")
        let plain = ScheduleDayNote(Day(2026, 11, 26))
        #expect(plain.label == lunarCalendarLabel(toLunar(Day(2026, 11, 26))!))
        #expect(plain.off == nil)
    }
}

// MARK: - Debug routes

@Test(arguments: ScheduleDebugState.allCases)
func scheduleRoutes(_ state: ScheduleDebugState) {
    let route = DebugRoute("schedule:\(state.rawValue)")
    #expect(route == .schedule(state.rawValue))
    #expect(route?.text == "schedule:\(state.rawValue)")
    #expect(state.draft(today: today).dueDate == (state == .none ? nil : state.draft(today: today).dueDate))
    #expect(DebugRoute("schedule:") == nil)
}
