/// What the buttons on a reminder do. 完成 ticks the task off (a repeating
/// one moves on to its next date); 稍后提醒 brings the reminder back after the
/// snooze time set in 设置. Snoozes are kept on this device only.
library;

import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant, IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/db.dart';
import '../data/keys.dart';
import '../data/repo.dart';
import '../domain/reminders.dart';
import '../state/settings_providers.dart';
import 'reminder_backend.dart';
import 'reminder_scheduler.dart';

/// Reminders put off with 稍后提醒: when each task's comes back. Stored in
/// the local [KeyValues], so the app and a background isolate both see them.
class Snoozes {
  Snoozes(this.db);

  final AppDatabase db;

  Future<Map<String, DateTime>> load() async {
    final raw = await db.getValue(Keys.snoozes);
    if (raw == null) return {};
    try {
      return {
        for (final MapEntry(:key, :value) in (jsonDecode(raw) as Map<String, dynamic>).entries)
          if (value is int) key: DateTime.fromMillisecondsSinceEpoch(value),
      };
    } on Object {
      return {};
    }
  }

  Future<void> _save(Map<String, DateTime> snoozes) => db.setValue(
        Keys.snoozes,
        snoozes.isEmpty
            ? null
            : jsonEncode({for (final e in snoozes.entries) e.key: e.value.millisecondsSinceEpoch}),
      );

  Future<void> put(String taskId, DateTime at) async => _save({...await load(), taskId: at});

  Future<void> remove(String taskId) async {
    final all = await load();
    if (all.remove(taskId) != null) await _save(all);
  }

  /// The snoozes still to come; the ones that went off are dropped.
  Future<Map<String, DateTime>> upcoming(DateTime now) async {
    final all = await load();
    final ahead = {...all}..removeWhere((_, at) => !at.isAfter(now));
    if (ahead.length != all.length) await _save(ahead);
    return ahead;
  }
}

/// Carries out a button press. Opening a reminder is the app's business, not
/// this.
Future<void> applyReminderAction(
  TaskRepo repo,
  Snoozes snoozes,
  ReminderResponse r, {
  required DateTime now,
  required int snoozeMinutes,
}) async {
  switch (r.action) {
    case ReminderAction.done:
      final t = await repo.getTask(r.taskId);
      // It may have been finished or deleted elsewhere in the meantime.
      if (t != null && t.status == TaskStatus.open && t.trashedAt == null && t.deletedAt == null) {
        await repo.setCompleted(t.id, true);
      }
      await snoozes.remove(r.taskId);
    case ReminderAction.snooze:
      await snoozes.put(r.taskId, now.add(Duration(minutes: snoozeMinutes)));
    case ReminderAction.open:
      break;
  }
}

/// A response as a background isolate sends it to the app, and back.
List<String> encodeReminderResponse(ReminderResponse r) => [r.taskId, r.action.name];

ReminderResponse? decodeReminderResponse(Object? message) {
  if (message case [final String taskId, final String name]) {
    final action = ReminderAction.values.where((a) => a.name == name).firstOrNull;
    if (action != null) return (taskId: taskId, action: action);
  }
  return null;
}

/// A button pressed while the app isn't in charge (iOS and Android). With
/// the app running, it is passed on, so the screen follows; otherwise this
/// isolate acts on the database and reschedules on its own.
@pragma('vm:entry-point')
Future<void> reminderActionInBackground(NotificationResponse response) async {
  final r = reminderResponse(response);
  if (r == null || r.action == ReminderAction.open) return;
  final app = IsolateNameServer.lookupPortByName(reminderActionPortName);
  if (app != null) {
    app.send(encodeReminderResponse(r));
    return;
  }
  DartPluginRegistrant.ensureInitialized();
  final db = AppDatabase();
  try {
    await runReminderActionAlone(db, SystemReminderBackend(), r, DateTime.now());
  } catch (e) {
    debugPrint('reminder action failed: $e');
  } finally {
    await db.close();
  }
}

/// What a background isolate does with the app not running: the action,
/// then the system's reminders brought in line (the task's later ones go
/// when it's done; a snooze is handed over).
Future<void> runReminderActionAlone(
  AppDatabase db,
  ReminderBackend backend,
  ReminderResponse r,
  DateTime now,
) async {
  final settings = await loadSettings(db);
  final snoozes = Snoozes(db);
  await applyReminderAction(
    TaskRepo(db, clock: () => now, defaults: () => settings.defaults),
    snoozes,
    r,
    now: now,
    snoozeMinutes: settings.snoozeMinutes,
  );
  final tasks = await (db.select(db.tasks)..where((t) => t.deletedAt.isNull())).get();
  // Notifications are allowed: one of them was just pressed. Asking again
  // in the background could need a screen there isn't.
  await ReminderScheduler(backend, allowed: true)
      .apply(upcomingReminders(tasks, now, snoozed: await snoozes.upcoming(now)));
}
