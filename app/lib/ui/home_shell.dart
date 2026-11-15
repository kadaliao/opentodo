import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';

import '../domain/views.dart';
import '../state/calendar_providers.dart';
import '../state/providers.dart';
import '../state/reminder_providers.dart';
import 'calendar/calendar_screen.dart';
import 'quick_add_field.dart';
import 'sidebar.dart';
import 'task_detail.dart';
import 'task_list_pane.dart';
import 'theme.dart';

/// The modules down the side of a computer window and along the bottom of a
/// phone.
const _modules = [
  (AppModule.tasks, Icons.check_box_outlined, Icons.check_box, '任务'),
  (AppModule.calendar, Icons.calendar_month_outlined, Icons.calendar_month, '日历'),
];

/// A rail of modules on the left. In the tasks module: three panes on a
/// wide window (lists, tasks, detail), two on a medium one (the detail opens
/// as a page), and one on a phone with the lists in a drawer and the modules
/// in a bottom bar.
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
    ref.read(moduleProvider.notifier).select(AppModule.tasks);
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
    final module = ref.watch(moduleProvider);
    return LayoutBuilder(builder: (context, constraints) {
      final layout = ShellLayout.of(constraints.maxWidth);
      if (layout != ShellLayout.phone) {
        final Widget body = switch (module) {
          AppModule.calendar => CalendarScreen(layout: layout),
          AppModule.tasks when layout == ShellLayout.wide => Row(children: [
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
          AppModule.tasks => Row(children: [
              const SizedBox(width: 220, child: Sidebar()),
              const VerticalDivider(width: 1),
              Expanded(
                child: TaskListPane(onOpenTask: (id) => _openTaskPage(context, ref, id)),
              ),
            ]),
        };
        return Scaffold(
          body: Row(children: [
            const _ModuleRail(),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ]),
        );
      }
      final calendar = module == AppModule.calendar;
      return Scaffold(
        drawer: calendar
            ? null
            : Drawer(
                child: SafeArea(
                  child: Builder(
                    builder: (drawerContext) =>
                        Sidebar(onSelected: () => Navigator.of(drawerContext).pop()),
                  ),
                ),
              ),
        body: SafeArea(
          bottom: false,
          child: calendar
              ? const CalendarScreen(layout: ShellLayout.phone)
              : TaskListPane(
                  showMenuButton: true,
                  showInlineQuickAdd: false,
                  onOpenTask: (id) => _openTaskPage(context, ref, id),
                ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: '添加任务',
          onPressed: () => calendar
              ? showNewTaskDialog(context, date: ref.read(calendarAnchorProvider), sheet: true)
              : showQuickAddSheet(context),
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: NavigationBar(
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: _modules.indexWhere((m) => m.$1 == module),
          onDestinationSelected: (i) => ref.read(moduleProvider.notifier).select(_modules[i].$1),
          destinations: [
            for (final (_, icon, selectedIcon, label) in _modules)
              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: label),
          ],
        ),
      );
    });
  }
}

/// The modules as icons down the left edge of a computer window.
class _ModuleRail extends ConsumerWidget {
  const _ModuleRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final module = ref.watch(moduleProvider);
    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        width: 56,
        child: Column(children: [
          const SizedBox(height: 12),
          for (final (m, icon, selectedIcon, label) in _modules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: IconButton(
                tooltip: label,
                isSelected: m == module,
                icon: Icon(icon),
                selectedIcon: Icon(selectedIcon),
                style: IconButton.styleFrom(
                  foregroundColor: m == module ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                  backgroundColor: m == module ? scheme.secondaryContainer : null,
                ),
                onPressed: () => ref.read(moduleProvider.notifier).select(m),
              ),
            ),
        ]),
      ),
    );
  }
}
