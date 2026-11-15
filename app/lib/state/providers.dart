import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show AppLifecycleListener;

import '../data/db.dart';
import '../data/repo.dart';
import '../domain/views.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final repoProvider = Provider<TaskRepo>((ref) => TaskRepo(ref.watch(databaseProvider)));

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
    // Changing views clears the selection.
    ref.watch(selectedViewProvider);
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
  );
});
