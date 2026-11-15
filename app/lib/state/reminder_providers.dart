import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show AppLifecycleListener;

import '../data/keys.dart';
import '../domain/reminders.dart';
import '../notify/reminder_actions.dart';
import '../notify/reminder_backend.dart';
import '../notify/reminder_scheduler.dart';
import 'providers.dart';
import 'settings_providers.dart';

final reminderBackendProvider = Provider<ReminderBackend>((ref) => platformReminderBackend());

/// A task the person opened from a notification, waiting for the home
/// screen to show it.
class OpenTaskRequest extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String taskId) => state = taskId;
  void clear() => state = null;
}

final openTaskRequestProvider = NotifierProvider<OpenTaskRequest, String?>(OpenTaskRequest.new);

/// Bumped when the notifications handed to the system change shape, so the
/// ones already there are replaced: 2 added the 完成 and 稍后提醒 buttons.
const _reminderFormat = '2';

/// Schedules reminders whenever tasks change, when the app comes back to
/// the foreground, and every so often as later reminders move into the
/// window the system holds; carries out what the person does with a
/// notification. Its state: whether notifications are allowed (null until
/// there was a reminder to ask about).
class ReminderController extends Notifier<bool?> {
  static const debounce = Duration(milliseconds: 500);
  static const refresh = Duration(minutes: 15);

  late ReminderBackend _backend;
  late ReminderScheduler _scheduler;
  Timer? _debounce;
  bool _ready = false;
  bool _running = false;
  bool _again = false;

  @override
  bool? build() {
    _backend = ref.watch(reminderBackendProvider);
    _scheduler = ReminderScheduler(_backend);
    _ready = false;
    _backend.init(_respond).then(
      (launchedFrom) {
        if (!ref.mounted) return;
        if (launchedFrom != null) _respond(launchedFrom);
        _ready = true;
        _kick();
      },
      onError: (Object e) => debugPrint('reminders unavailable: $e'),
    );
    ref.listen(tasksProvider, (_, _) => _kick());
    final periodic = Timer.periodic(refresh, (_) => _kick());
    final lifecycle = AppLifecycleListener(onResume: () {
      _scheduler.recheckPermission();
      _kick();
    });
    ref.onDispose(() {
      periodic.cancel();
      lifecycle.dispose();
      _debounce?.cancel();
    });
    return null;
  }

  void _kick() {
    _debounce?.cancel();
    _debounce = Timer(debounce, _run);
  }

  /// A notification clicked (show its task) or one of its buttons pressed.
  void _respond(ReminderResponse r) {
    if (!ref.mounted) return;
    if (r.action == ReminderAction.open) {
      ref.read(openTaskRequestProvider.notifier).open(r.taskId);
      return;
    }
    applyReminderAction(
      ref.read(repoProvider),
      Snoozes(ref.read(databaseProvider)),
      r,
      now: DateTime.now(),
      snoozeMinutes: ref.read(settingsProvider).snoozeMinutes,
    ).then((_) {
      // A finished task reschedules as the tasks change; a snooze doesn't.
      if (ref.mounted) _kick();
    }, onError: (Object e) => debugPrint('reminder action failed: $e'));
  }

  Future<void> _run() async {
    if (!_ready || !ref.mounted) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final tasks = ref.read(tasksProvider).value;
        if (tasks == null) break;
        final db = ref.read(databaseProvider);
        final now = DateTime.now();
        // Snoozes may also come from a button pressed in the background.
        final snoozed = await Snoozes(db).upcoming(now);
        final replaceAll = await db.getValue(Keys.reminderFormat) != _reminderFormat;
        await _scheduler.apply(upcomingReminders(tasks, now, snoozed: snoozed), replaceAll: replaceAll);
        if (replaceAll) await db.setValue(Keys.reminderFormat, _reminderFormat);
        if (ref.mounted) state = _scheduler.allowed;
      } while (_again && ref.mounted);
    } catch (e) {
      debugPrint('scheduling reminders failed: $e');
    } finally {
      _running = false;
    }
  }

  /// For the 去开启 button: the system settings, where a refusal is undone.
  Future<void> openSettings() => _backend.openSettings();
}

final reminderControllerProvider =
    NotifierProvider<ReminderController, bool?>(ReminderController.new);
