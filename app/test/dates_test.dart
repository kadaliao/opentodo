import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/dates.dart';

void main() {
  // Sunday.
  final today = DateTime(2026, 11, 15);

  test('dateLabel', () {
    expect(dateLabel(today, today), '今天');
    expect(dateLabel(DateTime(2026, 11, 16), today), '明天');
    expect(dateLabel(DateTime(2026, 11, 17), today), '后天');
    expect(dateLabel(DateTime(2026, 11, 14), today), '昨天');
    // Monday-start weeks: from a Sunday, Wednesday is next week.
    expect(dateLabel(DateTime(2026, 11, 18), today), '下周三');
    expect(dateLabel(DateTime(2026, 11, 25), today), '11月25日');
    expect(dateLabel(DateTime(2027, 1, 3), today), '2027年1月3日');

    final wednesday = DateTime(2026, 11, 11);
    expect(dateLabel(DateTime(2026, 11, 14), wednesday), '周六');
    expect(dateLabel(DateTime(2026, 11, 19), wednesday), '下周四');
  });

  test('timeLabel', () {
    expect(timeLabel(0), '上午12:00');
    expect(timeLabel(9 * 60), '上午9:00');
    expect(timeLabel(12 * 60 + 30), '下午12:30');
    expect(timeLabel(15 * 60 + 5), '下午3:05');
  });

  test('dueLabel shows the time for today only', () {
    expect(dueLabel('2026-11-15', 9 * 60, today), '上午9:00');
    expect(dueLabel('2026-11-15', null, today), '今天');
    expect(dueLabel('2026-11-16', 9 * 60, today), '明天');
    expect(fullDueLabel('2026-11-16', 15 * 60, today), '明天, 下午3:00');
  });

  test('daySectionTitle', () {
    expect(daySectionTitle(today, today), '今天, 周日');
    expect(daySectionTitle(DateTime(2026, 11, 18), today), '11月18日, 周三');
  });

  test('daysBetween across the end of DST', () {
    expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
    expect(daysBetween(DateTime(2026, 11, 1), DateTime(2026, 10, 31)), -1);
  });

  group('spans', () {
    test('end, last day and days covered', () {
      // 上午11:30-下午12:30.
      expect(spanEnd('2026-11-15', 690, 60), DateTime(2026, 11, 15, 12, 30));
      expect(spanLastDay('2026-11-15', 690, 60), today);
      expect(spanDays('2026-11-15', 690, 60), 1);
      // 22:00 to 01:00 runs into Monday; to midnight it doesn't.
      expect(spanLastDay('2026-11-15', 22 * 60, 180), DateTime(2026, 11, 16));
      expect(spanLastDay('2026-11-15', 22 * 60, 120), today);
      // All day, Sunday to Tuesday.
      expect(spanEnd('2026-11-15', null, 3 * 1440), DateTime(2026, 11, 18));
      expect(spanLastDay('2026-11-15', null, 3 * 1440), DateTime(2026, 11, 17));
      expect(spanDays('2026-11-15', null, 3 * 1440), 3);
      // No span.
      expect(spanEnd('2026-11-15', 690, null), isNull);
      expect(spanLastDay('2026-11-15', null, null), today);
      expect(spanDays('2026-11-15', null, null), 1);
    });

    test('normalized for the kind of task', () {
      expect(normalizeDuration(600, 45), 45);
      expect(normalizeDuration(600, 0), isNull);
      expect(normalizeDuration(600, -30), isNull);
      expect(normalizeDuration(600, null), isNull);
      // All day: whole days, and one day is no span.
      expect(normalizeDuration(null, 1440), isNull);
      expect(normalizeDuration(null, 2880), 2880);
      expect(normalizeDuration(null, 1500), 2880);
    });

    test('moving between timed and all day', () {
      // 10:00 for three hours, then all day: one day, no span.
      expect(durationForTimeChange('2026-11-15', 600, null, 180), isNull);
      // Overnight into Monday: Sunday and Monday.
      expect(durationForTimeChange('2026-11-15', 22 * 60, null, 180), 2880);
      // All day to timed: starts over.
      expect(durationForTimeChange('2026-11-15', null, 600, 2880), isNull);
      // Same kind keeps it.
      expect(durationForTimeChange('2026-11-15', 600, 720, 90), 90);
      expect(durationForTimeChange('2026-11-15', null, null, 2880), 2880);
    });

    test('labels', () {
      expect(timeRangeLabel(9 * 60, 11 * 60), '上午9:00-11:00');
      expect(timeRangeLabel(690, 750), '上午11:30-下午12:30');
      expect(timeRangeLabel(15 * 60, 17 * 60 + 30), '下午3:00-5:30');

      // Task rows: the times today, the dates across days.
      expect(dueLabel('2026-11-15', 690, today, duration: 60), '上午11:30-下午12:30');
      expect(dueLabel('2026-11-16', 690, today, duration: 60), '明天');
      expect(dueLabel('2026-11-15', null, today, duration: 3 * 1440), '今天-后天');
      expect(dueLabel('2026-11-14', null, today, duration: 2 * 1440), '昨天-今天');

      // The detail view.
      expect(fullDueLabel('2026-11-16', 15 * 60, today, duration: 120), '明天, 下午3:00-5:00');
      expect(fullDueLabel('2026-11-15', null, today, duration: 3 * 1440), '今天 - 后天');
      expect(fullDueLabel('2026-11-15', 22 * 60, today, duration: 180),
          '今天 下午10:00 - 明天 上午1:00');
    });
  });
}
