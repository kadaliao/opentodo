import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/reminders.dart';

import 'views_test.dart' show task;

void main() {
  test('when a reminder goes off', () {
    expect(reminderTime('2026-11-16', 900, 0), DateTime(2026, 11, 16, 15));
    expect(reminderTime('2026-11-16', 900, -30), DateTime(2026, 11, 16, 14, 30));
    expect(reminderTime('2026-11-16', 900, -1440), DateTime(2026, 11, 15, 15));
    // All day: from the start of the day.
    expect(reminderTime('2026-11-16', null, 540), DateTime(2026, 11, 16, 9));
    expect(reminderTime('2026-11-16', null, -900), DateTime(2026, 11, 15, 9));
    expect(reminderTime('2026-11-16', null, -9540), DateTime(2026, 11, 9, 9));
  });

  test('labels', () {
    String timed(int o) => reminderLabel(o, allDay: false);
    String allDay(int o) => reminderLabel(o, allDay: true);
    expect(timedReminderPresets.map(timed), ['准时', '提前5分钟', '提前30分钟', '提前1小时', '提前1天']);
    expect(timed(-90), '提前1小时30分钟');
    expect(timed(-10080), '提前1周');
    expect(timed(-2880 - 120), '提前2天2小时');
    expect(allDayReminderPresets.map(allDay),
        ['当天 09:00', '提前1天 09:00', '提前2天 09:00', '提前1周 09:00']);
    expect(allDay(-1440 + 20 * 60 + 30), '提前1天 20:30');
    expect(remindersSummary([-30, 0, -30], allDay: false), '提前30分钟、准时');
  });

  test('notification ids are stable per task and minute', () {
    final at = DateTime(2026, 11, 16, 15);
    expect(notificationId('a', at), notificationId('a', at.add(const Duration(seconds: 30))));
    expect(notificationId('a', at), isNot(notificationId('b', at)));
    expect(notificationId('a', at), isNot(notificationId('a', at.add(const Duration(minutes: 1)))));
    expect(notificationId('a', at), inInclusiveRange(0, 0x7fffffff));
  });

  group('upcoming reminders', () {
    final now = DateTime(2026, 11, 15, 10);

    test('open tasks with reminders still to come, soonest first', () {
      final events = upcomingReminders([
        task('开会', due: '2026-11-15', time: 15 * 60, reminders: [0, -30], content: '带上电脑\n第二行'),
        task('交房租', due: '2026-11-16', reminders: [-900, 540]),
        task('没提醒', due: '2026-11-15', time: 16 * 60),
        task('过去了', due: '2026-11-15', time: 9 * 60, reminders: [0]),
        task('做完了', due: '2026-11-15', time: 15 * 60, reminders: [0], status: TaskStatus.done),
        task('删了', due: '2026-11-15', time: 15 * 60, reminders: [0], trashedAt: 1),
      ], now);
      expect(events.map((e) => '${e.title} ${e.at}'), [
        '开会 2026-11-15 14:30:00.000',
        '开会 2026-11-15 15:00:00.000',
        // Its 提前1天 09:00 (today, 9:00) has already gone by.
        '交房租 2026-11-16 09:00:00.000',
      ]);
      expect(events.first.body, '今天, 下午3:00 · 带上电脑');
      expect(events.last.body, '今天');
    });

    test('worded for the day it shows up', () {
      final events = upcomingReminders(
          [task('开会', due: '2026-11-17', time: 15 * 60, reminders: [-1440])], now);
      expect(events.single.at, DateTime(2026, 11, 16, 15));
      expect(events.single.body, '明天, 下午3:00');
    });

    test('only the soonest are kept', () {
      final tasks = [
        for (var i = 0; i < 60; i++)
          task('t$i', due: '2026-11-16', time: i, reminders: [0]),
      ];
      final events = upcomingReminders(tasks, now);
      expect(events.length, maxScheduledReminders);
      expect(events.last.title, 't${maxScheduledReminders - 1}');
    });
  });
}
