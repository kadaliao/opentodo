// Ported from app/test/reminders_test.dart, case for case.

import Foundation
import Testing
@testable import OpenTodoDomain

/// Like `task` in app/test/views_test.dart: the title doubles as the id.
private func task(
    _ title: String,
    due: String? = nil,
    time: Int? = nil,
    status: TaskStatus = .open,
    trashedAt: Int? = nil,
    reminders: [Int] = [],
    content: String = ""
) -> TodoTask {
    TodoTask(
        id: title, title: title, content: content, dueDate: due.map { Day($0)! }, dueTime: time,
        status: status, reminders: reminders, trashedAt: trashedAt
    )
}

private let day16 = Day(2026, 11, 16)

@Suite("reminders")
struct RemindersTests {
    @Test("when a reminder goes off") func whenItGoesOff() {
        #expect(reminderTime(day16, 900, 0) == LocalDateTime(2026, 11, 16, 15))
        #expect(reminderTime(day16, 900, -30) == LocalDateTime(2026, 11, 16, 14, 30))
        #expect(reminderTime(day16, 900, -1440) == LocalDateTime(2026, 11, 15, 15))
        // All day: from the start of the day.
        #expect(reminderTime(day16, nil, 540) == LocalDateTime(2026, 11, 16, 9))
        #expect(reminderTime(day16, nil, -900) == LocalDateTime(2026, 11, 15, 9))
        #expect(reminderTime(day16, nil, -9540) == LocalDateTime(2026, 11, 9, 9))
    }

    @Test("labels") func labels() {
        func timed(_ o: Int) -> String { reminderLabel(o, allDay: false) }
        func allDay(_ o: Int) -> String { reminderLabel(o, allDay: true) }
        #expect(timedReminderPresets.map(timed) == ["准时", "提前5分钟", "提前30分钟", "提前1小时", "提前1天"])
        #expect(timed(-90) == "提前1小时30分钟")
        #expect(timed(-10080) == "提前1周")
        #expect(timed(-2880 - 120) == "提前2天2小时")
        #expect(allDayReminderPresets.map(allDay) == ["当天 09:00", "提前1天 09:00", "提前2天 09:00", "提前1周 09:00"])
        #expect(allDay(-1440 + 20 * 60 + 30) == "提前1天 20:30")
        #expect(remindersSummary([-30, 0, -30], allDay: false) == "提前30分钟、准时")
    }

    @Test("notification ids are stable per task and minute") func notificationIds() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let at = LocalDateTime(2026, 11, 16, 15)
        // A moment 30 seconds later is the same minute.
        let later = LocalDateTime(at.date(in: tz).addingTimeInterval(30), in: tz)
        #expect(notificationId("a", at, in: tz) == notificationId("a", later, in: tz))
        #expect(notificationId("a", at, in: tz) != notificationId("b", at, in: tz))
        #expect(notificationId("a", at, in: tz) != notificationId("a", at + 1, in: tz))
        #expect((0...0x7fff_ffff).contains(notificationId("a", at, in: tz)))
        // The Dart version's number for the same task and minute
        // (FNV-1a of "a@29913540", 15:00 China time in epoch minutes).
        #expect(notificationId("a", at, in: tz) == fnv1a31("a@29913540"))
        #expect(ReminderEvent(taskId: "a", at: at, title: "", body: "").id(in: tz) == notificationId("a", at, in: tz))
    }

    /// Printed by the Dart `notificationId(taskId, DateTime.fromMillisecondsSinceEpoch(ms))`,
    /// so the Flutter version's pending notifications are found by id.
    @Test("notification ids match the Flutter version's numbers",
          arguments: [
              ("task-1", 1_795_000_000_000, 1_809_615_429),
              ("0193a1b2-0000-7000-8000-000000000000", 1_764_140_400_000, 1_484_228_159),
              ("中文😀", 1_800_000_060_000, 488_086_208),
          ])
    func notificationIdsMatchDart(taskId: String, ms: Int, expected: Int) {
        for zone in ["Asia/Shanghai", "America/New_York", "UTC"] {
            let tz = TimeZone(identifier: zone)!
            let at = LocalDateTime(Date(timeIntervalSince1970: Double(ms) / 1000), in: tz)
            #expect(notificationId(taskId, at, in: tz) == expected, "\(zone)")
        }
    }

    @Test("upcoming reminders: open tasks with reminders still to come, soonest first") func upcoming() {
        let now = LocalDateTime(2026, 11, 15, 10)
        let events = upcomingReminders([
            task("开会", due: "2026-11-15", time: 15 * 60, reminders: [0, -30], content: "带上电脑\n第二行"),
            task("交房租", due: "2026-11-16", reminders: [-900, 540]),
            task("没提醒", due: "2026-11-15", time: 16 * 60),
            task("过去了", due: "2026-11-15", time: 9 * 60, reminders: [0]),
            task("做完了", due: "2026-11-15", time: 15 * 60, status: .done, reminders: [0]),
            task("删了", due: "2026-11-15", time: 15 * 60, trashedAt: 1, reminders: [0]),
        ], now)
        #expect(events.map { "\($0.title) \($0.at)" } == [
            "开会 2026-11-15T14:30",
            "开会 2026-11-15T15:00",
            // Its 提前1天 09:00 (today, 9:00) has already gone by.
            "交房租 2026-11-16T09:00",
        ])
        #expect(events.first?.body == "今天, 下午3:00 · 带上电脑")
        #expect(events.last?.body == "今天")
    }

    @Test("upcoming reminders: worded for the day it shows up") func wordedForTheDay() {
        let now = LocalDateTime(2026, 11, 15, 10)
        let events = upcomingReminders([task("开会", due: "2026-11-17", time: 15 * 60, reminders: [-1440])], now)
        #expect(events.count == 1)
        #expect(events.first?.at == LocalDateTime(2026, 11, 16, 15))
        #expect(events.first?.body == "明天, 下午3:00")
    }

    @Test("upcoming reminders: only the soonest are kept") func onlyTheSoonest() {
        let now = LocalDateTime(2026, 11, 15, 10)
        let tasks = (0..<60).map { (i: Int) in task("t\(i)", due: "2026-11-16", time: i, reminders: [0]) }
        let events = upcomingReminders(tasks, now)
        #expect(events.count == maxScheduledReminders)
        let lastTitle = "t\(maxScheduledReminders - 1)"
        #expect(events.last?.title == lastTitle)
    }

    @Test("upcoming reminders: snoozed ones come back") func snoozed() {
        let now = LocalDateTime(2026, 11, 15, 10)
        let events = upcomingReminders(
            [task("开会", due: "2026-11-15", time: 9 * 60, reminders: [0])], now,
            snoozed: ["开会": LocalDateTime(2026, 11, 15, 10, 10), "别的": LocalDateTime(2026, 11, 15, 11)]
        )
        #expect(events.map(\.at) == [LocalDateTime(2026, 11, 15, 10, 10)])
    }
}

private func fnv1a31(_ s: String) -> Int {
    var h: UInt32 = 0x811c_9dc5
    for c in s.utf16 {
        h ^= UInt32(c)
        h = h &* 0x0100_0193
    }
    return Int(h & 0x7fff_ffff)
}
