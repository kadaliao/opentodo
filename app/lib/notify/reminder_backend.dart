/// Hands reminders to the operating system.
///
/// On iOS, macOS and Android the system holds scheduled notifications and
/// shows them even when the app isn't running. Windows and Linux have no
/// scheduler the plugin can use, so there reminders go off from timers while
/// the app is open.
///
/// Reminders carry two buttons, 完成 and 稍后提醒 (`reminder_actions.dart`).
/// macOS and Linux hand a press to the running app, starting it if need be;
/// iOS and Android to a background isolate ([reminderActionInBackground]),
/// which passes it on to the app when the app is running.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminders.dart';
import 'reminder_actions.dart';

/// A notification the system is holding for later.
typedef PendingReminder = ({int id, String? title, String? body});

/// What the person did with a reminder: opened it, or pressed a button.
enum ReminderAction { open, done, snooze }

/// A reminder the person responded to.
typedef ReminderResponse = ({String taskId, ReminderAction action});

const doneActionId = 'done';
const snoozeActionId = 'snooze';

/// The task and button of a plugin response; null if it isn't a reminder.
ReminderResponse? reminderResponse(NotificationResponse r) {
  final taskId = r.payload;
  if (taskId == null || taskId.isEmpty) return null;
  final action = switch (r.actionId) {
    doneActionId => ReminderAction.done,
    snoozeActionId => ReminderAction.snooze,
    // A click on the notification itself (Linux names it `default`).
    _ => ReminderAction.open,
  };
  return (taskId: taskId, action: action);
}

/// Where a background isolate finds the app, when it is running, to pass a
/// button press on to.
const reminderActionPortName = 'opentodo.reminderActions';

abstract class ReminderBackend {
  /// Sets up the system side; [onResponse] gets the notifications the
  /// person clicks or presses a button on. Returns the one the app was
  /// launched from, if any.
  Future<ReminderResponse?> init(void Function(ReminderResponse r) onResponse);

  /// Asks for permission the first time; later calls just report it.
  Future<bool> requestPermission();

  Future<List<PendingReminder>> pending();
  Future<void> schedule(ReminderEvent e);
  Future<void> cancel(int id);

  /// Opens the system's notification settings for the app.
  Future<void> openSettings();
}

/// Does nothing: tests and platforms without notifications.
class NoReminderBackend implements ReminderBackend {
  const NoReminderBackend();

  @override
  Future<ReminderResponse?> init(void Function(ReminderResponse r) onResponse) async => null;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<List<PendingReminder>> pending() async => const [];
  @override
  Future<void> schedule(ReminderEvent e) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> openSettings() async {}
}

/// The backend for the platform the app is running on.
ReminderBackend platformReminderBackend() {
  if (kIsWeb) return const NoReminderBackend();
  // Widget tests run on the host OS but without its plugins.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return const NoReminderBackend();
  if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
    return SystemReminderBackend();
  }
  if (Platform.isWindows || Platform.isLinux) return TimerReminderBackend();
  return const NoReminderBackend();
}

/// The buttons on Apple's platforms come with a category set up once.
const _category = 'reminder';

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'reminders',
    '任务提醒',
    channelDescription: '任务到了提醒时间',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    actions: [
      AndroidNotificationAction(doneActionId, '完成'),
      AndroidNotificationAction(snoozeActionId, '稍后提醒'),
    ],
  ),
  iOS: DarwinNotificationDetails(threadIdentifier: 'reminders', categoryIdentifier: _category),
  macOS: DarwinNotificationDetails(threadIdentifier: 'reminders', categoryIdentifier: _category),
  linux: LinuxNotificationDetails(
    category: LinuxNotificationCategory.imReceived,
    actions: [
      LinuxNotificationAction(key: doneActionId, label: '完成'),
      LinuxNotificationAction(key: snoozeActionId, label: '稍后提醒'),
    ],
  ),
);

final _darwin = DarwinInitializationSettings(
  // Asked for later, when there's a reminder to show, not at first launch.
  requestAlertPermission: false,
  requestBadgePermission: false,
  requestSoundPermission: false,
  notificationCategories: [
    DarwinNotificationCategory(_category, actions: [
      DarwinNotificationAction.plain(doneActionId, '完成'),
      DarwinNotificationAction.plain(snoozeActionId, '稍后提醒'),
    ]),
  ],
);

final _settings = InitializationSettings(
  android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
  iOS: _darwin,
  macOS: _darwin,
  linux: const LinuxInitializationSettings(defaultActionName: '打开'),
  windows: const WindowsInitializationSettings(
    appName: 'OpenTodo',
    appUserModelId: 'com.liaoxingyi.opentodo',
    guid: '6b0c7f0e-5d55-4f5e-9a3c-2f1f5b6f8a41',
  ),
);

/// Scheduled by the system (iOS, macOS, Android).
class SystemReminderBackend implements ReminderBackend {
  SystemReminderBackend([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _exact = false;
  ReceivePort? _port;

  @override
  Future<ReminderResponse?> init(void Function(ReminderResponse r) onResponse) async {
    // Button presses handled in the background come here while the app runs.
    _port?.close();
    final port = _port = ReceivePort();
    port.listen((m) {
      if (decodeReminderResponse(m) case final r?) onResponse(r);
    });
    IsolateNameServer.removePortNameMapping(reminderActionPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, reminderActionPortName);

    await _plugin.initialize(
      settings: _settings,
      onDidReceiveNotificationResponse: (r) {
        if (reminderResponse(r) case final response?) onResponse(response);
      },
      onDidReceiveBackgroundNotificationResponse: reminderActionInBackground,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.didNotificationLaunchApp == true ? launch!.notificationResponse : null;
    return response == null ? null : reminderResponse(response);
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isMacOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isAndroid) {
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final allowed = await android?.requestNotificationsPermission() ?? false;
      // Exact alarms need a separate grant on Android 14+; without it the
      // reminder still comes, possibly a few minutes late.
      _exact = await android?.canScheduleExactNotifications() ?? false;
      return allowed;
    }
    return true;
  }

  @override
  Future<List<PendingReminder>> pending() async => [
        for (final p in await _plugin.pendingNotificationRequests())
          (id: p.id, title: p.title, body: p.body),
      ];

  @override
  Future<void> schedule(ReminderEvent e) => _plugin.zonedSchedule(
        id: e.id,
        title: e.title,
        body: e.body,
        payload: e.taskId,
        // The moment, not the wall-clock time: reminders float with the
        // device's clock, and the app reschedules when it comes back.
        scheduledDate: tz.TZDateTime.from(e.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: _exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> openSettings() async {
    try {
      await _plugin.openAppNotificationSettings();
    } on UnimplementedError {
      // Nothing to open on this platform.
    }
  }
}

/// Fires reminders from timers while the app runs (Windows, Linux).
class TimerReminderBackend implements ReminderBackend {
  TimerReminderBackend([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _timers = <int, (Timer, ReminderEvent)>{};
  bool _ready = false;

  @override
  Future<ReminderResponse?> init(void Function(ReminderResponse r) onResponse) async {
    try {
      await _plugin.initialize(
        settings: _settings,
        onDidReceiveNotificationResponse: (r) {
          if (reminderResponse(r) case final response?) onResponse(response);
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
    return null;
  }

  @override
  Future<bool> requestPermission() async => _ready;

  @override
  Future<List<PendingReminder>> pending() async => [
        for (final (_, e) in _timers.values) (id: e.id, title: e.title, body: e.body),
      ];

  @override
  Future<void> schedule(ReminderEvent e) async {
    _timers.remove(e.id)?.$1.cancel();
    final wait = e.at.difference(DateTime.now());
    _timers[e.id] = (
      Timer(wait.isNegative ? Duration.zero : wait, () {
        _timers.remove(e.id);
        if (_ready) {
          _plugin.show(
              id: e.id, title: e.title, body: e.body, notificationDetails: _details, payload: e.taskId);
        }
      }),
      e,
    );
  }

  @override
  Future<void> cancel(int id) async => _timers.remove(id)?.$1.cancel();

  @override
  Future<void> openSettings() async {}
}
