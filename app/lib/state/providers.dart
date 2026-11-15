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

/// How a list is laid out on this device.
enum ListLayout { list, board }

/// How a list shows on this device: as a list or a board, and in which
/// order. A phone may want the list where the computer shows the board.
class ListPrefs {
  const ListPrefs({this.layout = ListLayout.list, this.sort = ListSort.manual});

  final ListLayout layout;
  final ListSort sort;

  bool get isDefault => layout == ListLayout.list && sort == ListSort.manual;

  ListPrefs copyWith({ListLayout? layout, ListSort? sort}) =>
      ListPrefs(layout: layout ?? this.layout, sort: sort ?? this.sort);

  Map<String, String> toJson() => {'layout': layout.name, 'sort': sort.name};

  /// Also reads the bare layout name the first version stored.
  factory ListPrefs.fromJson(Object? json) {
    T? byName<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;
    if (json is String) return ListPrefs(layout: byName(ListLayout.values, json) ?? ListLayout.list);
    if (json is! Map) return const ListPrefs();
    return ListPrefs(
      layout: byName(ListLayout.values, json['layout']) ?? ListLayout.list,
      sort: byName(ListSort.values, json['sort']) ?? ListSort.manual,
    );
  }
}

/// [ListPrefs] per list (the inbox too), by list id; kept on this device,
/// not synced.
class ListPrefsNotifier extends Notifier<Map<String, ListPrefs>> {
  bool _changed = false;

  @override
  Map<String, ListPrefs> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final raw = await ref.read(databaseProvider).getValue(Keys.listPrefs);
    if (raw == null || _changed || !ref.mounted) return;
    try {
      state = {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: ListPrefs.fromJson(e.value),
      };
    } on Object {
      // Damaged: every list as a list, in manual order.
    }
  }

  ListPrefs of(String listId) => state[listId] ?? const ListPrefs();

  void setLayout(String listId, ListLayout layout) => _set(listId, of(listId).copyWith(layout: layout));

  void setSort(String listId, ListSort sort) => _set(listId, of(listId).copyWith(sort: sort));

  void _set(String listId, ListPrefs prefs) {
    _changed = true;
    state = {...state, listId: prefs}..removeWhere((_, p) => p.isDefault);
    ref.read(databaseProvider).setValue(
        Keys.listPrefs, jsonEncode({for (final e in state.entries) e.key: e.value.toJson()}));
  }
}

final listPrefsProvider =
    NotifierProvider<ListPrefsNotifier, Map<String, ListPrefs>>(ListPrefsNotifier.new);

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
    listSorts: {for (final e in ref.watch(listPrefsProvider).entries) e.key: e.value.sort},
  );
});
