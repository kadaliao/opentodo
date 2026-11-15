import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/ordering.dart';
import '../state/providers.dart';
import 'dialogs.dart';

/// Asks for a name and adds a section at the end of [listId]'s.
Future<void> addSection(BuildContext context, WidgetRef ref, String listId) async {
  final name = await promptName(context, title: '添加分组', hint: '分组名称，比如“进行中”');
  if (name == null) return;
  await ref.read(repoProvider).addSection(listId, name);
}

/// Moves [section] [delta] places among its list's sections.
Future<void> moveSection(WidgetRef ref, ListSection section, int delta) async {
  final sections = ref.read(sectionsByListProvider)[section.listId] ?? const <ListSection>[];
  final ids = [for (final s in sections) s.id];
  final from = ids.indexOf(section.id);
  final to = from + delta;
  if (from < 0 || to < 0 || to >= ids.length) return;
  final byId = {for (final s in sections) s.id: s};
  // planMove counts the index with the section still in place.
  final orders = planMove(ids, section.id, delta > 0 ? to + 1 : to, (id) => byId[id]!.sortOrder);
  final repo = ref.read(repoProvider);
  for (final e in orders.entries) {
    await repo.updateSection(e.key, sortOrder: e.value);
  }
}

/// The ⋯ button of a section header or a board column.
class SectionMenuButton extends ConsumerWidget {
  const SectionMenuButton({super.key, required this.section, this.horizontal = false});

  final ListSection section;

  /// On the board the sections run left to right.
  final bool horizontal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(sectionsByListProvider)[section.listId] ?? const <ListSection>[];
    final index = sections.indexWhere((s) => s.id == section.id);
    return PopupMenuButton<String>(
      tooltip: '分组操作',
      icon: const Icon(Icons.more_horiz, size: 18),
      iconSize: 18,
      padding: EdgeInsets.zero,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        if (index > 0) PopupMenuItem(value: 'back', child: Text(horizontal ? '左移' : '上移')),
        if (index >= 0 && index < sections.length - 1)
          PopupMenuItem(value: 'forward', child: Text(horizontal ? '右移' : '下移')),
        const PopupMenuItem(value: 'delete', child: Text('删除分组')),
      ],
      onSelected: (action) async {
        final repo = ref.read(repoProvider);
        switch (action) {
          case 'rename':
            final name = await promptName(context, title: '重命名分组', initial: section.name);
            if (name != null) await repo.updateSection(section.id, name: name);
          case 'back':
            await moveSection(ref, section, -1);
          case 'forward':
            await moveSection(ref, section, 1);
          case 'delete':
            final ok = await confirm(
              context,
              title: '删除分组“${section.name}”？',
              message: '分组里的任务会留在清单里，归到“未分组”。',
              action: '删除',
            );
            if (ok) await repo.deleteSection(section.id);
        }
      },
    );
  }
}
