/// When a task's reminders go off, and what they are called.
///
/// A reminder is stored as minutes relative to the task's due moment: its
/// due time, or the midnight that starts its day for an all-day task.
/// Negative means before, as in iCalendar's TRIGGER, so 0 is 准时, -30 is
/// 提前30分钟, and for an all-day task 540 is 当天 09:00 and -900 is
/// 提前1天 09:00. Like task dates, reminders float with the device's clock.
library;

import '../data/db.dart';
import 'dates.dart';

/// Offered for a task with a time: 准时, 提前5分钟, 30分钟, 1小时, 1天.
const timedReminderPresets = [0, -5, -30, -60, -1440];

/// Offered for an all-day task: 当天 / 提前1天 / 提前2天 / 提前1周, at 09:00.
const allDayReminderPresets = [540, -900, -2340, -9540];

/// The moment a reminder goes off, in local time.
DateTime reminderTime(String dueDate, int? dueTime, int offset) {
  final d = parseDateKey(dueDate);
  // Wall-clock arithmetic, so 提前1天 stays at the same time across DST.
  return DateTime(d.year, d.month, d.day, 0, (dueTime ?? 0) + offset);
}

String _span(int minutes) {
  if (minutes % 10080 == 0) return '${minutes ~/ 10080}周';
  final d = minutes ~/ 1440, h = minutes % 1440 ~/ 60, m = minutes % 60;
  return [
    if (d > 0) '$d天',
    if (h > 0) '$h小时',
    if (m > 0) '$m分钟',
  ].join();
}

String _clock(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

/// 准时 / 提前30分钟 / 提前1天 for a timed task; 当天 09:00 / 提前1天 09:00 for
/// an all-day one.
String reminderLabel(int offset, {required bool allDay}) {
  if (allDay) {
    final days = (offset / 1440).floor();
    final at = _clock(offset - days * 1440);
    if (days == 0) return '当天 $at';
    if (days < 0) return '提前${_span(-days * 1440)} $at';
    return '$days天后 $at';
  }
  if (offset == 0) return '准时';
  return offset < 0 ? '提前${_span(-offset)}' : '延后${_span(offset)}';
}

/// Reminders in the order they go off.
List<int> sortedReminders(Iterable<int> offsets) => offsets.toSet().toList()..sort();

/// The reminders, in words, for the detail view.
String remindersSummary(List<int> offsets, {required bool allDay}) =>
    sortedReminders(offsets).map((o) => reminderLabel(o, allDay: allDay)).join('、');

/// A reminder to hand to the system.
class ReminderEvent {
  const ReminderEvent({
    required this.taskId,
    required this.at,
    required this.title,
    required this.body,
  });

  final String taskId;
  final DateTime at;
  final String title;
  final String body;

  /// Stable for the same task and minute, so rescheduling the same reminder
  /// leaves the system's copy alone.
  int get id => notificationId(taskId, at);

  @override
  String toString() => 'ReminderEvent($taskId @ $at: $title / $body)';
}

/// FNV-1a over the task id and minute, cut to 31 bits (Android wants a
/// positive 32-bit int).
int notificationId(String taskId, DateTime at) {
  var h = 0x811c9dc5;
  for (final c in '$taskId@${at.millisecondsSinceEpoch ~/ 60000}'.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// The system keeps only so many pending notifications (iOS and macOS: 64),
/// so only the soonest are handed over; the rest follow as these fire and
/// the app reschedules.
const maxScheduledReminders = 48;

/// The reminders still to come for open tasks, soonest first.
List<ReminderEvent> upcomingReminders(
  Iterable<Task> tasks,
  DateTime now, {
  int limit = maxScheduledReminders,
}) {
  final out = <ReminderEvent>[];
  for (final t in tasks) {
    final due = t.dueDate;
    if (due == null || t.reminders.isEmpty) continue;
    if (t.status != TaskStatus.open || t.trashedAt != null || t.deletedAt != null) continue;
    for (final offset in t.reminders.toSet()) {
      final at = reminderTime(due, t.dueTime, offset);
      if (!at.isAfter(now)) continue;
      out.add(ReminderEvent(
        taskId: t.id,
        at: at,
        title: t.title.trim().isEmpty ? '无标题' : t.title.trim(),
        body: _body(t, dateOnly(at)),
      ));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// 今天, 下午3:00 · 带上电脑. Worded for the day the reminder shows up.
String _body(Task t, DateTime onDay) {
  final when = fullDueLabel(t.dueDate!, t.dueTime, onDay, duration: t.duration);
  final note = t.content.trim().split('\n').first.trim();
  if (note.isEmpty) return when;
  return '$when · ${note.length > 60 ? '${note.substring(0, 60)}…' : note}';
}
