import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/filters.dart';
import 'package:opentodo/domain/views.dart';

import 'views_test.dart' show now, task, shape, sec;

FilterRule rule(List<FilterCondition> conditions, {bool all = true}) =>
    FilterRule(matchAll: all, conditions: conditions);

FilterCondition cond(FilterField f, List<String> values, {bool exclude = false}) =>
    FilterCondition(f, values, exclude: exclude);

List<String> titles(FilterRule r, List<Task> tasks) =>
    tasks.where(r.matcher(now)).map((t) => t.title).toList();

void main() {
  // now is Sunday 2026-11-15, 10:00; the week runs Monday 11-09 to 11-15.
  final tasks = [
    task('过期', due: '2026-11-10', priority: Priority.high, tags: ['工作']),
    task('早上', due: '2026-11-15', time: 9 * 60, listId: 'work', tags: ['工作', '会议']),
    task('今天', due: '2026-11-15', priority: Priority.medium),
    task('明天', due: '2026-11-16', listId: 'work', priority: Priority.high),
    task('下周三', due: '2026-11-18', content: '准备季度周报'),
    task('下月', due: '2026-12-02', listId: 'home', priority: Priority.low),
    task('没日期', listId: 'home', tags: ['购物']),
    task('跨周末', due: '2026-11-14', duration: 3 * 1440), // Sat–Mon
    task('垃圾', due: '2026-11-15', trashedAt: 1),
  ];

  test('an empty rule takes every task that is not in the trash', () {
    expect(titles(const FilterRule(), tasks), hasLength(8));
    // A condition with nothing chosen is left out.
    expect(titles(rule([cond(FilterField.list, [])]), tasks), hasLength(8));
  });

  test('lists, tags and priorities', () {
    expect(titles(rule([cond(FilterField.list, ['work', 'home'])]), tasks),
        ['早上', '明天', '下月', '没日期']);
    expect(titles(rule([cond(FilterField.tag, ['工作'])]), tasks), ['过期', '早上']);
    expect(titles(rule([cond(FilterField.tag, [noTag])]), tasks),
        ['今天', '明天', '下周三', '下月', '跨周末']);
    expect(titles(rule([cond(FilterField.priority, ['high', 'medium'])]), tasks),
        ['过期', '今天', '明天']);
    expect(titles(rule([cond(FilterField.priority, ['none'])]), tasks),
        ['早上', '下周三', '没日期', '跨周末']);
  });

  test('dates: a span is on every day it covers', () {
    List<String> on(List<String> v) => titles(rule([cond(FilterField.date, v)]), tasks);
    expect(on(['overdue']), ['过期', '早上']); // 9:00 has passed
    expect(on(['today']), ['早上', '今天', '跨周末']);
    expect(on(['tomorrow']), ['明天', '跨周末']);
    expect(on(['thisWeek']), ['过期', '早上', '今天', '跨周末']);
    expect(on(['nextWeek']), ['明天', '下周三', '跨周末']);
    expect(on(['next7']), ['早上', '今天', '明天', '下周三', '跨周末']);
    expect(on(['thisMonth']), ['过期', '早上', '今天', '明天', '下周三', '跨周末']);
    expect(on(['none']), ['没日期']);
    expect(on(['none', 'tomorrow']), ['明天', '没日期', '跨周末']);
  });

  test('keywords look in the title and the notes, ignoring case', () {
    expect(titles(rule([cond(FilterField.keyword, ['周报'])]), tasks), ['下周三']);
    expect(titles(rule([cond(FilterField.keyword, ['  '])]), tasks), hasLength(8));
    final english = [task('Weekly Report')];
    expect(titles(rule([cond(FilterField.keyword, ['report'])]), english), ['Weekly Report']);
  });

  test('all, any, and excluding', () {
    final work = cond(FilterField.list, ['work']);
    final high = cond(FilterField.priority, ['high']);
    expect(titles(rule([work, high]), tasks), ['明天']);
    expect(titles(rule([work, high], all: false), tasks), ['过期', '早上', '明天']);
    expect(titles(rule([cond(FilterField.tag, ['工作'], exclude: true), cond(FilterField.date, ['today'])]), tasks),
        ['今天', '跨周末']);
  });

  test('JSON round trip keeps conditions from a newer version', () {
    final text = rule([
      cond(FilterField.list, ['inbox', 'work']),
      cond(FilterField.tag, [noTag], exclude: true),
    ], all: false)
        .encode();
    final back = FilterRule.parse(text);
    expect(back.encode(), text);
    expect(back.matchAll, isFalse);
    expect(back.conditions[1].exclude, isTrue);

    final future = FilterRule.parse(
        '{"match":"all","conditions":[{"field":"assignee","values":["me"]},'
        '{"field":"priority","values":["high"]}]}');
    expect(future.conditions.first.isKnown, isFalse);
    // Left out when matching, kept when saving.
    expect(titles(future, tasks), ['过期', '明天']);
    expect(future.encode(), contains('"assignee"'));
    expect(future.isSimple, isFalse);

    expect(FilterRule.parse('not json').conditions, isEmpty);
    expect(FilterRule.parse('[]').conditions, isEmpty);
    expect(FilterRule.parse('{"conditions":5}').conditions, isEmpty);
  });

  test('the simple form: one row per field, all included, joined by all', () {
    var r = const FilterRule();
    expect(r.isSimple, isTrue);
    r = r.withValues(FilterField.priority, ['high']).withValues(FilterField.list, ['work']);
    expect(r.conditions.map((c) => c.field), [FilterField.list, FilterField.priority]);
    expect(r.valuesOf(FilterField.list), ['work']);
    r = r.withValues(FilterField.list, []);
    expect(r.conditions.map((c) => c.field), [FilterField.priority]);
    expect(r.isSimple, isTrue);

    expect(rule([cond(FilterField.list, ['a'], exclude: true)]).isSimple, isFalse);
    expect(rule([cond(FilterField.list, ['a']), cond(FilterField.list, ['b'])]).isSimple, isFalse);
    expect(rule([cond(FilterField.list, ['a'])], all: false).isSimple, isFalse);
    // Empty rows don't count.
    expect(rule([cond(FilterField.list, []), cond(FilterField.list, ['b'])]).isSimple, isTrue);
  });

  test('a task added in a filter goes where the filter asks', () {
    final today = DateTime(2026, 11, 15);
    final h = rule([
      cond(FilterField.list, ['work']),
      cond(FilterField.tag, [noTag, '会议']),
      cond(FilterField.date, ['tomorrow']),
      cond(FilterField.priority, ['high']),
    ]).quickAddHints(today);
    expect(h.listId, 'work');
    expect(h.tag, '会议');
    expect(h.date, DateTime(2026, 11, 16));
    expect(h.priority, Priority.high);

    final vague = rule([
      cond(FilterField.list, ['work', 'home']),
      cond(FilterField.date, ['thisWeek']),
    ]).quickAddHints(today);
    expect(vague.listId, isNull);
    expect(vague.date, isNull);

    final d = quickAddDefaults(const FilterViewRef('f'), today, {
      'f': rule([cond(FilterField.list, ['work']), cond(FilterField.tag, ['会议'])]),
    });
    expect(d.listId, 'work');
    expect(d.tags, ['会议']);
    expect(quickAddDefaults(const FilterViewRef('gone'), today).listId, inboxListId);
  });

  test('a filter view groups by date, then later and undated; finished ones last', () {
    final rules = {'f': const FilterRule()};
    final all = [
      ...tasks,
      task('很久以后', due: '2027-03-01'),
      task('做完了', due: '2026-11-15', status: TaskStatus.done, completedAt: 5),
    ];
    expect(
      shape(buildSections(
          view: const FilterViewRef('f'), tasks: all, lists: const {}, now: now, filters: rules)),
      [
        sec('已过期', ['过期']),
        sec('今天, 周日', ['跨周末', '今天', '早上']),
        sec('明天, 周一', ['明天']),
        sec('11月18日, 周三', ['下周三']),
        sec('以后', ['下月', '很久以后']),
        sec('无日期', ['没日期']),
        sec('已完成', ['做完了']),
      ],
    );
    expect(openCount(const FilterViewRef('f'), all, now, rules), 9);
    // A filter that isn't there lists nothing.
    expect(openCount(const FilterViewRef('gone'), all, now, rules), 0);
    expect(viewTitle(const FilterViewRef('gone'), const {}), '过滤器');
  });

  test('describeValues', () {
    expect(describeValues(FilterField.date, [], lists: const {}), '所有');
    expect(describeValues(FilterField.date, ['today', 'none'], lists: const {}), '今天、无日期');
    expect(describeValues(FilterField.list, ['inbox', 'gone'], lists: const {}), '收集箱、已删除的清单');
    expect(describeValues(FilterField.tag, [noTag, '工作'], lists: const {}), '无标签、工作');
    expect(describeValues(FilterField.priority, ['high', 'low'], lists: const {}), '高、低');
  });
}
