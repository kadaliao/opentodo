import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/search.dart';

import 'views_test.dart' show task;

ChecklistItem item(String taskId, String title, {bool done = false}) => ChecklistItem(
      id: '$taskId-$title',
      taskId: taskId,
      title: title,
      done: done,
      sortOrder: 0,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      serverVersion: 0,
      dirty: false,
    );

TaskList list(String id, String name) => TaskList(
      id: id,
      name: name,
      emoji: null,
      color: null,
      sortOrder: 0,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      serverVersion: 0,
      dirty: false,
    );

TaskFilter filter(String id, String name) => TaskFilter(
      id: id,
      name: name,
      rule: '{}',
      sortOrder: 0,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      serverVersion: 0,
      dirty: false,
    );

void main() {
  test('terms: split on spaces, lower case, # dropped', () {
    expect(searchTerms('  周报  Q3 #工作 # '), ['周报', 'q3', '工作']);
    expect(searchTerms('   '), isEmpty);
  });

  test('ranges are merged and ignore case', () {
    expect(findRanges('Weekly report, weekly', ['weekly']), [(0, 6), (15, 21)]);
    expect(findRanges('abcdef', ['abc', 'cde']), [(0, 5)]);
    expect(findRanges('晨会会议', ['会']), [(1, 3)]);
    expect(findRanges('无', ['x']), isEmpty);
  });

  test('every word has to be somewhere: title, notes, subtasks or tags', () {
    final tasks = [
      task('写周报', content: '本周数据'),
      task('开会', tags: ['周报']),
      task('整理', content: ''),
      task('季度总结'),
    ];
    final checklist = {
      '整理': [item('整理', '周报附件')],
    };
    final r = search('周报', tasks: tasks, checklist: checklist);
    expect(r.tasks.map((h) => h.task.title), containsAll(['写周报', '开会', '整理']));
    expect(r.tasks, hasLength(3));
    // Title matches first.
    expect(r.tasks.first.task.title, '写周报');

    final both = search('周报 数据', tasks: tasks, checklist: checklist);
    expect(both.tasks.map((h) => h.task.title), ['写周报']);
    expect(both.tasks.single.titleRanges, [(1, 3)]);
    expect(both.tasks.single.snippet, '本周数据');
    expect(both.tasks.single.snippetRanges, [(2, 4)]);

    final sub = search('附件', tasks: tasks, checklist: checklist).tasks.single;
    expect(sub.snippet, '☐ 周报附件');
    expect(sub.snippetRanges, [(4, 6)]);

    final tag = search('#周报', tasks: tasks).tasks.firstWhere((h) => h.task.title == '开会');
    expect(tag.snippet, '#周报');
  });

  test('open before finished, trash left out, newest first', () {
    final tasks = [
      task('周报 旧', status: TaskStatus.done),
      task('周报 一'),
      task('周报 二'),
      task('周报 删了', trashedAt: 1),
    ];
    final r = search('周报', tasks: tasks);
    expect(r.tasks.map((h) => h.task.title), ['周报 二', '周报 一', '周报 旧']);
  });

  test('notes are cut around the match', () {
    final long = '${'甲' * 40}关键词${'乙' * 100}';
    final hit = search('关键词', tasks: [task('标题', content: long)]).tasks.single;
    expect(hit.snippet, startsWith('…'));
    expect(hit.snippet, endsWith('…'));
    expect(hit.snippet!.substring(1, 13), '甲' * 12);
    expect(hit.snippetRanges, [(13, 16)]);
  });

  test('lists, tags and filters by name; long results are capped', () {
    final r = search(
      '工作',
      tasks: [for (var i = 0; i < 5; i++) task('工作$i')],
      lists: [list('a', '工作'), list('b', '家里')],
      tags: ['工作', '个人'],
      filters: [filter('f', '本周工作')],
      taskLimit: 3,
    );
    expect(r.lists.map((l) => l.name), ['工作']);
    expect(r.tags, ['工作']);
    expect(r.filters.map((f) => f.name), ['本周工作']);
    expect(r.tasks, hasLength(3));
    expect(r.moreTasks, 2);
    expect(search(' ', tasks: [task('x')]).isEmpty, isTrue);
  });
}
