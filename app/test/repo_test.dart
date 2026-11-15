import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/domain/recurrence.dart';
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
}
