import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/views.dart';

final now = DateTime(2026, 11, 15, 10); // Sunday
var _seq = 0;

Task task(
  String title, {
  String listId = inboxListId,
  String? due,
  int? time,
  int priority = 0,
  int status = TaskStatus.open,
  int? completedAt,
  int? trashedAt,
  List<String> tags = const [],
}) {
  final created = now.millisecondsSinceEpoch + _seq++;
  return Task(
    id: title,
    listId: listId,
    title: title,
    content: '',
    priority: priority,
    dueDate: due,
    dueTime: time,
    timeZone: null,
    tags: tags,
    status: status,
    completedAt: completedAt,
    trashedAt: trashedAt,
    sortOrder: -created.toDouble(),
    createdAt: created,
    updatedAt: created,
    deletedAt: null,
    serverVersion: 0,
    dirty: true,
  );
}

/// `title: a, b` per section, so failures print readably.
List<String> shape(List<TaskSection> sections) => [
      for (final s in sections) '${s.title}: ${s.tasks.map((t) => t.title).join(', ')}'
    ];

String sec(String? title, List<String> tasks) => '$title: ${tasks.join(', ')}';

void main() {
  final tasks = [
    task('过期', due: '2026-11-10'),
    task('晨会', due: '2026-11-15', time: 9 * 60),
    task('全天', due: '2026-11-15'),
    task('写周报', due: '2026-11-15', time: 15 * 60, priority: Priority.high),
    task('买菜', due: '2026-11-16'),
    task('读书', due: '2026-11-18', tags: ['自我提升']),
    task('远期', due: '2026-12-01'),
    task('无日期'),
    task('工作任务', listId: 'work', tags: ['自我提升']),
    task('做完了', due: '2026-11-15', status: TaskStatus.done,
        completedAt: now.millisecondsSinceEpoch),
    task('早就做完', due: '2026-11-01', status: TaskStatus.done,
        completedAt: DateTime(2026, 11, 1).millisecondsSinceEpoch),
    task('删掉的', due: '2026-11-15', trashedAt: now.millisecondsSinceEpoch),
  ];
  final lists = <String, TaskList>{};

  List<TaskSection> sections(ViewRef v) =>
      buildSections(view: v, tasks: tasks, lists: lists, now: now);

  test('today: overdue first, all-day before timed, finished today at the end', () {
    expect(shape(sections(const SmartViewRef(SmartKind.today))), [
      sec('已过期', ['过期']),
      sec('今天, 周日', ['全天', '晨会', '写周报']),
      sec('已完成', ['做完了']),
    ]);
  });

  test('tomorrow', () {
    expect(shape(sections(const SmartViewRef(SmartKind.tomorrow))), [
      sec('明天, 周一', ['买菜']),
    ]);
  });

  test('next 7 days groups by day', () {
    expect(shape(sections(const SmartViewRef(SmartKind.next7))), [
      sec('已过期', ['过期']),
      sec('今天, 周日', ['全天', '晨会', '写周报']),
      sec('明天, 周一', ['买菜']),
      sec('11月18日, 周三', ['读书']),
      sec('已完成', ['做完了']),
    ]);
  });

  test('inbox: newest first, finished collapsed at the end', () {
    final s = sections(const SmartViewRef(SmartKind.inbox));
    expect(s.first.title, isNull);
    expect(s.first.tasks.first.title, '无日期');
    expect(s.first.tasks.map((t) => t.title), isNot(contains('工作任务')));
    expect(s.last.title, '已完成');
  });

  test('a list', () {
    expect(shape(sections(const ListViewRef('work'))), [
      sec(null, ['工作任务']),
    ]);
  });

  test('a tag groups by list', () {
    expect(shape(sections(const TagViewRef('自我提升'))), [
      sec('收集箱', ['读书']),
      sec('收集箱', ['工作任务']),
    ]);
  });

  test('completed groups by the day it was finished', () {
    expect(shape(sections(const SmartViewRef(SmartKind.completed))), [
      sec('今天, 周日', ['做完了']),
      sec('11月1日, 周日', ['早就做完']),
    ]);
  });

  test('trash', () {
    expect(shape(sections(const SmartViewRef(SmartKind.trash))), [
      sec(null, ['删掉的']),
    ]);
  });

  test('counts are open tasks only', () {
    expect(openCount(const SmartViewRef(SmartKind.today), tasks, now), 4);
    expect(openCount(const SmartViewRef(SmartKind.next7), tasks, now), 6);
    expect(openCount(const SmartViewRef(SmartKind.inbox), tasks, now), 8);
  });

  test('dateViewShows', () {
    final today = DateTime(2026, 11, 15);
    const todayView = SmartViewRef(SmartKind.today);
    expect(dateViewShows(todayView, today, today), isTrue);
    expect(dateViewShows(todayView, DateTime(2026, 11, 16), today), isFalse);
    expect(dateViewShows(const SmartViewRef(SmartKind.next7), DateTime(2026, 11, 21), today), isTrue);
    expect(dateViewShows(const SmartViewRef(SmartKind.next7), DateTime(2026, 11, 22), today), isFalse);
    expect(dateViewShows(const ListViewRef('work'), DateTime(2030), today), isTrue);
  });

  test('quick-add defaults follow the view', () {
    final today = DateTime(2026, 11, 15);
    expect(quickAddDefaults(const SmartViewRef(SmartKind.tomorrow), today).date,
        DateTime(2026, 11, 16));
    expect(quickAddDefaults(const ListViewRef('work'), today).listId, 'work');
    expect(quickAddDefaults(const TagViewRef('x'), today).tags, ['x']);
  });
}
