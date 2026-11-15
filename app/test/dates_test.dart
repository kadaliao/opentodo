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
}
