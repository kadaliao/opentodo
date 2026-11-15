/// What the calendar shows: which days each mode covers, which tasks land on
/// them (a repeating task on its later dates too), and how timed tasks that
/// overlap share a day's column.
library;

import 'dart:math' as math;

import '../data/db.dart';
import 'dates.dart';
import 'recurrence.dart';
import 'views.dart';

enum CalendarMode {
  day('日'),
  threeDays('3天'),
  week('周'),
  month('月'),
  agenda('日程');

  const CalendarMode(this.label);
  final String label;

  /// Day, 3-day and week are hour grids.
  bool get isTimeGrid => this == day || this == threeDays || this == week;

  static CalendarMode? byName(String? name) =>
      values.where((m) => m.name == name).firstOrNull;
}

/// Calendar days from [start] up to, not including, [end].
class DayRange {
  DayRange(DateTime start, DateTime end)
      : start = dateOnly(start),
        end = dateOnly(end);

  final DateTime start;
  final DateTime end;

  int get length => daysBetween(start, end);

  List<DateTime> get days => [for (var i = 0; i < length; i++) addDays(start, i)];

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is DayRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '${dateKey(start)}..${dateKey(end)}';
}

/// Whole weeks (Monday first) covering a month: what the month grid shows.
DayRange monthGrid(int year, int month) {
  final first = DateTime(year, month);
  final last = DateTime(year, month + 1, 0);
  return DayRange(startOfWeek(first), addDays(startOfWeek(last), 7));
}

/// The days [mode] shows around [anchor], the day the person is looking at.
DayRange visibleRange(CalendarMode mode, DateTime anchor) {
  final a = dateOnly(anchor);
  return switch (mode) {
    CalendarMode.day => DayRange(a, addDays(a, 1)),
    CalendarMode.threeDays => DayRange(a, addDays(a, 3)),
    CalendarMode.week => DayRange(startOfWeek(a), addDays(startOfWeek(a), 7)),
    CalendarMode.month => monthGrid(a.year, a.month),
    CalendarMode.agenda => DayRange(DateTime(a.year, a.month), DateTime(a.year, a.month + 1)),
  };
}

/// The anchor one page on (or back, for a negative [pages]). Month pages
/// keep the day of the month where they can (31 Jan → 28 Feb).
DateTime shiftAnchor(CalendarMode mode, DateTime anchor, int pages) {
  final a = dateOnly(anchor);
  switch (mode) {
    case CalendarMode.day:
      return addDays(a, pages);
    case CalendarMode.threeDays:
      return addDays(a, 3 * pages);
    case CalendarMode.week:
      return addDays(a, 7 * pages);
    case CalendarMode.month:
    case CalendarMode.agenda:
      final m = DateTime(a.year, a.month + pages);
      return DateTime(m.year, m.month, math.min(a.day, daysInMonth(m.year, m.month)));
  }
}

/// 2026年11月; a week running into the next month, 2026年11月–12月.
String calendarTitle(CalendarMode mode, DateTime anchor) {
  String ym(DateTime d) => '${d.year}年${d.month}月';
  if (!mode.isTimeGrid) return ym(anchor);
  final r = visibleRange(mode, anchor);
  final first = r.start, last = addDays(r.end, -1);
  if (first.month == last.month) return ym(first);
  if (first.year == last.year) return '${ym(first)}–${last.month}月';
  return '${ym(first)}–${ym(last)}';
}

/// One task on one day of the calendar.
class CalendarEntry {
  const CalendarEntry(this.task, this.date, {this.projected = false});

  final Task task;
  final DateTime date;

  /// A later date of a repeating task, shown ahead of time. Only the task's
  /// own date is real: a projected one can't be ticked off or moved.
  final bool projected;

  int? get time => task.dueTime;
  bool get allDay => task.dueTime == null;
  bool get done => task.status != TaskStatus.open;

  /// Unique within a calendar page.
  String get key => '${task.id}@${dateKey(date)}';

  @override
  String toString() => '$key${projected ? '*' : ''}';
}

/// What the person chose to see.
class CalendarFilter {
  const CalendarFilter({
    this.showCompleted = true,
    this.showRepeats = true,
    this.hiddenLists = const {},
  });

  final bool showCompleted;

  /// Show every later date of a repeating task, not just the next one.
  final bool showRepeats;

  /// Lists (by id, [inboxListId] included) left off the calendar.
  final Set<String> hiddenLists;
}

/// A daily task looked at decades ahead stops here.
const _maxProjected = 20000;

/// The tasks on the days of [range], in display order.
///
/// A repeating task also shows on the dates it will move to, which are all
/// after [today]: finishing an overdue one skips the dates already passed
/// (see `advanceRepeat`), and one counted from completion starts again from
/// the day it's done.
List<CalendarEntry> calendarEntries(
  List<Task> tasks,
  DayRange range, {
  required DateTime today,
  CalendarFilter filter = const CalendarFilter(),
}) {
  today = dateOnly(today);
  final startKey = dateKey(range.start), endKey = dateKey(range.end);
  final out = <CalendarEntry>[];
  for (final t in tasks) {
    final due = t.dueDate;
    if (due == null || t.trashedAt != null || filter.hiddenLists.contains(t.listId)) continue;
    final open = t.status == TaskStatus.open;
    if (!open && !filter.showCompleted) continue;
    if (due.compareTo(startKey) >= 0 && due.compareTo(endKey) < 0) {
      out.add(CalendarEntry(t, parseDateKey(due)));
    }
    if (!open || !filter.showRepeats || due.compareTo(endKey) >= 0) continue;
    final rule = RepeatRule.tryParse(t.repeatRule);
    if (rule == null) continue;
    final dueDate = parseDateKey(due);
    final from = t.repeatFrom == RepeatFrom.completion && dueDate.isBefore(today) ? today : dueDate;
    var steps = 0;
    for (final d in occurrencesAfter(rule, from)) {
      if (!d.isBefore(range.end) || ++steps > _maxProjected) break;
      if (d.isAfter(today) && !d.isBefore(range.start)) {
        out.add(CalendarEntry(t, d, projected: true));
      }
    }
  }
  return out..sort(compareEntries);
}

/// By day; within a day open before finished, all-day before timed, then
/// by time and priority.
int compareEntries(CalendarEntry a, CalendarEntry b) {
  final d = a.date.compareTo(b.date);
  if (d != 0) return d;
  if (a.done != b.done) return a.done ? 1 : -1;
  final at = a.time ?? -1, bt = b.time ?? -1;
  if (at != bt) return at.compareTo(bt);
  return compareByPriority(a.task, b.task);
}

/// Entries by `YYYY-MM-DD`, each day's in display order.
Map<String, List<CalendarEntry>> entriesByDay(List<CalendarEntry> entries) {
  final out = <String, List<CalendarEntry>>{};
  for (final e in entries) {
    out.putIfAbsent(dateKey(e.date), () => []).add(e);
  }
  return out;
}

const minutesPerDay = 24 * 60;

/// Where a timed entry sits in its day's column.
class TimedPlacement {
  const TimedPlacement(this.entry, this.start, this.end, this.column, this.columns);

  final CalendarEntry entry;

  /// Minutes after midnight; [end] is exclusive.
  final int start, end;

  /// Side by side with [columns] - 1 others it overlaps, in slot [column].
  final int column, columns;

  @override
  String toString() => '${entry.task.title} $start-$end $column/$columns';
}

/// Lays out one day's timed entries. Tasks have no length yet, so each takes
/// [span] minutes (cut short at midnight). Entries that overlap share the
/// width, each in the first free slot, as in most calendars.
List<TimedPlacement> layoutTimed(List<CalendarEntry> entries, {int span = 30}) {
  final timed = entries.where((e) => e.time != null).toList()
    ..sort((a, b) {
      final c = a.time!.compareTo(b.time!);
      return c != 0 ? c : compareEntries(a, b);
    });
  final out = <TimedPlacement>[];
  var cluster = <(CalendarEntry, int, int, int)>[];
  var slotEnds = <int>[];
  var clusterEnd = -1;

  void flush() {
    for (final (e, s, end, col) in cluster) {
      out.add(TimedPlacement(e, s, end, col, slotEnds.length));
    }
    cluster = [];
    slotEnds = [];
  }

  for (final e in timed) {
    final start = e.time!.clamp(0, minutesPerDay - 1);
    final end = math.min(start + span, minutesPerDay);
    if (start >= clusterEnd) flush();
    var col = slotEnds.indexWhere((slotEnd) => slotEnd <= start);
    if (col < 0) {
      col = slotEnds.length;
      slotEnds.add(end);
    } else {
      slotEnds[col] = end;
    }
    cluster.add((e, start, end, col));
    clusterEnd = math.max(clusterEnd, end);
  }
  flush();
  return out;
}

/// Rounds [minutes] down to a whole [step] that still fits in the day.
int snapMinutes(double minutes, {int step = 15}) {
  final m = (minutes / step).floor() * step;
  return m.clamp(0, minutesPerDay - step);
}

/// 09:00.
String clockLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
