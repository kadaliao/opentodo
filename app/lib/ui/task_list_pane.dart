import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import '../state/selection.dart';
import 'batch_actions.dart';
import 'board_view.dart';
import 'dialogs.dart';
import 'filter_editor.dart';
import 'quick_add_field.dart';
import 'search_panel.dart';
import 'section_actions.dart';
import 'task_drag.dart';
import 'task_tile.dart';
import 'timeline_view.dart';

class TaskListPane extends ConsumerStatefulWidget {
  const TaskListPane({
    super.key,
    required this.onOpenTask,
    this.showMenuButton = false,
    this.showInlineQuickAdd = true,
    this.showBatchBar = false,
  });

  final ValueChanged<String> onOpenTask;
  final bool showMenuButton;
  final bool showInlineQuickAdd;

  /// Batch actions for picked tasks along the bottom (where there's no
  /// detail pane to show them).
  final bool showBatchBar;

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
    final prefs = ref.watch(currentViewPrefsProvider);
    // Rows name their list where tasks from several show, unless the
    // headers already do.
    final showList = (view is SmartViewRef || view is TagViewRef || view is FilterViewRef) &&
        prefs.groupingIn(view) != TaskGrouping.list;
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
    final anyTarget = sections.any((s) => s.target != null);
    final arrangedList = arrangedListId(view);
    final board = arrangedList != null && prefs.layout == ListLayout.board;
    final timeline = arrangedList != null && prefs.layout == ListLayout.timeline;
    final touch = dragsOnLongPress(context);
    final selection = ref.watch(taskSelectionProvider);
    final picking = selection.active;
    // The tasks as shown, for Shift-click ranges and 全选.
    final order = [
      for (final s in sections)
        if (!_isCollapsed(view, s)) for (final t in s.tasks) t.id,
    ];
    // The picked tasks that can be dragged, which go together.
    final picked = [
      if (picking)
        for (final s in sections)
          if (!_isCollapsed(view, s))
            for (final t in s.tasks)
              if (selection.ids.contains(t.id) && t.status == TaskStatus.open && t.trashedAt == null) t,
    ];
    // In the trash, a click only opens.
    void open(String id) => isTrash
        ? widget.onOpenTask(id)
        : tapTask(ref, id, order, widget.onOpenTask, touch: touch);

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
          if (groupingsFor(view).isNotEmpty) _ArrangeMenu(view: view, prefs: prefs, board: board || timeline),
          if (arrangedList != null) _ListMenu(view: view, listId: arrangedList, prefs: prefs),
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
                ? BoardView(listId: arrangedList, onOpenTask: widget.onOpenTask)
                : timeline
                ? TimelineView(key: ValueKey(arrangedList), listId: arrangedList, onOpenTask: widget.onOpenTask)
                : sections.isEmpty
                ? _EmptyState(view: view)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                    children: [
                      for (final s in sections) ...() {
                        final group = s.target == null
                            ? null
                            : GroupDrop(s.target!, tasks: s.tasks, manual: s.manualOrder);
                        // Open tasks can be dragged when there's a group to
                        // drop them in, also out of one that takes none
                        // (已过期, 以后).
                        final draggable = !s.finished && anyTarget;
                        Widget header = _SectionHeader(
                          title: s.title ?? '',
                          alert: s.alert,
                          // An empty day (there to drag onto) shows no 0.
                          count: s.day != null && s.tasks.isEmpty ? null : s.tasks.length,
                          collapsed: _isCollapsed(view, s),
                          onToggle: () => setState(() {
                            _toggled['$view/${s.id}'] = !_isCollapsed(view, s);
                          }),
                          menu: s.listSection == null ? null : SectionMenuButton(section: s.listSection!),
                        );
                        // A list's section moves by dragging its header.
                        if (s.listSection != null) header = SectionDraggable(section: s.listSection!, child: header);
                        // Dropped on a header: first in that section.
                        if (group != null) header = TaskDropArea(group: group, index: 0, child: header);
                        final rows = [
                          if (s.title != null) header,
                          if (!_isCollapsed(view, s))
                            for (final (i, t) in s.tasks.indexed)
                              () {
                                if (!draggable) {
                                  return TaskTile(
                                    key: ValueKey(t.id),
                                    task: t,
                                    showList: showList,
                                    onOpen: open,
                                  );
                                }
                                final Widget row = TaskDraggable(
                                  task: t,
                                  picked: picked,
                                  child: TaskTile(
                                    task: t,
                                    showList: showList,
                                    onOpen: open,
                                    longPressMenu: !touch,
                                  ),
                                );
                                return group == null
                                    ? KeyedSubtree(key: ValueKey(t.id), child: row)
                                    : TaskDropRow(key: ValueKey(t.id), group: group, index: i, child: row);
                              }(),
                        ];
                        // Another section dropped on this one's upper half
                        // goes before it, on the lower half after it.
                        if (s.listSection == null) return rows;
                        return [
                          SectionDropTarget(
                            key: ValueKey('section-${s.listSection!.id}'),
                            section: s.listSection!,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
                          ),
                        ];
                      }(),
                    ],
                  ),
      ),
      if (widget.showBatchBar && picking && !isTrash) BatchBar(order: order),
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

  /// Null shows none.
  final int? count;
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
                  color: alert
                      ? scheme.error
                      : count == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 12, color: scheme.outline)),
          ],
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

/// ⇅: how the view's open tasks are grouped (分组) and ordered (排序).
class _ArrangeMenu extends ConsumerWidget {
  const _ArrangeMenu({required this.view, required this.prefs, required this.board});

  final ViewRef view;
  final ViewPrefs prefs;

  /// A board's columns (a timeline's lanes) are always the list's
  /// sections: only the order.
  final bool board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(viewPrefsProvider.notifier);
    final grouping = prefs.groupingIn(view)!;
    final sort = prefs.sortIn(view)!;
    const check = Icon(Icons.check, size: 18);
    return MenuAnchor(
      menuChildren: [
        if (!board)
          SubmenuButton(
            leadingIcon: const Icon(Icons.view_agenda_outlined),
            menuChildren: [
              for (final g in groupingsFor(view))
                MenuItemButton(
                  trailingIcon: g == grouping ? check : null,
                  onPressed: () => notifier.setGrouping(view, g),
                  child: Text(switch (g) {
                    TaskGrouping.sections => '自定义分组',
                    TaskGrouping.none => '不分组',
                    _ => '按${g.label}',
                  }),
                ),
            ],
            child: Text('分组：${grouping.label}'),
          ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.sort),
          menuChildren: [
            for (final o in sortsFor(view))
              MenuItemButton(
                trailingIcon: o == sort ? check : null,
                onPressed: () => notifier.setSort(view, o),
                child: Text(o == TaskSort.manual ? '自定义（拖动）' : '按${o.label}'),
              ),
          ],
          child: Text('排序：${sort.label}'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: board ? '排序' : '分组和排序',
        icon: const Icon(Icons.swap_vert),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// The ⋯ of a list: show it as a list, a board or a timeline, add a
/// section.
class _ListMenu extends ConsumerWidget {
  const _ListMenu({required this.view, required this.listId, required this.prefs});

  final ViewRef view;
  final String listId;
  final ViewPrefs prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(viewPrefsProvider.notifier);
    const check = Icon(Icons.check, size: 18);
    return MenuAnchor(
      menuChildren: [
        for (final (l, icon, label) in const [
          (ListLayout.list, Icons.view_list_outlined, '列表'),
          (ListLayout.board, Icons.view_kanban_outlined, '看板'),
          (ListLayout.timeline, Icons.view_timeline_outlined, '时间线'),
        ])
          MenuItemButton(
            leadingIcon: Icon(icon),
            trailingIcon: prefs.layout == l ? check : null,
            onPressed: () => notifier.setLayout(view, l),
            child: Text(label),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add),
          onPressed: () async {
            final added = await addSection(context, ref, listId);
            // Show the sections, so the new one is there to see.
            if (added != null && prefs.groupingIn(view) != TaskGrouping.sections) {
              notifier.setGrouping(view, TaskGrouping.sections);
            }
          },
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
