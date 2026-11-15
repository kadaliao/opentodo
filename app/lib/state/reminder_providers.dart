import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show AppLifecycleListener;

import '../domain/reminders.dart';
import '../notify/reminder_backend.dart';
import '../notify/reminder_scheduler.dart';
import 'providers.dart';

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

/// Schedules reminders whenever tasks change, when the app comes back to
/// the foreground, and every so often as later reminders move into the
/// window the system holds. Its state: whether notifications are allowed
/// (null until there was a reminder to ask about).
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
    _backend.init((id) => ref.read(openTaskRequestProvider.notifier).open(id)).then(
      (launchedFrom) {
        if (!ref.mounted) return;
        if (launchedFrom != null) ref.read(openTaskRequestProvider.notifier).open(launchedFrom);
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
        await _scheduler.apply(upcomingReminders(tasks, DateTime.now()));
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
