/// Calendar-date helpers. Task dates are stored as `YYYY-MM-DD` strings in
/// local calendar terms, so everything here works on dates, not instants.
library;

String _two(int n) => n.toString().padLeft(2, '0');

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [from] to [to]; DST-safe.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

const weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String weekdayName(DateTime d) => weekdayNames[d.weekday - 1];

/// Monday of the week [d] is in.
DateTime startOfWeek(DateTime d) => addDays(dateOnly(d), 1 - d.weekday);

/// 今天 / 明天 / 后天 / 昨天 / 周三 / 下周一 / 11月20日 / 2027年1月3日.
String dateLabel(DateTime date, DateTime today) {
  final d = daysBetween(today, date);
  switch (d) {
    case 0:
      return '今天';
    case 1:
      return '明天';
    case 2:
      return '后天';
    case -1:
      return '昨天';
  }
  final nextWeek = addDays(startOfWeek(today), 7);
  if (d > 0 && date.isBefore(nextWeek)) return weekdayName(date);
  if (d > 0 && date.isBefore(addDays(nextWeek, 7))) {
    return '下${weekdayName(date)}';
  }
  if (date.year == today.year) return '${date.month}月${date.day}日';
  return '${date.year}年${date.month}月${date.day}日';
}

/// 上午9:00 / 下午3:30.
String timeLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${h < 12 ? '上午' : '下午'}$h12:${_two(m)}';
}

/// Short due label for a task row: just the time for today's timed tasks,
/// otherwise the date label.
String dueLabel(String dueDate, int? dueTime, DateTime today) {
  final date = parseDateKey(dueDate);
  if (dueTime != null && daysBetween(today, date) == 0) {
    return timeLabel(dueTime);
  }
  return dateLabel(date, today);
}

/// Full label for the detail view: 明天, 下午3:00.
String fullDueLabel(String dueDate, int? dueTime, DateTime today) {
  final label = dateLabel(parseDateKey(dueDate), today);
  return dueTime == null ? label : '$label, ${timeLabel(dueTime)}';
}

/// Section header for a day: 今天, 周日 / 11月18日, 周三.
String daySectionTitle(DateTime date, DateTime today) {
  final d = daysBetween(today, date);
  final head = switch (d) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    _ => date.year == today.year
        ? '${date.month}月${date.day}日'
        : '${date.year}年${date.month}月${date.day}日',
  };
  return '$head, ${weekdayName(date)}';
}
