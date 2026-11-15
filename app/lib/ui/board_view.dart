import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import '../state/selection.dart';
import 'quick_add_field.dart';
import 'section_actions.dart';
import 'task_actions.dart';
import 'task_drag.dart';
import 'task_tile.dart' show PriorityCheckbox;
import 'theme.dart' show Breakpoints;

const _columnWidth = 272.0;

/// A list as a board (看板): a column per section, cards dragged between
/// and within them.
class BoardView extends ConsumerWidget {
  const BoardView({super.key, required this.listId, required this.onOpenTask});

  final String listId;
  final ValueChanged<String> onOpenTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = (ref.watch(viewPrefsProvider)[listId] ?? const ViewPrefs()).sortIn(ListViewRef(listId))!;
    final columns = boardColumns(
      listId,
      ref.watch(tasksProvider).value ?? const [],
      ref.watch(sectionsByListProvider)[listId] ?? const [],
      sort: sort,
    );
    // Clicks with ⌘ / Shift pick cards; the order runs column by column.
    final order = [
      for (final c in columns) ...[for (final t in c.group.tasks) t.id, for (final t in c.done) t.id],
    ];
    void open(String id) => tapTask(ref, id, order, onOpenTask, touch: dragsOnLongPress(context));
    // The picked open cards, which are dragged together.
    final selection = ref.watch(taskSelectionProvider);
    final picked = [
      for (final c in columns)
        for (final t in c.group.tasks)
          if (selection.ids.contains(t.id)) t,
    ];
    // A phone shows one column and a bit of the next.
    final width = MediaQuery.sizeOf(context).width < Breakpoints.twoPane
        ? MediaQuery.sizeOf(context).width * 0.82
        : _columnWidth;
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        for (final c in columns)
          Padding(
            key: ValueKey(c.group.section?.id ?? 'none'),
            padding: const EdgeInsets.only(right: 12),
            child: () {
              final Widget column = SizedBox(
                width: width,
                child: _Column(
                  listId: listId,
                  column: c,
                  manual: sort == TaskSort.manual,
                  onOpenTask: open,
                  cardWidth: width,
                  picked: picked,
                ),
              );
              // Another column dropped on this one's left half goes before
              // it, on the right half after it.
              final section = c.group.section;
              return section == null
                  ? column
                  : SectionDropTarget(section: section, axis: Axis.horizontal, child: column);
            }(),
          ),
        Align(
          alignment: Alignment.topLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加分组'),
            onPressed: () => addSection(context, ref, listId),
          ),
        ),
      ],
    );
  }
}

class _Column extends ConsumerStatefulWidget {
  const _Column({
    required this.listId,
    required this.column,
    required this.manual,
    required this.onOpenTask,
    required this.cardWidth,
    required this.picked,
  });

  final String listId;
  final BoardColumn column;

  /// The picked cards of the whole board, in order.
  final List<Task> picked;

  /// The list is in manual order: where a card lands counts.
  final bool manual;
  final ValueChanged<String> onOpenTask;
  final double cardWidth;

  @override
  ConsumerState<_Column> createState() => _ColumnState();
}

class _ColumnState extends ConsumerState<_Column> {
  bool _adding = false;
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = widget.column;
    final section = c.group.section;
    final group = GroupDrop(
      SectionTarget(widget.listId, section?.id),
      tasks: c.group.tasks,
      manual: widget.manual,
    );

    Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(children: [
        Flexible(
          child: Text(
            c.group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        Text('${c.group.tasks.length}', style: TextStyle(fontSize: 12, color: scheme.outline)),
        const Spacer(),
        IconButton(
          tooltip: '在“${c.group.title}”里添加任务',
          visualDensity: VisualDensity.compact,
          icon: Icon(_adding ? Icons.close : Icons.add, size: 18),
          onPressed: () => setState(() => _adding = !_adding),
        ),
        if (section != null) SectionMenuButton(section: section, horizontal: true),
      ]),
    );
    // The column moves by dragging its top; cards dropped there go first.
    if (section != null) header = SectionDraggable(section: section, child: header);
    header = TaskDropArea(group: group, index: 0, child: header);

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        if (_adding)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: QuickAddField(
              autofocus: true,
              target: QuickAddTarget(listId: widget.listId, sectionId: section?.id),
              hintText: '添加任务，回车创建',
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              for (final (i, t) in c.group.tasks.indexed)
                Padding(
                  key: ValueKey(t.id),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TaskDropRow(
                    group: group,
                    index: i,
                    child: TaskDraggable(
                      task: t,
                      picked: widget.picked,
                      width: widget.cardWidth - 16,
                      child: _Card(task: t, onOpen: widget.onOpenTask),
                    ),
                  ),
                ),
              // The rest of the column takes a drop at the end.
              TaskDropArea(
                group: group,
                index: c.group.tasks.length,
                child: SizedBox(
                  height: c.group.tasks.isEmpty ? 80 : 40,
                  child: c.group.tasks.isEmpty
                      ? Center(
                          child: Text('拖任务到这里', style: TextStyle(fontSize: 12, color: scheme.outline)),
                        )
                      : null,
                ),
              ),
              if (c.done.isNotEmpty) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _showDone = !_showDone),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(children: [
                      AnimatedRotation(
                        turns: _showDone ? 0 : -0.25,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 4),
                      Text('已完成', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 6),
                      Text('${c.done.length}', style: TextStyle(fontSize: 12, color: scheme.outline)),
                    ]),
                  ),
                ),
                if (_showDone)
                  for (final t in c.done)
                    Padding(
                      key: ValueKey(t.id),
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _Card(task: t, onOpen: widget.onOpenTask),
                    ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

/// A task on the board: checkbox and title, then its date, marks and tags.
class _Card extends ConsumerWidget {
  const _Card({required this.task, required this.onOpen});

  final Task task;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final picking = ref.watch(taskSelectionProvider);
    final selected = picking.active ? picking.ids.contains(task.id) : ref.watch(selectedTaskProvider) == task.id;
    final now = ref.watch(clockProvider);
    final done = task.status != TaskStatus.open;
    final overdue = isOverdue(task, now);
    final dueColor = done ? scheme.outline : (overdue ? scheme.error : scheme.primary);
    final touch = dragsOnLongPress(context);

    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onOpen(task.id),
        onSecondaryTapDown: (d) => showTaskMenu(context, ref, task, d.globalPosition),
        // On a touch screen a long press drags; the menu comes from letting
        // go without moving (TaskDraggable). Finished cards don't drag.
        onLongPress: touch && !done
            ? null
            : () {
                final box = context.findRenderObject()! as RenderBox;
                showTaskMenu(context, ref, task, box.localToGlobal(box.size.center(Offset.zero)));
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: PriorityCheckbox(
                checked: done,
                priority: task.priority,
                onChanged: (v) => setTaskDone(context, ref, task, v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  task.title.isEmpty ? '无标题' : task.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: done || task.title.isEmpty ? scheme.outline : scheme.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: scheme.outline,
                  ),
                ),
                if (task.dueDate != null || task.tags.isNotEmpty || (task.pinnedAt != null && !done))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (task.pinnedAt != null && !done)
                          Icon(Icons.push_pin, size: 13, color: scheme.outline, semanticLabel: '已置顶'),
                        if (task.dueDate != null)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            if (task.reminders.isNotEmpty && !done)
                              Icon(Icons.alarm, size: 12, color: dueColor, semanticLabel: '有提醒'),
                            if (task.repeatRule != null)
                              Icon(Icons.repeat, size: 12, color: dueColor, semanticLabel: '重复'),
                            if (task.reminders.isNotEmpty || task.repeatRule != null)
                              const SizedBox(width: 3),
                            Text(
                              dueLabel(task.dueDate!, task.dueTime, dateOnly(now), duration: task.duration),
                              style: TextStyle(
                                fontSize: 12,
                                color: dueColor,
                                fontWeight: overdue ? FontWeight.w600 : null,
                              ),
                            ),
                          ]),
                        for (final tag in task.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(tag,
                                style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer)),
                          ),
                      ],
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
