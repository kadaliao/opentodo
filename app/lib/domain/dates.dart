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
/// otherwise the date label. A span shows both ends: 上午9:00-11:00 today,
/// 今天-11月17日 across days.
String dueLabel(String dueDate, int? dueTime, DateTime today, {int? duration}) {
  final date = parseDateKey(dueDate);
  final last = spanLastDay(dueDate, dueTime, duration);
  if (last != date) return '${dateLabel(date, today)}-${dateLabel(last, today)}';
  if (dueTime != null && daysBetween(today, date) == 0) {
    return duration == null ? timeLabel(dueTime) : timeRangeLabel(dueTime, dueTime + duration);
  }
  return dateLabel(date, today);
}

/// Full label for the detail view: 明天, 下午3:00; with a span 明天,
/// 下午3:00-5:00, 今天 - 11月17日 or 今天 下午10:00 - 明天 上午1:00.
String fullDueLabel(String dueDate, int? dueTime, DateTime today, {int? duration}) {
  final date = parseDateKey(dueDate);
  final label = dateLabel(date, today);
  final end = spanEnd(dueDate, dueTime, duration);
  if (end == null) return dueTime == null ? label : '$label, ${timeLabel(dueTime)}';
  final last = spanLastDay(dueDate, dueTime, duration);
  if (dueTime == null) return last == date ? label : '$label - ${dateLabel(last, today)}';
  if (last == date) return '$label, ${timeRangeLabel(dueTime, dueTime + duration!)}';
  return '$label ${timeLabel(dueTime)} - '
      '${dateLabel(dateOnly(end), today)} ${timeLabel(end.hour * 60 + end.minute)}';
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

// ---- spans (时间段) ----
//
// A task that spans a while starts at its due date and time and lasts
// `duration` minutes; the end is exclusive. An all-day span is whole days,
// so 2880 is the due date and the day after. Like due dates, spans float
// with the device's clock: the arithmetic is on wall-clock time.

const minutesPerDay = 24 * 60;

/// How long a span is when the person first asks for one.
const defaultSpanMinutes = 60;

/// Where a task's day or time begins: its due time, or the midnight that
/// starts its due date.
DateTime dueStart(String dueDate, int? dueTime) {
  final d = parseDateKey(dueDate);
  return DateTime(d.year, d.month, d.day, 0, dueTime ?? 0);
}

/// Where a span ends (exclusive); null for a task without one.
DateTime? spanEnd(String dueDate, int? dueTime, int? duration) {
  if (duration == null) return null;
  final d = parseDateKey(dueDate);
  return DateTime(d.year, d.month, d.day, 0, (dueTime ?? 0) + duration);
}

/// The last day a task is on: its due date, or the day its span ends on
/// (a span ending at midnight ends the day before).
DateTime spanLastDay(String dueDate, int? dueTime, int? duration) {
  final end = spanEnd(dueDate, dueTime, duration);
  final start = parseDateKey(dueDate);
  if (end == null) return start;
  final last = dateOnly(DateTime(end.year, end.month, end.day, end.hour, end.minute - 1));
  return last.isBefore(start) ? start : last;
}

/// How many calendar days a task is on: 1 unless it spans midnight.
int spanDays(String dueDate, int? dueTime, int? duration) =>
    daysBetween(parseDateKey(dueDate), spanLastDay(dueDate, dueTime, duration)) + 1;

/// A span that makes sense for a task with [dueTime]: positive, and whole
/// days of two or more for an all-day task (one day is no span at all).
int? normalizeDuration(int? dueTime, int? duration) {
  if (duration == null || duration <= 0) return null;
  if (dueTime != null) return duration;
  final days = (duration / minutesPerDay).ceil();
  return days < 2 ? null : days * minutesPerDay;
}

/// The span a task keeps when it moves between having a time and being all
/// day: the days it covered, or nothing. Same kind, same span.
int? durationForTimeChange(String dueDate, int? fromTime, int? toTime, int? duration) {
  if ((fromTime == null) == (toTime == null)) return duration;
  if (duration == null || toTime != null) return null;
  return normalizeDuration(null, spanDays(dueDate, fromTime, duration) * minutesPerDay);
}

/// 上午9:00-11:00 / 上午11:30-下午12:30: the end leaves out 上午 or 下午 when
/// the start has the same.
String timeRangeLabel(int start, int end) {
  final e = end % minutesPerDay;
  final a = timeLabel(start), b = timeLabel(e);
  return (start < 720) == (e < 720) ? '$a-${b.substring(2)}' : '$a-$b';
}
