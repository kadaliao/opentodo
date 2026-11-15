import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/views.dart';
import '../state/providers.dart';
import 'dialogs.dart';
import 'quick_add_field.dart';
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
    final loading = ref.watch(tasksProvider).isLoading;
    final sections = ref.watch(sectionsProvider);
    final showList = view is SmartViewRef || view is TagViewRef;
    final isTrash = view == const SmartViewRef(SmartKind.trash);

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
              viewTitle(view, lists),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
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
      if (widget.showInlineQuickAdd && canQuickAdd(view))
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: QuickAddField(),
        ),
      Expanded(
        child: loading
            ? const SizedBox.shrink()
            : sections.isEmpty
                ? _EmptyState(view: view)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                    children: [
                      for (final s in sections) ...[
                        if (s.title != null)
                          _SectionHeader(
                            title: s.title!,
                            count: s.tasks.length,
                            collapsed: _isCollapsed(view, s),
                            onToggle: () => setState(() {
                              _toggled['$view/${s.id}'] = !_isCollapsed(view, s);
                            }),
                          ),
                        if (!_isCollapsed(view, s))
                          for (final t in s.tasks)
                            TaskTile(
                              key: ValueKey(t.id),
                              task: t,
                              showList: showList,
                              onOpen: widget.onOpenTask,
                            ),
                      ],
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
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

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
                  fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          const SizedBox(width: 6),
          Text('$count', style: TextStyle(fontSize: 12, color: scheme.outline)),
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
