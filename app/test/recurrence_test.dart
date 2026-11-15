import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/dates.dart';
import 'package:opentodo/domain/recurrence.dart';

DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);
RepeatRule rule(String s) => RepeatRule.tryParse(s)!;

/// The next [n] dates after [from].
List<DateTime> series(RepeatRule r, DateTime from, int n) {
  final out = <DateTime>[];
  var at = from;
  for (var i = 0; i < n; i++) {
    final next = nextOccurrence(r, at);
    if (next == null) break;
    out.add(next);
    at = next;
  }
  return out;
}

void main() {
  // 2026-11-15 is a Sunday.
  group('parse and format', () {
    test('round trip in a fixed order', () {
      for (final s in [
        'FREQ=DAILY',
        'FREQ=DAILY;INTERVAL=3',
        'FREQ=WEEKLY;BYDAY=MO,WE,FR',
        'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU',
        'FREQ=MONTHLY;BYMONTHDAY=15',
        'FREQ=MONTHLY;BYMONTHDAY=-1',
        'FREQ=MONTHLY;BYDAY=2TU',
        'FREQ=MONTHLY;BYDAY=-1FR',
        'FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=15',
        'FREQ=DAILY;UNTIL=20261231',
        'FREQ=WEEKLY;COUNT=5',
      ]) {
        expect(rule(s).toString(), s);
      }
    });

    test('lenient about case, order, prefixes and extras', () {
      expect(rule('RRULE:byday=we,mo;freq=weekly;INTERVAL=1;WKST=MO').toString(),
          'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(rule('FREQ=DAILY;UNTIL=20261231T235959Z').until, d(12, 31));
      expect(rule('FREQ=DAILY;INTERVAL=0').interval, 1);
    });

    test('unusable rules are null', () {
      expect(RepeatRule.tryParse(null), isNull);
      expect(RepeatRule.tryParse(''), isNull);
      expect(RepeatRule.tryParse('FREQ=HOURLY'), isNull);
      expect(RepeatRule.tryParse('nonsense'), isNull);
    });

    test('equality is by text', () {
      expect(rule('FREQ=WEEKLY;BYDAY=WE,MO'), rule('FREQ=WEEKLY;BYDAY=MO,WE'));
      expect(RepeatRule.workdays, rule('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'));
    });
  });

  group('next occurrence', () {
    test('daily', () {
      expect(series(RepeatRule.daily, d(11, 15), 2), [d(11, 16), d(11, 17)]);
      expect(series(rule('FREQ=DAILY;INTERVAL=3'), d(11, 15), 2), [d(11, 18), d(11, 21)]);
      // Across the end of the year.
      expect(nextOccurrence(RepeatRule.daily, d(12, 31)), d(1, 1, 2027));
    });

    test('weekly keeps the task weekday unless days are given', () {
      expect(series(RepeatRule.weekly, d(11, 15), 2), [d(11, 22), d(11, 29)]);
      expect(series(rule('FREQ=WEEKLY;BYDAY=MO,WE'), d(11, 15), 3),
          [d(11, 16), d(11, 18), d(11, 23)]);
    });

    test('every other week stays in step', () {
      expect(series(rule('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE'), d(11, 16), 4),
          [d(11, 18), d(11, 30), d(12, 2), d(12, 14)]);
    });

    test('workdays skip the weekend', () {
      expect(series(RepeatRule.workdays, d(11, 19), 3), [d(11, 20), d(11, 23), d(11, 24)]);
      expect(series(RepeatRule.weekends, d(11, 15), 2), [d(11, 21), d(11, 22)]);
    });

    test('monthly on a day skips months without it', () {
      expect(series(RepeatRule.monthly, d(1, 31), 3), [d(3, 31), d(5, 31), d(7, 31)]);
      expect(series(rule('FREQ=MONTHLY;BYMONTHDAY=15'), d(11, 20), 2), [d(12, 15), d(1, 15, 2027)]);
      expect(series(rule('FREQ=MONTHLY;INTERVAL=3'), d(11, 15), 2), [d(2, 15, 2027), d(5, 15, 2027)]);
    });

    test('monthly on the last day', () {
      expect(series(rule('FREQ=MONTHLY;BYMONTHDAY=-1'), d(11, 30), 4),
          [d(12, 31), d(1, 31, 2027), d(2, 28, 2027), d(3, 31, 2027)]);
    });

    test('monthly on the nth weekday', () {
      expect(series(rule('FREQ=MONTHLY;BYDAY=2TU'), d(11, 10), 2), [d(12, 8), d(1, 12, 2027)]);
      expect(series(rule('FREQ=MONTHLY;BYDAY=-1FR'), d(11, 27), 2), [d(12, 25), d(1, 29, 2027)]);
      // Months without a fifth Monday are skipped.
      expect(series(rule('FREQ=MONTHLY;BYDAY=5MO'), d(11, 30), 2), [d(3, 29, 2027), d(5, 31, 2027)]);
    });

    test('yearly, and Feb 29 waits for a leap year', () {
      expect(nextOccurrence(RepeatRule.yearly, d(11, 15)), d(11, 15, 2027));
      expect(nextOccurrence(RepeatRule.yearly, d(2, 29, 2028)), d(2, 29, 2032));
      expect(nextOccurrence(rule('FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=8'), d(11, 15)), d(3, 8, 2027));
      expect(nextOccurrence(rule('FREQ=YEARLY;BYMONTH=11;BYDAY=4TH'), d(1, 1)), d(11, 26));
    });

    test('until and count end the series', () {
      expect(series(rule('FREQ=DAILY;UNTIL=20261117'), d(11, 15), 5), [d(11, 16), d(11, 17)]);
      expect(nextOccurrence(rule('FREQ=DAILY;COUNT=1'), d(11, 15)), isNull);
      expect(nextOccurrence(rule('FREQ=DAILY;COUNT=2'), d(11, 15)), d(11, 16));
    });
  });

  group('advancing a repeating task', () {
    final today = d(11, 15);

    test('on time: the next occurrence', () {
      final a = advanceRepeat(RepeatRule.daily, today, today: today)!;
      expect(a.date, d(11, 16));
      expect(a.rule, RepeatRule.daily);
    });

    test('overdue: past occurrences are passed over', () {
      expect(advanceRepeat(RepeatRule.daily, d(11, 12), today: today)!.date, d(11, 16));
      // A Monday task done on Sunday goes to the coming Monday.
      expect(advanceRepeat(rule('FREQ=WEEKLY;BYDAY=MO'), d(11, 9), today: today)!.date, d(11, 16));
    });

    test('done early: the occurrence after its date', () {
      expect(advanceRepeat(RepeatRule.daily, d(11, 20), today: today)!.date, d(11, 21));
    });

    test('from completion: the rule restarts today', () {
      expect(
        advanceRepeat(rule('FREQ=DAILY;INTERVAL=3'), d(11, 10),
                today: today, repeatFrom: RepeatFrom.completion)!
            .date,
        d(11, 18),
      );
    });

    test('count goes down, and passed-over occurrences use it up', () {
      final a = advanceRepeat(rule('FREQ=DAILY;COUNT=3'), today, today: today)!;
      expect(a.date, d(11, 16));
      expect(a.rule.count, 2);
      expect(advanceRepeat(rule('FREQ=DAILY;COUNT=1'), today, today: today), isNull);
      // 12th, 13th and 14th were the three; nothing is left.
      expect(advanceRepeat(rule('FREQ=DAILY;COUNT=3'), d(11, 12), today: today), isNull);
    });

    test('until', () {
      expect(advanceRepeat(rule('FREQ=DAILY;UNTIL=20261115'), today, today: today), isNull);
      expect(advanceRepeat(rule('FREQ=DAILY;UNTIL=20261116'), today, today: today)!.date, d(11, 16));
    });
  });

  test('occurrences after a date, as far as the series runs', () {
    expect(occurrencesAfter(RepeatRule.daily, d(11, 15)).take(3), [d(11, 16), d(11, 17), d(11, 18)]);
    // COUNT counts the date itself.
    expect(occurrencesAfter(rule('FREQ=WEEKLY;COUNT=3'), d(11, 15)), [d(11, 22), d(11, 29)]);
    expect(occurrencesAfter(rule('FREQ=DAILY;COUNT=1'), d(11, 15)), isEmpty);
    expect(occurrencesAfter(rule('FREQ=DAILY;UNTIL=20261117'), d(11, 15)), [d(11, 16), d(11, 17)]);
    expect(occurrencesAfter(rule('FREQ=MONTHLY;BYMONTHDAY=31'), d(10, 31)).take(3),
        [d(12, 31), d(1, 31, 2027), d(3, 31, 2027)]);
  });

  test('first occurrence for a new task', () {
    expect(firstOccurrence(RepeatRule.daily, today()), today());
    expect(firstOccurrence(RepeatRule.weekly, today()), today());
    expect(firstOccurrence(rule('FREQ=WEEKLY;BYDAY=MO'), d(11, 15)), d(11, 16));
    expect(firstOccurrence(rule('FREQ=WEEKLY;BYDAY=MO'), d(11, 16)), d(11, 16));
    expect(firstOccurrence(rule('FREQ=MONTHLY;BYMONTHDAY=15'), d(11, 15)), d(11, 15));
    expect(firstOccurrence(rule('FREQ=MONTHLY;BYMONTHDAY=15'), d(11, 16)), d(12, 15));
    expect(firstOccurrence(rule('FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=1'), d(11, 16)), d(1, 1, 2027));
    expect(firstOccurrence(RepeatRule.workdays, d(11, 15)), d(11, 16));
  });

  test('nth weekday of a month', () {
    expect(nthWeekdayOfMonth(2026, 11, 1, 7), d(11, 1));
    expect(nthWeekdayOfMonth(2026, 11, 2, 2), d(11, 10));
    expect(nthWeekdayOfMonth(2026, 11, -1, 1), d(11, 30));
    expect(nthWeekdayOfMonth(2026, 11, -1, 2), d(11, 24));
    expect(nthWeekdayOfMonth(2026, 11, 5, 1), d(11, 30));
    expect(nthWeekdayOfMonth(2026, 11, 5, 2), isNull);
  });

  test('described in words', () {
    final sun = d(11, 15);
    String say(String s, {int from = RepeatFrom.dueDate}) =>
        describeRepeat(rule(s), sun, repeatFrom: from);
    expect(say('FREQ=DAILY'), '每天');
    expect(say('FREQ=DAILY;INTERVAL=3'), '每3天');
    expect(say('FREQ=WEEKLY'), '每周日');
    expect(say('FREQ=WEEKLY;BYDAY=MO,WE,FR'), '每周一、三、五');
    expect(say('FREQ=WEEKLY;INTERVAL=2;BYDAY=TU'), '每2周的周二');
    expect(say('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'), '工作日');
    expect(say('FREQ=WEEKLY;BYDAY=SA,SU'), '周末');
    expect(say('FREQ=MONTHLY'), '每月15日');
    expect(say('FREQ=MONTHLY;BYMONTHDAY=-1'), '每月最后一天');
    expect(say('FREQ=MONTHLY;BYDAY=2TU'), '每月第2个周二');
    expect(say('FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR'), '每2个月的最后一个周五');
    expect(say('FREQ=YEARLY'), '每年11月15日');
    expect(say('FREQ=YEARLY;INTERVAL=2;BYMONTH=3;BYMONTHDAY=8'), '每2年的3月8日');
    expect(say('FREQ=DAILY;INTERVAL=3', from: RepeatFrom.completion), '每3天（按完成日期）');
    expect(say('FREQ=DAILY;UNTIL=20261231'), '每天，至2026年12月31日');
    expect(say('FREQ=DAILY;COUNT=5'), '每天，还剩5次');
  });

  group('China', () {
    List<String> next(RepeatRule r, String from, int n) =>
        occurrencesAfter(r, parseDateKey(from)).take(n).map(dateKey).toList();

    test('text', () {
      for (final text in [
        'RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=15;SKIP=BACKWARD',
        'RSCALE=CHINESE;FREQ=MONTHLY;BYMONTHDAY=1;SKIP=BACKWARD',
        'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;X-HOLIDAYS=CN',
      ]) {
        expect(RepeatRule.tryParse(text).toString(), text);
      }
      expect(RepeatRule.tryParse('FREQ=YEARLY;RSCALE=HEBREW;BYMONTH=5'), isNull);
      expect(RepeatRule.tryParse('RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=6L;BYMONTHDAY=1')!.month, 6);
      expect(RepeatRule.lunarYearlyOn(DateTime(2026, 9, 25)).toString(),
          'RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=15;SKIP=BACKWARD');
      expect(RepeatRule.statutoryWorkdays.toString(), 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;X-HOLIDAYS=CN');
    });

    test('法定工作日 skips the holidays and works the weekend days in exchange', () {
      const r = RepeatRule.statutoryWorkdays;
      expect(next(r, '2026-09-18', 2), ['2026-09-20', '2026-09-21']); // Sunday 9/20 is worked
      expect(next(r, '2026-09-30', 4), ['2026-10-08', '2026-10-09', '2026-10-10', '2026-10-12']);
      expect(firstOccurrence(r, DateTime(2026, 10, 3)), DateTime(2026, 10, 8));
      final done = advanceRepeat(r, DateTime(2027, 2, 4), today: DateTime(2027, 2, 4))!;
      expect(done.date, DateTime(2027, 2, 14)); // 春节 off, Sunday 2/14 worked
      expect(describeRepeat(r, DateTime(2026, 11, 16)), '法定工作日');
    });

    test('农历每年 and 农历每月, leap months and 除夕', () {
      final midAutumn = RepeatRule.lunarYearlyOn(DateTime(2026, 9, 25))!;
      expect(next(midAutumn, '2026-09-25', 2), ['2027-09-15', '2028-10-03']);
      expect(describeRepeat(midAutumn, DateTime(2026, 9, 25)), '农历每年八月十五');

      // 腊月三十: 除夕 even when the month has 29 days.
      const eve = RepeatRule(Freq.yearly, lunar: true, month: 12, monthDays: [30]);
      expect(next(eve, '2026-02-16', 2), ['2027-02-05', '2028-01-25']);
      expect(describeRepeat(eve, DateTime(2026, 2, 16)), '农历每年腊月三十');

      // Every 初一, through 2025's leap sixth month.
      final first = RepeatRule.lunarMonthlyOn(DateTime(2025, 6, 25))!;
      expect(next(first, '2025-06-25', 3), ['2025-07-25', '2025-08-23', '2025-09-22']);
      expect(describeRepeat(first, DateTime(2025, 6, 25)), '农历每月初一');
      expect(firstOccurrence(first, DateTime(2025, 7, 1)), DateTime(2025, 7, 25));

      const every2 = RepeatRule(Freq.yearly, interval: 2, lunar: true, month: 1, monthDays: [1]);
      expect(next(every2, '2026-02-17', 1), ['2028-01-26']);
      expect(describeRepeat(every2, DateTime(2026, 2, 17)), '每2年的农历正月初一');
    });
  });
}

DateTime today() => DateTime(2026, 11, 15);
