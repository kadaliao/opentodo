import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/domain/views.dart';

import 'views_test.dart' show now, task, shape, sec;

TaskList list(String id, String name, double order) => TaskList(
      id: id,
      name: name,
      emoji: null,
      color: null,
      sortOrder: order,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      serverVersion: 0,
      dirty: false,
    );

void main() {
  final tasks = [
    task('过期', listId: 'w', due: '2026-11-10', priority: Priority.low),
    task('今天', listId: 'w', due: '2026-11-15', tags: ['家', '急']),
    task('后天', listId: 'w', due: '2026-11-17', tags: ['工作'], priority: Priority.high),
    task('下个月', listId: 'w', due: '2026-12-20', priority: Priority.high),
    task('没日期', listId: 'w', tags: ['急']),
    task('做完了', listId: 'w', status: TaskStatus.done, completedAt: 1, priority: Priority.high),
  ];
  List<TaskSection> inList(TaskGrouping g, [TaskSort? sort]) => buildSections(
      view: const ListViewRef('w'), tasks: tasks, lists: const {}, now: now, grouping: g, sort: sort);

  test('a list grouped by date, tag, priority or not at all', () {
    expect(shape(inList(TaskGrouping.date)), [
      sec('已过期', ['过期']),
      sec('今天, 周日', ['今天']),
      sec('11月17日, 周二', ['后天']),
      sec('以后', ['下个月']),
      sec('无日期', ['没日期']),
      sec('已完成', ['做完了']),
    ]);
    // Filed under the first tag; tags A to Z in pinyin (gong, ji, jia).
    expect(shape(inList(TaskGrouping.tag)), [
      sec('工作', ['后天']),
      sec('急', ['没日期']),
      sec('家', ['今天']),
      sec('无标签', ['下个月', '过期']),
      sec('已完成', ['做完了']),
    ]);
    // Only the priorities that have tasks; finished ones in 已完成.
    expect(shape(inList(TaskGrouping.priority)), [
      sec('高优先级', ['下个月', '后天']),
      sec('低优先级', ['过期']),
      sec('无优先级', ['没日期', '今天']),
      sec('已完成', ['做完了']),
    ]);
    expect(shape(inList(TaskGrouping.none, TaskSort.due)), [
      sec(null, ['过期', '今天', '后天', '下个月', '没日期']),
      sec('已完成', ['做完了']),
    ]);
  });

  test('what a drop into each group does, and whether order counts', () {
    final byDate = inList(TaskGrouping.date);
    expect([for (final s in byDate) s.target.runtimeType], [
      Null, DateTarget, DateTarget, Null, DateTarget, Null, // 已过期 and 以后 take nothing
    ]);
    expect(byDate[4].day, isNull); // 无日期
    expect(byDate[1].day, DateTime(2026, 11, 15));
    expect(byDate.every((s) => s.target == null || s.manualOrder), isTrue); // a list's default
    expect(byDate.last.finished, isTrue);
    expect(inList(TaskGrouping.date, TaskSort.title).any((s) => s.manualOrder), isFalse);

    final none = inList(TaskGrouping.none);
    expect(none.first.target, isA<OrderTarget>());
    // Not grouped and not in manual order: nothing to drop.
    expect(inList(TaskGrouping.none, TaskSort.due).first.target, isNull);

    final byPriority = inList(TaskGrouping.priority);
    expect((byPriority.first.target! as PriorityTarget).priority, Priority.high);
  });

  test('a grouping or order a view does not offer falls back to its default', () {
    // 今天 has no sections of its own, nor an order by hand.
    final today = buildSections(
        view: const SmartViewRef(SmartKind.today),
        tasks: tasks,
        lists: const {},
        now: now,
        grouping: TaskGrouping.sections,
        sort: TaskSort.manual);
    expect(shape(today), [
      sec('已过期', ['过期']),
      sec('今天, 周日', ['今天']),
    ]);
    expect(groupingsFor(const TagViewRef('家')), isNot(contains(TaskGrouping.tag)));
    expect(groupingsFor(const SmartViewRef(SmartKind.trash)), isEmpty);
    expect(sortsFor(const SmartViewRef(SmartKind.completed)), isEmpty);
    expect(sortsFor(const SmartViewRef(SmartKind.inbox)).first, TaskSort.manual);
    expect(sortsFor(const FilterViewRef('f')).first, TaskSort.due);
  });

  test('by list: the sidebar order, 收集箱 first, a list that is gone last', () {
    final lists = {'b': list('b', '生活', 2), 'a': list('a', '工作', 1)};
    final s = buildSections(
      view: const SmartViewRef(SmartKind.next7),
      tasks: [
        task('生活的', listId: 'b', due: '2026-11-15'),
        task('没了的', listId: 'gone', due: '2026-11-15'),
        task('工作的', listId: 'a', due: '2026-11-16'),
        task('收集的', due: '2026-11-17'),
      ],
      lists: lists,
      now: now,
      grouping: TaskGrouping.list,
    );
    expect([for (final x in s) x.id], ['list-inbox', 'list-a', 'list-b', 'list-gone']);
    expect([for (final x in s) (x.target as ListTarget?)?.listId], ['inbox', 'a', 'b', null]);
    // A tag view groups by list by default.
    final tagged = buildSections(
      view: const TagViewRef('t'),
      tasks: [task('甲', listId: 'b', tags: ['t']), task('乙', listId: 'a', tags: ['t'])],
      lists: lists,
      now: now,
    );
    expect(shape(tagged), [sec('工作', ['乙']), sec('生活', ['甲'])]);
  });

  test('order by tag: first tag A to Z in pinyin, untagged last, then by date', () {
    final s = buildSections(
      view: const ListViewRef('w'),
      tasks: [
        task('无标签', listId: 'w', due: '2026-11-15'),
        task('b晚', listId: 'w', tags: ['b'], due: '2026-11-20'),
        task('急', listId: 'w', tags: ['急']),
        task('b早', listId: 'w', tags: ['b'], due: '2026-11-16'),
        task('阿', listId: 'w', tags: ['阿姨', 'z']),
      ],
      lists: const {},
      now: now,
      sort: TaskSort.tag,
    );
    expect(s.single.tasks.map((t) => t.title), ['阿', 'b早', 'b晚', '急', '无标签']);
  });

  test('a tag group swaps the tag a task was filed under', () {
    expect(const TagTarget('乙').retag(['甲', '丙']), ['乙', '丙']);
    expect(const TagTarget('丙').retag(['甲', '丙']), ['丙']);
    expect(const TagTarget('乙').retag([]), ['乙']);
    expect(const TagTarget(null).retag(['甲', '丙']), isEmpty);
    expect(const TagTarget('甲').has(task('x', tags: ['甲', '乙'])), isTrue);
    expect(const TagTarget('乙').has(task('x', tags: ['甲', '乙'])), isFalse);
  });

  test('dropInto: each kind of group, in one go, with the new order', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TaskRepo(db, clock: () => DateTime(2026, 11, 15, 10));
    final w = await repo.addList('工作');
    final a = await repo.addTask(title: '甲', dueDate: DateTime(2026, 11, 14), dueTime: 9 * 60, tags: ['x', 'y']);
    final b = await repo.addTask(title: '乙');
    Future<Task> get(String id) async => (await repo.getTask(id))!;

    await repo.dropInto([a, b], DateTarget(DateTime(2026, 11, 20)), {a: 5, b: 6});
    expect([(await get(a)).dueDate, (await get(a)).dueTime], ['2026-11-20', 9 * 60]);
    expect((await get(b)).dueDate, '2026-11-20');
    expect([(await get(a)).sortOrder, (await get(b)).sortOrder], [5, 6]);

    await repo.dropInto([a], const DateTarget(null), const {});
    expect((await get(a)).dueDate, isNull);
    expect((await get(a)).dueTime, isNull);

    await repo.dropInto([a], const PriorityTarget(Priority.medium), const {});
    expect((await get(a)).priority, Priority.medium);

    await repo.dropInto([a], const TagTarget('z'), const {});
    expect((await get(a)).tags, ['z', 'y']);

    final section = await repo.addSection(w, '进行中');
    await repo.dropInto([a], ListTarget(w), const {});
    expect((await get(a)).listId, w);
    await repo.dropInto([a], SectionTarget(w, section), const {});
    expect((await get(a)).sectionId, section);
    // Into another list: out of the section.
    await repo.dropInto([a], const ListTarget(inboxListId), const {});
    expect([(await get(a)).listId, (await get(a)).sectionId], [inboxListId, null]);

    // Only the order: nothing else changes.
    final before = await get(b);
    await repo.dropInto([b], const OrderTarget(), {b: -1});
    final after = await get(b);
    expect(after.sortOrder, -1);
    // (Lists inside compare by reference, so compare as JSON.)
    expect(after.copyWith(sortOrder: before.sortOrder, updatedAt: before.updatedAt).toJson().toString(),
        before.toJson().toString());
  });
}
