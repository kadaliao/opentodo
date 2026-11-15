/// What the middle pane shows: a smart list, a list of the person's own, a
/// tag or a saved filter, and how its tasks are grouped into sections.
library;

import '../data/db.dart';
import 'dates.dart';
import 'filters.dart';
import 'pinyin.dart';

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
    this.target,
    this.manualOrder = false,
    this.listSection,
    this.finished = false,
  });

  final String id;

  /// Null for a list without headers.
  final String? title;
  final List<Task> tasks;
  final bool collapsedByDefault;

  /// Shown in the warning colour (已过期).
  final bool alert;

  /// What the section's open tasks have in common, which a task dragged
  /// into it takes on; null when nothing can be dropped in it (已过期,
  /// 以后, 已完成).
  final GroupTarget? target;

  /// The list is in manual order (自定义), so where a task is dropped
  /// counts.
  final bool manualOrder;

  /// The list's section (分组) this is; null for 未分组 and for sections
  /// that aren't a list's.
  final ListSection? listSection;

  /// Finished (or trashed) tasks, which don't move.
  final bool finished;

  /// The day a task dropped here moves to, if this is a day's section.
  DateTime? get day => switch (target) {
        DateTarget(:final day) => day,
        _ => null,
      };
}

/// What the open tasks of a section have in common, which a task dragged
/// into the section takes on.
sealed class GroupTarget {
  const GroupTarget();

  /// Whether [t] has it already.
  bool has(Task t);

  /// Whether [t] can be dropped here at all.
  bool takes(Task t) => true;
}

/// A section (分组) of the list [listId]; [sectionId] null is 未分组.
final class SectionTarget extends GroupTarget {
  const SectionTarget(this.listId, this.sectionId);

  final String listId;
  final String? sectionId;

  @override
  bool has(Task t) => t.listId == listId && t.sectionId == sectionId;

  @override
  bool takes(Task t) => t.listId == listId;
}

/// A day, each task keeping its time; [day] null is 无日期.
final class DateTarget extends GroupTarget {
  const DateTarget(this.day);

  final DateTime? day;

  @override
  bool has(Task t) => t.dueDate == (day == null ? null : dateKey(day!));
}

final class PriorityTarget extends GroupTarget {
  const PriorityTarget(this.priority);

  final int priority;

  @override
  bool has(Task t) => t.priority == priority;
}

final class ListTarget extends GroupTarget {
  const ListTarget(this.listId);

  final String listId;

  @override
  bool has(Task t) => t.listId == listId;
}

/// The tasks filed under [tag], their first one; [tag] null is 无标签.
final class TagTarget extends GroupTarget {
  const TagTarget(this.tag);

  final String? tag;

  @override
  bool has(Task t) => t.tags.firstOrNull == tag;

  /// A task's [tags] once it's moved here: [tag] in place of the one it was
  /// filed under, or none at all for 无标签.
  List<String> retag(List<String> tags) =>
      tag == null ? const [] : [tag!, ...tags.skip(1).where((x) => x != tag)];
}

/// A list shown without groups, in its own order: only where a task lands
/// counts.
final class OrderTarget extends GroupTarget {
  const OrderTarget();

  @override
  bool has(Task t) => true;
}

/// How a view groups its open tasks (分组).
enum TaskGrouping {
  /// The list's own sections.
  sections('自定义'),
  date('时间'),
  list('清单'),
  tag('标签'),
  priority('优先级'),
  none('无');

  const TaskGrouping(this.label);
  final String label;
}

/// The groupings [view] offers, its default first; none for 已完成 and
/// 垃圾桶, which always go by day.
List<TaskGrouping> groupingsFor(ViewRef view) => switch (view) {
      ListViewRef() || SmartViewRef(kind: SmartKind.inbox) => const [
          TaskGrouping.sections,
          TaskGrouping.date,
          TaskGrouping.tag,
          TaskGrouping.priority,
          TaskGrouping.none,
        ],
      SmartViewRef(kind: SmartKind.today || SmartKind.tomorrow || SmartKind.next7) ||
      FilterViewRef() =>
        const [
          TaskGrouping.date,
          TaskGrouping.list,
          TaskGrouping.tag,
          TaskGrouping.priority,
          TaskGrouping.none,
        ],
      TagViewRef() => const [
          TaskGrouping.list,
          TaskGrouping.date,
          TaskGrouping.priority,
          TaskGrouping.none,
        ],
      _ => const [],
    };

/// The orders [view] offers, its default first. Only a list (the inbox
/// too) can be ordered by hand.
List<TaskSort> sortsFor(ViewRef view) => arrangedListId(view) != null
    ? TaskSort.values
    : groupingsFor(view).isEmpty
        ? const []
        : const [TaskSort.due, TaskSort.title, TaskSort.tag, TaskSort.priority];

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

/// Pinned (置顶) tasks before the rest, each part in [compare]'s order.
Comparator<Task> pinnedFirst(Comparator<Task> compare) => (a, b) {
      final ap = a.pinnedAt != null, bp = b.pinnedAt != null;
      if (ap != bp) return ap ? -1 : 1;
      return compare(a, b);
    };

/// How a view orders the tasks in each of its groups (排序).
enum TaskSort {
  manual('自定义'),
  due('时间'),
  title('标题'),
  tag('标签'),
  priority('优先级');

  const TaskSort(this.label);
  final String label;

  Comparator<Task> get compare => pinnedFirst(switch (this) {
        TaskSort.manual => compareByOrder,
        TaskSort.due => compareByDue,
        TaskSort.title => compareByTitle,
        TaskSort.tag => compareByTag,
        TaskSort.priority => (a, b) =>
            a.priority != b.priority ? b.priority.compareTo(a.priority) : compareByDue(a, b),
      });
}

/// One section of a list and its tasks; [section] null is 未分组: tasks
/// without a section, or with one that isn't this list's (any more).
class ListGroup {
  const ListGroup(this.section, this.tasks);
  final ListSection? section;
  final List<Task> tasks;

  String get title => section?.name ?? '未分组';
}

/// The tasks of a list sorted into its [sections], each in [sort]'s order
/// (pinned ones first). 未分组 comes first, and only when it has tasks or
/// the list has no sections.
List<ListGroup> listGroups(List<Task> tasks, List<ListSection> sections,
    {TaskSort sort = TaskSort.manual}) {
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
    if (loose.isNotEmpty || ordered.isEmpty) ListGroup(null, loose..sort(sort.compare)),
    for (final s in ordered) ListGroup(s, byId[s.id]!..sort(sort.compare)),
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
    String listId, List<Task> tasks, List<ListSection> sections,
    {TaskSort sort = TaskSort.manual}) {
  final inList = tasks.where((t) => t.listId == listId && t.trashedAt == null).toList();
  final open = listGroups(inList.where(isOpen).toList(), sections, sort: sort);
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

/// A to Z in pinyin (Chinese and Latin together), untitled last; the same
/// title in manual order.
int compareByTitle(Task a, Task b) {
  final ae = a.title.trim().isEmpty, be = b.title.trim().isEmpty;
  if (ae != be) return ae ? 1 : -1;
  final c = comparePinyin(a.title.trim(), b.title.trim());
  return c != 0 ? c : compareByOrder(a, b);
}

/// By first tag, A to Z in pinyin, untagged last; then by date.
int compareByTag(Task a, Task b) {
  final at = a.tags.firstOrNull, bt = b.tags.firstOrNull;
  if (at != bt) {
    if (at == null) return 1;
    if (bt == null) return -1;
    final c = comparePinyin(at, bt);
    if (c != 0) return c;
  }
  return compareByDue(a, b);
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

/// The sections of [view]: its open tasks grouped by [grouping] and in
/// [sort]'s order within each group (the view's defaults when null or not
/// one it offers), then 已完成.
List<TaskSection> buildSections({
  required ViewRef view,
  required List<Task> tasks,
  required Map<String, TaskList> lists,
  required DateTime now,
  Map<String, FilterRule> filters = const {},
  Map<String, List<ListSection>> sectionsByList = const {},
  TaskGrouping? grouping,
  TaskSort? sort,
}) {
  final today = dateOnly(now);
  final todayKey = dateKey(today);
  final inView = tasks.where(viewMatcher(view, now, filters)).toList();

  if (view == const SmartViewRef(SmartKind.trash)) {
    inView.sort((a, b) => (b.trashedAt ?? 0).compareTo(a.trashedAt ?? 0));
    return [
      if (inView.isNotEmpty) TaskSection(id: 'trash', title: null, tasks: inView, finished: true),
    ];
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
          finished: true,
        ),
    ];
  }

  final isDateView = view is SmartViewRef &&
      (view.kind == SmartKind.today ||
          view.kind == SmartKind.tomorrow ||
          view.kind == SmartKind.next7);
  final groupings = groupingsFor(view);
  final groupBy = groupings.contains(grouping) ? grouping! : groupings.first;
  final sorts = sortsFor(view);
  final order = sorts.contains(sort) ? sort! : sorts.first;
  final manual = order == TaskSort.manual;
  final open = inView.where(isOpen).toList()..sort(order.compare);
  // A date view lists finished tasks from its own days, not every task
  // ever finished that was due in the past.
  final done = inView
      .where((t) =>
          isDone(t) && (!isDateView || lastDueKey(t).compareTo(todayKey) >= 0))
      .toList()
    ..sort(_compareCompleted);

  final sections = switch (groupBy) {
    TaskGrouping.sections => _bySection(
        open, arrangedListId(view)!, sectionsByList[arrangedListId(view)] ?? const [], order),
    TaskGrouping.date when isDateView =>
      _byViewDay(open, today, view == const SmartViewRef(SmartKind.next7) ? 7 : 1,
          firstKey: view == const SmartViewRef(SmartKind.tomorrow) ? dateKey(addDays(today, 1)) : todayKey),
    TaskGrouping.date => _byDate(open, today, manual),
    TaskGrouping.list => _byList(open, lists),
    TaskGrouping.tag => _byTag(open, manual),
    TaskGrouping.priority => _byPriority(open, manual),
    TaskGrouping.none => [
        if (open.isNotEmpty)
          TaskSection(
            id: 'all',
            title: null,
            tasks: open,
            target: manual ? const OrderTarget() : null,
            manualOrder: manual,
          ),
      ],
  };
  return [
    ...sections,
    if (done.isNotEmpty)
      TaskSection(
        id: 'done',
        title: '已完成',
        tasks: done,
        collapsedByDefault: view is! SmartViewRef,
        finished: true,
      ),
  ];
}

/// A list's own sections (分组).
List<TaskSection> _bySection(
    List<Task> open, String listId, List<ListSection> listSections, TaskSort order) {
  return [
    for (final g in listGroups(open, listSections, sort: order))
      // A list without sections has no headers, and nothing at all when
      // it's empty (so the empty state shows).
      if (listSections.isNotEmpty || g.tasks.isNotEmpty)
        TaskSection(
          id: g.section == null ? 'section-none' : 'section-${g.section!.id}',
          title: listSections.isEmpty ? null : g.title,
          tasks: g.tasks,
          target: SectionTarget(listId, g.section?.id),
          manualOrder: order == TaskSort.manual,
          listSection: g.section,
        ),
  ];
}

/// 今天 / 明天 / 最近7天 by day: 已过期, then each of the view's [days]
/// days from [firstKey].
List<TaskSection> _byViewDay(List<Task> open, DateTime today, int days, {required String firstKey}) {
  final todayKey = dateKey(today);
  final overdue = open.where((t) => lastDueKey(t).compareTo(todayKey) < 0).toList();
  // A span that began earlier shows once, on the view's first day.
  final byDay = <String, List<Task>>{};
  for (final t in open.where((t) => lastDueKey(t).compareTo(todayKey) >= 0)) {
    final key = t.dueDate!.compareTo(firstKey) < 0 ? firstKey : t.dueDate!;
    byDay.putIfAbsent(key, () => []).add(t);
  }
  // With an open task to drag, every day of the view is there, empty or
  // not, so it can be dropped onto it (out of 已过期, say).
  final keys = open.isEmpty
      ? byDay.keys
      : [for (var d = 0; d < days; d++) dateKey(addDays(parseDateKey(firstKey), d))];
  return [
    if (overdue.isNotEmpty) TaskSection(id: 'overdue', title: '已过期', tasks: overdue, alert: true),
    for (final key in keys)
      TaskSection(
        id: 'day-$key',
        title: daySectionTitle(parseDateKey(key), today),
        tasks: byDay[key] ?? const [],
        target: DateTarget(parseDateKey(key)),
      ),
  ];
}

/// By date: 已过期, each of the next seven days, 以后, 无日期.
List<TaskSection> _byDate(List<Task> open, DateTime today, bool manual) {
  final todayKey = dateKey(today);
  final weekEndKey = dateKey(addDays(today, 6));
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
  int rank(String k) => switch (k) { 'overdue' => 0, 'later' => 2, 'none' => 3, _ => 1 };
  final keys = byKey.keys.toList()
    ..sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final k in keys)
      switch (k) {
        'overdue' => TaskSection(id: k, title: '已过期', tasks: byKey[k]!, alert: true),
        'later' => TaskSection(id: k, title: '以后', tasks: byKey[k]!),
        'none' => TaskSection(
            id: k, title: '无日期', tasks: byKey[k]!, target: const DateTarget(null), manualOrder: manual),
        _ => TaskSection(
            id: 'day-$k',
            title: daySectionTitle(parseDateKey(k), today),
            tasks: byKey[k]!,
            target: DateTarget(parseDateKey(k)),
            manualOrder: manual,
          ),
      },
  ];
}

/// By list, in the sidebar's order (收集箱 first).
List<TaskSection> _byList(List<Task> open, Map<String, TaskList> lists) {
  final byList = <String, List<Task>>{};
  for (final t in open) {
    byList.putIfAbsent(t.listId, () => []).add(t);
  }
  // A list that's gone (deleted on another device, say) goes last.
  (int, double, int) rank(String id) => id == inboxListId
      ? (0, 0, 0)
      : lists[id] == null
          ? (2, 0, 0)
          : (1, lists[id]!.sortOrder, lists[id]!.createdAt);
  final ids = byList.keys.toList()
    ..sort((a, b) {
      final (ra, rb) = (rank(a), rank(b));
      var c = ra.$1.compareTo(rb.$1);
      if (c == 0) c = ra.$2.compareTo(rb.$2);
      return c != 0 ? c : ra.$3.compareTo(rb.$3);
    });
  return [
    for (final id in ids)
      TaskSection(
        id: 'list-$id',
        title: listName(id, lists),
        tasks: byList[id]!,
        target: id == inboxListId || lists[id] != null ? ListTarget(id) : null,
      ),
  ];
}

/// By each task's first tag, A to Z in pinyin, then 无标签.
List<TaskSection> _byTag(List<Task> open, bool manual) {
  final byTag = <String?, List<Task>>{};
  for (final t in open) {
    byTag.putIfAbsent(t.tags.firstOrNull, () => []).add(t);
  }
  final tags = byTag.keys.nonNulls.toList()..sort(comparePinyin);
  return [
    for (final tag in [...tags, if (byTag.containsKey(null)) null])
      TaskSection(
        id: 'tag-${tag ?? ''}',
        title: tag ?? '无标签',
        tasks: byTag[tag]!,
        target: TagTarget(tag),
        manualOrder: manual,
      ),
  ];
}

/// High priority first, 无优先级 last.
List<TaskSection> _byPriority(List<Task> open, bool manual) => [
      for (final p in const [Priority.high, Priority.medium, Priority.low, Priority.none])
        if (open.where((t) => t.priority == p).toList() case final tasks when tasks.isNotEmpty)
          TaskSection(
            id: 'priority-$p',
            title: priorityName(p),
            tasks: tasks,
            target: PriorityTarget(p),
            manualOrder: manual,
          ),
    ];

String priorityName(int priority) => switch (priority) {
      Priority.high => '高优先级',
      Priority.medium => '中优先级',
      Priority.low => '低优先级',
      _ => '无优先级',
    };
