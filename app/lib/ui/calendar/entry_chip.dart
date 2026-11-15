import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/calendar.dart';
import '../../domain/dates.dart';
import '../../domain/views.dart';
import '../../state/providers.dart';
import '../task_actions.dart';
import '../task_tile.dart';

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

/// Touch screens drag after a long press, so a swipe still scrolls; a mouse
/// drags straight away.
bool _dragOnLongPress(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };

/// Lets the person drag [child], an entry on the calendar, to another day or
/// time. Drop targets receive the [CalendarEntry].
class EntryDraggable extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (!canMoveEntry(entry)) return child;
    final feedback = Material(
      elevation: 6,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox.fromSize(size: size, child: child),
    );
    final dimmed = Opacity(opacity: 0.35, child: child);
    if (_dragOnLongPress(context)) {
      return LongPressDraggable<CalendarEntry>(
        data: entry,
        feedback: feedback,
        childWhenDragging: dimmed,
        child: child,
      );
    }
    return Draggable<CalendarEntry>(
      data: entry,
      feedback: feedback,
      childWhenDragging: dimmed,
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
    final (bg, fg) = entry.done
        ? (scheme.surfaceContainerHighest, scheme.outline)
        : entry.projected
        ? (
            scheme.primaryContainer.withValues(alpha: 0.4),
            scheme.onSurfaceVariant,
          )
        : (scheme.primaryContainer, scheme.onPrimaryContainer);
    final title = task.title.isEmpty ? '无标题' : task.title;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(task.id),
        onSecondaryTapDown: entry.projected
            ? null
            : (d) => showTaskMenu(context, ref, task, d.globalPosition),
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
