import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/domain/views.dart';
import 'package:opentodo/state/providers.dart';
import 'package:opentodo/sync/codec.dart';

import 'views_test.dart' show now, task, shape, sec;

Task pinned(Task t, int at) => t.copyWith(pinnedAt: Value(at));

void main() {
  test('pinned tasks come first in a list, a section, a day, a tag', () {
    final tasks = [
      task('一', listId: 'w'),
      task('二', listId: 'w'),
      pinned(task('钉住', listId: 'w'), 1),
      task('今天早', due: '2026-11-15', time: 8 * 60, tags: ['t']),
      pinned(task('今天钉住', due: '2026-11-15', time: 20 * 60, tags: ['t']), 1),
      pinned(task('做完的钉住', listId: 'w', status: TaskStatus.done, completedAt: 9), 1),
    ];
    expect(shape(buildSections(view: const ListViewRef('w'), tasks: tasks, lists: const {}, now: now)), [
      sec(null, ['钉住', '二', '一']),
      sec('已完成', ['做完的钉住']),
    ]);
    final today = buildSections(
        view: const SmartViewRef(SmartKind.today), tasks: tasks, lists: const {}, now: now);
    expect(today.first.tasks.map((t) => t.title), ['今天钉住', '今天早']);
    expect(today.first.day, DateTime(2026, 11, 15));
    final byTag = buildSections(view: const TagViewRef('t'), tasks: tasks, lists: const {}, now: now);
    expect(byTag.first.tasks.map((t) => t.title), ['今天钉住', '今天早']);
  });

  test('a list can be ordered by date or priority instead of by hand', () {
    final tasks = [
      task('无日期高', listId: 'w', priority: Priority.high),
      task('后天', listId: 'w', due: '2026-11-17'),
      task('明天中', listId: 'w', due: '2026-11-16', priority: Priority.medium),
      task('明天低', listId: 'w', due: '2026-11-16', priority: Priority.low),
    ];
    List<String> order(ListSort sort) => [
          for (final t in buildSections(
            view: const ListViewRef('w'),
            tasks: tasks,
            lists: const {},
            now: now,
            listSorts: {'w': sort},
          ).single.tasks)
            t.title,
        ];
    expect(order(ListSort.manual), ['明天低', '明天中', '后天', '无日期高']); // newest first
    expect(order(ListSort.due), ['明天中', '明天低', '后天', '无日期高']);
    expect(order(ListSort.priority), ['无日期高', '明天中', '明天低', '后天']);
    final s = buildSections(
        view: const ListViewRef('w'), tasks: tasks, lists: const {}, now: now, listSorts: {'w': ListSort.due});
    expect(s.single.manualOrder, isFalse);
    expect(
        buildSections(view: const ListViewRef('w'), tasks: tasks, lists: const {}, now: now)
            .single
            .manualOrder,
        isTrue);
  });

  test('overdue has no day to drop onto; each day of 最近7天 has one', () {
    final tasks = [
      task('过期', due: '2026-11-10'),
      task('后天', due: '2026-11-17'),
    ];
    final s = buildSections(
        view: const SmartViewRef(SmartKind.next7), tasks: tasks, lists: const {}, now: now);
    expect([for (final x in s) x.day], [null, DateTime(2026, 11, 17)]);
  });

  test('pinning is stored and synced; a finished copy of a repeating task is not pinned', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var clock = DateTime(2026, 11, 15, 10);
    final repo = TaskRepo(db, clock: () => clock);
    final id = await repo.addTask(
        title: '每天跑步', dueDate: DateTime(2026, 11, 15), repeatRule: 'FREQ=DAILY');
    await repo.setPinned(id, true);
    var t = (await repo.getTask(id))!;
    expect(t.pinnedAt, clock.millisecondsSinceEpoch);

    final wire = WireRecord.fromJson(
        jsonDecode(jsonEncode(taskToWire(t).toJson())) as Map<String, dynamic>);
    expect(wireToTask(wire).pinnedAt.value, t.pinnedAt);

    clock = clock.add(const Duration(minutes: 1));
    await repo.setCompleted(id, true);
    final all = await repo.watchTasks().first;
    expect(all.firstWhere((x) => x.id != id).pinnedAt, isNull); // the copy
    expect(all.firstWhere((x) => x.id == id).pinnedAt, isNotNull); // still pinned

    await repo.setPinned(id, false);
    t = (await repo.getTask(id))!;
    expect(t.pinnedAt, isNull);
  });

  test('list preferences read what the first version stored', () {
    expect(ListPrefs.fromJson('board').layout, ListLayout.board);
    expect(ListPrefs.fromJson('board').sort, ListSort.manual);
    final p = ListPrefs.fromJson({'layout': 'list', 'sort': 'due'});
    expect((p.layout, p.sort), (ListLayout.list, ListSort.due));
    expect(ListPrefs.fromJson({'layout': 'gallery', 'sort': 'mood'}).isDefault, isTrue);
    expect(ListPrefs.fromJson(42).isDefault, isTrue);
  });
}
