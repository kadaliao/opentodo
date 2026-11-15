/// The timeline (时间线) of a list or another view: its dated tasks as bars
/// along the days they cover, one lane per section (or group), packed into
/// as few rows as fit.
library;

import 'dart:math' as math;

import '../data/db.dart';
import 'dates.dart';
import 'filters.dart';
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

/// One lane of the timeline: a section of the list, or a group of the
/// view's tasks (a list, a tag, a priority), and its dated tasks.
class TimelineLane {
  const TimelineLane(this.id, this.title, this.target, this.bars);

  /// Tells the lanes apart (which ones are folded).
  final String id;

  /// Its header; null for none (a list without sections, a view that
  /// isn't grouped).
  final String? title;

  /// What a task dragged into the lane takes on (a section, a list, a tag,
  /// a priority); null: only its dates change.
  final GroupTarget? target;

  /// By first day; on the same day open before finished, then in the
  /// view's order.
  final List<TimelineBar> bars;
}

/// The open tasks without a date of one group (a section, a list…).
class UndatedGroup {
  const UndatedGroup(this.title, this.tasks);

  final String? title;
  final List<Task> tasks;
}

/// What a timeline shows.
class Timeline {
  const Timeline(this.lanes, this.undated, {this.takesUndated = true});

  /// At least one.
  final List<TimelineLane> lanes;

  /// Open tasks without a date by group, in the view's order, leaving out
  /// groups without any; they wait beside the timeline (无日期) to be
  /// dragged onto it.
  final List<UndatedGroup> undated;

  /// Whether the view can have tasks without a date at all, so 无日期
  /// shows: not 今天, 明天 or 最近7天.
  final bool takesUndated;

  Iterable<Task> get undatedTasks => undated.expand((g) => g.tasks);

  /// The lanes have headers.
  bool get titled => lanes.any((l) => l.title != null);
}

/// Bars by first day; on the same day open before finished, then in
/// [compare]'s order.
List<TimelineBar> _bars(Iterable<Task> tasks, Comparator<Task> compare) => [
      for (final t in tasks)
        if (t.dueDate != null) TimelineBar(t),
    ]..sort((a, b) {
        final c = a.start.compareTo(b.start);
        if (c != 0) return c;
        if (a.done != b.done) return a.done ? 1 : -1;
        return compare(a.task, b.task);
      });

/// Whether [t] shows on a timeline: open, or finished with a date when
/// [showDone].
bool _shows(Task t, bool showDone) =>
    t.trashedAt == null && (isOpen(t) || (showDone && isDone(t) && t.dueDate != null));

/// The timeline of the list [listId]: a lane per section. Finished tasks
/// show only with [showDone], and only those with a date.
Timeline buildTimeline(
  String listId,
  List<Task> tasks,
  List<ListSection> sections, {
  TaskSort sort = TaskSort.manual,
  bool showDone = false,
}) {
  final shown = tasks.where((t) => t.listId == listId && _shows(t, showDone)).toList();
  final groups = listGroups(shown, sections, sort: sort);
  return Timeline(
    [
      for (final g in groups)
        if (g.section != null || sections.isEmpty || g.tasks.any((t) => t.dueDate != null))
          TimelineLane(
            g.section?.id ?? '',
            sections.isEmpty ? null : g.title,
            SectionTarget(listId, g.section?.id),
            _bars(g.tasks, sort.compare),
          ),
    ],
    [
      for (final g in groups)
        if (g.tasks.where((t) => t.dueDate == null).toList() case final undated when undated.isNotEmpty)
          UndatedGroup(g.title, undated),
    ],
  );
}

/// The timeline of any view but 已完成 and 垃圾桶: a list's (the inbox's)
/// lanes are its sections, as [buildTimeline]; elsewhere the view's tasks
/// go in a lane per group of [grouping] (the view's first timeline grouping
/// when it doesn't offer that one), one for each group with any task, so
/// an undated task can be dragged on without leaving its group.
Timeline buildViewTimeline(
  ViewRef view,
  List<Task> tasks, {
  required DateTime now,
  Map<String, TaskList> lists = const {},
  Map<String, FilterRule> filters = const {},
  Map<String, List<ListSection>> sectionsByList = const {},
  TaskGrouping? grouping,
  TaskSort? sort,
  bool showDone = false,
}) {
  final sorts = sortsFor(view);
  final order = sorts.contains(sort) ? sort! : (sorts.firstOrNull ?? TaskSort.due);
  final listId = arrangedListId(view);
  if (listId != null) {
    return buildTimeline(listId, tasks, sectionsByList[listId] ?? const [], sort: order, showDone: showDone);
  }
  final matches = viewMatcher(view, now, filters);
  final shown = [
    for (final t in tasks)
      if (matches(t) && _shows(t, showDone)) t,
  ]..sort(order.compare);
  final groupings = timelineGroupingsFor(view);
  final by = groupings.contains(grouping) ? grouping! : (groupings.firstOrNull ?? TaskGrouping.none);
  final groups = groupForTimeline(shown, by, lists);
  final takesUndated = !isDateView(view);
  final lanes = [
    for (final g in groups)
      TimelineLane(g.id, by == TaskGrouping.none ? null : g.title, g.target, _bars(g.tasks, order.compare)),
  ];
  return Timeline(
    lanes.isEmpty ? const [TimelineLane('all', null, null, [])] : lanes,
    [
      if (takesUndated)
        for (final g in groups)
          if (g.tasks.where((t) => t.dueDate == null && isOpen(t)).toList() case final undated
              when undated.isNotEmpty)
            UndatedGroup(g.title, undated),
    ],
    takesUndated: takesUndated,
  );
}

/// What a task added on a lane of [view]'s timeline starts with: what the
/// view gives new tasks, and what the lane ([target]) stands for.
({String listId, String? sectionId, List<String> tags, int? priority}) laneNewTask(
  ViewRef view,
  GroupTarget? target,
  DateTime today, [
  Map<String, FilterRule> filters = const {},
]) {
  final d = quickAddDefaults(view, today, filters);
  return switch (target) {
    SectionTarget(:final listId, :final sectionId) =>
      (listId: listId, sectionId: sectionId, tags: d.tags, priority: d.priority),
    ListTarget(:final listId) => (listId: listId, sectionId: null, tags: d.tags, priority: d.priority),
    TagTarget() => (listId: d.listId, sectionId: null, tags: target.retag(d.tags), priority: d.priority),
    PriorityTarget(:final priority) => (listId: d.listId, sectionId: null, tags: d.tags, priority: priority),
    _ => (listId: d.listId, sectionId: null, tags: d.tags, priority: d.priority),
  };
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

/// Where [t] starts, and how long it lasts, once its left edge is dragged
/// to [firstDay] (never after its last day): it still ends when it did. An
/// all-day task covers whole days to its last (one day is no span). A timed
/// one keeps its time of day; when that's no longer before its end (it's on
/// its last day now, which it reached after midnight), it has no span.
({DateTime date, int? duration}) restartedSchedule(Task t, DateTime firstDay) {
  final start = parseDateKey(t.dueDate!);
  final last = spanLastDay(t.dueDate!, t.dueTime, t.duration);
  final first = firstDay.isAfter(last) ? last : dateOnly(firstDay);
  final time = t.dueTime;
  if (time == null) {
    return (date: first, duration: normalizeDuration(null, (daysBetween(first, last) + 1) * minutesPerDay));
  }
  // On the wall clock, from the old first day's midnight.
  final end = time + (t.duration ?? 0);
  final d = end - (daysBetween(start, first) * minutesPerDay + time);
  return (date: first, duration: normalizeDuration(time, d));
}

/// The month a timeline shows from [day]: 2026年11月.
String timelineMonthLabel(DateTime day) => '${day.year}年${day.month}月';
