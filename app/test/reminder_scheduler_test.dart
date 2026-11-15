import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/reminders.dart';
import 'package:opentodo/notify/reminder_backend.dart';
import 'package:opentodo/notify/reminder_scheduler.dart';

/// Stands in for the system: remembers what is pending and logs calls.
class FakeBackend implements ReminderBackend {
  FakeBackend({this.allow = true});

  bool allow;
  final pendingById = <int, ReminderEvent>{};
  final log = <String>[];
  int permissionRequests = 0;

  /// Where the app hears about notifications the person responds to.
  void Function(ReminderResponse r)? respond;

  /// What the app was "launched from".
  ReminderResponse? launchedFrom;

  @override
  Future<ReminderResponse?> init(void Function(ReminderResponse r) onResponse) async {
    respond = onResponse;
    return launchedFrom;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allow;
  }

  @override
  Future<List<PendingReminder>> pending() async => [
        for (final e in pendingById.values) (id: e.id, title: e.title, body: e.body),
      ];

  @override
  Future<void> schedule(ReminderEvent e) async {
    log.add('schedule ${e.title}');
    pendingById[e.id] = e;
  }

  @override
  Future<void> cancel(int id) async {
    log.add('cancel ${pendingById[id]?.title}');
    pendingById.remove(id);
  }

  @override
  Future<void> openSettings() async {}
}

ReminderEvent event(String task, int hour, {String? title}) => ReminderEvent(
      taskId: task,
      at: DateTime(2026, 11, 16, hour),
      title: title ?? task,
      body: '明天',
    );

void main() {
  test('only what changed is touched', () async {
    final backend = FakeBackend();
    final s = ReminderScheduler(backend);

    await s.apply([event('a', 9), event('b', 10)]);
    expect(backend.log, ['schedule a', 'schedule b']);

    backend.log.clear();
    await s.apply([event('a', 9), event('b', 10)]);
    expect(backend.log, isEmpty);

    // b renamed, a moved, c new.
    backend.log.clear();
    await s.apply([event('a', 11), event('b', 10, title: 'B'), event('c', 12)]);
    expect(backend.log, ['cancel a', 'cancel b', 'schedule a', 'schedule B', 'schedule c']);

    backend.log.clear();
    await s.apply([]);
    expect(backend.log.toSet(), {'cancel a', 'cancel B', 'cancel c'});
    expect(backend.pendingById, isEmpty);
  });

  test('permission is asked once there is something to remind about', () async {
    final backend = FakeBackend(allow: false);
    final s = ReminderScheduler(backend);
    await s.apply([]);
    expect(backend.permissionRequests, 0);
    expect(s.allowed, isNull);

    await s.apply([event('a', 9)]);
    await s.apply([event('a', 9)]);
    expect(backend.permissionRequests, 1);
    expect(s.allowed, isFalse);

    // Back from Settings with notifications turned on.
    backend.allow = true;
    s.recheckPermission();
    await s.apply([event('a', 9)]);
    expect(backend.permissionRequests, 2);
    expect(s.allowed, isTrue);
  });
}
