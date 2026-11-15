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
    List<String> order(TaskSort sort) => [
          for (final t in buildSections(
            view: const ListViewRef('w'),
            tasks: tasks,
            lists: const {},
            now: now,
            sort: sort,
          ).single.tasks)
            t.title,
        ];
    expect(order(TaskSort.manual), ['明天低', '明天中', '后天', '无日期高']); // newest first
    expect(order(TaskSort.due), ['明天中', '明天低', '后天', '无日期高']);
    expect(order(TaskSort.priority), ['无日期高', '明天中', '明天低', '后天']);
    // A to Z in pinyin: hou, mingtiandi, mingtianzhong, wu.
    expect(order(TaskSort.title), ['后天', '明天低', '明天中', '无日期高']);
    final s = buildSections(
        view: const ListViewRef('w'), tasks: tasks, lists: const {}, now: now, sort: TaskSort.due);
    expect(s.single.manualOrder, isFalse);
    expect(
        buildSections(view: const ListViewRef('w'), tasks: tasks, lists: const {}, now: now)
            .single
            .manualOrder,
        isTrue);
  });

  test('overdue has no day to drop onto; every day of 最近7天 has one, empty or not', () {
    final tasks = [
      task('过期', due: '2026-11-10'),
      task('后天', due: '2026-11-17'),
    ];
    final s = buildSections(
        view: const SmartViewRef(SmartKind.next7), tasks: tasks, lists: const {}, now: now);
    expect([for (final x in s) x.day], [null, for (var d = 15; d <= 21; d++) DateTime(2026, 11, d)]);
    expect([for (final x in s) x.tasks.length], [1, 0, 0, 1, 0, 0, 0, 0]);
    // 今天 with only overdue tasks still has today to drag them onto.
    final today = buildSections(
        view: const SmartViewRef(SmartKind.today), tasks: tasks, lists: const {}, now: now);
    expect([for (final x in today) (x.day, x.tasks.length)], [(null, 1), (DateTime(2026, 11, 15), 0)]);
    // Nothing at all: no sections, so the empty state shows. Only finished
    // ones: nothing to drag, so no empty days either.
    expect(
        buildSections(view: const SmartViewRef(SmartKind.next7), tasks: const [], lists: const {}, now: now),
        isEmpty);
    final done = buildSections(
        view: const SmartViewRef(SmartKind.today),
        tasks: [task('做完了', due: '2026-11-15', status: TaskStatus.done, completedAt: 1)],
        lists: const {},
        now: now);
    expect([for (final x in done) x.title], ['已完成']);
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

  test('view preferences read what earlier versions stored', () {
    const list = ListViewRef('w');
    expect(ViewPrefs.fromJson('board').layout, ListLayout.board);
    expect(ViewPrefs.fromJson('board').sortIn(list), TaskSort.manual);
    final p = ViewPrefs.fromJson({'layout': 'list', 'sort': 'due'});
    expect((p.layout, p.sortIn(list), p.groupingIn(list)), (ListLayout.list, TaskSort.due, TaskGrouping.sections));
    expect(ViewPrefs.fromJson({'layout': 'gallery', 'sort': 'mood', 'group': 'x'}).isDefault, isTrue);
    expect(ViewPrefs.fromJson(42).isDefault, isTrue);
    // A choice a view doesn't offer falls back to its default.
    const today = SmartViewRef(SmartKind.today);
    expect(p.sortIn(today), TaskSort.due);
    expect(const ViewPrefs(sort: TaskSort.manual, grouping: TaskGrouping.sections).groupingIn(today), TaskGrouping.date);
    expect(const ViewPrefs(sort: TaskSort.manual).sortIn(today), TaskSort.due);
    final round = ViewPrefs.fromJson(const ViewPrefs(grouping: TaskGrouping.priority, sort: TaskSort.tag).toJson());
    expect((round.grouping, round.sort), (TaskGrouping.priority, TaskSort.tag));
    expect(const ViewPrefs().sortIn(const SmartViewRef(SmartKind.trash)), isNull);
  });
}
