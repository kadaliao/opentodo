import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/keys.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/domain/reminders.dart';
import 'package:opentodo/notify/reminder_actions.dart';
import 'package:opentodo/notify/reminder_backend.dart';
import 'package:opentodo/notify/reminder_scheduler.dart';

import 'reminder_scheduler_test.dart' show FakeBackend;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 11, 16, 15); // Monday 15:00

  late AppDatabase db;
  late TaskRepo repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TaskRepo(db, clock: () => now);
  });
  tearDown(() => db.close());

  NotificationResponse response(String? payload, String? actionId) => NotificationResponse(
        notificationResponseType: actionId == null
            ? NotificationResponseType.selectedNotification
            : NotificationResponseType.selectedNotificationAction,
        payload: payload,
        actionId: actionId,
      );

  test('responses: a click opens, the buttons are done and snooze', () {
    expect(reminderResponse(response('t', null)), (taskId: 't', action: ReminderAction.open));
    expect(reminderResponse(response('t', 'done')), (taskId: 't', action: ReminderAction.done));
    expect(reminderResponse(response('t', 'snooze')), (taskId: 't', action: ReminderAction.snooze));
    expect(reminderResponse(response('t', 'default')), (taskId: 't', action: ReminderAction.open));
    expect(reminderResponse(response(null, 'done')), isNull);
    expect(reminderResponse(response('', null)), isNull);

    const r = (taskId: 't', action: ReminderAction.snooze);
    expect(decodeReminderResponse(encodeReminderResponse(r)), r);
    expect(decodeReminderResponse(['t', 'explode']), isNull);
    expect(decodeReminderResponse('t'), isNull);
  });

  test('snoozes are kept until they go off', () async {
    final s = Snoozes(db);
    await s.put('a', now.add(const Duration(minutes: 10)));
    await s.put('b', now.subtract(const Duration(minutes: 1)));
    expect((await s.load()).keys, {'a', 'b'});
    expect((await s.upcoming(now)).keys, {'a'});
    expect((await s.load()).keys, {'a'}, reason: 'b went off and is dropped');
    await s.remove('a');
    expect(await db.getValue(Keys.snoozes), isNull);
    // Damaged: nothing, not an error.
    await db.setValue(Keys.snoozes, 'nonsense');
    expect(await s.load(), isEmpty);
  });

  test('a snooze comes back as a reminder while its task is open', () async {
    final open = (await repo.getTask(await repo.addTask(title: '开会', dueDate: now, dueTime: 900)))!;
    final done = (await repo.getTask(await repo.addTask(title: '已完成', dueDate: now)))!
        .copyWith(status: TaskStatus.done);
    final later = now.add(const Duration(minutes: 15));
    final events = upcomingReminders([open, done], now, snoozed: {
      open.id: later,
      done.id: later,
      'gone': later,
    });
    expect(events.map((e) => '${e.title} ${e.at}'), ['开会 $later']);
    expect(events.single.body, '今天, 下午3:00');
    // One that went off is no reminder.
    expect(upcomingReminders([open], now, snoozed: {open.id: now}), isEmpty);
  });

  group('in the background, with the app not running', () {
    late FakeBackend system;
    setUp(() async {
      system = FakeBackend();
    });

    Future<void> scheduleAll(DateTime at) async => ReminderScheduler(system)
        .apply(upcomingReminders(await db.select(db.tasks).get(), at));

    test('完成 ticks the task off and takes back its later reminders', () async {
      final id = await repo.addTask(title: '交报告', dueDate: now, dueTime: 16 * 60, reminders: [-60, 0]);
      await scheduleAll(now.subtract(const Duration(hours: 2)));
      expect(system.pendingById, hasLength(2));

      // The 15:00 one went off and 完成 was pressed on it.
      await runReminderActionAlone(db, system, (taskId: id, action: ReminderAction.done), now);
      expect((await repo.getTask(id))!.status, TaskStatus.done);
      expect(system.pendingById, isEmpty);
    });

    test('完成 on a repeating task moves it on, with its next reminder', () async {
      final id = await repo.addTask(
          title: '吃药', dueDate: now, dueTime: 15 * 60, reminders: [0], repeatRule: 'FREQ=DAILY');
      await runReminderActionAlone(db, system, (taskId: id, action: ReminderAction.done), now);
      final t = (await repo.getTask(id))!;
      expect((t.status, t.dueDate), (TaskStatus.open, '2026-11-17'));
      expect(system.pendingById.values.single.at, DateTime(2026, 11, 17, 15));
    });

    test('稍后提醒 hands over a reminder after the snooze time from the settings', () async {
      final id = await repo.addTask(title: '回电话', dueDate: now, dueTime: 15 * 60, reminders: [0]);
      await db.setValue(Keys.settings, '{"snoozeMinutes":10}');
      await runReminderActionAlone(db, system, (taskId: id, action: ReminderAction.snooze), now);
      final e = system.pendingById.values.single;
      expect((e.title, e.at), ('回电话', DateTime(2026, 11, 16, 15, 10)));
      expect(system.permissionRequests, 0, reason: 'no asking in the background');
      expect((await Snoozes(db).load())[id], DateTime(2026, 11, 16, 15, 10));

      // Done before it comes back: the snooze goes too.
      await runReminderActionAlone(db, system, (taskId: id, action: ReminderAction.done), now);
      expect(system.pendingById, isEmpty);
      expect(await Snoozes(db).load(), isEmpty);
    });

    test('a task finished or deleted elsewhere is left alone', () async {
      final id = await repo.addTask(title: '旧的', dueDate: now);
      await repo.setCompleted(id, true);
      final before = (await repo.getTask(id))!.updatedAt;
      await runReminderActionAlone(db, system, (taskId: id, action: ReminderAction.done), now);
      expect((await repo.getTask(id))!.updatedAt, before);
      await runReminderActionAlone(db, system, (taskId: 'nope', action: ReminderAction.done), now);
    });
  });

  test('replacing all hands every reminder over again', () async {
    final system = FakeBackend();
    final s = ReminderScheduler(system);
    final e = ReminderEvent(taskId: 't', at: DateTime(2026, 11, 17, 9), title: 't', body: '明天');
    await s.apply([e]);
    system.log.clear();
    await s.apply([e]);
    expect(system.log, isEmpty);
    await s.apply([e], replaceAll: true);
    expect(system.log, ['cancel t', 'schedule t']);
  });
}
