/// What the middle pane shows: a smart list, a list of the person's own, a
/// tag or a saved filter, and how its tasks are grouped into sections.
library;

import '../data/db.dart';
import 'dates.dart';
import 'filters.dart';

enum SmartKind { today, tomorrow, next7, inbox, completed, trash }

sealed class ViewRef {
  const ViewRef();
}

final class SmartViewRef extends ViewRef {
  const SmartViewRef(this.kind);
  final SmartKind kind;

  @override
  bool operator ==(Object other) => other is SmartViewRef && other.kind == kind;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'smart:${kind.name}';
}

final class ListViewRef extends ViewRef {
  const ListViewRef(this.listId);
  final String listId;

  @override
  bool operator ==(Object other) =>
      other is ListViewRef && other.listId == listId;
  @override
  int get hashCode => listId.hashCode;
  @override
  String toString() => 'list:$listId';
}

final class TagViewRef extends ViewRef {
  const TagViewRef(this.tag);
  final String tag;

  @override
  bool operator ==(Object other) => other is TagViewRef && other.tag == tag;
  @override
  int get hashCode => tag.hashCode;
  @override
  String toString() => 'tag:$tag';
}

final class FilterViewRef extends ViewRef {
  const FilterViewRef(this.filterId);
  final String filterId;

  @override
  bool operator ==(Object other) =>
      other is FilterViewRef && other.filterId == filterId;
  @override
  int get hashCode => filterId.hashCode;
  @override
  String toString() => 'filter:$filterId';
}

class TaskSection {
  const TaskSection({
    required this.id,
    required this.title,
    required this.tasks,
    this.collapsedByDefault = false,
    this.alert = false,
    this.arrangeable = false,
    this.listSection,
  });

  final String id;

  /// Null for a list without headers.
  final String? title;
  final List<Task> tasks;
  final bool collapsedByDefault;

  /// Shown in the warning colour (已过期).
  final bool alert;

  /// Open tasks of one section of a list, in manual order: they can be
  /// dragged within it and dropped into it.
  final bool arrangeable;

  /// The list's section (分组) this is; null for 未分组 and for sections
  /// that aren't a list's.
  final ListSection? listSection;
}

/// The list a view shows, if it is one the person arranges by hand: one of
/// their lists, or the inbox.
String? arrangedListId(ViewRef view) => switch (view) {
      ListViewRef(:final listId) => listId,
      SmartViewRef(kind: SmartKind.inbox) => inboxListId,
      _ => null,
    };

/// Manual order: smallest `sortOrder` first, newest first on a tie.
int compareByOrder(Task a, Task b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
}

/// One section of a list and its tasks; [section] null is 未分组: tasks
/// without a section, or with one that isn't this list's (any more).
class ListGroup {
  const ListGroup(this.section, this.tasks);
  final ListSection? section;
  final List<Task> tasks;

  String get title => section?.name ?? '未分组';
}

/// The tasks of a list sorted into its [sections], each in manual order.
/// 未分组 comes first, and only when it has tasks or the list has no
/// sections.
List<ListGroup> listGroups(List<Task> tasks, List<ListSection> sections) {
  final ordered = [...sections]..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
  final byId = {for (final s in ordered) s.id: <Task>[]};
  final loose = <Task>[];
  for (final t in tasks) {
    (byId[t.sectionId] ?? loose).add(t);
  }
  return [
    if (loose.isNotEmpty || ordered.isEmpty) ListGroup(null, loose..sort(compareByOrder)),
    for (final s in ordered) ListGroup(s, byId[s.id]!..sort(compareByOrder)),
  ];
}

/// A column of the board: a section's open tasks in manual order, and its
/// finished ones, most recent first.
class BoardColumn {
  const BoardColumn(this.group, this.done);
  final ListGroup group;
  final List<Task> done;
}

/// The board (看板) of the list [listId]: one column per section.
List<BoardColumn> boardColumns(
    String listId, List<Task> tasks, List<ListSection> sections) {
  final inList = tasks.where((t) => t.listId == listId && t.trashedAt == null).toList();
  final open = listGroups(inList.where(isOpen).toList(), sections);
  final done = listGroups(inList.where(isDone).toList(), sections);
  final doneBySection = {for (final g in done) g.section?.id: g.tasks};
  final columns = [
    for (final g in open)
      BoardColumn(g, [...?doneBySection[g.section?.id]]..sort(_compareCompleted)),
  ];
  // Finished tasks without a section get a 未分组 column too.
  if (open.first.section != null && (doneBySection[null]?.isNotEmpty ?? false)) {
    columns.insert(0, BoardColumn(const ListGroup(null, []), [...doneBySection[null]!]..sort(_compareCompleted)));
  }
  return columns;
}

bool isOpen(Task t) => t.status == TaskStatus.open && t.trashedAt == null;

/// The last day a dated task is on, `YYYY-MM-DD`: its due date, or where
/// its span ends.
String lastDueKey(Task t) => t.duration == null
    ? t.dueDate!
    : dateKey(spanLastDay(t.dueDate!, t.dueTime, t.duration));

/// Whether an open task's due moment has come: an earlier day, or today
/// once its time is reached (the minute its 准时 reminder goes off). A span
/// is due when it ends.
bool isOverdue(Task t, DateTime now) {
  if (!isOpen(t) || t.dueDate == null) return false;
  final end = spanEnd(t.dueDate!, t.dueTime, t.duration);
  if (end != null) {
    return !DateTime(now.year, now.month, now.day, now.hour, now.minute).isBefore(end);
  }
  final c = t.dueDate!.compareTo(dateKey(now));
  if (c != 0) return c < 0;
  return t.dueTime != null && t.dueTime! <= now.hour * 60 + now.minute;
}
bool isDone(Task t) => t.status != TaskStatus.open && t.trashedAt == null;

String listName(String listId, Map<String, TaskList> lists) =>
    listId == inboxListId ? '收集箱' : (lists[listId]?.name ?? '收集箱');

String viewTitle(ViewRef view, Map<String, TaskList> lists,
        [Map<String, TaskFilter> filters = const {}]) =>
    switch (view) {
      SmartViewRef(kind: SmartKind.today) => '今天',
      SmartViewRef(kind: SmartKind.tomorrow) => '明天',
      SmartViewRef(kind: SmartKind.next7) => '最近7天',
      SmartViewRef(kind: SmartKind.inbox) => '收集箱',
      SmartViewRef(kind: SmartKind.completed) => '已完成',
      SmartViewRef(kind: SmartKind.trash) => '垃圾桶',
      ListViewRef(:final listId) => listName(listId, lists),
      TagViewRef(:final tag) => '#$tag',
      FilterViewRef(:final filterId) => filters[filterId]?.name ?? '过滤器',
    };

/// Where a task typed into this view's quick-add field goes.
({String listId, DateTime? date, List<String> tags, int? priority}) quickAddDefaults(
    ViewRef view, DateTime today,
    [Map<String, FilterRule> filters = const {}]) {
  return switch (view) {
    SmartViewRef(kind: SmartKind.today || SmartKind.next7) => (
        listId: inboxListId,
        date: today,
        tags: const <String>[],
        priority: null,
      ),
    SmartViewRef(kind: SmartKind.tomorrow) => (
        listId: inboxListId,
        date: addDays(today, 1),
        tags: const <String>[],
        priority: null,
      ),
    ListViewRef(:final listId) => (
        listId: listId,
        date: null,
        tags: const <String>[],
        priority: null,
      ),
    TagViewRef(:final tag) => (listId: inboxListId, date: null, tags: [tag], priority: null),
    FilterViewRef(:final filterId) when filters[filterId] != null => () {
        final h = filters[filterId]!.quickAddHints(today);
        return (
          listId: h.listId ?? inboxListId,
          date: h.date,
          tags: [?h.tag],
          priority: h.priority,
        );
      }(),
    _ => (listId: inboxListId, date: null, tags: const <String>[], priority: null),
  };
}

/// Whether a date view lists a task due on [date]. Views that aren't about
/// dates show it regardless.
bool dateViewShows(ViewRef view, DateTime date, DateTime today) {
  final d = daysBetween(today, date);
  return switch (view) {
    SmartViewRef(kind: SmartKind.today) => d <= 0,
    SmartViewRef(kind: SmartKind.tomorrow) => d == 1,
    SmartViewRef(kind: SmartKind.next7) => d <= 6,
    _ => true,
  };
}

bool canQuickAdd(ViewRef view) => switch (view) {
      SmartViewRef(kind: SmartKind.completed || SmartKind.trash) => false,
      _ => true,
    };

/// Dated tasks first by date and time (all-day before timed), then by
/// priority, then newest first.
int compareByDue(Task a, Task b) {
  final ad = a.dueDate, bd = b.dueDate;
  if (ad != bd) {
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  }
  final at = a.dueTime ?? -1, bt = b.dueTime ?? -1;
  if (at != bt) return at.compareTo(bt);
  return compareByPriority(a, b);
}

int compareByPriority(Task a, Task b) {
  if (a.priority != b.priority) return b.priority.compareTo(a.priority);
  return b.createdAt.compareTo(a.createdAt);
}

int _compareCompleted(Task a, Task b) =>
    (b.completedAt ?? 0).compareTo(a.completedAt ?? 0);

/// A test for the tasks [view] lists as of [now], finished ones included.
/// A filter that isn't in [filters] (deleted, or not loaded yet) lists
/// nothing.
bool Function(Task) viewMatcher(ViewRef view, DateTime now,
    [Map<String, FilterRule> filters = const {}]) {
  if (view case FilterViewRef(:final filterId)) {
    return filters[filterId]?.matcher(now) ?? (_) => false;
  }
  final today = dateOnly(now);
  final keys = (
    dateKey(today),
    dateKey(addDays(today, 1)),
    dateKey(addDays(today, 6)),
  );
  return (t) => _matchesView(t, view, keys.$1, keys.$2, keys.$3);
}

bool _matchesView(Task t, ViewRef view, String todayKey, String tomorrowKey,
    String weekEndKey) {
  if (t.trashedAt != null) {
    return view == const SmartViewRef(SmartKind.trash);
  }
  return switch (view) {
    SmartViewRef(kind: SmartKind.today) =>
      t.dueDate != null && t.dueDate!.compareTo(todayKey) <= 0,
    SmartViewRef(kind: SmartKind.tomorrow) => t.dueDate != null &&
        t.dueDate!.compareTo(tomorrowKey) <= 0 &&
        lastDueKey(t).compareTo(tomorrowKey) >= 0,
    SmartViewRef(kind: SmartKind.next7) =>
      t.dueDate != null && t.dueDate!.compareTo(weekEndKey) <= 0,
    SmartViewRef(kind: SmartKind.inbox) => t.listId == inboxListId,
    SmartViewRef(kind: SmartKind.completed) => isDone(t),
    SmartViewRef(kind: SmartKind.trash) => false,
    ListViewRef(:final listId) => t.listId == listId,
    TagViewRef(:final tag) => t.tags.contains(tag),
    FilterViewRef() => false, // see viewMatcher
  };
}

/// Where to show a task opened from elsewhere, such as a notification: the
/// current view if it lists the task, else 今天 for one due by today, else
/// its list.
ViewRef viewForTask(Task t, ViewRef current, DateTime now,
    [Map<String, FilterRule> filters = const {}]) {
  final todayKey = dateKey(now);
  if (viewMatcher(current, now, filters)(t)) return current;
  if (t.trashedAt != null) return const SmartViewRef(SmartKind.trash);
  if (t.status != TaskStatus.open) return const SmartViewRef(SmartKind.completed);
  if (t.dueDate != null && t.dueDate!.compareTo(todayKey) <= 0) {
    return const SmartViewRef(SmartKind.today);
  }
  return t.listId == inboxListId
      ? const SmartViewRef(SmartKind.inbox)
      : ListViewRef(t.listId);
}

/// Number shown next to a view in the sidebar: its open tasks.
int openCount(ViewRef view, List<Task> tasks, DateTime now,
    [Map<String, FilterRule> filters = const {}]) {
  final matches = viewMatcher(view, now, filters);
  return tasks.where((t) => isOpen(t) && matches(t)).length;
}

List<TaskSection> buildSections({
  required ViewRef view,
  required List<Task> tasks,
  required Map<String, TaskList> lists,
  required DateTime now,
  Map<String, FilterRule> filters = const {},
  Map<String, List<ListSection>> sectionsByList = const {},
}) {
  final today = dateOnly(now);
  final todayKey = dateKey(today);
  final tomorrowKey = dateKey(addDays(today, 1));
  final weekEndKey = dateKey(addDays(today, 6));
  final inView = tasks.where(viewMatcher(view, now, filters)).toList();

  if (view == const SmartViewRef(SmartKind.trash)) {
    inView.sort((a, b) => (b.trashedAt ?? 0).compareTo(a.trashedAt ?? 0));
    return [if (inView.isNotEmpty) TaskSection(id: 'trash', title: null, tasks: inView)];
  }

  if (view == const SmartViewRef(SmartKind.completed)) {
    inView.sort(_compareCompleted);
    final byDay = <String, List<Task>>{};
    for (final t in inView) {
      final at = DateTime.fromMillisecondsSinceEpoch(t.completedAt ?? t.updatedAt);
      byDay.putIfAbsent(dateKey(at), () => []).add(t);
    }
    return [
      for (final e in byDay.entries)
        TaskSection(
          id: 'done-${e.key}',
          title: daySectionTitle(parseDateKey(e.key), today),
          tasks: e.value,
        ),
    ];
  }

  final isDateView = view is SmartViewRef &&
      (view.kind == SmartKind.today ||
          view.kind == SmartKind.tomorrow ||
          view.kind == SmartKind.next7);
  final open = inView.where(isOpen).toList();
  // A date view lists finished tasks from its own days, not every task
  // ever finished that was due in the past.
  final done = inView
      .where((t) =>
          isDone(t) && (!isDateView || lastDueKey(t).compareTo(todayKey) >= 0))
      .toList()
    ..sort(_compareCompleted);
  final doneSection = done.isEmpty
      ? null
      : TaskSection(
          id: 'done',
          title: '已完成',
          tasks: done,
          collapsedByDefault: view is! SmartViewRef,
        );

  final sections = <TaskSection>[];
  switch (view) {
    case SmartViewRef(kind: SmartKind.today || SmartKind.tomorrow || SmartKind.next7):
      open.sort(compareByDue);
      final overdue = open.where((t) => lastDueKey(t).compareTo(todayKey) < 0);
      if (overdue.isNotEmpty) {
        sections.add(TaskSection(
            id: 'overdue', title: '已过期', tasks: overdue.toList(), alert: true));
      }
      // A span that began earlier shows once, on the view's first day.
      final firstKey = view == const SmartViewRef(SmartKind.tomorrow) ? tomorrowKey : todayKey;
      final byDay = <String, List<Task>>{};
      for (final t in open.where((t) => lastDueKey(t).compareTo(todayKey) >= 0)) {
        final key = t.dueDate!.compareTo(firstKey) < 0 ? firstKey : t.dueDate!;
        byDay.putIfAbsent(key, () => []).add(t);
      }
      for (final e in byDay.entries) {
        sections.add(TaskSection(
          id: 'day-${e.key}',
          title: daySectionTitle(parseDateKey(e.key), today),
          tasks: e.value,
        ));
      }
    case FilterViewRef():
      // By date: overdue, each of the next seven days, later, undated.
      open.sort(compareByDue);
      final byKey = <String, List<Task>>{};
      for (final t in open) {
        final String key;
        if (t.dueDate == null) {
          key = 'none';
        } else if (lastDueKey(t).compareTo(todayKey) < 0) {
          key = 'overdue';
        } else if (t.dueDate!.compareTo(weekEndKey) > 0) {
          key = 'later';
        } else {
          key = t.dueDate!.compareTo(todayKey) < 0 ? todayKey : t.dueDate!;
        }
        byKey.putIfAbsent(key, () => []).add(t);
      }
      final keys = byKey.keys.toList()
        ..sort((a, b) {
          int rank(String k) => switch (k) { 'overdue' => 0, 'later' => 2, 'none' => 3, _ => 1 };
          final c = rank(a).compareTo(rank(b));
          return c != 0 ? c : a.compareTo(b);
        });
      for (final k in keys) {
        sections.add(switch (k) {
          'overdue' => TaskSection(id: k, title: '已过期', tasks: byKey[k]!, alert: true),
          'later' => TaskSection(id: k, title: '以后', tasks: byKey[k]!),
          'none' => TaskSection(id: k, title: '无日期', tasks: byKey[k]!),
          _ => TaskSection(
              id: 'day-$k', title: daySectionTitle(parseDateKey(k), today), tasks: byKey[k]!),
        });
      }
    case TagViewRef():
      open.sort(compareByDue);
      final byList = <String, List<Task>>{};
      for (final t in open) {
        byList.putIfAbsent(t.listId, () => []).add(t);
      }
      for (final e in byList.entries) {
        sections.add(TaskSection(
            id: 'list-${e.key}', title: listName(e.key, lists), tasks: e.value));
      }
    default:
      final listSections = sectionsByList[arrangedListId(view)] ?? const <ListSection>[];
      for (final g in listGroups(open, listSections)) {
        // A list without sections has no headers, and nothing at all when
        // it's empty (so the empty state shows).
        if (listSections.isEmpty && g.tasks.isEmpty) continue;
        sections.add(TaskSection(
          id: g.section == null ? 'section-none' : 'section-${g.section!.id}',
          title: listSections.isEmpty ? null : g.title,
          tasks: g.tasks,
          arrangeable: true,
          listSection: g.section,
        ));
      }
  }
  if (doneSection != null) sections.add(doneSection);
  return sections;
}
