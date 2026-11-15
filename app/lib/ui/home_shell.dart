import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';

import '../domain/views.dart';
import '../state/providers.dart';
import '../state/reminder_providers.dart';
import 'quick_add_field.dart';
import 'sidebar.dart';
import 'task_detail.dart';
import 'task_list_pane.dart';
import 'theme.dart';

/// Three panes on a wide window (lists, tasks, detail), two on a medium one
/// (the detail opens as a page), and one on a phone with the lists in a drawer.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  void _openTaskPage(BuildContext context, WidgetRef ref, String id) {
    ref.read(selectedTaskProvider.notifier).select(id);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TaskDetailPage(taskId: id),
    ));
  }

  /// Shows a task the person opened from a notification: switches to a view
  /// that lists it, selects it, and on a narrow window opens its page.
  void _openRequested(BuildContext context, WidgetRef ref, String id, List<Task> tasks) {
    // Several frames may have queued this; only the first acts.
    if (!context.mounted || ref.read(openTaskRequestProvider) != id) return;
    ref.read(openTaskRequestProvider.notifier).clear();
    final task = tasks.where((t) => t.id == id).firstOrNull;
    if (task == null || !context.mounted) return;
    final view = viewForTask(task, ref.read(selectedViewProvider), DateTime.now());
    ref.read(selectedViewProvider.notifier).select(view);
    if (MediaQuery.sizeOf(context).width >= Breakpoints.threePane) {
      ref.read(selectedTaskProvider.notifier).select(id);
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
      _openTaskPage(context, ref, id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requested = ref.watch(openTaskRequestProvider);
    if (requested != null) {
      // Launched from a notification, the tasks may still be loading.
      final tasks = ref.watch(tasksProvider).value;
      if (tasks != null) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _openRequested(context, ref, requested, tasks));
      }
    }
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width >= Breakpoints.threePane) {
        return Scaffold(
          body: Row(children: [
            const SizedBox(width: 248, child: Sidebar()),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 5,
              child: TaskListPane(
                onOpenTask: (id) => ref.read(selectedTaskProvider.notifier).select(id),
              ),
            ),
            const VerticalDivider(width: 1),
            const Expanded(flex: 4, child: TaskDetailPane()),
          ]),
        );
      }
      if (width >= Breakpoints.twoPane) {
        return Scaffold(
          body: Row(children: [
            const SizedBox(width: 220, child: Sidebar()),
            const VerticalDivider(width: 1),
            Expanded(
              child: TaskListPane(onOpenTask: (id) => _openTaskPage(context, ref, id)),
            ),
          ]),
        );
      }
      return Scaffold(
        drawer: Drawer(
          child: SafeArea(
            child: Builder(
              builder: (drawerContext) =>
                  Sidebar(onSelected: () => Navigator.of(drawerContext).pop()),
            ),
          ),
        ),
        body: SafeArea(
          child: TaskListPane(
            showMenuButton: true,
            showInlineQuickAdd: false,
            onOpenTask: (id) => _openTaskPage(context, ref, id),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: '添加任务',
          onPressed: () => showQuickAddSheet(context),
          child: const Icon(Icons.add),
        ),
      );
    });
  }
}
