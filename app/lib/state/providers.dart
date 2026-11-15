import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show AppLifecycleListener;

import '../data/db.dart';
import '../data/keys.dart';
import '../data/repo.dart';
import '../domain/filters.dart';
import '../domain/views.dart';
import 'settings_providers.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final repoProvider = Provider<TaskRepo>((ref) => TaskRepo(
      ref.watch(databaseProvider),
      defaults: () => ref.read(settingsProvider).defaults,
    ));

final listsProvider = StreamProvider<List<TaskList>>(
    (ref) => ref.watch(repoProvider).watchLists());

final listsByIdProvider = Provider<Map<String, TaskList>>((ref) {
  final lists = ref.watch(listsProvider).value ?? const [];
  return {for (final l in lists) l.id: l};
});

final tasksProvider =
    StreamProvider<List<Task>>((ref) => ref.watch(repoProvider).watchTasks());

final checklistProvider = StreamProvider.family<List<ChecklistItem>, String>(
    (ref, taskId) => ref.watch(repoProvider).watchChecklist(taskId));

final listSectionsProvider = StreamProvider<List<ListSection>>(
    (ref) => ref.watch(repoProvider).watchSections());

/// Each list's sections (分组), in order, by list id.
final sectionsByListProvider = Provider<Map<String, List<ListSection>>>((ref) {
  final out = <String, List<ListSection>>{};
  for (final s in ref.watch(listSectionsProvider).value ?? const <ListSection>[]) {
    out.putIfAbsent(s.listId, () => []).add(s);
  }
  return out;
});

/// How a list is laid out on this device. A version that doesn't know a
/// layout shows the list.
enum ListLayout { list, board, timeline }

/// The key a view's [ViewPrefs] are kept under: a list's id (the inbox's
/// too), or the view's name for the rest.
String viewPrefsKey(ViewRef view) => arrangedListId(view) ?? view.toString();

/// How a view shows on this device: a list as a list, a board or a
/// timeline, and how
/// the open tasks are grouped and ordered. A phone may want the list where
/// the computer shows the board.
class ViewPrefs {
  const ViewPrefs({this.layout = ListLayout.list, this.sort, this.grouping});

  final ListLayout layout;

  /// Null: the view's default.
  final TaskSort? sort;
  final TaskGrouping? grouping;

  bool get isDefault => layout == ListLayout.list && sort == null && grouping == null;

  /// The order [view] uses: [sort] if it offers it, else its default.
  TaskSort? sortIn(ViewRef view) {
    final sorts = sortsFor(view);
    return sorts.contains(sort) ? sort : sorts.firstOrNull;
  }

  /// The grouping [view] uses: [grouping] if it offers it, else its
  /// default.
  TaskGrouping? groupingIn(ViewRef view) {
    final groupings = groupingsFor(view);
    return groupings.contains(grouping) ? grouping : groupings.firstOrNull;
  }

  Map<String, String> toJson() => {
        'layout': layout.name,
        if (sort != null) 'sort': sort!.name,
        if (grouping != null) 'group': grouping!.name,
      };

  /// Also reads the bare layout name the first version stored.
  factory ViewPrefs.fromJson(Object? json) {
    T? byName<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;
    if (json is String) return ViewPrefs(layout: byName(ListLayout.values, json) ?? ListLayout.list);
    if (json is! Map) return const ViewPrefs();
    return ViewPrefs(
      layout: byName(ListLayout.values, json['layout']) ?? ListLayout.list,
      sort: byName(TaskSort.values, json['sort']),
      grouping: byName(TaskGrouping.values, json['group']),
    );
  }
}

/// [ViewPrefs] by [viewPrefsKey]; kept on this device, not synced.
class ViewPrefsNotifier extends Notifier<Map<String, ViewPrefs>> {
  bool _changed = false;

  @override
  Map<String, ViewPrefs> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final raw = await ref.read(databaseProvider).getValue(Keys.listPrefs);
    if (raw == null || _changed || !ref.mounted) return;
    try {
      state = {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: ViewPrefs.fromJson(e.value),
      };
    } on Object {
      // Damaged: every view as it is out of the box.
    }
  }

  ViewPrefs of(ViewRef view) => state[viewPrefsKey(view)] ?? const ViewPrefs();

  void setLayout(ViewRef view, ListLayout layout) {
    final p = of(view);
    _set(view, ViewPrefs(layout: layout, sort: p.sort, grouping: p.grouping));
  }

  /// The view's default is stored as no choice, so a later change of
  /// default reaches it.
  void setSort(ViewRef view, TaskSort sort) {
    final p = of(view);
    _set(view, ViewPrefs(layout: p.layout, sort: sort == sortsFor(view).firstOrNull ? null : sort, grouping: p.grouping));
  }

  void setGrouping(ViewRef view, TaskGrouping grouping) {
    final p = of(view);
    _set(view, ViewPrefs(
      layout: p.layout,
      sort: p.sort,
      grouping: grouping == groupingsFor(view).firstOrNull ? null : grouping,
    ));
  }

  void _set(ViewRef view, ViewPrefs prefs) {
    _changed = true;
    state = {...state, viewPrefsKey(view): prefs}..removeWhere((_, p) => p.isDefault);
    ref.read(databaseProvider).setValue(
        Keys.listPrefs, jsonEncode({for (final e in state.entries) e.key: e.value.toJson()}));
  }
}

final viewPrefsProvider =
    NotifierProvider<ViewPrefsNotifier, Map<String, ViewPrefs>>(ViewPrefsNotifier.new);

/// The current view's [ViewPrefs].
final currentViewPrefsProvider = Provider<ViewPrefs>((ref) =>
    ref.watch(viewPrefsProvider)[viewPrefsKey(ref.watch(selectedViewProvider))] ?? const ViewPrefs());

final filtersProvider = StreamProvider<List<TaskFilter>>(
    (ref) => ref.watch(repoProvider).watchFilters());

final filtersByIdProvider = Provider<Map<String, TaskFilter>>((ref) {
  final filters = ref.watch(filtersProvider).value ?? const [];
  return {for (final f in filters) f.id: f};
});

/// Each saved filter's rule, read from its JSON.
final filterRulesProvider = Provider<Map<String, FilterRule>>((ref) => {
      for (final f in ref.watch(filtersProvider).value ?? const <TaskFilter>[])
        f.id: FilterRule.parse(f.rule),
    });

/// Every subtask by task id; only watched while searching.
final allChecklistProvider =
    StreamProvider.autoDispose<Map<String, List<ChecklistItem>>>((ref) => ref
        .watch(repoProvider)
        .watchAllChecklistItems()
        .map((items) {
          final byTask = <String, List<ChecklistItem>>{};
          for (final i in items) {
            byTask.putIfAbsent(i.taskId, () => []).add(i);
          }
          return byTask;
        }));

/// Every tag used by a task that isn't trashed, sorted.
final tagsProvider = Provider<List<String>>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  final tags = <String>{
    for (final t in tasks)
      if (t.trashedAt == null) ...t.tags,
  };
  return tags.toList()..sort();
});

/// The current time, refreshed on every turn of the minute (so a task turns
/// overdue the moment its reminder goes off, and 今天 rolls over at
/// midnight) and when the app comes back to the foreground.
class Clock extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    _scheduleTick();
    final lifecycle = AppLifecycleListener(onResume: () => state = DateTime.now());
    ref.onDispose(() {
      _timer?.cancel();
      lifecycle.dispose();
    });
    return DateTime.now();
  }

  void _scheduleTick() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    // A little past the minute, so a timer firing early still lands in it.
    _timer = Timer(next.difference(now) + const Duration(milliseconds: 50), () {
      state = DateTime.now();
      _scheduleTick();
    });
  }
}

final clockProvider = NotifierProvider<Clock, DateTime>(Clock.new);

/// The part of the app on screen: tasks (lists) or the calendar.
enum AppModule { tasks, calendar }

class CurrentModule extends Notifier<AppModule> {
  @override
  AppModule build() => AppModule.tasks;

  void select(AppModule module) => state = module;
}

final moduleProvider = NotifierProvider<CurrentModule, AppModule>(CurrentModule.new);

class SelectedView extends Notifier<ViewRef> {
  @override
  ViewRef build() => const SmartViewRef(SmartKind.today);

  void select(ViewRef view) => state = view;
}

final selectedViewProvider =
    NotifierProvider<SelectedView, ViewRef>(SelectedView.new);

class SelectedTask extends Notifier<String?> {
  @override
  String? build() {
    // Changing views or modules clears the selection.
    ref.watch(selectedViewProvider);
    ref.watch(moduleProvider);
    return null;
  }

  void select(String? id) => state = id;
}

final selectedTaskProvider =
    NotifierProvider<SelectedTask, String?>(SelectedTask.new);

final taskByIdProvider = Provider.family<Task?, String>((ref, id) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  for (final t in tasks) {
    if (t.id == id) return t;
  }
  return null;
});

final sectionsProvider = Provider<List<TaskSection>>((ref) {
  return buildSections(
    view: ref.watch(selectedViewProvider),
    tasks: ref.watch(tasksProvider).value ?? const [],
    lists: ref.watch(listsByIdProvider),
    now: ref.watch(clockProvider),
    filters: ref.watch(filterRulesProvider),
    sectionsByList: ref.watch(sectionsByListProvider),
    grouping: ref.watch(currentViewPrefsProvider).grouping,
    sort: ref.watch(currentViewPrefsProvider).sort,
  );
});
