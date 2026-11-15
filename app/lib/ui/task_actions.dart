import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/dates.dart';
import '../state/providers.dart';
import 'dialogs.dart';
import 'theme.dart';

/// Right-click (or long-press) menu for a task row.
Future<void> showTaskMenu(
  BuildContext context,
  WidgetRef ref,
  Task task,
  Offset globalPosition,
) async {
  final repo = ref.read(repoProvider);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final position = RelativeRect.fromRect(
    globalPosition & const Size(1, 1),
    Offset.zero & overlay.size,
  );
  final scheme = Theme.of(context).colorScheme;
  final today = dateOnly(DateTime.now());

  if (task.trashedAt != null) {
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(value: 'restore', child: Text('恢复')),
        PopupMenuItem(value: 'purge', child: Text('永久删除')),
      ],
    );
    if (action == 'restore') await repo.restoreTask(task.id);
    if (action == 'purge') await repo.purgeTask(task.id);
    return;
  }

  PopupMenuItem<String> entry(String value, IconData icon, String label, {Color? color}) =>
      PopupMenuItem(
        value: value,
        height: 40,
        child: Row(children: [
          Icon(icon, size: 18, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label),
        ]),
      );

  final action = await showMenu<String>(
    context: context,
    position: position,
    items: [
      entry('today', Icons.today_outlined, '今天'),
      entry('tomorrow', Icons.wb_twilight_outlined, '明天'),
      entry('nextweek', Icons.next_week_outlined, '下周一'),
      entry('pickdate', Icons.edit_calendar_outlined, '选择日期…'),
      if (task.dueDate != null) entry('nodate', Icons.event_busy_outlined, '清除日期'),
      const PopupMenuDivider(),
      for (final p in [Priority.high, Priority.medium, Priority.low, Priority.none])
        entry('p$p', p == Priority.none ? Icons.outlined_flag : Icons.flag, priorityName(p),
            color: priorityColor(p, scheme)),
      const PopupMenuDivider(),
      entry('move', Icons.drive_file_move_outline, '移动到…'),
      entry('trash', Icons.delete_outline, '删除', color: scheme.error),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'today':
      await repo.setDue(task.id, today, task.dueTime);
    case 'tomorrow':
      await repo.setDue(task.id, addDays(today, 1), task.dueTime);
    case 'nextweek':
      await repo.setDue(task.id, addDays(startOfWeek(today), 7), task.dueTime);
    case 'pickdate':
      await pickDueDate(context, ref, task);
    case 'nodate':
      await repo.setDue(task.id, null, null);
    case 'move':
      final listId = await pickList(context, ref, current: task.listId);
      if (listId != null) await repo.moveToList(task.id, listId);
    case 'trash':
      await repo.trashTask(task.id);
    default:
      if (action.startsWith('p')) {
        await repo.setPriority(task.id, int.parse(action.substring(1)));
      }
  }
}

Future<void> pickDueDate(BuildContext context, WidgetRef ref, Task task) async {
  final choice = await showDueDateDialog(
    context,
    date: task.dueDate == null ? null : parseDateKey(task.dueDate!),
    time: task.dueTime,
  );
  if (choice == null) return;
  await ref.read(repoProvider).setDue(task.id, choice.date, choice.time);
}

/// Lets the person pick a list; returns its id, or null if dismissed.
Future<String?> pickList(BuildContext context, WidgetRef ref, {String? current}) {
  final lists = ref.read(listsProvider).value ?? const <TaskList>[];
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('移动到'),
      children: [
        _listOption(context, inboxListId, '📥', '收集箱', current),
        for (final l in lists) _listOption(context, l.id, l.emoji ?? '📋', l.name, current),
      ],
    ),
  );
}

Widget _listOption(BuildContext context, String id, String emoji, String name, String? current) {
  return SimpleDialogOption(
    onPressed: () => Navigator.pop(context, id),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 12),
      Expanded(child: Text(name)),
      if (id == current) Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
    ]),
  );
}
