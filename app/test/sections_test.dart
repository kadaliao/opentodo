import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/domain/ordering.dart';
import 'package:opentodo/domain/views.dart';

import 'package:drift/drift.dart' show Value;

import 'views_test.dart' show now, shape, sec, task;

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
  Future<List<ListSection>> sections() => repo.watchSections().first;
  Future<Task> load(String id) async => (await repo.getTask(id))!;
  void tick() => clock = clock.add(const Duration(seconds: 1));

  /// Adds tasks one second apart, so the later ones come first.
  Future<List<String>> add(List<String> titles, {String listId = 'work', String? sectionId}) async {
    final ids = <String>[];
    for (final t in titles) {
      tick();
      ids.add(await repo.addTask(title: t, listId: listId, sectionId: sectionId));
    }
    return ids;
  }

  List<String> titlesOf(List<Task> ts) => [for (final t in ts) t.title];

  test('sections go in order; a list without them has no headers', () async {
    await add(['甲', '乙']);
    var s = buildSections(
        view: const ListViewRef('work'), tasks: await tasks(), lists: const {}, now: now);
    expect(shape(s), [sec(null, ['乙', '甲'])]); // newest first
    expect(s.single.arrangeable, isTrue);

    final doing = await repo.addSection('work', '进行中');
    final todo = await repo.addSection('work', '待办');
    await repo.addSection('home', '别的清单的');
    // Each list numbers its own: new ones go last.
    expect([for (final x in await sections()) if (x.listId == 'work') x.name], ['进行中', '待办']);

    final byList = {'work': [for (final x in await sections()) if (x.listId == 'work') x]};
    s = buildSections(
        view: const ListViewRef('work'),
        tasks: await tasks(),
        lists: const {},
        now: now,
        sectionsByList: byList);
    // Unsectioned tasks first; empty sections still show, to drop into.
    expect(shape(s), [
      sec('未分组', ['乙', '甲']),
      sec('进行中', []),
      sec('待办', []),
    ]);
    expect(s[1].listSection!.id, doing);

    await add(['丙'], sectionId: todo);
    final all = await tasks();
    final jia = all.firstWhere((t) => t.title == '甲');
    final yi = all.firstWhere((t) => t.title == '乙');
    // Drag 甲 above 乙 within 未分组, then 乙 into 进行中.
    await repo.placeTask(jia.id, null, planMove([yi.id, jia.id], jia.id, 0, (id) => all.firstWhere((t) => t.id == id).sortOrder));
    tick();
    await repo.placeTask(yi.id, doing, {yi.id: 0});
    s = buildSections(
        view: const ListViewRef('work'),
        tasks: await tasks(),
        lists: const {},
        now: now,
        sectionsByList: byList);
    expect(shape(s), [
      sec('未分组', ['甲']),
      sec('进行中', ['乙']),
      sec('待办', ['丙']),
    ]);
    expect((await load(yi.id)).dirty, isTrue);

    // Once everything is sorted, 未分组 goes away.
    await repo.placeTask(jia.id, todo, {jia.id: 99999999999999});
    s = buildSections(
        view: const ListViewRef('work'),
        tasks: await tasks(),
        lists: const {},
        now: now,
        sectionsByList: byList);
    expect(shape(s), [
      sec('进行中', ['乙']),
      sec('待办', ['丙', '甲']),
    ]);
  });

  test('deleting a section keeps its tasks; moving a task to another list leaves its section', () async {
    final doing = await repo.addSection('work', '进行中');
    final [a, b] = await add(['甲', '乙'], sectionId: doing);
    tick();
    await repo.deleteSection(doing);
    expect(await sections(), isEmpty);
    expect((await load(a)).sectionId, isNull);
    expect((await load(a)).trashedAt, isNull);

    final review = await repo.addSection('work', '评审');
    await repo.placeTask(b, review, {b: 1});
    await repo.moveToList(b, 'home');
    expect(((await load(b)).listId, (await load(b)).sectionId), ('home', null));
  });

  test('deleting a list deletes its sections', () async {
    final listId = await repo.addList('工作');
    final s = await repo.addSection(listId, '进行中');
    final [t] = await add(['甲'], listId: listId, sectionId: s);
    await repo.deleteList(listId);
    expect(await sections(), isEmpty);
    final row = await (db.select(db.listSections)..where((x) => x.id.equals(s))).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(row.dirty, isTrue);
    expect((await load(t)).trashedAt, isNotNull);
    expect((await load(t)).sectionId, isNull);
  });

  test('the board: a column per section, finished cards at the bottom of theirs', () async {
    final doing = await repo.addSection('work', '进行中');
    final done = await repo.addSection('work', '完成了');
    final [a, _] = await add(['甲', '乙'], sectionId: doing);
    final [c] = await add(['丙'], sectionId: done);
    await add(['别处'], listId: 'home');
    tick();
    await repo.setCompleted(c, true);
    final secs = [for (final x in await sections()) if (x.listId == 'work') x];

    var cols = boardColumns('work', await tasks(), secs);
    expect([for (final c in cols) c.group.title], ['进行中', '完成了']);
    expect(titlesOf(cols[0].group.tasks), ['乙', '甲']);
    expect(titlesOf(cols[1].group.tasks), isEmpty);
    expect(titlesOf(cols[1].done), ['丙']);

    // A finished task outside any section brings 未分组 back.
    await repo.placeTask(a, null, {a: 0});
    await repo.setCompleted(a, true);
    cols = boardColumns('work', await tasks(), secs);
    expect([for (final c in cols) c.group.title], ['未分组', '进行中', '完成了']);
    expect(titlesOf(cols[0].done), ['甲']);

    // No sections: one 未分组 column, even when empty.
    cols = boardColumns('empty', await tasks(), const []);
    expect([for (final c in cols) c.group.title], ['未分组']);
  });

  test('a task whose section is gone, or another list\'s, is under 未分组', () {
    final mine = ListSection(
      id: 'mine', listId: 'work', name: '进行中', sortOrder: 0,
      createdAt: 0, updatedAt: 0, deletedAt: null, serverVersion: 0, dirty: false,
    );
    final stray = task('迷路', listId: 'work').copyWith(sectionId: const Value('elsewhere'));
    final placed = task('归位', listId: 'work').copyWith(sectionId: const Value('mine'));
    final groups = listGroups([stray, placed], [mine]);
    expect([for (final g in groups) '${g.title}: ${titlesOf(g.tasks).join()}'],
        ['未分组: 迷路', '进行中: 归位']);
    expect(arrangedListId(const SmartViewRef(SmartKind.inbox)), inboxListId);
    expect(arrangedListId(const SmartViewRef(SmartKind.today)), isNull);
    expect(arrangedListId(const TagViewRef('x')), isNull);
  });
}
