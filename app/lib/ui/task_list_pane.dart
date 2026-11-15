import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/views.dart';
import '../state/providers.dart';
import 'board_view.dart';
import 'dialogs.dart';
import 'filter_editor.dart';
import 'quick_add_field.dart';
import 'search_panel.dart';
import 'section_actions.dart';
import 'task_drag.dart';
import 'task_tile.dart';

class TaskListPane extends ConsumerStatefulWidget {
  const TaskListPane({
    super.key,
    required this.onOpenTask,
    this.showMenuButton = false,
    this.showInlineQuickAdd = true,
  });

  final ValueChanged<String> onOpenTask;
  final bool showMenuButton;
  final bool showInlineQuickAdd;

  @override
  ConsumerState<TaskListPane> createState() => _TaskListPaneState();
}

class _TaskListPaneState extends ConsumerState<TaskListPane> {
  /// Sections the person opened or closed, keyed by view and section id.
  final _toggled = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final view = ref.watch(selectedViewProvider);
    final lists = ref.watch(listsByIdProvider);
    final filters = ref.watch(filtersByIdProvider);
    final loading = ref.watch(tasksProvider).isLoading;
    final sections = ref.watch(sectionsProvider);
    final showList = view is SmartViewRef || view is TagViewRef || view is FilterViewRef;
    final filter = view is FilterViewRef ? filters[view.filterId] : null;
    // Deleted on another device while on screen.
    if (view is FilterViewRef && filter == null && ref.watch(filtersProvider).hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(selectedViewProvider) == view) {
          ref.read(selectedViewProvider.notifier).select(const SmartViewRef(SmartKind.today));
        }
      });
    }
    final isTrash = view == const SmartViewRef(SmartKind.trash);
    final arrangedList = arrangedListId(view);
    final listPrefs = arrangedList == null ? null : ref.watch(listPrefsProvider)[arrangedList];
    final board = listPrefs?.layout == ListLayout.board;
    final touch = dragsOnLongPress(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Row(children: [
          if (widget.showMenuButton)
            IconButton(
              tooltip: '清单',
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              viewTitle(view, lists, filters),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (filter != null)
            IconButton(
              tooltip: '编辑过滤器',
              icon: const Icon(Icons.tune),
              onPressed: () => editFilter(context, ref, filter),
            ),
          if (widget.showMenuButton)
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => openSearch(context),
            ),
          if (arrangedList != null)
            _ListMenu(listId: arrangedList, prefs: listPrefs ?? const ListPrefs()),
          if (isTrash && sections.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('清空'),
              onPressed: () async {
                final ok = await confirm(context,
                    title: '清空垃圾桶？', message: '垃圾桶里的任务会被永久删除，无法恢复。', action: '清空');
                if (ok) await ref.read(repoProvider).emptyTrash();
              },
            ),
        ]),
      ),
      // The board has a field in each column.
      if (widget.showInlineQuickAdd && canQuickAdd(view) && !board)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: QuickAddField(),
        ),
      Expanded(
        child: loading
            ? const SizedBox.shrink()
            : board
                ? BoardView(listId: arrangedList!, onOpenTask: widget.onOpenTask)
                : sections.isEmpty
                ? _EmptyState(view: view)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                    children: [
                      for (final s in sections) ...() {
                        final TaskDropGroup? group = s.arrangeable && arrangedList != null
                            ? ArrangeGroup(
                                listId: arrangedList,
                                sectionId: s.listSection?.id,
                                tasks: s.tasks,
                                manual: s.manualOrder,
                              )
                            : s.day != null
                                ? DayDropGroup(s.day!)
                                : null;
                        // Open tasks can be dragged in lists and date views,
                        // also out of 已过期 (onto a day).
                        final draggable = group != null || s.id == 'overdue';
                        Widget header = _SectionHeader(
                          title: s.title ?? '',
                          alert: s.alert,
                          count: s.tasks.length,
                          collapsed: _isCollapsed(view, s),
                          onToggle: () => setState(() {
                            _toggled['$view/${s.id}'] = !_isCollapsed(view, s);
                          }),
                          menu: s.listSection == null ? null : SectionMenuButton(section: s.listSection!),
                        );
                        // Dropped on a header: first in that section.
                        if (group != null) header = TaskDropArea(group: group, index: 0, child: header);
                        return [
                          if (s.title != null) header,
                          if (!_isCollapsed(view, s))
                            for (final (i, t) in s.tasks.indexed)
                              () {
                                if (!draggable) {
                                  return TaskTile(
                                    key: ValueKey(t.id),
                                    task: t,
                                    showList: showList,
                                    onOpen: widget.onOpenTask,
                                  );
                                }
                                final Widget row = TaskDraggable(
                                  task: t,
                                  child: TaskTile(
                                    task: t,
                                    showList: showList,
                                    onOpen: widget.onOpenTask,
                                    longPressMenu: !touch,
                                  ),
                                );
                                return group == null
                                    ? KeyedSubtree(key: ValueKey(t.id), child: row)
                                    : TaskDropRow(key: ValueKey(t.id), group: group, index: i, child: row);
                              }(),
                        ];
                      }(),
                    ],
                  ),
      ),
      if (isTrash && sections.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('垃圾桶里的任务可以恢复；清空后无法找回。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ),
    ]);
  }

  bool _isCollapsed(ViewRef view, TaskSection s) =>
      _toggled['$view/${s.id}'] ?? s.collapsedByDefault;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.alert = false,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    this.menu,
  });

  final String title;
  final bool alert;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  /// A list section's ⋯ (rename, move, delete).
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 8, 4),
        child: Row(children: [
          AnimatedRotation(
            turns: collapsed ? -0.25 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: alert ? scheme.error : scheme.onSurface)),
          const SizedBox(width: 6),
          Text('$count', style: TextStyle(fontSize: 12, color: scheme.outline)),
          if (menu != null) ...[const Spacer(), SizedBox(height: 24, child: menu)],
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.view});
  final ViewRef view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, title, hint) = switch (view) {
      SmartViewRef(kind: SmartKind.today) => (Icons.wb_sunny_outlined, '今天没有任务', '享受这一天，或者在上面添加一个'),
      SmartViewRef(kind: SmartKind.completed) => (Icons.task_alt, '还没有完成的任务', '完成的任务会出现在这里'),
      SmartViewRef(kind: SmartKind.trash) => (Icons.delete_outline, '垃圾桶是空的', '删除的任务会在这里保留，可以恢复'),
      SmartViewRef(kind: SmartKind.inbox) => (Icons.inbox_outlined, '收集箱是空的', '想到什么先记在这里，之后再整理'),
      FilterViewRef() => (Icons.filter_alt_outlined, '没有符合条件的任务', '可以点右上角调整条件'),
      _ => (Icons.checklist, '没有任务', '在上面的输入框添加任务'),
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: scheme.outlineVariant),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(hint, style: TextStyle(fontSize: 12, color: scheme.outline)),
      ]),
    );
  }
}

/// The ⋯ of a list: show it as a list or a board, the order, add a
/// section.
class _ListMenu extends ConsumerWidget {
  const _ListMenu({required this.listId, required this.prefs});

  final String listId;
  final ListPrefs prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = prefs.layout == ListLayout.board;
    final prefsNotifier = ref.read(listPrefsProvider.notifier);
    void layout(ListLayout l) => prefsNotifier.setLayout(listId, l);
    const check = Icon(Icons.check, size: 18);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.view_list_outlined),
          trailingIcon: board ? null : check,
          onPressed: () => layout(ListLayout.list),
          child: const Text('列表'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.view_kanban_outlined),
          trailingIcon: board ? check : null,
          onPressed: () => layout(ListLayout.board),
          child: const Text('看板'),
        ),
        const Divider(height: 8),
        SubmenuButton(
          leadingIcon: const Icon(Icons.sort),
          menuChildren: [
            for (final sort in ListSort.values)
              MenuItemButton(
                trailingIcon: prefs.sort == sort ? check : null,
                onPressed: () => prefsNotifier.setSort(listId, sort),
                child: Text(sort == ListSort.manual ? '自定义（拖动）' : '按${sort.label}'),
              ),
          ],
          child: Text('排序：${prefs.sort.label}'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add),
          onPressed: () => addSection(context, ref, listId),
          child: const Text('添加分组'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: '更多',
        icon: const Icon(Icons.more_horiz),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
