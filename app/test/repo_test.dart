import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
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
}
