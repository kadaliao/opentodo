import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:drift/drift.dart' show Value;
import 'package:opentodo/domain/recurrence.dart';
import 'package:opentodo/domain/task_defaults.dart';
import 'package:opentodo/domain/views.dart';

void main() {
  late AppDatabase db;
  late TaskRepo repo;
  var clock = DateTime(2026, 11, 15, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = DateTime(2026, 11, 15, 10);
    repo = TaskRepo(db, clock: () => clock);
  });
  tearDown(() => db.close());

  Future<List<Task>> tasks() => repo.watchTasks().first;

  test('adding a task stores its date as a calendar date', () async {
    final id = await repo.addTask(
      title: '开会',
      dueDate: DateTime(2026, 11, 16),
      dueTime: 15 * 60,
      tags: ['工作'],
      priority: Priority.high,
    );
    final t = (await repo.getTask(id))!;
    expect(t.title, '开会');
    expect(t.listId, inboxListId);
    expect(t.dueDate, '2026-11-16');
    expect(t.dueTime, 900);
    expect(t.tags, ['工作']);
    expect(t.priority, Priority.high);
    expect(t.dirty, isTrue);
    expect(t.serverVersion, 0);
  });

  test('a time without a date is dropped', () async {
    final id = await repo.addTask(title: 'x', dueTime: 60);
    expect((await repo.getTask(id))!.dueTime, isNull);
  });

  test('completing stamps completedAt and updatedAt', () async {
    final id = await repo.addTask(title: 'x');
    clock = clock.add(const Duration(minutes: 5));
    await repo.setCompleted(id, true);
    var t = (await repo.getTask(id))!;
    expect(t.status, TaskStatus.done);
    expect(t.completedAt, clock.millisecondsSinceEpoch);
    expect(t.updatedAt, clock.millisecondsSinceEpoch);
    await repo.setCompleted(id, false);
    t = (await repo.getTask(id))!;
    expect(t.status, TaskStatus.open);
    expect(t.completedAt, isNull);
  });

  test('trash, restore and purge', () async {
    final id = await repo.addTask(title: 'x');
    await repo.trashTask(id);
    expect((await tasks()).single.trashedAt, isNotNull);
    await repo.restoreTask(id);
    expect((await tasks()).single.trashedAt, isNull);
    await repo.trashTask(id);
    await repo.emptyTrash();
    expect(await tasks(), isEmpty);
    // The tombstone stays for sync.
    expect((await repo.getTask(id))!.deletedAt, isNotNull);
  });

  test('deleting a list trashes its tasks', () async {
    final listId = await repo.addList('工作', emoji: '💼');
    final a = await repo.addTask(title: 'a', listId: listId);
    final b = await repo.addTask(title: 'b');
    await repo.deleteList(listId);
    expect(await repo.watchLists().first, isEmpty);
    final byId = {for (final t in await tasks()) t.id: t};
    expect(byId[a]!.trashedAt, isNotNull);
    expect(byId[a]!.listId, inboxListId);
    expect(byId[b]!.trashedAt, isNull);
  });

  test('checklist items', () async {
    final id = await repo.addTask(title: 'x');
    final c1 = await repo.addChecklistItem(id, '鸡蛋');
    clock = clock.add(const Duration(seconds: 1));
    await repo.addChecklistItem(id, '牛奶');
    await repo.updateChecklistItem(c1, done: true);
    var items = await repo.watchChecklist(id).first;
    expect(items.map((i) => (i.title, i.done)), [('鸡蛋', true), ('牛奶', false)]);
    await repo.deleteChecklistItem(c1);
    items = await repo.watchChecklist(id).first;
    expect(items.map((i) => i.title), ['牛奶']);
  });

  test('seedIfEmpty runs once', () async {
    await repo.seedIfEmpty();
    final n = (await tasks()).length;
    expect(n, greaterThan(0));
    await repo.seedIfEmpty();
    expect((await tasks()).length, n);
    expect(openCount(const SmartViewRef(SmartKind.today), await tasks(), clock), 1);
  });

  group('repeating tasks', () {
    Future<String> daily({String? rule, int from = RepeatFrom.dueDate}) => repo.addTask(
          title: '吃药',
          dueDate: DateTime(2026, 11, 15),
          dueTime: 8 * 60,
          reminders: [0],
          repeatRule: rule ?? 'FREQ=DAILY',
          repeatFrom: from,
        );

    test('completing moves the task on and leaves a finished copy', () async {
      final id = await daily();
      final item = await repo.addChecklistItem(id, '饭后');
      await repo.updateChecklistItem(item, done: true);
      clock = clock.add(const Duration(minutes: 1));

      final done = await repo.setCompleted(id, true);
      expect(done!.next, DateTime(2026, 11, 16));

      final t = (await repo.getTask(id))!;
      expect(t.status, TaskStatus.open);
      expect(t.dueDate, '2026-11-16');
      expect(t.dueTime, 8 * 60);
      expect(t.reminders, [0]);
      expect(t.repeatRule, 'FREQ=DAILY');
      // Subtasks start over.
      expect((await repo.watchChecklist(id).first).single.done, isFalse);

      final copy = (await repo.getTask(done.copyId))!;
      expect(copy.title, '吃药');
      expect(copy.status, TaskStatus.done);
      expect(copy.completedAt, clock.millisecondsSinceEpoch);
      expect(copy.dueDate, '2026-11-15');
      expect(copy.repeatRule, isNull);
      expect(copy.reminders, isEmpty);
      expect(copy.dirty, isTrue);
      final copied = await repo.watchChecklist(done.copyId).first;
      expect(copied.map((i) => (i.title, i.done)), [('饭后', true)]);
    });

    test('the finished copy has the same id on every device', () async {
      final id = await daily();
      final a = (await repo.setCompleted(id, true))!;
      // Same task, same occurrence: same id, wherever it is computed.
      final db2 = AppDatabase(NativeDatabase.memory());
      addTearDown(db2.close);
      final repo2 = TaskRepo(db2, clock: () => clock);
      await repo2.addTask(
        id: id,
        title: '吃药',
        dueDate: DateTime(2026, 11, 15),
        repeatRule: 'FREQ=DAILY',
      );
      expect((await repo2.setCompleted(id, true))!.copyId, a.copyId);
    });

    test('undo puts everything back', () async {
      final id = await daily();
      final item = await repo.addChecklistItem(id, '饭后');
      await repo.updateChecklistItem(item, done: true);
      final done = (await repo.setCompleted(id, true))!;
      await repo.undoRepeatCompletion(done);

      final t = (await repo.getTask(id))!;
      expect(t.dueDate, '2026-11-15');
      expect(t.status, TaskStatus.open);
      expect((await repo.watchChecklist(id).first).single.done, isTrue);
      expect((await tasks()).map((t) => t.id), [id]);
      expect((await repo.getTask(done.copyId))!.deletedAt, isNotNull);

      // Completing again brings the copy back.
      final again = (await repo.setCompleted(id, true))!;
      expect(again.copyId, done.copyId);
      expect((await repo.getTask(done.copyId))!.deletedAt, isNull);
    });

    test('the last occurrence closes the task', () async {
      final id = await daily(rule: 'FREQ=DAILY;COUNT=2');
      expect(await repo.setCompleted(id, true), isNotNull);
      expect((await repo.getTask(id))!.repeatRule, 'FREQ=DAILY;COUNT=1');
      expect(await repo.setCompleted(id, true), isNull);
      final t = (await repo.getTask(id))!;
      expect(t.status, TaskStatus.done);
      expect(t.dueDate, '2026-11-16');
    });

    test('counting from completion', () async {
      clock = DateTime(2026, 11, 20, 9);
      final id = await daily(rule: 'FREQ=DAILY;INTERVAL=3', from: RepeatFrom.completion);
      await repo.setCompleted(id, true);
      expect((await repo.getTask(id))!.dueDate, '2026-11-23');
    });

    test('skipping moves on without a copy', () async {
      final id = await daily(rule: 'FREQ=WEEKLY;BYDAY=MO,FR');
      expect(await repo.skipOccurrence(id), DateTime(2026, 11, 16));
      expect((await tasks()).length, 1);
      expect((await repo.getTask(id))!.status, TaskStatus.open);
    });

    test('clearing the date clears reminders and repeat', () async {
      final id = await daily();
      await repo.setDue(id, DateTime(2026, 11, 20), 9 * 60);
      var t = (await repo.getTask(id))!;
      expect(t.reminders, [0]);
      expect(t.repeatRule, 'FREQ=DAILY');
      await repo.setDue(id, null, null);
      t = (await repo.getTask(id))!;
      expect(t.reminders, isEmpty);
      expect(t.repeatRule, isNull);
      // And completing it now is a plain completion.
      expect(await repo.setCompleted(id, true), isNull);
    });

    test('a task without a date takes no reminders or repeat', () async {
      final id = await repo.addTask(title: 'x', reminders: [0], repeatRule: 'FREQ=DAILY');
      final t = (await repo.getTask(id))!;
      expect(t.reminders, isEmpty);
      expect(t.repeatRule, isNull);
    });
  });
  test('moving a task on the calendar starts reminders over between timed and all-day', () async {
    final id = await repo.addTask(
      title: '开会',
      dueDate: DateTime(2026, 11, 16),
      dueTime: 9 * 60,
      reminders: [0, -30],
      repeatRule: 'FREQ=WEEKLY',
    );
    // Another time keeps them: they count from the time.
    await repo.moveTo(id, DateTime(2026, 11, 17), 14 * 60);
    var t = (await repo.getTask(id))!;
    expect('${(t.dueDate, t.dueTime, t.reminders)}', '(2026-11-17, 840, [0, -30])');
    expect(t.repeatRule, 'FREQ=WEEKLY');

    // All day: 准时 would mean midnight, so they go.
    await repo.moveTo(id, DateTime(2026, 11, 18), null);
    t = (await repo.getTask(id))!;
    expect('${(t.dueDate, t.dueTime, t.reminders)}', '(2026-11-18, null, [])');

    // Back to a time: 准时.
    await repo.moveTo(id, DateTime(2026, 11, 18), 10 * 60);
    t = (await repo.getTask(id))!;
    expect('${(t.dueTime, t.reminders)}', '(600, [0])');

    // Dropping it where it already is changes nothing.
    final before = t.updatedAt;
    clock = clock.add(const Duration(minutes: 1));
    await repo.moveTo(id, DateTime(2026, 11, 18), 10 * 60);
    expect((await repo.getTask(id))!.updatedAt, before);
  });

  group('spans', () {
    test('kept sensible when stored', () async {
      final a = await repo.addTask(title: '会', dueDate: DateTime(2026, 11, 16), dueTime: 600, duration: 90);
      final b = await repo.addTask(title: '一天', dueDate: DateTime(2026, 11, 16), duration: 1440);
      final c = await repo.addTask(title: '没日期', duration: 90);
      expect((await repo.getTask(a))!.duration, 90);
      expect((await repo.getTask(b))!.duration, isNull);
      expect((await repo.getTask(c))!.duration, isNull);

      await repo.setSchedule(a, date: DateTime(2026, 11, 17), duration: 2000);
      expect((await repo.getTask(a))!.duration, 2880, reason: 'all day: whole days');
      await repo.setDuration(a, 1440);
      expect((await repo.getTask(a))!.duration, isNull);
    });

    test('dragging moves the span; losing the time keeps its days', () async {
      final id = await repo.addTask(
          title: '夜班', dueDate: DateTime(2026, 11, 16), dueTime: 22 * 60, duration: 180, reminders: [0]);
      await repo.moveTo(id, DateTime(2026, 11, 18), 21 * 60);
      var t = (await repo.getTask(id))!;
      expect('${(t.dueDate, t.dueTime, t.duration, t.reminders)}', '(2026-11-18, 1260, 180, [0])');

      // 21:00 for three hours stays on one day.
      await repo.moveTo(id, DateTime(2026, 11, 18), null);
      t = (await repo.getTask(id))!;
      expect('${(t.dueTime, t.duration, t.reminders)}', '(null, null, [])');

      await repo.setSchedule(id, date: DateTime(2026, 11, 18), duration: 3 * 1440);
      await repo.moveTo(id, DateTime(2026, 11, 20), 600);
      t = (await repo.getTask(id))!;
      expect((t.dueDate, t.dueTime, t.duration), ('2026-11-20', 600, null));
    });

    test('clearing the date clears the span; moving the day keeps it', () async {
      final id = await repo.addTask(title: '会', dueDate: DateTime(2026, 11, 16), dueTime: 600, duration: 90);
      await repo.setDue(id, DateTime(2026, 11, 17), 600);
      expect((await repo.getTask(id))!.duration, 90);
      await repo.setDue(id, null, null);
      expect((await repo.getTask(id))!.duration, isNull);
    });

    test('a repeating span keeps its length on the next date', () async {
      final id = await repo.addTask(
          title: '周会',
          dueDate: DateTime(2026, 11, 16),
          dueTime: 600,
          duration: 60,
          repeatRule: 'FREQ=WEEKLY');
      await repo.setCompleted(id, true);
      final t = (await repo.getTask(id))!;
      expect((t.dueDate, t.dueTime, t.duration), ('2026-11-23', 600, 60));
    });
  });

  group('defaults', () {
    test('the person\'s defaults go with a new date or a change of kind', () async {
      var defaults = const TaskDefaults(timedReminders: [-15], allDayReminders: [540]);
      repo = TaskRepo(db, clock: () => clock, defaults: () => defaults);
      final id = await repo.addTask(title: '交报告');

      // First date from the menu: all day, so 当天 09:00.
      await repo.setDue(id, DateTime(2026, 11, 16), null);
      expect((await repo.getTask(id))!.reminders, [540]);
      // Moving it again keeps what it has.
      await repo.setCompleted(id, false);
      await repo.updateTask(id, const TasksCompanion(reminders: Value([-900])));
      await repo.setDue(id, DateTime(2026, 11, 17), null);
      expect((await repo.getTask(id))!.reminders, [-900]);

      // Dragged onto an hour, then back to all day.
      await repo.moveTo(id, DateTime(2026, 11, 17), 600);
      expect((await repo.getTask(id))!.reminders, [-15]);
      defaults = const TaskDefaults(allDayReminders: []);
      await repo.moveTo(id, DateTime(2026, 11, 17), null);
      expect((await repo.getTask(id))!.reminders, isEmpty);
    });
  });
}
