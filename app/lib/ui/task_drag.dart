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

/// What's being dragged: the task under the pointer ([lead]), and with it
/// the other picked ones (多选) when it is one of them.
class DraggedTasks {
  const DraggedTasks(this.lead, [List<Task>? tasks]) : tasks = tasks ?? const [];

  final Task lead;

  /// Every task dragged, in the order shown, [lead] among them; just
  /// [lead] when empty.
  final List<Task> tasks;

  List<Task> get all => tasks.isEmpty ? [lead] : tasks;

  int get count => all.length;
}

/// Where dragged tasks can land: a section of a list, or a day.
sealed class TaskDropGroup {
  const TaskDropGroup();

  bool accepts(Task t);

  /// Takes a drag when any of its tasks can go here.
  bool acceptsDrag(DraggedTasks d) => d.all.any(accepts);

  /// Whether where in the group it lands counts (a line shows where), or
  /// only which group.
  bool get ordered;

  /// Puts the dragged tasks that can go here in this group, together, at
  /// [index] among the tasks as shown (counting any of them where they are
  /// now) when [ordered].
  Future<void> drop(WidgetRef ref, DraggedTasks d, int index);
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
  Future<void> drop(WidgetRef ref, DraggedTasks d, int index) async {
    final moving = d.all.where(accepts).toList();
    if (moving.isEmpty) return;
    final repo = ref.read(repoProvider);
    final ids = [for (final t in moving) t.id];
    if (!manual) {
      await repo.placeTasks(ids, sectionId, const {});
      return;
    }
    // Pinned tasks move among the pinned ones, the rest among the rest.
    final firstUnpinned = tasks.indexWhere((x) => x.pinnedAt == null);
    final split = firstUnpinned < 0 ? tasks.length : firstUnpinned;
    final orders = <String, double>{};
    for (final pinned in [true, false]) {
      final movers = [
        for (final t in moving)
          if ((t.pinnedAt != null) == pinned) t,
      ];
      if (movers.isEmpty) continue;
      final peers = tasks.where((x) => (x.pinnedAt != null) == pinned).toList();
      final at = pinned ? index.clamp(0, split) : (index - split).clamp(0, peers.length);
      final byId = {
        for (final x in [...peers, ...movers]) x.id: x,
      };
      orders.addAll(
        planMoveMany([for (final x in peers) x.id], [for (final x in movers) x.id], at, (id) => byId[id]!.sortOrder),
      );
    }
    // Let go where they were: nothing to do.
    if (orders.isEmpty && moving.every((t) => tasks.any((x) => x.id == t.id))) return;
    await repo.placeTasks(ids, sectionId, orders);
  }
}

/// A day of 今天 / 明天 / 最近7天: tasks dropped on it move there, each
/// keeping its time.
class DayDropGroup extends TaskDropGroup {
  const DayDropGroup(this.day);

  final DateTime day;

  @override
  bool get ordered => false;

  @override
  bool accepts(Task t) => _movable(t) && t.dueDate != dateKey(day);

  @override
  Future<void> drop(WidgetRef ref, DraggedTasks d, int index) async {
    final ids = [
      for (final t in d.all)
        if (accepts(t)) t.id,
    ];
    if (ids.isNotEmpty) await ref.read(repoProvider).moveAllTo(ids, day);
  }
}

/// The tasks being dragged and how big the row under the pointer is, so
/// drop targets can tell where its middle is.
final _dragging = ValueNotifier<({DraggedTasks drag, Size size})?>(null);

/// Scrolls the lists (and the board) around a dragged thing when it nears
/// their edges.
class _EdgeScroll {
  final _scrollers = <EdgeDraggingAutoScroller>[];

  void start(BuildContext context) {
    for (final axis in [Axis.vertical, Axis.horizontal]) {
      final scrollable = Scrollable.maybeOf(context, axis: axis);
      if (scrollable != null) {
        _scrollers.add(EdgeDraggingAutoScroller(scrollable, velocityScalar: 20));
      }
    }
  }

  void update(Offset globalPosition) {
    final rect = Rect.fromCenter(center: globalPosition, width: 48, height: 48);
    for (final s in _scrollers) {
      s.startAutoScrollIfNecessary(rect);
    }
  }

  void stop() {
    for (final s in _scrollers) {
      s.stopAutoScroll();
    }
    _scrollers.clear();
  }
}

/// Lets the person drag [child], the row or card of [task], to another
/// place; when [task] is one of the picked tasks ([picked], in the order
/// shown), they all go together. On a touch screen the drag starts with a
/// long press; letting go without moving opens the task's menu instead.
class TaskDraggable extends ConsumerStatefulWidget {
  const TaskDraggable({super.key, required this.task, required this.child, this.picked = const [], this.width});

  final Task task;
  final Widget child;

  /// The picked tasks that can be dragged, in the order shown.
  final List<Task> picked;

  /// The dragged copy's width; the row's own when null.
  final double? width;

  @override
  ConsumerState<TaskDraggable> createState() => _TaskDraggableState();
}

class _TaskDraggableState extends ConsumerState<TaskDraggable> {
  Offset? _startTopLeft;
  final _scroll = _EdgeScroll();

  DraggedTasks get _data => widget.picked.length > 1 && widget.picked.any((t) => t.id == widget.task.id)
      ? DraggedTasks(widget.task, widget.picked)
      : DraggedTasks(widget.task);

  void _started(DraggedTasks data) {
    final box = context.findRenderObject()! as RenderBox;
    _startTopLeft = box.localToGlobal(Offset.zero);
    _dragging.value = (drag: data, size: box.size);
    _scroll.start(context);
  }

  void _ended(Offset offset) {
    _scroll.stop();
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
    _scroll.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = _data;
    // Built once the drag has started, when the row's size is known.
    final feedback = ValueListenableBuilder(
      valueListenable: _dragging,
      builder: (context, dragging, child) {
        final card = Material(
          elevation: 6,
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: widget.width ?? dragging?.size.width ?? 320, child: child),
        );
        final count = dragging?.drag.count ?? 1;
        if (count < 2) return card;
        // Several: a card behind, and how many (on a Material, for its
        // text style).
        return Material(
          type: MaterialType.transparency,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: Transform.translate(
                offset: const Offset(6, 6),
                child: Material(
                  elevation: 2,
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            card,
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(11)),
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onPrimary)),
              ),
            ),
          ]),
        );
      },
      child: widget.child,
    );
    final dimmed = Opacity(opacity: 0.3, child: widget.child);
    // The other picked rows dim too while they're dragged along.
    final child = ValueListenableBuilder(
      valueListenable: _dragging,
      builder: (context, dragging, child) => Opacity(
        opacity: dragging != null && dragging.drag.count > 1 && dragging.drag.all.any((t) => t.id == widget.task.id)
            ? 0.3
            : 1,
        child: child,
      ),
      child: widget.child,
    );
    if (dragsOnLongPress(context)) {
      return LongPressDraggable<DraggedTasks>(
        data: data,
        feedback: feedback,
        childWhenDragging: dimmed,
        onDragStarted: () => _started(data),
        onDragUpdate: (d) => _scroll.update(d.globalPosition),
        onDragEnd: (d) => _ended(d.offset),
        child: child,
      );
    }
    return Draggable<DraggedTasks>(
      data: data,
      feedback: feedback,
      childWhenDragging: dimmed,
      onDragStarted: () => _started(data),
      onDragUpdate: (d) => _scroll.update(d.globalPosition),
      onDragEnd: (d) => _ended(d.offset),
      child: child,
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
    return DragTarget<DraggedTasks>(
      onWillAcceptWithDetails: (d) => widget.group.acceptsDrag(d.data),
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
    return DragTarget<DraggedTasks>(
      onWillAcceptWithDetails: (d) => group.acceptsDrag(d.data),
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
