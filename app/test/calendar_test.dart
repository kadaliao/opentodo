import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/calendar.dart';
import 'package:opentodo/domain/dates.dart';

var _seq = 0;

Task task(
  String title, {
  String? due,
  int? time,
  String listId = inboxListId,
  int status = TaskStatus.open,
  String? repeat,
  int? trashedAt,
  int priority = 0,
}) {
  final created = 1000 + _seq++;
  return Task(
    id: title,
    listId: listId,
    title: title,
    content: '',
    priority: priority,
    dueDate: due,
    dueTime: time,
    timeZone: null,
    tags: const [],
    status: status,
    completedAt: status == TaskStatus.open ? null : created,
    reminders: const [],
    repeatRule: repeat,
    repeatFrom: 0,
    trashedAt: trashedAt,
    sortOrder: 0,
    createdAt: created,
    updatedAt: created,
    deletedAt: null,
    serverVersion: 0,
    dirty: true,
  );
}

/// `title@YYYY-MM-DD`, with `*` for a projected date.
List<String> keys(List<CalendarEntry> entries) => [for (final e in entries) '$e'];

void main() {
  final sunday = DateTime(2026, 11, 15);

  group('ranges', () {
    test('a month grid is whole weeks, Monday first', () {
      // 1 Nov 2026 is a Sunday, 30 Nov a Monday: six rows.
      final r = monthGrid(2026, 11);
      expect(r.toString(), '2026-10-26..2026-12-07');
      expect(r.length, 42);
      // February 2027 starts on a Monday and ends on a Sunday: four rows.
      expect(monthGrid(2027, 2).length, 28);
    });

    test('each mode covers its days around the anchor', () {
      expect(visibleRange(CalendarMode.day, sunday).toString(), '2026-11-15..2026-11-16');
      expect(visibleRange(CalendarMode.threeDays, sunday).toString(), '2026-11-15..2026-11-18');
      expect(visibleRange(CalendarMode.week, sunday).toString(), '2026-11-09..2026-11-16');
      expect(visibleRange(CalendarMode.agenda, sunday).toString(), '2026-11-01..2026-12-01');
      expect(visibleRange(CalendarMode.month, sunday), monthGrid(2026, 11));
    });

    test('pages move by the mode, months keeping the day where they can', () {
      expect(shiftAnchor(CalendarMode.day, sunday, -1), DateTime(2026, 11, 14));
      expect(shiftAnchor(CalendarMode.threeDays, sunday, 1), DateTime(2026, 11, 18));
      expect(shiftAnchor(CalendarMode.week, sunday, 2), DateTime(2026, 11, 29));
      expect(shiftAnchor(CalendarMode.month, DateTime(2027, 1, 31), 1), DateTime(2027, 2, 28));
      expect(shiftAnchor(CalendarMode.agenda, DateTime(2026, 12, 15), 1), DateTime(2027, 1, 15));
    });

    test('titles name the month, or both months a week runs across', () {
      expect(calendarTitle(CalendarMode.month, sunday), '2026年11月');
      expect(calendarTitle(CalendarMode.week, sunday), '2026年11月');
      expect(calendarTitle(CalendarMode.week, DateTime(2026, 12, 1)), '2026年11月–12月');
      expect(calendarTitle(CalendarMode.threeDays, DateTime(2026, 12, 31)), '2026年12月–2027年1月');
    });
  });

  group('entries', () {
    final week = visibleRange(CalendarMode.week, sunday); // 9–15 Nov

    test('dated tasks in the range, in day and time order', () {
      final entries = calendarEntries([
        task('下周', due: '2026-11-16'),
        task('下午', due: '2026-11-10', time: 15 * 60),
        task('全天', due: '2026-11-10'),
        task('上午', due: '2026-11-10', time: 9 * 60),
        task('没日期'),
        task('上周', due: '2026-11-08'),
      ], week, today: sunday);
      expect(keys(entries), ['全天@2026-11-10', '上午@2026-11-10', '下午@2026-11-10']);
    });

    test('finished tasks come after open ones and can be hidden; trashed never show', () {
      final tasks = [
        task('完成了', due: '2026-11-12', status: TaskStatus.done),
        task('没完成', due: '2026-11-12', time: 20 * 60),
        task('删了', due: '2026-11-12', trashedAt: 1),
      ];
      expect(keys(calendarEntries(tasks, week, today: sunday)), ['没完成@2026-11-12', '完成了@2026-11-12']);
      expect(
        keys(calendarEntries(tasks, week, today: sunday, filter: const CalendarFilter(showCompleted: false))),
        ['没完成@2026-11-12'],
      );
    });

    test('hidden lists are left off', () {
      final tasks = [
        task('收集箱的', due: '2026-11-12'),
        task('工作的', due: '2026-11-12', listId: 'work'),
      ];
      expect(
        keys(calendarEntries(tasks, week, today: sunday, filter: const CalendarFilter(hiddenLists: {inboxListId}))),
        ['工作的@2026-11-12'],
      );
    });

    test('a repeating task shows on its later dates too, marked as projected', () {
      final friday = DateTime(2026, 11, 13);
      final tasks = [task('晨跑', due: '2026-11-13', time: 7 * 60, repeat: 'FREQ=DAILY')];
      expect(keys(calendarEntries(tasks, week, today: friday)), [
        '晨跑@2026-11-13',
        '晨跑@2026-11-14*',
        '晨跑@2026-11-15*',
      ]);
      // Only the next one, when the person turns that off.
      expect(
        keys(calendarEntries(tasks, week, today: friday, filter: const CalendarFilter(showRepeats: false))),
        ['晨跑@2026-11-13'],
      );
      // A page further on shows only projected dates.
      final later = visibleRange(CalendarMode.week, DateTime(2026, 12, 1));
      expect(calendarEntries(tasks, later, today: friday).every((e) => e.projected), isTrue);
      expect(calendarEntries(tasks, later, today: friday), hasLength(7));
    });

    test('an overdue repeating task projects only dates after today', () {
      // Finishing it today moves it to the 16th, not the 13th.
      final tasks = [task('晨跑', due: '2026-11-12', repeat: 'FREQ=DAILY')];
      expect(keys(calendarEntries(tasks, week, today: sunday)), ['晨跑@2026-11-12']);
      final next = visibleRange(CalendarMode.week, DateTime(2026, 11, 16));
      expect(calendarEntries(tasks, next, today: sunday).first.toString(), '晨跑@2026-11-16*');

      // Counted from completion, the series starts again from today.
      final fromDone = task('浇花', due: '2026-11-12', repeat: 'FREQ=DAILY;INTERVAL=3');
      final relative = Task.fromJson({...fromDone.toJson(), 'repeatFrom': 1});
      expect(
        keys(calendarEntries([relative], next, today: sunday)),
        ['浇花@2026-11-18*', '浇花@2026-11-21*'],
      );
    });

    test('projections stop where the series ends', () {
      final month = visibleRange(CalendarMode.month, sunday);
      // COUNT=3 includes the current date: two more.
      expect(
        keys(calendarEntries([task('三次', due: '2026-11-02', repeat: 'FREQ=WEEKLY;COUNT=3')], month,
            today: DateTime(2026, 11, 2))),
        ['三次@2026-11-02', '三次@2026-11-09*', '三次@2026-11-16*'],
      );
      // Overdue, the dates passed over use the count up too: only the last is left.
      expect(
        keys(calendarEntries([task('三次', due: '2026-11-02', repeat: 'FREQ=WEEKLY;COUNT=3')], month,
            today: sunday)),
        ['三次@2026-11-02', '三次@2026-11-16*'],
      );
      expect(
        keys(calendarEntries([task('到月中', due: '2026-11-10', repeat: 'FREQ=DAILY;UNTIL=20261112')],
            month, today: DateTime(2026, 11, 10))),
        ['到月中@2026-11-10', '到月中@2026-11-11*', '到月中@2026-11-12*'],
      );
    });

    test('a finished repeating task projects nothing; its earlier dates are not shown', () {
      final month = visibleRange(CalendarMode.month, sunday);
      expect(
        keys(calendarEntries(
            [task('结束了', due: '2026-11-10', repeat: 'FREQ=DAILY', status: TaskStatus.done)],
            month, today: sunday)),
        ['结束了@2026-11-10'],
      );
      // A task due after the range has nothing in it.
      expect(
        calendarEntries([task('以后', due: '2027-01-05', repeat: 'FREQ=DAILY')], month, today: sunday),
        isEmpty,
      );
    });

    test('grouped by day', () {
      final byDay = entriesByDay(calendarEntries([
        task('a', due: '2026-11-10'),
        task('b', due: '2026-11-10'),
        task('c', due: '2026-11-12'),
      ], week, today: sunday));
      expect(byDay.keys, ['2026-11-10', '2026-11-12']);
      expect(byDay['2026-11-10'], hasLength(2));
    });
  });

  group('timed layout', () {
    List<String> layout(List<Task> tasks) => [
          for (final p in layoutTimed(calendarEntries(tasks, DayRange(sunday, addDays(sunday, 1)), today: sunday)))
            '$p',
        ];

    test('tasks that do not overlap get the full width', () {
      expect(layout([
        task('a', due: '2026-11-15', time: 9 * 60),
        task('b', due: '2026-11-15', time: 9 * 60 + 30),
        task('全天', due: '2026-11-15'),
      ]), ['a 540-570 0/1', 'b 570-600 0/1']);
    });

    test('overlapping tasks share the width, reusing free slots', () {
      expect(layout([
        task('a', due: '2026-11-15', time: 9 * 60),
        task('b', due: '2026-11-15', time: 9 * 60 + 10),
        task('c', due: '2026-11-15', time: 9 * 60 + 20),
        task('d', due: '2026-11-15', time: 9 * 60 + 35),
        task('e', due: '2026-11-15', time: 11 * 60),
      ]), [
        'a 540-570 0/3',
        'b 550-580 1/3',
        'c 560-590 2/3',
        'd 575-605 0/3', // a's slot is free again
        'e 660-690 0/1',
      ]);
    });

    test('a task late at night is cut at midnight', () {
      expect(layout([task('a', due: '2026-11-15', time: 23 * 60 + 50)]), ['a 1430-1440 0/1']);
    });

    test('minutes snap down to the step and stay in the day', () {
      expect(snapMinutes(9 * 60 + 14.9), 9 * 60);
      expect(snapMinutes(9 * 60 + 15), 9 * 60 + 15);
      expect(snapMinutes(-20), 0);
      expect(snapMinutes(24 * 60 + 5), 24 * 60 - 15);
      expect(snapMinutes(10 * 60 + 45, step: 30), 10 * 60 + 30);
      expect(clockLabel(9 * 60 + 5), '09:05');
    });
  });
}
