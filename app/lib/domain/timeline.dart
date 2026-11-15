/// The timeline (时间线) of a list: its dated tasks as bars along the days
/// they cover, one lane per section, packed into as few rows as fit.
library;

import 'dart:math' as math;

import '../data/db.dart';
import 'dates.dart';
import 'views.dart';

/// How much time a screen of the timeline takes in: how wide a day is.
enum TimelineScale {
  day('日'),
  week('周'),
  month('月');

  const TimelineScale(this.label);
  final String label;

  /// How many days a bar takes up in its row at the least, with its title
  /// beside it when the bar itself is too narrow to hold it.
  int get minDays => switch (this) {
        TimelineScale.day => 1,
        TimelineScale.week => 4,
        TimelineScale.month => 10,
      };

  static TimelineScale? byName(Object? name) =>
      values.where((s) => s.name == name).firstOrNull;
}

/// A task on the timeline, from the first day it is on to the last.
class TimelineBar {
  TimelineBar(this.task)
      : start = parseDateKey(task.dueDate!),
        last = spanLastDay(task.dueDate!, task.dueTime, task.duration);

  final Task task;
  final DateTime start, last;

  int get days => daysBetween(start, last) + 1;

  bool get done => task.status != TaskStatus.open;

  /// Whether any of it is on the days from [from] to [to], both included.
  bool overlaps(DateTime from, DateTime to) => !last.isBefore(from) && !start.isAfter(to);

  @override
  String toString() => '${task.title} ${dateKey(start)}..${dateKey(last)}';
}

/// One lane of the timeline: a section of the list, or 未分组 ([section]
/// null), and its dated tasks.
class TimelineLane {
  const TimelineLane(this.section, this.bars);

  final ListSection? section;

  /// By first day; on the same day open before finished, then in the
  /// list's order.
  final List<TimelineBar> bars;

  String get title => section?.name ?? '未分组';
}

/// What the timeline of a list shows.
class Timeline {
  const Timeline(this.lanes, this.undated);

  /// One per section, in order, with 未分组 first when it has dated tasks
  /// (and always when the list has no sections).
  final List<TimelineLane> lanes;

  /// Open tasks without a date by section, in the list's order, leaving
  /// out sections without any; they wait beside the timeline (无日期) to
  /// be dragged onto it.
  final List<ListGroup> undated;

  Iterable<Task> get undatedTasks => undated.expand((g) => g.tasks);
}

/// The timeline of the list [listId]. Finished tasks show only with
/// [showDone], and only those with a date.
Timeline buildTimeline(
  String listId,
  List<Task> tasks,
  List<ListSection> sections, {
  TaskSort sort = TaskSort.manual,
  bool showDone = false,
}) {
  final shown = tasks
      .where((t) => t.listId == listId && t.trashedAt == null && (isOpen(t) || (showDone && isDone(t) && t.dueDate != null)))
      .toList();
  final compare = sort.compare;
  int byStart(TimelineBar a, TimelineBar b) {
    final c = a.start.compareTo(b.start);
    if (c != 0) return c;
    if (a.done != b.done) return a.done ? 1 : -1;
    return compare(a.task, b.task);
  }

  final groups = listGroups(shown, sections, sort: sort);
  return Timeline(
    [
      for (final g in groups)
        if (g.section != null || sections.isEmpty || g.tasks.any((t) => t.dueDate != null))
          TimelineLane(g.section, [
            for (final t in g.tasks)
              if (t.dueDate != null) TimelineBar(t),
          ]..sort(byStart)),
    ],
    [
      for (final g in groups)
        if (g.tasks.where((t) => t.dueDate == null).toList() case final undated when undated.isNotEmpty)
          ListGroup(g.section, undated),
    ],
  );
}

/// Packs [bars] (by first day) into rows, each bar in the first row with
/// room for it. A bar takes [minDays] days at the least, for its title.
List<List<TimelineBar>> packRows(List<TimelineBar> bars, {int minDays = 1}) {
  final rows = <List<TimelineBar>>[];
  final ends = <DateTime>[];
  for (final b in bars) {
    final end = b.days >= minDays ? b.last : addDays(b.start, minDays - 1);
    final row = ends.indexWhere((e) => e.isBefore(b.start));
    if (row < 0) {
      rows.add([b]);
      ends.add(end);
    } else {
      rows[row].add(b);
      ends[row] = end;
    }
  }
  return rows;
}

/// How long [t] lasts once its right edge is dragged to [lastDay] (never
/// before its first day). An all-day task covers whole days (one day is no
/// span). A timed one ends at the same time of day as before, on the new
/// last day; one that can't (it ended at midnight, or it is back on its
/// first day and ended after midnight) ends with that day, or has no span
/// on its first.
int? resizedDuration(Task t, DateTime lastDay) {
  final start = parseDateKey(t.dueDate!);
  final k = math.max(daysBetween(start, lastDay), 0);
  final time = t.dueTime;
  if (time == null) return normalizeDuration(null, (k + 1) * minutesPerDay);
  int lastIndex(int? d) => daysBetween(start, spanLastDay(t.dueDate!, time, d));
  final was = lastIndex(t.duration);
  if (k == was) return t.duration;
  final d = (t.duration ?? 0) + (k - was) * minutesPerDay;
  if (d > 0 && lastIndex(d) == k) return d;
  return k == 0 ? null : (k + 1) * minutesPerDay - time;
}

/// The month a timeline shows from [day]: 2026年11月.
String timelineMonthLabel(DateTime day) => '${day.year}年${day.month}月';
