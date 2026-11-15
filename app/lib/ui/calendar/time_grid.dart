import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/calendar.dart';
import '../../domain/dates.dart';
import '../../state/calendar_providers.dart';
import '../../state/providers.dart';
import 'entry_chip.dart';

const hourHeight = 48.0;
const _gutterWidth = 52.0;
const _chipHeight = 20.0;
const _gap = 2.0;

/// Days side by side over the hours: the day, 3-day and week views.
/// All-day tasks sit in a strip on top. Tasks drag to another day or time
/// (snapping to 15 minutes) or into the strip, and their bottom edge drags
/// to set when they end; a click on an empty hour adds a task there.
class TimeGrid extends ConsumerStatefulWidget {
  const TimeGrid({super.key, required this.callbacks});

  final CalendarCallbacks callbacks;

  @override
  ConsumerState<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends ConsumerState<TimeGrid> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Open on the hours that matter: two hours before now when today is on
    // screen, otherwise the morning.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final now = DateTime.now();
      final range = ref.read(calendarRangeProvider);
      final minute = range.contains(dateOnly(now)) ? now.hour * 60 + now.minute - 120 : 7 * 60;
      _scroll.jumpTo((minute / 60 * hourHeight).clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final range = ref.watch(calendarRangeProvider);
    final byDay = entriesByDay(ref.watch(calendarEntriesProvider(range)));
    final today = dateOnly(ref.watch(clockProvider));
    final days = range.days;
    List<CalendarEntry> on(DateTime d) => byDay[dateKey(d)] ?? const [];
    final lineColor = scheme.outlineVariant.withValues(alpha: 0.6);

    return Column(children: [
      // Day headings.
      SizedBox(
        height: 44,
        child: Row(children: [
          const SizedBox(width: _gutterWidth),
          for (final d in days)
            Expanded(
              child: _DayHeading(
                date: d,
                isToday: d == today,
                showNote: ref.watch(calendarPrefsProvider.select((p) => p.showLunar)),
                onTap: days.length > 1 ? () => widget.callbacks.showDay(d) : null,
              ),
            ),
        ]),
      ),
      // All-day strip.
      _AllDayStrip(days: days, on: on, callbacks: widget.callbacks, lineColor: lineColor),
      Divider(height: 1, color: scheme.outlineVariant),
      Expanded(
        child: SingleChildScrollView(
          controller: _scroll,
          child: SizedBox(
            height: 24 * hourHeight,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _HourGutter(),
              for (final d in days)
                Expanded(
                  child: _DayColumn(
                    key: ValueKey(dateKey(d)),
                    date: d,
                    placements: layoutTimed(on(d)),
                    isToday: d == today,
                    callbacks: widget.callbacks,
                    lineColor: lineColor,
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.date, required this.isToday, this.showNote = false, this.onTap});

  final DateTime date;
  final bool isToday;

  /// The lunar day or festival, and 休 or 班.
  final bool showNote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(weekdayName(date), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(width: 6),
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isToday ? scheme.primary : null,
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isToday ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
        if (showNote) ...[
          const SizedBox(width: 4),
          Flexible(child: DayNoteLabel(date: date)),
        ],
      ]),
    );
  }
}

class _AllDayStrip extends ConsumerWidget {
  const _AllDayStrip({
    required this.days,
    required this.on,
    required this.callbacks,
    required this.lineColor,
  });

  final List<DateTime> days;
  final List<CalendarEntry> Function(DateTime) on;
  final CalendarCallbacks callbacks;
  final Color lineColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final maxRows = days.length == 1 ? 6 : 3;
    final busiest = days.map((d) => on(d).where((e) => e.allDay).length).fold(0, math.max);
    final rows = busiest.clamp(1, maxRows);
    final height = rows * (_chipHeight + _gap) + 6;

    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: _gutterWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Text('全天',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ),
        ),
        for (final d in days)
          Expanded(
            child: DragTarget<CalendarDrag>(
              onAcceptWithDetails: (det) {
                if (!droppedInPlace(det.offset)) ref.read(repoProvider).moveAll(det.data.to(d, allDay: true));
              },
              builder: (context, candidates, _) => LayoutBuilder(builder: (context, c) {
                final entries = on(d).where((e) => e.allDay).toList();
                final overflow = entries.length > maxRows;
                final shown = overflow ? maxRows - 1 : entries.length;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => callbacks.newTask(d, null),
                  child: Container(
                    decoration: BoxDecoration(
                      color: candidates.isNotEmpty ? scheme.primary.withValues(alpha: 0.10) : null,
                      border: Border(left: BorderSide(color: lineColor, width: 0.5)),
                    ),
                    padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final e in entries.take(shown))
                        Padding(
                          padding: const EdgeInsets.only(bottom: _gap),
                          child: EntryDraggable(
                            entry: e,
                            size: Size(c.maxWidth - 4, _chipHeight),
                            child: EntryChip(entry: e, onOpen: callbacks.openTask, showTime: false),
                          ),
                        ),
                      if (overflow)
                        MoreEntries(count: entries.length - shown, onTap: () => callbacks.showDay(d)),
                    ]),
                  ),
                );
              }),
            ),
          ),
      ]),
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline);
    return SizedBox(
      width: _gutterWidth,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var h = 1; h < 24; h++)
          Positioned(
            top: h * hourHeight - 7,
            right: 8,
            child: Text(clockLabel(h * 60), style: style),
          ),
      ]),
    );
  }
}

class _DayColumn extends ConsumerStatefulWidget {
  const _DayColumn({
    super.key,
    required this.date,
    required this.placements,
    required this.isToday,
    required this.callbacks,
    required this.lineColor,
  });

  final DateTime date;
  final List<TimedPlacement> placements;
  final bool isToday;
  final CalendarCallbacks callbacks;
  final Color lineColor;

  @override
  ConsumerState<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends ConsumerState<_DayColumn> {
  final _stackKey = GlobalKey();

  /// Where a dragged task would land, for how many minutes it shows and
  /// how many go with it, while it hovers over this day.
  ({int minute, int length, int count})? _hover;

  /// The end a task's bottom edge is being dragged to: the entry's key and
  /// the minute.
  (String, int)? _resize;

  /// How much of a dragged entry shows from where it's dropped: a span's
  /// length, half an hour for the rest.
  static int _lengthOf(CalendarEntry e) =>
      e.allDay || e.endTime == null ? 30 : e.endTime! - e.time!;

  /// The minute under the top of a dragged task, [globalTop] being where
  /// that top is on screen.
  int _minuteAt(Offset globalTop) {
    final box = _stackKey.currentContext!.findRenderObject()! as RenderBox;
    return snapMinutes(box.globalToLocal(globalTop).dy / hourHeight * 60);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(clockProvider);
    double y(int minute) => minute / 60 * hourHeight;

    return DragTarget<CalendarDrag>(
      onMove: (d) {
        final h = (minute: _minuteAt(d.offset), length: _lengthOf(d.data.lead), count: d.data.count);
        if (h != _hover) setState(() => _hover = h);
      },
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) {
        setState(() => _hover = null);
        if (droppedInPlace(d.offset)) return;
        ref.read(repoProvider).moveAll(d.data.to(widget.date, minute: _minuteAt(d.offset)));
      },
      builder: (context, _, _) => LayoutBuilder(builder: (context, c) {
        final width = c.maxWidth;
        return Stack(key: _stackKey, clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => widget.callbacks.newTask(
                widget.date,
                snapMinutes(d.localPosition.dy / hourHeight * 60, step: 30),
              ),
              child: CustomPaint(
                painter: _HourLines(color: widget.lineColor),
                child: widget.isToday
                    ? ColoredBox(color: scheme.primaryContainer.withValues(alpha: 0.08))
                    : null,
              ),
            ),
          ),
          for (final p in widget.placements)
            ...() {
              final resizing = _resize?.$1 == p.entry.key ? _resize!.$2 : null;
              final end = resizing ?? p.end;
              final h = math.max(y(end - p.start), _chipHeight) - 1;
              final w = width / p.columns - 3;
              // A task late at night stays inside the day.
              final top = math.min(y(p.start), 24 * hourHeight - h - 1);
              final left = width * p.column / p.columns + 1;
              return [
                Positioned(
                  top: top,
                  height: h,
                  left: left,
                  width: w,
                  child: EntryDraggable(
                    entry: p.entry,
                    size: Size(w, h),
                    child: EntryChip(
                      entry: p.entry,
                      onOpen: widget.callbacks.openTask,
                      height: h,
                      showTime: false,
                      endLabel: resizing == null ? null : clockLabel(resizing),
                    ),
                  ),
                ),
                // The bottom edge sets the end; a span that runs on into the
                // next day ends there, not here.
                if (canMoveEntry(p.entry) && (p.entry.endTime ?? 0) < minutesPerDay)
                  Positioned(
                    top: top + h - 5,
                    height: 8,
                    left: left,
                    width: w,
                    child: _ResizeHandle(
                      onStart: () => setState(() => _resize = (p.entry.key, p.end)),
                      onUpdate: (total) {
                        final m = (p.end + (total / hourHeight * 60 / 15).round() * 15)
                            .clamp(p.start + 15, minutesPerDay);
                        if (_resize?.$2 != m) setState(() => _resize = (p.entry.key, m));
                      },
                      onEnd: () {
                        final m = _resize?.$2;
                        setState(() => _resize = null);
                        if (m == null || m == p.end) return;
                        final e = p.entry;
                        ref.read(repoProvider).setDuration(
                              e.task.id,
                              e.dayIndex * minutesPerDay + m - e.task.dueTime!,
                            );
                      },
                    ),
                  ),
              ];
            }(),
          if (_hover case (:final minute, :final length, :final count))
            Positioned(
              top: y(minute),
              height: y(math.min(length, minutesPerDay - minute)),
              left: 1,
              right: 2,
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    border: Border.all(color: scheme.primary),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(count > 1 ? '${clockLabel(minute)} · $count 项' : clockLabel(minute),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(fontSize: 10, color: scheme.primary, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          if (widget.isToday)
            Positioned(
              top: y(now.hour * 60 + now.minute) - 4,
              left: -4,
              right: 0,
              height: 8,
              child: IgnorePointer(
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                  ),
                  Expanded(child: Container(height: 1.5, color: scheme.error)),
                ]),
              ),
            ),
        ]);
      }),
    );
  }
}

/// The strip along the bottom of a task on the hour grid that drags its
/// end up or down. [onUpdate] gets how far it has moved in all, in pixels.
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onStart, required this.onUpdate, required this.onEnd});

  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  double _startY = 0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: Semantics(
        label: '拖动改结束时间',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // From where the pointer went down, so the end keeps up with it.
          dragStartBehavior: DragStartBehavior.down,
          onVerticalDragStart: (d) {
            _startY = d.globalPosition.dy;
            widget.onStart();
          },
          onVerticalDragUpdate: (d) => widget.onUpdate(d.globalPosition.dy - _startY),
          onVerticalDragEnd: (_) => widget.onEnd(),
          onVerticalDragCancel: widget.onEnd,
        ),
      ),
    );
  }
}

class _HourLines extends CustomPainter {
  const _HourLines({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
    for (var h = 1; h < 24; h++) {
      final y = h * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_HourLines old) => old.color != color;
}
