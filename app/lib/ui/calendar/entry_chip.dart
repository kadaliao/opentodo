import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db.dart';
import '../../domain/calendar.dart';
import '../../domain/dates.dart';
import '../../domain/views.dart';
import '../../state/calendar_providers.dart';
import '../../state/providers.dart';
import '../../state/selection.dart';
import '../task_actions.dart';
import '../task_drag.dart' show dragsOnLongPress, severalDragged;
import '../task_tile.dart';
import '../theme.dart' show pickedFill;

/// What the calendar's views ask of the screen around them.
class CalendarCallbacks {
  const CalendarCallbacks({
    required this.openTask,
    required this.newTask,
    required this.showDay,
  });

  /// Shows a task's detail.
  final ValueChanged<String> openTask;

  /// Starts a new task on a day, at a time (null: all day).
  final void Function(DateTime date, int? time) newTask;

  /// Switches to the day view of [date].
  final ValueChanged<DateTime> showDay;
}

/// Whether an entry can be dragged to another day or time: only a task's own
/// date, not a later one of a repeating task, and only while it is open.
bool canMoveEntry(CalendarEntry e) =>
    !e.projected && !e.done && e.task.trashedAt == null;

/// What's dragged on the calendar: the entry under the pointer ([lead]),
/// and with it the other picked tasks (多选) when it is one of them.
class CalendarDrag {
  const CalendarDrag(this.lead, [this.others = const []]);

  final CalendarEntry lead;

  /// The other picked tasks going along: open, with a date.
  final List<Task> others;

  int get count => others.length + 1;

  bool has(String taskId) => lead.task.id == taskId || others.any((t) => t.id == taskId);

  /// Where they all go when [lead] lands on [day] (see [dropTargets]).
  List<CalendarMove> to(DateTime day, {int? minute, bool allDay = false}) =>
      dropTargets(lead, others, day, minute: minute, allDay: allDay);
}

/// The drag under way, and where its dragged copy started.
final _dragging = ValueNotifier<({CalendarDrag drag, Offset start})?>(null);

/// Whether a drop with the dragged copy's top left at [topLeft] is where the
/// drag began: a long press let go without moving (or a nudge), which moves
/// nothing. Drop targets hear of a drop before the drag ends.
bool droppedInPlace(Offset topLeft) {
  final d = _dragging.value;
  return d != null && (topLeft - d.start).distance < 8;
}

/// Lets the person drag [child], an entry on the calendar, to another day or
/// time; when its task is one of the picked ones, they all go together.
/// Drop targets receive a [CalendarDrag]. On a touch screen the drag starts
/// with a long press, and letting go without moving opens the task's menu.
class EntryDraggable extends ConsumerStatefulWidget {
  const EntryDraggable({
    super.key,
    required this.entry,
    required this.size,
    required this.child,
  });

  final CalendarEntry entry;

  /// The dragged copy's size: the same as the original.
  final Size size;
  final Widget child;

  @override
  ConsumerState<EntryDraggable> createState() => _EntryDraggableState();
}

class _EntryDraggableState extends ConsumerState<EntryDraggable> {
  /// This entry started the drag under way.
  bool _owns = false;

  void _started(CalendarDrag data) {
    final box = context.findRenderObject()! as RenderBox;
    _dragging.value = (drag: data, start: box.localToGlobal(Offset.zero));
    _owns = true;
  }

  void _ended(Offset offset) {
    final start = _dragging.value?.start;
    _dragging.value = null;
    _owns = false;
    if (start != null && (offset - start).distance < 8 && dragsOnLongPress(context) && mounted) {
      final box = context.findRenderObject()! as RenderBox;
      showTaskMenu(context, ref, widget.entry.task, box.localToGlobal(box.size.center(Offset.zero)));
    }
  }

  @override
  void dispose() {
    // Gone mid-drag (the day changed under it): the drag ends unheard.
    if (_owns) _dragging.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    if (!canMoveEntry(entry)) return widget.child;
    final picked = ref.watch(calendarPickedProvider);
    final data = picked.length > 1 && picked.any((t) => t.id == entry.task.id)
        ? CalendarDrag(entry, [for (final t in picked) if (t.id != entry.task.id) t])
        : CalendarDrag(entry);
    final feedback = severalDragged(
      Theme.of(context).colorScheme,
      Material(
        elevation: 6,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox.fromSize(size: widget.size, child: widget.child),
      ),
      data.count,
      radius: 4,
    );
    final dimmed = Opacity(opacity: 0.35, child: widget.child);
    // The other picked tasks dim too while they're dragged along.
    final child = ValueListenableBuilder(
      valueListenable: _dragging,
      builder: (context, dragging, child) => Opacity(
        opacity: dragging != null && dragging.drag.count > 1 && dragging.drag.has(entry.task.id) ? 0.35 : 1,
        child: child,
      ),
      child: widget.child,
    );
    if (dragsOnLongPress(context)) {
      return LongPressDraggable<CalendarDrag>(
        data: data,
        feedback: feedback,
        childWhenDragging: dimmed,
        onDragStarted: () => _started(data),
        onDragEnd: (d) => _ended(d.offset),
        child: child,
      );
    }
    return Draggable<CalendarDrag>(
      data: data,
      feedback: feedback,
      childWhenDragging: dimmed,
      onDragStarted: () => _started(data),
      onDragEnd: (d) => _ended(d.offset),
      child: child,
    );
  }
}

/// A task on the calendar: a tinted bar with a checkbox and the title.
/// A later date of a repeating task shows faded, with a repeat mark instead.
class EntryChip extends ConsumerWidget {
  const EntryChip({
    super.key,
    required this.entry,
    required this.onOpen,
    this.height = 20,
    this.showTime = true,
    this.endLabel,
  });

  final CalendarEntry entry;
  final ValueChanged<String> onOpen;
  final double height;

  /// Shows the time at the end (the month board); hour grids leave it out.
  final bool showTime;

  /// Where the task will end while its bottom edge is dragged (17:30).
  final String? endLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final task = entry.task;
    final overdue =
        !entry.projected && isOverdue(task, ref.watch(clockProvider));
    final picking = ref.watch(taskSelectionProvider);
    // The picked tasks, or else the one open in the detail.
    final selected = !entry.projected &&
        (picking.active ? picking.ids.contains(task.id) : ref.watch(selectedTaskProvider) == task.id);
    final (bg, fg) = entry.done
        ? (scheme.surfaceContainerHighest, scheme.outline)
        : entry.projected
        ? (
            scheme.primaryContainer.withValues(alpha: 0.4),
            scheme.onSurfaceVariant,
          )
        : selected
        ? (pickedFill(scheme), scheme.onPrimaryContainer)
        : (scheme.primaryContainer, scheme.onPrimaryContainer);
    final title = task.title.isEmpty ? '无标题' : task.title;
    void menu() {
      final box = context.findRenderObject()! as RenderBox;
      showTaskMenu(context, ref, task, box.localToGlobal(box.size.center(Offset.zero)));
    }

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: selected ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(task.id),
        onSecondaryTapDown: entry.projected
            ? null
            : (d) => showTaskMenu(context, ref, task, d.globalPosition),
        // On a touch screen a long press drags a task that can move; the
        // menu comes from letting go without moving (EntryDraggable).
        onLongPress: entry.projected || (dragsOnLongPress(context) && canMoveEntry(entry)) ? null : menu,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, c) {
              // A narrow day keeps the title and drops the time.
              final width = c.maxWidth;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  crossAxisAlignment: height > 26
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: height > 26 ? 4 : 0),
                      child: entry.projected
                          ? Icon(
                              Icons.repeat,
                              size: 12,
                              color: fg,
                              semanticLabel: '重复',
                            )
                          : PriorityCheckbox(
                              checked: entry.done,
                              priority: task.priority,
                              size: 12,
                              onChanged: task.trashedAt != null
                                  ? null
                                  : (v) => setTaskDone(context, ref, task, v),
                            ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: height > 26 ? 3 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                color: fg,
                                decoration: entry.done
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: fg,
                              ),
                            ),
                            // A span tall enough on the hour grid says when.
                            if (!showTime && height >= 40 && entry.endTime != null)
                              Text(
                                '${clockLabel(entry.time!)}-${clockLabel(entry.endTime!)}',
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.4,
                                  color: overdue ? scheme.error : fg.withValues(alpha: 0.8),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (endLabel != null)
                      Padding(
                        padding: EdgeInsets.only(left: 4, top: height > 26 ? 4 : 0),
                        child: Text(
                          '→ $endLabel',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
                        ),
                      ),
                    if (showTime && entry.time != null && entry.dayIndex == 0 && width >= 120)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          timeLabel(entry.time!),
                          style: TextStyle(
                            fontSize: 10,
                            color: overdue
                                ? scheme.error
                                : fg.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Beside a day's number: its lunar day or festival, and 休 or 班.
class DayNoteLabel extends StatelessWidget {
  const DayNoteLabel({super.key, required this.date, this.dim = false});

  final DateTime date;

  /// A day outside the month on show.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final note = dayNote(date);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(
          note.label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 10,
            color: dim ? scheme.outlineVariant : (note.special ? scheme.primary : scheme.outline),
          ),
        ),
      ),
      if (note.off != null) ...[
        const SizedBox(width: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: (note.off! ? scheme.primary : scheme.error).withValues(alpha: dim ? 0.06 : 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            note.off! ? '休' : '班',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: (note.off! ? scheme.primary : scheme.error).withValues(alpha: dim ? 0.5 : 1),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// “还有3项”: more entries than a day has room for.
class MoreEntries extends StatelessWidget {
  const MoreEntries({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: SizedBox(
        height: 18,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '还有$count项',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
