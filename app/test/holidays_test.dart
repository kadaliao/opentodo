import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/holidays.dart';

void main() {
  test('days off and the weekend days worked, by the notices', () {
    expect(holidayOn(DateTime(2026, 2, 15)), (name: '春节', off: true));
    expect(holidayOn(DateTime(2026, 2, 23)), (name: '春节', off: true));
    expect(holidayOn(DateTime(2026, 2, 28)), (name: '春节', off: false));
    expect(holidayOn(DateTime(2026, 9, 20)), (name: '国庆节', off: false));
    expect(holidayOn(DateTime(2025, 10, 6)), (name: '国庆节、中秋节', off: true));
    expect(holidayOn(DateTime(2027, 6, 9)), (name: '端午节', off: true));
    expect(holidayOn(DateTime(2027, 1, 31)), (name: '春节', off: false));
    expect(holidayOn(DateTime(2026, 11, 16)), isNull);
    expect(holidayYears, containsAll([2025, 2026, 2027]));
  });

  test('working days', () {
    expect(isWorkday(DateTime(2026, 11, 16)), isTrue); // a Monday
    expect(isWorkday(DateTime(2026, 11, 15)), isFalse); // a Sunday
    expect(isWorkday(DateTime(2026, 10, 1)), isFalse); // 国庆节, a Thursday
    expect(isWorkday(DateTime(2026, 10, 10)), isTrue); // worked, a Saturday
    // A year without a schedule: just the weekdays.
    expect(isWorkday(DateTime(2030, 10, 1)), isTrue);
    expect(isWorkday(DateTime(2030, 10, 5)), isFalse);
  });

  test('every year adds up: days off are 休 and worked days are weekends', () {
    for (final year in holidayYears) {
      for (var d = DateTime(year); d.year == year; d = DateTime(d.year, d.month, d.day + 1)) {
        final h = holidayOn(d);
        if (h != null && !h.off) {
          expect(d.weekday, greaterThanOrEqualTo(DateTime.saturday), reason: '$d is worked in exchange');
        }
      }
    }
  });
}
