import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';

import '../domain/views.dart';
import '../state/calendar_providers.dart';
import '../state/providers.dart';
import '../state/reminder_providers.dart';
import '../state/selection.dart';
import 'batch_actions.dart';
import 'calendar/calendar_screen.dart';
import 'quick_add_field.dart';
import 'search_panel.dart';
import 'settings_page.dart';
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
    revealTask(ref, Navigator.of(context), task,
        wide: MediaQuery.sizeOf(context).width >= Breakpoints.threePane);
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
    final picking = ref.watch(taskSelectionProvider).active;
    return LayoutBuilder(builder: (context, constraints) {
      final layout = ShellLayout.of(constraints.maxWidth);
      if (layout != ShellLayout.phone) {
        final Widget body = switch (module) {
          AppModule.calendar => CalendarScreen(layout: layout),
          // A board or a timeline wants the width: the detail shows only
          // for a selected task, beside it.
          AppModule.tasks when layout == ShellLayout.wide && _wantsWidth(ref) => Row(children: [
              const SizedBox(width: 248, child: Sidebar()),
              const VerticalDivider(width: 1),
              Expanded(
                child: TaskListPane(
                  onOpenTask: (id) => ref.read(selectedTaskProvider.notifier).select(id),
                ),
              ),
              if (picking) ...[
                const VerticalDivider(width: 1),
                const SizedBox(width: 400, child: BatchPanel()),
              ] else if (ref.watch(selectedTaskProvider) != null) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 400,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 4, 0),
                      child: IconButton(
                        tooltip: '关闭详情',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => ref.read(selectedTaskProvider.notifier).select(null),
                      ),
                    ),
                    const Expanded(child: TaskDetailPane()),
                  ]),
                ),
              ],
            ]),
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
              Expanded(flex: 4, child: picking ? const BatchPanel() : const TaskDetailPane()),
            ]),
          AppModule.tasks => Row(children: [
              const SizedBox(width: 220, child: Sidebar()),
              const VerticalDivider(width: 1),
              Expanded(
                child: TaskListPane(
                  showBatchBar: true,
                  onOpenTask: (id) => _openTaskPage(context, ref, id),
                ),
              ),
            ]),
        };
        return _SearchShortcut(
          child: Scaffold(
            body: Row(children: [
              const _ModuleRail(),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ]),
          ),
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
                  showBatchBar: true,
                  onOpenTask: (id) => _openTaskPage(context, ref, id),
                ),
        ),
        // While picking tasks, the bar at the bottom has the room.
        floatingActionButton: picking
            ? null
            : FloatingActionButton(
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

/// Whether the list on screen is a board or a timeline.
bool _wantsWidth(WidgetRef ref) {
  final listId = arrangedListId(ref.watch(selectedViewProvider));
  return listId != null && (ref.watch(viewPrefsProvider)[listId]?.layout ?? ListLayout.list) != ListLayout.list;
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: IconButton(
              tooltip: '搜索（${_searchKeyLabel()}）',
              icon: const Icon(Icons.search),
              color: scheme.onSurfaceVariant,
              onPressed: () => openSearch(context),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            color: scheme.onSurfaceVariant,
            onPressed: () => showSettings(context),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}

String _searchKeyLabel() => usesCommandKey ? '⌘F' : 'Ctrl+F';

/// Keys for the whole main screen on a computer, but not over a dialog or
/// another page: ⌘F (Ctrl+F elsewhere) opens search, even while typing in
/// a field; ⌘A picks every task in the view (or on the calendar's page)
/// when not typing; Esc stops picking.
class _SearchShortcut extends ConsumerStatefulWidget {
  const _SearchShortcut({required this.child});
  final Widget child;

  @override
  ConsumerState<_SearchShortcut> createState() => _SearchShortcutState();
}

class _SearchShortcutState extends ConsumerState<_SearchShortcut> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    final keyboard = HardwareKeyboard.instance;
    final modifier = usesCommandKey ? keyboard.isMetaPressed : keyboard.isControlPressed;
    final plain = !keyboard.isShiftPressed && !keyboard.isAltPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyF && modifier && plain) {
      openSearch(context);
      return true;
    }
    final selection = ref.read(taskSelectionProvider.notifier);
    if (key == LogicalKeyboardKey.escape && ref.read(taskSelectionProvider).active) {
      selection.clear();
      return true;
    }
    if (key == LogicalKeyboardKey.keyA && modifier && plain && !_typing) {
      switch (ref.read(moduleProvider)) {
        case AppModule.calendar:
          selection.selectAll(ref.read(calendarOrderProvider));
          return true;
        case AppModule.tasks when ref.read(selectedViewProvider) != const SmartViewRef(SmartKind.trash):
          selection.selectAll([
            for (final s in ref.read(sectionsProvider)) for (final t in s.tasks) t.id,
          ]);
          return true;
        case AppModule.tasks:
      }
    }
    return false;
  }

  /// Whether a text field has the keyboard (⌘A selects its text then).
  bool get _typing =>
      FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;

  @override
  Widget build(BuildContext context) => widget.child;
}
