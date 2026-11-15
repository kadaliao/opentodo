import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/ordering.dart';
import '../state/providers.dart';
import 'task_actions.dart';

/// Touch screens drag after a long press, so a swipe still scrolls; a mouse
/// drags straight away.
bool dragsOnLongPress(BuildContext context) => switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android || TargetPlatform.fuchsia => true,
      _ => false,
    };

/// Where a dragged task can land: a section of a list, or a day.
sealed class TaskDropGroup {
  const TaskDropGroup();

  bool accepts(Task t);

  /// Whether where in the group it lands counts (a line shows where), or
  /// only which group.
  bool get ordered;

  /// Puts [t] in this group, at [index] among the tasks as shown (counting
  /// [t] where it is now if it's one of them) when [ordered].
  Future<void> drop(WidgetRef ref, Task t, int index);
}

bool _movable(Task t) => t.status == TaskStatus.open && t.trashedAt == null;

/// The open tasks of one section of a list, in the order shown.
class ArrangeGroup extends TaskDropGroup {
  const ArrangeGroup({
    required this.listId,
    required this.sectionId,
    required this.tasks,
    this.manual = true,
  });

  final String listId;

  /// Null for 未分组.
  final String? sectionId;

  /// Pinned ones first, as the list shows them.
  final List<Task> tasks;

  /// The list is in manual order; otherwise a drop only changes section.
  final bool manual;

  @override
  bool get ordered => manual;

  @override
  bool accepts(Task t) => t.listId == listId && _movable(t);

  @override
  Future<void> drop(WidgetRef ref, Task t, int index) async {
    if (!accepts(t)) return;
    final repo = ref.read(repoProvider);
    final sameSection = tasks.any((x) => x.id == t.id);
    if (!manual) {
      if (!sameSection) await repo.placeTask(t.id, sectionId, const {});
      return;
    }
    // Pinned tasks move among the pinned ones, the rest among the rest.
    final pinned = t.pinnedAt != null;
    final firstUnpinned = tasks.indexWhere((x) => x.pinnedAt == null);
    final split = firstUnpinned < 0 ? tasks.length : firstUnpinned;
    final peers = tasks.where((x) => (x.pinnedAt != null) == pinned).toList();
    final at = pinned ? index.clamp(0, split) : (index - split).clamp(0, peers.length + 1);
    final ids = [for (final x in peers) x.id];
    final from = ids.indexOf(t.id);
    // Let go where it was: nothing to do.
    if (from >= 0 && (at == from || at == from + 1)) return;
    final byId = {for (final x in peers) x.id: x};
    final orders = planMove(ids, t.id, at, (id) => byId[id]?.sortOrder ?? t.sortOrder);
    await repo.placeTask(t.id, sectionId, orders);
  }
}

/// A day of 今天 / 明天 / 最近7天: a task dropped on it moves there,
/// keeping its time.
class DayDropGroup extends TaskDropGroup {
  const DayDropGroup(this.day);

  final DateTime day;

  @override
  bool get ordered => false;

  @override
  bool accepts(Task t) => _movable(t) && t.dueDate != dateKey(day);

  @override
  Future<void> drop(WidgetRef ref, Task t, int index) async {
    if (!accepts(t)) return;
    await ref.read(repoProvider).moveTo(t.id, day, t.dueTime);
  }
}

/// The task being dragged and how big its row is, so drop targets can tell
/// where its middle is.
final _dragging = ValueNotifier<({Task task, Size size})?>(null);

/// Lets the person drag [child], the row or card of [task], to another
/// place. On a touch screen the drag starts with a long press; letting go
/// without moving opens the task's menu instead.
class TaskDraggable extends ConsumerStatefulWidget {
  const TaskDraggable({super.key, required this.task, required this.child, this.width});

  final Task task;
  final Widget child;

  /// The dragged copy's width; the row's own when null.
  final double? width;

  @override
  ConsumerState<TaskDraggable> createState() => _TaskDraggableState();
}

class _TaskDraggableState extends ConsumerState<TaskDraggable> {
  Offset? _startTopLeft;
  final _scrollers = <EdgeDraggingAutoScroller>[];

  void _started() {
    final box = context.findRenderObject()! as RenderBox;
    _startTopLeft = box.localToGlobal(Offset.zero);
    _dragging.value = (task: widget.task, size: box.size);
    // Scroll the list (and the board) when the drag nears an edge.
    for (final axis in [Axis.vertical, Axis.horizontal]) {
      final scrollable = Scrollable.maybeOf(context, axis: axis);
      if (scrollable != null) {
        _scrollers.add(EdgeDraggingAutoScroller(scrollable, velocityScalar: 20));
      }
    }
  }

  void _updated(DragUpdateDetails d) {
    final rect = Rect.fromCenter(center: d.globalPosition, width: 48, height: 48);
    for (final s in _scrollers) {
      s.startAutoScrollIfNecessary(rect);
    }
  }

  void _ended(Offset offset) {
    for (final s in _scrollers) {
      s.stopAutoScroll();
    }
    _scrollers.clear();
    _dragging.value = null;
    final start = _startTopLeft;
    _startTopLeft = null;
    // A long press that didn't move: the menu, as a long press elsewhere.
    if (start != null && (offset - start).distance < 8 && dragsOnLongPress(context) && mounted) {
      final box = context.findRenderObject()! as RenderBox;
      showTaskMenu(context, ref, widget.task, box.localToGlobal(box.size.center(Offset.zero)));
    }
  }

  @override
  void dispose() {
    for (final s in _scrollers) {
      s.stopAutoScroll();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Built once the drag has started, when the row's size is known.
    final feedback = ValueListenableBuilder(
      valueListenable: _dragging,
      builder: (context, dragging, child) => Material(
        elevation: 6,
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: widget.width ?? dragging?.size.width ?? 320, child: child),
      ),
      child: widget.child,
    );
    final dimmed = Opacity(opacity: 0.3, child: widget.child);
    if (dragsOnLongPress(context)) {
      return LongPressDraggable<Task>(
        data: widget.task,
        feedback: feedback,
        childWhenDragging: dimmed,
        onDragStarted: _started,
        onDragUpdate: _updated,
        onDragEnd: (d) => _ended(d.offset),
        child: widget.child,
      );
    }
    return Draggable<Task>(
      data: widget.task,
      feedback: feedback,
      childWhenDragging: dimmed,
      onDragStarted: _started,
      onDragUpdate: _updated,
      onDragEnd: (d) => _ended(d.offset),
      child: widget.child,
    );
  }
}

/// A row or card in [group] at [index]: a dragged task dropped on its top
/// half goes before it, on its bottom half after it. A line shows where.
class TaskDropRow extends ConsumerStatefulWidget {
  const TaskDropRow({super.key, required this.group, required this.index, required this.child});

  final TaskDropGroup group;
  final int index;
  final Widget child;

  @override
  ConsumerState<TaskDropRow> createState() => _TaskDropRowState();
}

class _TaskDropRowState extends ConsumerState<TaskDropRow> {
  /// Where the line is while a task hovers: before or after this row.
  bool? _before;

  bool _isBefore(Offset feedbackTopLeft) {
    final box = context.findRenderObject()! as RenderBox;
    final size = _dragging.value?.size ?? box.size;
    final middle = box.globalToLocal(feedbackTopLeft).dy + size.height / 2;
    return middle < box.size.height / 2;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = BorderSide(color: scheme.primary, width: 2);
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => widget.group.accepts(d.data),
      onMove: (d) {
        final before = _isBefore(d.offset);
        if (before != _before) setState(() => _before = before);
      },
      onLeave: (_) => setState(() => _before = null),
      onAcceptWithDetails: (d) {
        final before = _isBefore(d.offset);
        setState(() => _before = null);
        widget.group.drop(ref, d.data, before ? widget.index : widget.index + 1);
      },
      // Always the same widgets around the child, decoration or not: a
      // change in shape would rebuild the row being dragged and lose the
      // drag.
      builder: (context, candidates, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: candidates.isEmpty || _before == null
            ? const BoxDecoration()
            : widget.group.ordered
                ? BoxDecoration(border: _before! ? Border(top: line) : Border(bottom: line))
                // Only the group counts: tint the row instead of a line.
                : BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
        child: widget.child,
      ),
    );
  }
}

/// A place that takes a dragged task into [group] at [index] (a section's
/// header, or the empty space below a column's cards), lit up while a task
/// hovers.
class TaskDropArea extends ConsumerWidget {
  const TaskDropArea({super.key, required this.group, required this.index, required this.child});

  final TaskDropGroup group;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => group.accepts(d.data),
      onAcceptWithDetails: (d) => group.drop(ref, d.data, index),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: candidates.isEmpty ? null : scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}
