import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/calendar.dart';
import '../../domain/dates.dart';
import '../../state/calendar_providers.dart';
import '../../state/providers.dart';
import '../task_tile.dart';
import 'entry_chip.dart';

const _shortWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// The month as a board of days, each listing its tasks; for a window wide
/// enough to read them. Tasks drag between days; a click on a day's empty
/// space adds one there.
class MonthBoard extends ConsumerWidget {
  const MonthBoard({super.key, required this.callbacks});

  final CalendarCallbacks callbacks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final anchor = ref.watch(calendarAnchorProvider);
    final range = monthGrid(anchor.year, anchor.month);
    final byDay = entriesByDay(ref.watch(calendarEntriesProvider(range)));
    final today = dateOnly(ref.watch(clockProvider));
    final days = range.days;

    return Column(children: [
      SizedBox(
        height: 28,
        child: Row(children: [
          for (final name in weekdayNames)
            Expanded(
              child: Center(
                child: Text(name, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            ),
        ]),
      ),
      Divider(height: 1, color: scheme.outlineVariant),
      Expanded(
        child: Column(children: [
          for (var w = 0; w < days.length ~/ 7; w++)
            Expanded(
              child: Row(children: [
                for (final d in days.sublist(w * 7, w * 7 + 7))
                  Expanded(
                    child: _DayCell(
                      date: d,
                      inMonth: d.month == anchor.month,
                      isToday: d == today,
                      entries: byDay[dateKey(d)] ?? const [],
                      callbacks: callbacks,
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.entries,
    required this.callbacks,
  });

  final DateTime date;
  final bool inMonth;
  final bool isToday;
  final List<CalendarEntry> entries;
  final CalendarCallbacks callbacks;

  static const _headerHeight = 28.0;
  static const _chipHeight = 20.0;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final border = BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6), width: 0.5);
    return DragTarget<CalendarEntry>(
      onWillAcceptWithDetails: (d) => canMoveEntry(d.data),
      onAcceptWithDetails: (d) =>
          ref.read(repoProvider).moveTo(d.data.task.id, date, d.data.task.dueTime),
      builder: (context, candidates, _) => LayoutBuilder(builder: (context, c) {
        final room = math.max(0, ((c.maxHeight - _headerHeight - 4) / (_chipHeight + _gap)).floor());
        final overflow = entries.length > room;
        final shown = overflow ? math.max(0, room - 1) : entries.length;
        final Color? background = candidates.isNotEmpty
            ? scheme.primary.withValues(alpha: 0.10)
            : isToday
                ? scheme.primaryContainer.withValues(alpha: 0.18)
                : (inMonth ? null : scheme.surfaceContainerLow);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => callbacks.newTask(date, null),
          child: Container(
            decoration: BoxDecoration(
              color: background,
              border: Border(right: border, bottom: border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: _headerHeight, child: _dayNumber(scheme)),
              for (final e in entries.take(shown))
                Padding(
                  padding: const EdgeInsets.only(bottom: _gap),
                  child: EntryDraggable(
                    entry: e,
                    size: Size(c.maxWidth - 6, _chipHeight),
                    child: EntryChip(entry: e, onOpen: callbacks.openTask),
                  ),
                ),
              if (overflow)
                MoreEntries(
                  count: entries.length - shown,
                  onTap: () => callbacks.showDay(date),
                ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _dayNumber(ColorScheme scheme) {
    final label = date.day == 1 ? '${date.month}月1日' : '${date.day}';
    final color = inMonth ? scheme.onSurface : scheme.outline;
    return Align(
      alignment: Alignment.centerLeft,
      child: isToday
          ? DecoratedBox(
              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(11)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text(label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onPrimary)),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(label, style: TextStyle(fontSize: 12, color: color)),
            ),
    );
  }
}

/// A small month of day numbers, dotted where there are tasks: the phone's
/// month view and the sidebar's date picker.
class MiniMonth extends StatelessWidget {
  const MiniMonth({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.marked,
    required this.onTap,
    this.rowHeight = 40,
  });

  /// Any day of the month to show.
  final DateTime month;
  final DateTime selected;
  final DateTime today;

  /// Days (`YYYY-MM-DD`) with something on them.
  final Set<String> marked;
  final ValueChanged<DateTime> onTap;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = monthGrid(month.year, month.month).days;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 24,
        child: Row(children: [
          for (final d in _shortWeekdays)
            Expanded(
              child: Center(child: Text(d, style: TextStyle(fontSize: 11, color: scheme.outline))),
            ),
        ]),
      ),
      for (var w = 0; w < days.length ~/ 7; w++)
        SizedBox(
          height: rowHeight,
          child: Row(children: [
            for (final d in days.sublist(w * 7, w * 7 + 7))
              Expanded(child: _miniDay(d, scheme)),
          ]),
        ),
    ]);
  }

  Widget _miniDay(DateTime d, ColorScheme scheme) {
    final isSelected = d == selected;
    final isToday = d == today;
    final inMonth = d.month == month.month;
    final size = math.min(28.0, rowHeight - 8);
    return InkResponse(
      onTap: () => onTap(d),
      radius: size / 2 + 2,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? scheme.primary
                : (isToday ? scheme.primaryContainer : null),
          ),
          child: Text(
            '${d.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday || isSelected ? FontWeight.w600 : null,
              color: isSelected
                  ? scheme.onPrimary
                  : isToday
                      ? scheme.onPrimaryContainer
                      : (inMonth ? scheme.onSurface : scheme.outlineVariant),
            ),
          ),
        ),
        SizedBox(
          height: 6,
          child: marked.contains(dateKey(d))
              ? Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: inMonth ? scheme.primary : scheme.outlineVariant,
                    ),
                  ),
                )
              : null,
        ),
      ]),
    );
  }
}

/// The phone's month: a small month to pick a day from, that day's tasks
/// below. Swiping the month sideways turns the page.
class PhoneMonth extends ConsumerWidget {
  const PhoneMonth({super.key, required this.callbacks});

  final CalendarCallbacks callbacks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(calendarAnchorProvider);
    final today = dateOnly(ref.watch(clockProvider));
    final range = monthGrid(anchor.year, anchor.month);
    final byDay = entriesByDay(ref.watch(calendarEntriesProvider(range)));
    final anchorNotifier = ref.read(calendarAnchorProvider.notifier);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 200) anchorNotifier.page(v < 0 ? 1 : -1);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: MiniMonth(
            month: anchor,
            selected: anchor,
            today: today,
            marked: byDay.keys.toSet(),
            onTap: anchorNotifier.go,
            rowHeight: 44,
          ),
        ),
      ),
      const Divider(height: 16),
      Expanded(
        child: DayTaskList(
          date: anchor,
          entries: byDay[dateKey(anchor)] ?? const [],
          callbacks: callbacks,
        ),
      ),
    ]);
  }
}

/// One day's tasks as list rows, under a heading.
class DayTaskList extends ConsumerWidget {
  const DayTaskList({
    super.key,
    required this.date,
    required this.entries,
    required this.callbacks,
  });

  final DateTime date;
  final List<CalendarEntry> entries;
  final CalendarCallbacks callbacks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final today = dateOnly(ref.watch(clockProvider));
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Text(daySectionTitle(date, today),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              Icon(Icons.event_available_outlined, size: 40, color: scheme.outlineVariant),
              const SizedBox(height: 8),
              Text('这天没有任务', style: TextStyle(color: scheme.onSurfaceVariant)),
            ]),
          ),
        for (final e in entries)
          e.projected
              ? ProjectedTile(key: ValueKey(e.key), entry: e, onOpen: callbacks.openTask)
              : TaskTile(key: ValueKey(e.key), task: e.task, onOpen: callbacks.openTask, showList: true),
      ],
    );
  }
}

/// A later date of a repeating task in a list: faded, opens the task.
class ProjectedTile extends StatelessWidget {
  const ProjectedTile({super.key, required this.entry, required this.onOpen});

  final CalendarEntry entry;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = entry.task;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onOpen(t.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(children: [
          SizedBox(
            width: 18,
            child: Icon(Icons.repeat, size: 16, color: scheme.outline, semanticLabel: '重复'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(t.title.isEmpty ? '无标题' : t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
          ),
          if (t.dueTime != null)
            Text(timeLabel(t.dueTime!), style: TextStyle(fontSize: 12, color: scheme.outline)),
        ]),
      ),
    );
  }
}
