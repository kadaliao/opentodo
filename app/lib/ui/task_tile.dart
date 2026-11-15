import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import 'task_actions.dart';
import 'theme.dart';

class TaskTile extends ConsumerWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onOpen,
    this.showList = false,
  });

  final Task task;
  final ValueChanged<String> onOpen;

  /// Shows which list the task is in (for smart lists and tags).
  final bool showList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedTaskProvider) == task.id;
    final now = ref.watch(clockProvider);
    final today = dateOnly(now);
    final done = task.status != TaskStatus.open;
    final trashed = task.trashedAt != null;

    Color dueColor() {
      final cmp = task.dueDate!.compareTo(dateKey(today));
      if (done) return scheme.outline;
      if (cmp < 0) return scheme.error;
      if (cmp == 0 && task.dueTime != null && task.dueTime! < now.hour * 60 + now.minute) {
        return scheme.error;
      }
      return scheme.primary;
    }

    return Material(
      color: selected ? scheme.secondaryContainer.withValues(alpha: 0.6) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onOpen(task.id),
        onSecondaryTapDown: (d) => showTaskMenu(context, ref, task, d.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject()! as RenderBox;
          showTaskMenu(context, ref, task, box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            PriorityCheckbox(
              checked: done,
              priority: task.priority,
              onChanged: trashed
                  ? null
                  : (v) => ref.read(repoProvider).setCompleted(task.id, v),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title.isEmpty ? '无标题' : task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: done || task.title.isEmpty ? scheme.outline : scheme.onSurface,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: scheme.outline,
                ),
              ),
            ),
            for (final tag in task.tags.take(2))
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _TagChip(tag),
              ),
            if (showList)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  listName(task.listId, ref.watch(listsByIdProvider)),
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ),
            if (task.dueDate != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  dueLabel(task.dueDate!, task.dueTime, today),
                  style: TextStyle(fontSize: 12, color: dueColor()),
                ),
              ),
            if (trashed) ...[
              IconButton(
                tooltip: '恢复',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restore, size: 18),
                onPressed: () => ref.read(repoProvider).restoreTask(task.id),
              ),
              IconButton(
                tooltip: '永久删除',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                onPressed: () => ref.read(repoProvider).purgeTask(task.id),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.tag);
  final String tag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(tag, style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer)),
    );
  }
}

/// A rounded square whose border shows the priority.
class PriorityCheckbox extends StatelessWidget {
  const PriorityCheckbox({
    super.key,
    required this.checked,
    required this.priority,
    required this.onChanged,
    this.size = 18,
  });

  final bool checked;
  final int priority;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = checked ? scheme.outline : priorityColor(priority, scheme);
    return Semantics(
      checked: checked,
      button: true,
      label: checked ? '标记为未完成' : '完成',
      child: InkResponse(
        radius: size,
        onTap: onChanged == null ? null : () => onChanged!(!checked),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 1.6),
            color: checked
                ? scheme.outline
                : (priority == Priority.none ? null : color.withValues(alpha: 0.08)),
          ),
          child: checked ? Icon(Icons.check, size: size - 4, color: scheme.surface) : null,
        ),
      ),
    );
  }
}
