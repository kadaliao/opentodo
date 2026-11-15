import '../domain/reminders.dart';
import 'reminder_backend.dart';

/// Keeps the system's pending notifications in line with the reminders the
/// tasks call for, touching only what changed. Delivered notifications are
/// left alone: cancelling one would also pull it out of the notification
/// centre.
class ReminderScheduler {
  ReminderScheduler(this.backend);

  final ReminderBackend backend;
  bool? _allowed;

  /// Whether the system lets the app show notifications; null until there
  /// has been something to ask about.
  bool? get allowed => _allowed;

  /// Asks again next time (the person may have changed it in Settings).
  void recheckPermission() {
    if (_allowed == false) _allowed = null;
  }

  Future<void> apply(List<ReminderEvent> events) async {
    if (events.isNotEmpty && _allowed == null) {
      _allowed = await backend.requestPermission();
    }
    final want = {for (final e in events) e.id: e};
    final keep = <int>{};
    for (final p in await backend.pending()) {
      final e = want[p.id];
      if (e != null && e.title == p.title && e.body == p.body) {
        keep.add(p.id);
      } else {
        await backend.cancel(p.id);
      }
    }
    for (final e in want.values) {
      if (!keep.contains(e.id)) await backend.schedule(e);
    }
  }
}
