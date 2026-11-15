/// What the middle pane shows: a smart list, a list of the person's own, or a
/// tag, and how its tasks are grouped into sections.
library;

import '../data/db.dart';
import 'dates.dart';

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

class TaskSection {
  const TaskSection({
    required this.id,
    required this.title,
    required this.tasks,
    this.collapsedByDefault = false,
  });

  final String id;

  /// Null for a list without headers.
  final String? title;
  final List<Task> tasks;
  final bool collapsedByDefault;
}

bool isOpen(Task t) => t.status == TaskStatus.open && t.trashedAt == null;
bool isDone(Task t) => t.status != TaskStatus.open && t.trashedAt == null;

String listName(String listId, Map<String, TaskList> lists) =>
    listId == inboxListId ? '收集箱' : (lists[listId]?.name ?? '收集箱');

String viewTitle(ViewRef view, Map<String, TaskList> lists) => switch (view) {
      SmartViewRef(kind: SmartKind.today) => '今天',
      SmartViewRef(kind: SmartKind.tomorrow) => '明天',
      SmartViewRef(kind: SmartKind.next7) => '最近7天',
      SmartViewRef(kind: SmartKind.inbox) => '收集箱',
      SmartViewRef(kind: SmartKind.completed) => '已完成',
      SmartViewRef(kind: SmartKind.trash) => '垃圾桶',
      ListViewRef(:final listId) => listName(listId, lists),
      TagViewRef(:final tag) => '#$tag',
    };

/// Where a task typed into this view's quick-add field goes.
({String listId, DateTime? date, List<String> tags}) quickAddDefaults(
    ViewRef view, DateTime today) {
  return switch (view) {
    SmartViewRef(kind: SmartKind.today || SmartKind.next7) => (
        listId: inboxListId,
        date: today,
        tags: const <String>[],
      ),
    SmartViewRef(kind: SmartKind.tomorrow) => (
        listId: inboxListId,
        date: addDays(today, 1),
        tags: const <String>[],
      ),
    ListViewRef(:final listId) => (
        listId: listId,
        date: null,
        tags: const <String>[],
      ),
    TagViewRef(:final tag) => (listId: inboxListId, date: null, tags: [tag]),
    _ => (listId: inboxListId, date: null, tags: const <String>[]),
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

bool matchesView(Task t, ViewRef view, String todayKey, String tomorrowKey,
    String weekEndKey) {
  if (t.trashedAt != null) {
    return view == const SmartViewRef(SmartKind.trash);
  }
  return switch (view) {
    SmartViewRef(kind: SmartKind.today) =>
      t.dueDate != null && t.dueDate!.compareTo(todayKey) <= 0,
    SmartViewRef(kind: SmartKind.tomorrow) => t.dueDate == tomorrowKey,
    SmartViewRef(kind: SmartKind.next7) =>
      t.dueDate != null && t.dueDate!.compareTo(weekEndKey) <= 0,
    SmartViewRef(kind: SmartKind.inbox) => t.listId == inboxListId,
    SmartViewRef(kind: SmartKind.completed) => isDone(t),
    SmartViewRef(kind: SmartKind.trash) => false,
    ListViewRef(:final listId) => t.listId == listId,
    TagViewRef(:final tag) => t.tags.contains(tag),
  };
}

/// Where to show a task opened from elsewhere, such as a notification: the
/// current view if it lists the task, else 今天 for one due by today, else
/// its list.
ViewRef viewForTask(Task t, ViewRef current, DateTime now) {
  final today = dateOnly(now);
  final todayKey = dateKey(today);
  if (matchesView(t, current, todayKey, dateKey(addDays(today, 1)),
      dateKey(addDays(today, 6)))) {
    return current;
  }
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
int openCount(ViewRef view, List<Task> tasks, DateTime now) {
  final today = dateOnly(now);
  final keys = (
    dateKey(today),
    dateKey(addDays(today, 1)),
    dateKey(addDays(today, 6)),
  );
  return tasks
      .where((t) =>
          isOpen(t) && matchesView(t, view, keys.$1, keys.$2, keys.$3))
      .length;
}

List<TaskSection> buildSections({
  required ViewRef view,
  required List<Task> tasks,
  required Map<String, TaskList> lists,
  required DateTime now,
}) {
  final today = dateOnly(now);
  final todayKey = dateKey(today);
  final tomorrowKey = dateKey(addDays(today, 1));
  final weekEndKey = dateKey(addDays(today, 6));
  final inView = tasks
      .where((t) => matchesView(t, view, todayKey, tomorrowKey, weekEndKey))
      .toList();

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
          isDone(t) && (!isDateView || t.dueDate!.compareTo(todayKey) >= 0))
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
      final overdue = open.where((t) => t.dueDate!.compareTo(todayKey) < 0);
      if (overdue.isNotEmpty) {
        sections.add(TaskSection(id: 'overdue', title: '已过期', tasks: overdue.toList()));
      }
      final byDay = <String, List<Task>>{};
      for (final t in open.where((t) => t.dueDate!.compareTo(todayKey) >= 0)) {
        byDay.putIfAbsent(t.dueDate!, () => []).add(t);
      }
      for (final e in byDay.entries) {
        sections.add(TaskSection(
          id: 'day-${e.key}',
          title: daySectionTitle(parseDateKey(e.key), today),
          tasks: e.value,
        ));
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
      open.sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });
      if (open.isNotEmpty) {
        sections.add(TaskSection(id: 'open', title: null, tasks: open));
      }
  }
  if (doneSection != null) sections.add(doneSection);
  return sections;
}
