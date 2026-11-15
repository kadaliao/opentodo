/// Hands reminders to the operating system.
///
/// On iOS, macOS and Android the system holds scheduled notifications and
/// shows them even when the app isn't running. Windows and Linux have no
/// scheduler the plugin can use, so there reminders go off from timers while
/// the app is open.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminders.dart';

/// A notification the system is holding for later.
typedef PendingReminder = ({int id, String? title, String? body});

abstract class ReminderBackend {
  /// Sets up the system side; [onOpen] gets the task id of a notification
  /// the person clicks. Returns the task id the app was launched from, if
  /// any.
  Future<String?> init(void Function(String taskId) onOpen);

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
  Future<String?> init(void Function(String taskId) onOpen) async => null;
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

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'reminders',
    '任务提醒',
    channelDescription: '任务到了提醒时间',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  ),
  iOS: DarwinNotificationDetails(threadIdentifier: 'reminders'),
  macOS: DarwinNotificationDetails(threadIdentifier: 'reminders'),
  linux: LinuxNotificationDetails(category: LinuxNotificationCategory.imReceived),
);

const _settings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  // Asked for later, when there's a reminder to show, not at first launch.
  iOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  ),
  macOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  ),
  linux: LinuxInitializationSettings(defaultActionName: '打开'),
  windows: WindowsInitializationSettings(
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

  @override
  Future<String?> init(void Function(String taskId) onOpen) async {
    await _plugin.initialize(
      settings: _settings,
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) onOpen(id);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.didNotificationLaunchApp == true
        ? launch!.notificationResponse?.payload
        : null;
    return payload == null || payload.isEmpty ? null : payload;
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
  Future<String?> init(void Function(String taskId) onOpen) async {
    try {
      await _plugin.initialize(
        settings: _settings,
        onDidReceiveNotificationResponse: (r) {
          final id = r.payload;
          if (id != null && id.isNotEmpty) onOpen(id);
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
