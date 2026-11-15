import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/domain/dates.dart';
import 'package:opentodo/domain/timeline.dart';
import 'package:opentodo/domain/views.dart';

import 'views_test.dart' show task;

ListSection section(String id, String name, double order) => ListSection(
      id: id,
      listId: 'w',
      name: name,
      sortOrder: order,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      serverVersion: 0,
      dirty: false,
    );

Task inSection(Task t, String? sectionId) => t.copyWith(sectionId: Value(sectionId));

/// `title start..last` for each bar of each row.
List<List<String>> shapeRows(List<List<TimelineBar>> rows) => [
      for (final r in rows) [for (final b in r) '${b.task.title} ${b.start.day}..${b.last.day}'],
    ];

void main() {
  group('bars', () {
    test('cover the days a task is on', () {
      expect(TimelineBar(task('一天', due: '2026-11-15')).days, 1);
      // An all-day span of three days.
      final allDay = TimelineBar(task('三天', due: '2026-11-15', duration: 3 * minutesPerDay));
      expect((allDay.start, allDay.last, allDay.days),
          (DateTime(2026, 11, 15), DateTime(2026, 11, 17), 3));
      // 22:00 for three hours ends the next day; ending at midnight doesn't.
      expect(TimelineBar(task('过夜', due: '2026-11-15', time: 22 * 60, duration: 180)).days, 2);
      expect(TimelineBar(task('到半夜', due: '2026-11-15', time: 22 * 60, duration: 120)).days, 1);
    });

    test('overlap a range of days', () {
      final b = TimelineBar(task('三天', due: '2026-11-15', duration: 3 * minutesPerDay));
      expect(b.overlaps(DateTime(2026, 11, 17), DateTime(2026, 11, 20)), isTrue);
      expect(b.overlaps(DateTime(2026, 11, 10), DateTime(2026, 11, 15)), isTrue);
      expect(b.overlaps(DateTime(2026, 11, 18), DateTime(2026, 11, 20)), isFalse);
      expect(b.overlaps(DateTime(2026, 11, 10), DateTime(2026, 11, 14)), isFalse);
    });
  });

  group('lanes', () {
    final sections = [section('s2', '下周', 2), section('s1', '本周', 1)];
    final tasks = [
      inSection(task('甲', listId: 'w', due: '2026-11-16'), 's1'),
      inSection(task('乙', listId: 'w', due: '2026-11-15'), 's1'),
      inSection(task('丙', listId: 'w', due: '2026-11-23'), 's2'),
      inSection(task('想法', listId: 'w'), 's2'),
      task('散的', listId: 'w'),
      task('完成了', listId: 'w', due: '2026-11-14', status: TaskStatus.done, completedAt: 1),
      task('删了', listId: 'w', due: '2026-11-14', trashedAt: 1),
      task('别的清单', listId: 'x', due: '2026-11-14'),
      // A section that's gone: 未分组.
      inSection(task('旧分组', listId: 'w', due: '2026-11-20'), 'gone'),
    ];
    String titles(TimelineLane l) => '${l.title}: ${l.bars.map((b) => b.task.title).join(', ')}';

    test('one per section, in order, bars by first day', () {
      final t = buildTimeline('w', tasks, sections);
      expect(t.lanes.map(titles), ['未分组: 旧分组', '本周: 乙, 甲', '下周: 丙']);
      // Undated open tasks wait beside it, by section.
      expect([for (final g in t.undated) '${g.title}: ${g.tasks.map((x) => x.title).join(', ')}'],
          ['未分组: 散的', '下周: 想法']);
      expect(t.undatedTasks.map((x) => x.title), ['散的', '想法']);
    });

    test('finished tasks only when asked, after open ones on the same day', () {
      final more = [...tasks, task('同一天', listId: 'w', due: '2026-11-14')];
      final t = buildTimeline('w', more, sections, showDone: true);
      expect(titles(t.lanes.first), '未分组: 同一天, 完成了, 旧分组');
      expect(buildTimeline('w', more, sections).lanes.first.bars.map((b) => b.task.title), ['同一天', '旧分组']);
    });

    test('未分组 shows only with dated tasks, unless the list has no sections', () {
      final noLoose = tasks.where((t) => t.sectionId == 's1' || t.sectionId == 's2').toList();
      expect(buildTimeline('w', noLoose, sections).lanes.map((l) => l.title), ['本周', '下周']);
      // Its undated tasks still wait beside.
      expect(buildTimeline('w', [...noLoose, task('散的', listId: 'w')], sections).undated.first.title, '未分组');
      final plain = buildTimeline('w', [task('散的', listId: 'w')], const []);
      expect(plain.lanes.map(titles), ['null: ']); // no header without sections
    });

    test('on the same day, in the list\'s order', () {
      final a = task('先加的', listId: 'w', due: '2026-11-15', priority: Priority.low);
      final b = task('后加的', listId: 'w', due: '2026-11-15', priority: Priority.high);
      // Manual order: newest first (the helper's sortOrder).
      expect(buildTimeline('w', [a, b], const []).lanes.single.bars.map((x) => x.task.title), ['后加的', '先加的']);
      expect(
        buildTimeline('w', [a, b], const [], sort: TaskSort.title).lanes.single.bars.map((x) => x.task.title),
        ['后加的', '先加的'], // hou, xian
      );
    });
  });

  group('rows', () {
    final bars = [
      TimelineBar(task('长', due: '2026-11-15', duration: 4 * minutesPerDay)), // 15..18
      TimelineBar(task('甲', due: '2026-11-16')),
      TimelineBar(task('乙', due: '2026-11-17')),
      TimelineBar(task('丙', due: '2026-11-19')),
      TimelineBar(task('丁', due: '2026-11-19')),
    ];

    test('each bar in the first row with room', () {
      expect(shapeRows(packRows(bars)), [
        ['长 15..18', '丙 19..19'],
        ['甲 16..16', '乙 17..17', '丁 19..19'],
      ]);
    });

    test('a bar takes room for its title when the days are narrow', () {
      expect(shapeRows(packRows(bars, minDays: 3)), [
        ['长 15..18', '丙 19..19'],
        ['甲 16..16', '丁 19..19'],
        ['乙 17..17'],
      ]);
    });
  });

  group('dragging the right edge', () {
    DateTime d(int day) => DateTime(2026, 11, day);

    test('an all-day task covers whole days', () {
      final t = task('全天', due: '2026-11-15');
      expect(resizedDuration(t, d(17)), 3 * minutesPerDay);
      expect(resizedDuration(t, d(15)), isNull);
      // Never before its first day.
      expect(resizedDuration(t, d(12)), isNull);
      final span = task('三天', due: '2026-11-15', duration: 3 * minutesPerDay);
      expect(resizedDuration(span, d(16)), 2 * minutesPerDay);
      expect(resizedDuration(span, d(15)), isNull);
    });

    test('a timed task ends at the same time on the new day', () {
      // 9:00-11:00 → 9:00 to 11:00 two days later.
      final t = task('会', due: '2026-11-15', time: 9 * 60, duration: 120);
      expect(resizedDuration(t, d(17)), 2 * minutesPerDay + 120);
      expect(resizedDuration(t, d(15)), 120);
      // And back again.
      final long = task('会', due: '2026-11-15', time: 9 * 60, duration: 2 * minutesPerDay + 120);
      expect(resizedDuration(long, d(15)), 120);
      expect(resizedDuration(long, d(16)), minutesPerDay + 120);
      // A moment becomes a span to the same time.
      final moment = task('点', due: '2026-11-15', time: 9 * 60);
      expect(resizedDuration(moment, d(16)), minutesPerDay);
      expect(resizedDuration(moment, d(15)), isNull);
    });

    test('a timed task that can\'t keep its end time ends with the day', () {
      // At midnight for no time: to the next day, it ends at the end of it.
      final midnight = task('零点', due: '2026-11-15', time: 0);
      final d1 = resizedDuration(midnight, d(16))!;
      expect(spanLastDay('2026-11-15', 0, d1), d(16));
      expect(d1, 2 * minutesPerDay);
      // 23:00 for two hours, back onto its first day: no span.
      final late = task('夜', due: '2026-11-15', time: 23 * 60, duration: 120);
      expect(resizedDuration(late, d(15)), isNull);
      expect(spanLastDay('2026-11-15', 23 * 60, resizedDuration(late, d(17))), d(17));
    });
  });

  group('dragging the left edge', () {
    DateTime d(int day) => DateTime(2026, 11, day);
    String shape(({DateTime date, int? duration}) s) => '${dateKey(s.date)} ${s.duration}';

    test('an all-day task still ends on its last day', () {
      final t = task('全天', due: '2026-11-15');
      // Two days earlier: three days to the 15th.
      expect(shape(restartedSchedule(t, d(13))), '2026-11-13 ${3 * minutesPerDay}');
      expect(shape(restartedSchedule(t, d(15))), '2026-11-15 null');
      // Never past its last day.
      expect(shape(restartedSchedule(t, d(18))), '2026-11-15 null');
      final span = task('三天', due: '2026-11-15', duration: 3 * minutesPerDay); // 15..17
      expect(shape(restartedSchedule(span, d(16))), '2026-11-16 ${2 * minutesPerDay}');
      expect(shape(restartedSchedule(span, d(17))), '2026-11-17 null');
      expect(shape(restartedSchedule(span, d(20))), '2026-11-17 null');
    });

    test('a timed task keeps its time of day and its end', () {
      // 9:00-11:00 on the 15th, started two days earlier: 9:00 on the 13th
      // to 11:00 on the 15th.
      final t = task('会', due: '2026-11-15', time: 9 * 60, duration: 120);
      expect(shape(restartedSchedule(t, d(13))), '2026-11-13 ${2 * minutesPerDay + 120}');
      // And back.
      final long = task('会', due: '2026-11-13', time: 9 * 60, duration: 2 * minutesPerDay + 120);
      expect(shape(restartedSchedule(long, d(15))), '2026-11-15 120');
      // A moment becomes a span that ends at it.
      final moment = task('点', due: '2026-11-15', time: 9 * 60);
      expect(shape(restartedSchedule(moment, d(14))), '2026-11-14 $minutesPerDay');
      // 22:00 to 6:00 the next day, started on the next day: 22:00 is after
      // 6:00, so no span.
      final night = task('夜班', due: '2026-11-15', time: 22 * 60, duration: 8 * 60);
      expect(shape(restartedSchedule(night, d(16))), '2026-11-16 null');
    });
  });

  group('timelines of other views', () {
    final now = DateTime(2026, 11, 15, 10);
    final lists = {
      'w': TaskList(
        id: 'w', name: '工作', emoji: null, color: null, sortOrder: 1, createdAt: 0, updatedAt: 0,
        deletedAt: null, serverVersion: 0, dirty: false,
      ),
    };
    final tasks = [
      task('晨会', listId: 'w', due: '2026-11-15', tags: ['会']),
      task('交房租', due: '2026-11-14', priority: Priority.high),
      task('下周', listId: 'w', due: '2026-11-20', tags: ['会']),
      task('想法', listId: 'w', tags: ['会']),
      task('完成了', due: '2026-11-15', status: TaskStatus.done, completedAt: 1),
    ];
    String lanes(Timeline t) =>
        [for (final l in t.lanes) '${l.title}: ${l.bars.map((b) => b.task.title).join(', ')}'].join(' / ');

    test('今天 goes by list by default (not by date), and has no 无日期', () {
      final t = buildViewTimeline(const SmartViewRef(SmartKind.today), tasks, now: now, lists: lists);
      expect(lanes(t), '收集箱: 交房租 / 工作: 晨会');
      expect(t.lanes.map((l) => l.target).whereType<ListTarget>().map((x) => x.listId), [inboxListId, 'w']);
      expect(t.takesUndated, isFalse);
      expect(t.undated, isEmpty);
      // By date, as the list shows it, is no lanes at all on a timeline.
      final byDate = buildViewTimeline(const SmartViewRef(SmartKind.today), tasks,
          now: now, lists: lists, grouping: TaskGrouping.date);
      expect(lanes(byDate), lanes(t));
      final none = buildViewTimeline(const SmartViewRef(SmartKind.today), tasks,
          now: now, lists: lists, grouping: TaskGrouping.none);
      expect(lanes(none), 'null: 交房租, 晨会');
      expect(none.titled, isFalse);
      // Finished ones when asked.
      final done = buildViewTimeline(const SmartViewRef(SmartKind.today), tasks,
          now: now, lists: lists, grouping: TaskGrouping.none, showDone: true);
      expect(lanes(done), 'null: 交房租, 晨会, 完成了');
    });

    test('a tag: undated tasks wait beside, in a lane of their own group', () {
      final t = buildViewTimeline(const TagViewRef('会'), tasks, now: now, lists: lists);
      expect(lanes(t), '工作: 晨会, 下周');
      expect([for (final g in t.undated) '${g.title}: ${g.tasks.map((x) => x.title).join(', ')}'], ['工作: 想法']);
      // A group with only undated tasks still has its lane, to drag them
      // onto without leaving it.
      final onlyIdea = buildViewTimeline(const TagViewRef('会'), [tasks[3]], now: now, lists: lists);
      expect(lanes(onlyIdea), '工作: ');
      // By priority.
      final byPriority = buildViewTimeline(const TagViewRef('会'), tasks,
          now: now, lists: lists, grouping: TaskGrouping.priority);
      expect(lanes(byPriority), '无优先级: 晨会, 下周');
    });

    test('nothing to show is still one lane, to click on', () {
      final t = buildViewTimeline(const TagViewRef('空'), tasks, now: now, lists: lists);
      expect(t.lanes.single.title, isNull);
      expect(t.lanes.single.bars, isEmpty);
    });

    test('a list is its sections, whatever the grouping', () {
      final t = buildViewTimeline(const ListViewRef('w'), tasks, now: now, lists: lists, grouping: TaskGrouping.tag);
      expect(lanes(t), 'null: 晨会, 下周');
      expect(t.lanes.single.target, isA<SectionTarget>());
    });

    test('a task added on a lane starts with what the lane stands for', () {
      final today = DateTime(2026, 11, 15);
      expect(laneNewTask(const SmartViewRef(SmartKind.today), const ListTarget('w'), today).listId, 'w');
      final tag = laneNewTask(const TagViewRef('会'), const PriorityTarget(Priority.high), today);
      expect('${(tag.listId, tag.tags, tag.priority)}', '${(inboxListId, ['会'], Priority.high)}');
      final section = laneNewTask(const ListViewRef('w'), const SectionTarget('w', 's1'), today);
      expect((section.listId, section.sectionId), ('w', 's1'));
      expect(laneNewTask(const TagViewRef('会'), null, today).tags, ['会']);
    });
  });

  test('the month label', () {
    expect(timelineMonthLabel(DateTime(2026, 11, 20)), '2026年11月');
  });

  group('dropping on the timeline', () {
    late AppDatabase db;
    late TaskRepo repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = TaskRepo(db, clock: () => DateTime(2026, 11, 15, 10));
    });
    tearDown(() => db.close());

    test('dated tasks move by the same days, undated ones go on the day, all into the section', () async {
      final list = await repo.addList('工作');
      final s = await repo.addSection(list, '本周');
      final meeting = await repo.addTask(title: '会', listId: list, dueDate: DateTime(2026, 11, 15), dueTime: 9 * 60);
      await repo.setDuration(meeting, 90);
      final trip = await repo.addTask(title: '出差', listId: list, dueDate: DateTime(2026, 11, 16));
      await repo.setDuration(trip, 3 * minutesPerDay);
      final idea = await repo.addTask(title: '想法', listId: list);

      await repo.placeOnTimeline([meeting, trip, idea], days: 2, day: DateTime(2026, 11, 20), target: SectionTarget(list, s));
      final m = (await repo.getTask(meeting))!, t = (await repo.getTask(trip))!, i = (await repo.getTask(idea))!;
      expect((m.dueDate, m.dueTime, m.duration, m.sectionId), ('2026-11-17', 9 * 60, 90, s));
      expect((t.dueDate, t.dueTime, t.duration, t.sectionId), ('2026-11-18', null, 3 * minutesPerDay, s));
      expect((i.dueDate, i.dueTime, i.duration, i.sectionId), ('2026-11-20', null, null, s));

      // Another list, a tag, a priority: what the lane stands for.
      await repo.placeOnTimeline([idea], days: 1, day: DateTime(2026, 11, 1), target: const ListTarget(inboxListId));
      expect((await repo.getTask(idea))!.listId, inboxListId);
      await repo.placeOnTimeline([idea], days: 0, day: DateTime(2026, 11, 1), target: const TagTarget('会'));
      expect((await repo.getTask(idea))!.tags, ['会']);
      await repo.placeOnTimeline([idea], days: 0, day: DateTime(2026, 11, 1), target: const PriorityTarget(Priority.high));
      expect((await repo.getTask(idea))!.priority, Priority.high);
      expect((await repo.getTask(idea))!.dueDate, '2026-11-21'); // moved a day with the first

      // Back to 未分组 without moving.
      await repo.placeOnTimeline([meeting], days: 0, day: DateTime(2026, 11, 1), target: SectionTarget(list, null));
      final back = (await repo.getTask(meeting))!;
      expect((back.dueDate, back.sectionId), ('2026-11-17', null));
    });

    test('the left edge sets where it starts, keeping its time and reminders', () async {
      final id = await repo.addTask(title: '会', dueDate: DateTime(2026, 11, 15), dueTime: 9 * 60, reminders: [-15]);
      await repo.setDuration(id, 120);
      final t = (await repo.getTask(id))!;
      final to = restartedSchedule(t, DateTime(2026, 11, 13));
      await repo.setStart(id, to.date, to.duration);
      final m = (await repo.getTask(id))!;
      expect('${(m.dueDate, m.dueTime, m.duration, m.reminders)}', '${('2026-11-13', 9 * 60, 2 * minutesPerDay + 120, [-15])}');
    });
  });
}
