import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import 'account_ui.dart';
import 'dialogs.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, this.onSelected});

  /// Called after a view is picked (closes the drawer on a phone).
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];
    final tags = ref.watch(tagsProvider);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final now = ref.watch(clockProvider);
    int count(ViewRef v) => openCount(v, tasks, now);

    Widget item(
      ViewRef view,
      Widget leading,
      String label, {
      bool showCount = true,
      VoidCallback? onMenu,
    }) {
      return _SidebarItem(
        view: view,
        leading: leading,
        label: label,
        count: showCount ? count(view) : 0,
        onSelected: onSelected,
        onMenu: onMenu,
      );
    }

    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          Expanded(child: _buildList(context, ref, item, lists, tags)),
          const Divider(),
          const AccountTile(),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    Widget Function(
      ViewRef,
      Widget,
      String, {
      bool showCount,
      VoidCallback? onMenu,
    })
    item,
    List<TaskList> lists,
    List<String> tags,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      children: [
        item(
          const SmartViewRef(SmartKind.today),
          const Icon(Icons.today_outlined),
          '今天',
        ),
        item(
          const SmartViewRef(SmartKind.tomorrow),
          const Icon(Icons.wb_twilight_outlined),
          '明天',
        ),
        item(
          const SmartViewRef(SmartKind.next7),
          const Icon(Icons.date_range_outlined),
          '最近7天',
        ),
        item(
          const SmartViewRef(SmartKind.inbox),
          const Icon(Icons.inbox_outlined),
          '收集箱',
        ),
        const SizedBox(height: 8),
        _SectionHeader(
          title: '清单',
          action: IconButton(
            tooltip: '添加清单',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await showListEditor(context);
              if (result == null) return;
              final id = await ref
                  .read(repoProvider)
                  .addList(result.name, emoji: result.emoji);
              ref.read(selectedViewProvider.notifier).select(ListViewRef(id));
              onSelected?.call();
            },
          ),
        ),
        for (final l in lists)
          item(
            ListViewRef(l.id),
            _Emoji(l.emoji),
            l.name,
            onMenu: () => _listMenu(context, ref, l),
          ),
        if (lists.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              '用清单把任务分类，比如“工作”“购物”',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          const _SectionHeader(title: '标签'),
          for (final tag in tags)
            item(TagViewRef(tag), const Icon(Icons.sell_outlined), tag),
        ],
        const Divider(height: 24),
        item(
          const SmartViewRef(SmartKind.completed),
          const Icon(Icons.task_alt),
          '已完成',
          showCount: false,
        ),
        item(
          const SmartViewRef(SmartKind.trash),
          const Icon(Icons.delete_outline),
          '垃圾桶',
          showCount: false,
        ),
      ],
    );
  }

  Future<void> _listMenu(
    BuildContext context,
    WidgetRef ref,
    TaskList list,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑清单'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除清单'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final repo = ref.read(repoProvider);
    if (action == 'edit') {
      final result = await showListEditor(
        context,
        name: list.name,
        emoji: list.emoji,
      );
      if (result != null) {
        await repo.updateList(list.id, name: result.name, emoji: result.emoji);
      }
    } else if (action == 'delete') {
      final ok = await confirm(
        context,
        title: '删除清单“${list.name}”？',
        message: '清单里的任务会移到垃圾桶，可以从那里恢复。',
        action: '删除',
      );
      if (!ok) return;
      await repo.deleteList(list.id);
      if (ref.read(selectedViewProvider) == ListViewRef(list.id)) {
        ref
            .read(selectedViewProvider.notifier)
            .select(const SmartViewRef(SmartKind.inbox));
      }
    }
  }
}

class _SidebarItem extends ConsumerWidget {
  const _SidebarItem({
    required this.view,
    required this.leading,
    required this.label,
    required this.count,
    this.onSelected,
    this.onMenu,
  });

  final ViewRef view;
  final Widget leading;
  final String label;
  final int count;
  final VoidCallback? onSelected;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedViewProvider) == view;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            ref.read(selectedViewProvider.notifier).select(view);
            onSelected?.call();
          },
          onSecondaryTap: onMenu,
          onLongPress: onMenu,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(size: 20, color: scheme.onSurfaceVariant),
                  child: SizedBox(width: 22, child: Center(child: leading)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _Emoji extends StatelessWidget {
  const _Emoji(this.emoji);
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    if (emoji == null || emoji!.isEmpty) return const Icon(Icons.list);
    return Text(emoji!, style: const TextStyle(fontSize: 16));
  }
}
