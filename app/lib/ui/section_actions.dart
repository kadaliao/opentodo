import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/ordering.dart';
import '../state/providers.dart';
import 'dialogs.dart';
import 'task_drag.dart' show dragsOnLongPress;

/// Asks for a name and adds a section at the end of [listId]'s.
Future<void> addSection(BuildContext context, WidgetRef ref, String listId) async {
  final name = await promptName(context, title: '添加分组', hint: '分组名称，比如“进行中”');
  if (name == null) return;
  await ref.read(repoProvider).addSection(listId, name);
}

/// Moves [section] [delta] places among its list's sections.
Future<void> moveSection(WidgetRef ref, ListSection section, int delta) async {
  final sections = ref.read(sectionsByListProvider)[section.listId] ?? const <ListSection>[];
  final from = sections.indexWhere((s) => s.id == section.id);
  final to = from + delta;
  if (from < 0 || to < 0 || to >= sections.length) return;
  // The index counts the section still in place.
  await moveSectionTo(ref, section, delta > 0 ? to + 1 : to);
}

/// Puts [section] at [index] of its list's sections (counting it where it
/// is now), as dragging it there does.
Future<void> moveSectionTo(WidgetRef ref, ListSection section, int index) async {
  final sections = ref.read(sectionsByListProvider)[section.listId] ?? const <ListSection>[];
  final ids = [for (final s in sections) s.id];
  final from = ids.indexOf(section.id);
  if (from < 0 || index == from || index == from + 1) return;
  final byId = {for (final s in sections) s.id: s};
  final orders = planMove(ids, section.id, index, (id) => byId[id]!.sortOrder);
  final repo = ref.read(repoProvider);
  for (final e in orders.entries) {
    await repo.updateSection(e.key, sortOrder: e.value);
  }
}

/// The section header being dragged and how big it is.
final _draggingSection = ValueNotifier<Size?>(null);

/// Lets the person drag a section's header (a list's heading, a board
/// column's top) to move the section; after a long press on a touch
/// screen.
class SectionDraggable extends StatelessWidget {
  const SectionDraggable({super.key, required this.section, required this.child});

  final ListSection section;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final feedback = ValueListenableBuilder(
      valueListenable: _draggingSection,
      builder: (context, size, child) => Material(
        elevation: 6,
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: size?.width ?? 240, child: child),
      ),
      child: child,
    );
    void started() => _draggingSection.value = (context.findRenderObject()! as RenderBox).size;
    void ended(DraggableDetails _) => _draggingSection.value = null;
    final dimmed = Opacity(opacity: 0.3, child: child);
    if (dragsOnLongPress(context)) {
      return LongPressDraggable<ListSection>(
        data: section,
        feedback: feedback,
        childWhenDragging: dimmed,
        onDragStarted: started,
        onDragEnd: ended,
        child: child,
      );
    }
    return Draggable<ListSection>(
      data: section,
      feedback: feedback,
      childWhenDragging: dimmed,
      onDragStarted: started,
      onDragEnd: ended,
      child: child,
    );
  }
}

/// A section's header or column that takes another section of the list
/// dropped before or after it: above or below a header ([axis] vertical),
/// left or right of a column (horizontal). A line shows which.
class SectionDropTarget extends ConsumerStatefulWidget {
  const SectionDropTarget({super.key, required this.section, required this.child, this.axis = Axis.vertical});

  final ListSection section;
  final Widget child;
  final Axis axis;

  @override
  ConsumerState<SectionDropTarget> createState() => _SectionDropTargetState();
}

class _SectionDropTargetState extends ConsumerState<SectionDropTarget> {
  bool? _before;

  bool _isBefore(Offset feedbackTopLeft) {
    final box = context.findRenderObject()! as RenderBox;
    final size = _draggingSection.value ?? Size.zero;
    final local = box.globalToLocal(feedbackTopLeft);
    return widget.axis == Axis.vertical
        ? local.dy + size.height / 2 < box.size.height / 2
        : local.dx + size.width / 2 < box.size.width / 2;
  }

  /// Whether dropping [dragged] where the line would be leaves it where
  /// it is (right next to this one already): then no line.
  bool _wouldStay(ListSection? dragged) {
    final sections = ref.read(sectionsByListProvider)[widget.section.listId] ?? const <ListSection>[];
    final from = sections.indexWhere((s) => s.id == dragged?.id);
    final at = sections.indexWhere((s) => s.id == widget.section.id);
    final to = _before! ? at : at + 1;
    return from >= 0 && (to == from || to == from + 1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = BorderSide(color: scheme.primary, width: 2);
    return DragTarget<ListSection>(
      onWillAcceptWithDetails: (d) => d.data.listId == widget.section.listId && d.data.id != widget.section.id,
      onMove: (d) {
        final before = _isBefore(d.offset);
        if (before != _before) setState(() => _before = before);
      },
      onLeave: (_) => setState(() => _before = null),
      onAcceptWithDetails: (d) {
        final before = _isBefore(d.offset);
        setState(() => _before = null);
        final sections = ref.read(sectionsByListProvider)[widget.section.listId] ?? const <ListSection>[];
        final at = sections.indexWhere((s) => s.id == widget.section.id);
        if (at >= 0) moveSectionTo(ref, d.data, before ? at : at + 1);
      },
      // Same widgets around the child whether something hovers or not (see
      // TaskDropRow).
      builder: (context, candidates, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: candidates.isEmpty || _before == null || _wouldStay(candidates.first)
            ? const BoxDecoration()
            : BoxDecoration(
                border: widget.axis == Axis.vertical
                    ? (_before! ? Border(top: line) : Border(bottom: line))
                    : (_before! ? Border(left: line) : Border(right: line)),
              ),
        child: widget.child,
      ),
    );
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
