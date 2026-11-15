import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/calendar.dart';
import '../../domain/dates.dart';
import '../../domain/views.dart';
import '../../state/calendar_providers.dart';
import '../../state/providers.dart';
import '../task_actions.dart';
import '../task_tile.dart';
import 'entry_chip.dart';

/// The month's days that have something on, one under another. In the
/// current month it starts at today: the agenda looks ahead.
class AgendaView extends ConsumerWidget {
  const AgendaView({super.key, required this.callbacks});

  final CalendarCallbacks callbacks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final range = ref.watch(calendarRangeProvider);
    final today = dateOnly(ref.watch(clockProvider));
    final from = dateKey(range.contains(today) ? today : range.start);
    final byDay = entriesByDay(ref.watch(calendarEntriesProvider(range)));
    final days = [for (final k in byDay.keys) if (k.compareTo(from) >= 0) k];

    if (days.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.event_note_outlined, size: 56, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text('这段时间没有安排', style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: days.length,
      separatorBuilder: (_, _) => const Divider(height: 17),
      itemBuilder: (context, i) {
        final date = parseDateKey(days[i]);
        final isToday = date == today;
        final color = isToday ? scheme.primary : scheme.onSurface;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 76,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => callbacks.showDay(date),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('${date.day}',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: color)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(weekdayName(date),
                        maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11, color: color)),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(
            child: Column(children: [
              for (final e in byDay[days[i]]!) _AgendaRow(key: ValueKey(e.key), entry: e, callbacks: callbacks),
            ]),
          ),
        ]);
      },
    );
  }
}

class _AgendaRow extends ConsumerWidget {
  const _AgendaRow({super.key, required this.entry, required this.callbacks});

  final CalendarEntry entry;
  final CalendarCallbacks callbacks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final task = entry.task;
    final faded = entry.done || entry.projected;
    final overdue = !entry.projected && isOverdue(task, ref.watch(clockProvider));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => callbacks.openTask(task.id),
      onSecondaryTapDown:
          entry.projected ? null : (d) => showTaskMenu(context, ref, task, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(children: [
          SizedBox(
            width: 52,
            child: Text(
              entry.allDay ? '全天' : clockLabel(entry.time!),
              style: TextStyle(fontSize: 12, color: overdue ? scheme.error : scheme.outline),
            ),
          ),
          SizedBox(
            width: 18,
            child: entry.projected
                ? Icon(Icons.repeat, size: 16, color: scheme.outline, semanticLabel: '重复')
                : PriorityCheckbox(
                    checked: entry.done,
                    priority: task.priority,
                    onChanged: (v) => setTaskDone(context, ref, task, v),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              task.title.isEmpty ? '无标题' : task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: faded ? scheme.outline : scheme.onSurface,
                decoration: entry.done ? TextDecoration.lineThrough : null,
                decorationColor: scheme.outline,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(listName(task.listId, ref.watch(listsByIdProvider)),
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ),
        ]),
      ),
    );
  }
}
