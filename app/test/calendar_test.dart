import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/calendar.dart';
import 'package:opentodo/domain/dates.dart';

var _seq = 0;

Task task(
  String title, {
  String? due,
  int? time,
  int? duration,
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
    duration: duration,
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

  group('spans', () {
    final week = visibleRange(CalendarMode.week, sunday); // Mon 9 - Sun 15

    test('a span is on every day it covers in the range', () {
      expect(
        keys(calendarEntries([task('出差', due: '2026-11-08', duration: 3 * 1440)], week, today: sunday)),
        ['出差@2026-11-09+1', '出差@2026-11-10+2'],
      );
      final overnight = calendarEntries(
          [task('夜班', due: '2026-11-10', time: 22 * 60, duration: 10 * 60)], week, today: sunday);
      expect(keys(overnight), ['夜班@2026-11-10', '夜班@2026-11-11+1']);
      expect([for (final e in overnight) '${e.time}-${e.endTime}'], ['1320-1440', '0-480']);
    });

    test('a repeating span shows its later occurrences, overlapping the range too', () {
      // Every Saturday for two days, seen in the next week.
      final next = visibleRange(CalendarMode.week, addDays(sunday, 7)); // Mon 16 - Sun 22
      expect(
        keys(calendarEntries(
            [task('周末班', due: '2026-11-14', duration: 2 * 1440, repeat: 'FREQ=WEEKLY')], next,
            today: sunday)),
        ['周末班@2026-11-21*', '周末班@2026-11-22+1*'],
      );
      // From Sunday's own page: the real one ends today.
      expect(
        keys(calendarEntries(
            [task('周末班', due: '2026-11-14', duration: 2 * 1440, repeat: 'FREQ=WEEKLY')], week,
            today: sunday)),
        ['周末班@2026-11-14', '周末班@2026-11-15+1'],
      );
    });

    test('timed layout uses the real length', () {
      final day = DayRange(sunday, addDays(sunday, 1));
      expect(
        [
          for (final p in layoutTimed(calendarEntries([
            task('长会', due: '2026-11-15', time: 9 * 60, duration: 120),
            task('短', due: '2026-11-15', time: 10 * 60),
            task('五分钟', due: '2026-11-15', time: 12 * 60, duration: 5),
            task('之后', due: '2026-11-15', time: 12 * 60 + 10),
          ], day, today: sunday)))
            '$p',
        ],
        [
          '长会 540-660 0/2',
          '短 600-630 1/2',
          // Drawn no smaller than half an hour, so 之后 goes beside it.
          '五分钟 720-725 0/2',
          '之后 730-760 1/2',
        ],
      );
    });

    test('dropping moves the whole span', () {
      CalendarEntry entryOn(Task t, String day) => calendarEntries(
              [t], DayRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1)), today: sunday)
          .firstWhere((e) => dateKey(e.date) == day);
      String target(({DateTime date, int? time}) to) =>
          '${dateKey(to.date)}${to.time == null ? '' : ' ${clockLabel(to.time!)}'}';

      final trip = task('出差', due: '2026-11-16', duration: 3 * 1440); // Mon-Wed
      // Its Tuesday dropped on Friday: Thursday to Saturday.
      expect(target(dropTarget(entryOn(trip, '2026-11-17'), DateTime(2026, 11, 20))), '2026-11-19');
      expect(target(dropTarget(entryOn(trip, '2026-11-17'), DateTime(2026, 11, 20), allDay: true)),
          '2026-11-19');
      // Onto the hour grid: starts where dropped.
      expect(target(dropTarget(entryOn(trip, '2026-11-17'), DateTime(2026, 11, 20), minute: 600)),
          '2026-11-20 10:00');

      final night = task('夜班', due: '2026-11-16', time: 22 * 60, duration: 10 * 60);
      // Its Tuesday part (0:00-8:00) dropped at Wednesday 2:00: two hours
      // later and a day on.
      expect(target(dropTarget(entryOn(night, '2026-11-17'), DateTime(2026, 11, 18), minute: 120)),
          '2026-11-18 00:00');
      // The first part dropped at 21:30 the same day.
      expect(target(dropTarget(entryOn(night, '2026-11-16'), DateTime(2026, 11, 16), minute: 21 * 60 + 30)),
          '2026-11-16 21:30');
      // A month cell keeps the time.
      expect(target(dropTarget(entryOn(night, '2026-11-17'), DateTime(2026, 11, 20))), '2026-11-19 22:00');
    });
  });

  group('dragging several', () {
    CalendarEntry entryOf(Task t) => CalendarEntry(t, parseDateKey(t.dueDate!));
    List<String> moves(List<CalendarMove> m) =>
        [for (final x in m) '${x.id} ${dateKey(x.date)}${x.time == null ? '' : ' ${clockLabel(x.time!)}'}'];

    final meeting = task('晨会', due: '2026-11-16', time: 9 * 60);
    final review = task('评审', due: '2026-11-17', time: 14 * 60, duration: 60);
    final rent = task('交房租', due: '2026-11-18');
    final late = task('上线', due: '2026-11-16', time: 23 * 60);

    test('on a month cell everyone moves as many days and keeps its time', () {
      expect(moves(dropTargets(entryOf(meeting), [review, rent], DateTime(2026, 11, 19))), [
        '晨会 2026-11-19 09:00',
        '评审 2026-11-20 14:00',
        '交房租 2026-11-21',
      ]);
      // Back a week, led by the all-day one.
      expect(moves(dropTargets(entryOf(rent), [meeting], DateTime(2026, 11, 11))), [
        '交房租 2026-11-11',
        '晨会 2026-11-09 09:00',
      ]);
    });

    test('into the all-day row: a timed lead takes them all out of their hours', () {
      expect(moves(dropTargets(entryOf(meeting), [review, rent], DateTime(2026, 11, 17), allDay: true)), [
        '晨会 2026-11-17',
        '评审 2026-11-18',
        '交房租 2026-11-19',
      ]);
      // An all-day lead moving to another day leaves the timed ones timed.
      expect(moves(dropTargets(entryOf(rent), [meeting], DateTime(2026, 11, 19), allDay: true)), [
        '交房租 2026-11-19',
        '晨会 2026-11-17 09:00',
      ]);
    });

    test('onto the hour grid: timed ones move by as many minutes', () {
      // 晨会 two hours later the next day: 评审 too, 交房租 a day on.
      expect(moves(dropTargets(entryOf(meeting), [review, rent, late], DateTime(2026, 11, 17), minute: 11 * 60)), [
        '晨会 2026-11-17 11:00',
        '评审 2026-11-18 16:00',
        '交房租 2026-11-19',
        // Two hours after 23:00 is the day after.
        '上线 2026-11-18 01:00',
      ]);
      // Earlier the same day.
      expect(moves(dropTargets(entryOf(meeting), [late], DateTime(2026, 11, 16), minute: 7 * 60)), [
        '晨会 2026-11-16 07:00',
        '上线 2026-11-16 21:00',
      ]);
    });

    test('onto the hour grid: an all-day lead gives the all-day ones its hour', () {
      final shop = task('买菜', due: '2026-11-20');
      expect(moves(dropTargets(entryOf(rent), [shop, meeting], DateTime(2026, 11, 19), minute: 10 * 60)), [
        '交房租 2026-11-19 10:00',
        '买菜 2026-11-21 10:00',
        '晨会 2026-11-17 09:00',
      ]);
    });

    test('finished, trashed and undated ones stay; the lead is not counted twice', () {
      final done = task('已完成', due: '2026-11-16', status: TaskStatus.done);
      final trashed = task('已删除', due: '2026-11-16', trashedAt: 1);
      final undated = task('无日期');
      expect(moves(dropTargets(entryOf(meeting), [meeting, done, trashed, undated], DateTime(2026, 11, 18))), [
        '晨会 2026-11-18 09:00',
      ]);
    });

    test('a span dragged by a later day moves the others by as much as its start', () {
      final trip = task('出差', due: '2026-11-16', duration: 3 * 1440); // Mon-Wed
      final tuesday = CalendarEntry(trip, DateTime(2026, 11, 17), occurrence: DateTime(2026, 11, 16));
      // Tuesday dropped on Friday: the trip starts Thursday, three days on.
      expect(moves(dropTargets(tuesday, [rent], DateTime(2026, 11, 20))), [
        '出差 2026-11-19',
        '交房租 2026-11-21',
      ]);
    });

    test('the order for Shift-click: each task once, no later dates of repeats', () {
      final daily = task('打卡', due: '2026-11-16', repeat: 'FREQ=DAILY');
      final trip = task('出差', due: '2026-11-16', duration: 2 * 1440);
      final entries = calendarEntries(
        [daily, trip, rent],
        DayRange(DateTime(2026, 11, 16), DateTime(2026, 11, 23)),
        today: DateTime(2026, 11, 15),
      );
      expect(entryOrder(entries), ['出差', '打卡', '交房租']);
    });
  });

  test('the agenda starts today in this month, else on the first', () {
    final november = DayRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    expect(agendaFrom(november, DateTime(2026, 11, 15, 9)), DateTime(2026, 11, 15));
    expect(agendaFrom(november, DateTime(2026, 10, 30)), DateTime(2026, 11, 1));
  });

  test('what a day says beside its number', () {
    expect(dayNote(DateTime(2026, 2, 17)), (label: '春节', special: true, off: true));
    expect(dayNote(DateTime(2026, 2, 28)), (label: '十二', special: false, off: false)); // worked
    expect(dayNote(DateTime(2026, 10, 1)), (label: '国庆节', special: true, off: true));
    expect(dayNote(DateTime(2026, 11, 9)), (label: '十月', special: false, off: null));
    expect(dayNote(sunday), (label: '初七', special: false, off: null));
  });
}
