/// Saved filters (过滤器): rules that gather tasks from every list, such as
/// "high priority this week in 工作".
///
/// A rule is a set of conditions joined by 且 (all must hold) or 或 (any
/// may). Each condition looks at one field of a task and lists the values
/// it accepts; it can be turned around to exclude them instead. A condition
/// with no values is left out, so an empty rule matches every task.
///
/// Stored as JSON in `TaskFilters.rule` and synced as is:
///
/// ```json
/// {"match": "all", "conditions": [
///   {"field": "list", "values": ["inbox", "<list id>"]},
///   {"field": "date", "values": ["today", "overdue"]},
///   {"field": "tag", "values": ["工作", ""], "exclude": true},
///   {"field": "priority", "values": ["high"]},
///   {"field": "keyword", "values": ["周报"]}
/// ]}
/// ```
///
/// The tag value `""` stands for a task without tags. Conditions on a field
/// this version doesn't know (written by a newer one) are kept as they are
/// and left out when matching.
library;

import 'dart:convert';

import '../data/db.dart';
import 'dates.dart';
import 'views.dart' show isOverdue, lastDueKey;

enum FilterField {
  list('清单'),
  tag('标签'),
  date('日期'),
  priority('优先级'),
  keyword('内容');

  const FilterField(this.label);
  final String label;
}

/// The date choices a filter offers.
enum DateChoice {
  overdue('已过期'),
  today('今天'),
  tomorrow('明天'),
  thisWeek('本周'),
  next7('最近7天'),
  nextWeek('下周'),
  thisMonth('本月'),
  none('无日期');

  const DateChoice(this.label);
  final String label;
}

/// Priority values as a filter stores them, highest first.
const priorityChoices = [
  ('high', Priority.high, '高'),
  ('medium', Priority.medium, '中'),
  ('low', Priority.low, '低'),
  ('none', Priority.none, '无'),
];

String _priorityKey(int p) =>
    priorityChoices.firstWhere((c) => c.$2 == p, orElse: () => priorityChoices.last).$1;

/// The tag value that stands for "no tags".
const noTag = '';

class FilterCondition {
  const FilterCondition(this.field, this.values, {this.exclude = false})
      : raw = null;

  /// A condition this version can't read, kept so saving doesn't drop it.
  const FilterCondition._unknown(Map<String, dynamic> this.raw)
      : field = null,
        values = const [],
        exclude = false;

  factory FilterCondition.fromJson(Map<String, dynamic> j) {
    final field = FilterField.values.where((f) => f.name == j['field']).firstOrNull;
    final values = j['values'];
    if (field == null || values is! List) return FilterCondition._unknown(j);
    return FilterCondition(
      field,
      [for (final v in values) if (v is String) v],
      exclude: j['exclude'] == true,
    );
  }

  /// Null for a condition from a newer version; see [raw].
  final FilterField? field;
  final List<String> values;

  /// Keeps the tasks that *don't* match instead (不包含).
  final bool exclude;
  final Map<String, dynamic>? raw;

  bool get isKnown => field != null;

  /// Whether it takes part in matching.
  bool get isActive =>
      isKnown && values.any((v) => field != FilterField.keyword || v.trim().isNotEmpty);

  FilterCondition copyWith({FilterField? field, List<String>? values, bool? exclude}) =>
      FilterCondition(
        field ?? this.field!,
        values ?? this.values,
        exclude: exclude ?? this.exclude,
      );

  Map<String, dynamic> toJson() =>
      raw ??
      {
        'field': field!.name,
        'values': values,
        if (exclude) 'exclude': true,
      };
}

class FilterRule {
  const FilterRule({this.matchAll = true, this.conditions = const []});

  factory FilterRule.fromJson(Map<String, dynamic> j) {
    final conditions = j['conditions'];
    return FilterRule(
      matchAll: j['match'] != 'any',
      conditions: [
        if (conditions is List)
          for (final c in conditions)
            if (c is Map) FilterCondition.fromJson(c.cast<String, dynamic>()),
      ],
    );
  }

  /// Reads the stored text; anything unreadable is an empty rule.
  factory FilterRule.parse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is Map) return FilterRule.fromJson(j.cast<String, dynamic>());
    } on FormatException {
      // Fall through.
    }
    return const FilterRule();
  }

  /// 且 (true) or 或.
  final bool matchAll;
  final List<FilterCondition> conditions;

  Map<String, dynamic> toJson() => {
        'match': matchAll ? 'all' : 'any',
        'conditions': [for (final c in conditions) c.toJson()],
      };

  String encode() => jsonEncode(toJson());

  FilterRule copyWith({bool? matchAll, List<FilterCondition>? conditions}) => FilterRule(
        matchAll: matchAll ?? this.matchAll,
        conditions: conditions ?? this.conditions,
      );

  /// Whether the simple form (one row per field, everything 包含, joined by
  /// 且) can show this rule.
  bool get isSimple {
    if (!matchAll) return false;
    final seen = <FilterField>{};
    for (final c in conditions) {
      if (!c.isKnown) return false;
      if (!c.isActive) continue;
      if (c.exclude || !seen.add(c.field!)) return false;
      if (c.field == FilterField.keyword && c.values.length > 1) return false;
    }
    return true;
  }

  /// The values the simple form shows for [field].
  List<String> valuesOf(FilterField field) => conditions
      .where((c) => c.field == field && c.isActive && !c.exclude)
      .expand((c) => c.values)
      .toList();

  /// Replaces [field]'s row in the simple form; no values removes it.
  FilterRule withValues(FilterField field, List<String> values) {
    final out = <FilterCondition>[];
    var placed = false;
    for (final c in conditions) {
      if (c.field != field) {
        out.add(c);
      } else if (!placed && values.isNotEmpty) {
        out.add(FilterCondition(field, values));
        placed = true;
      }
    }
    if (!placed && values.isNotEmpty) out.add(FilterCondition(field, values));
    // Keep the rows in the order the form shows them.
    out.sort((a, b) =>
        (a.field?.index ?? FilterField.values.length).compareTo(b.field?.index ?? FilterField.values.length));
    return FilterRule(conditions: out);
  }

  /// Leaves out conditions with nothing chosen.
  FilterRule tidy() => copyWith(
      conditions: [for (final c in conditions) if (c.isActive || !c.isKnown) c]);

  /// A test for tasks as of [now]. Trashed tasks never match.
  bool Function(Task) matcher(DateTime now) {
    final tests = [
      for (final c in conditions)
        if (c.isActive) _conditionTest(c, now),
    ];
    if (tests.isEmpty) return (t) => t.trashedAt == null;
    return matchAll
        ? (t) => t.trashedAt == null && tests.every((test) => test(t))
        : (t) => t.trashedAt == null && tests.any((test) => test(t));
  }

  /// Where a task typed into the filter's quick-add field goes: into the
  /// list, tag, day and priority the rule asks for, when it asks for one.
  ({String? listId, DateTime? date, String? tag, int? priority}) quickAddHints(
      DateTime today) {
    if (!matchAll) return (listId: null, date: null, tag: null, priority: null);
    String? only(FilterField f) {
      final c = conditions.where((c) => c.field == f && c.isActive && !c.exclude);
      return c.length == 1 && c.single.values.length == 1 ? c.single.values.single : null;
    }

    final list = only(FilterField.list);
    final tag = conditions
        .where((c) => c.field == FilterField.tag && c.isActive && !c.exclude)
        .expand((c) => c.values)
        .where((v) => v != noTag)
        .firstOrNull;
    final date = switch (only(FilterField.date)) {
      'today' => today,
      'tomorrow' => addDays(today, 1),
      _ => null,
    };
    final p = only(FilterField.priority);
    return (
      listId: list,
      date: date,
      tag: tag,
      priority: p == null ? null : priorityChoices.where((c) => c.$1 == p).firstOrNull?.$2,
    );
  }
}

bool Function(Task) _conditionTest(FilterCondition c, DateTime now) {
  final values = c.values.toSet();
  final bool Function(Task) test = switch (c.field!) {
    FilterField.list => (t) => values.contains(t.listId),
    FilterField.tag => (t) => t.tags.isEmpty ? values.contains(noTag) : t.tags.any(values.contains),
    FilterField.priority => (t) => values.contains(_priorityKey(t.priority)),
    FilterField.keyword => _keywordTest(c.values),
    FilterField.date => _dateTest(values, now),
  };
  return c.exclude ? (t) => !test(t) : test;
}

bool Function(Task) _keywordTest(List<String> values) {
  final words = [
    for (final v in values)
      if (v.trim().isNotEmpty) v.trim().toLowerCase(),
  ];
  return (t) {
    final title = t.title.toLowerCase(), content = t.content.toLowerCase();
    return words.any((w) => title.contains(w) || content.contains(w));
  };
}

bool Function(Task) _dateTest(Set<String> values, DateTime now) {
  final today = dateOnly(now);
  final weekStart = startOfWeek(today);
  // Inclusive ranges of date keys.
  final ranges = <(String, String)>[];
  void range(DateTime from, DateTime to) => ranges.add((dateKey(from), dateKey(to)));
  for (final v in values) {
    switch (DateChoice.values.where((d) => d.name == v).firstOrNull) {
      case DateChoice.today:
        range(today, today);
      case DateChoice.tomorrow:
        range(addDays(today, 1), addDays(today, 1));
      case DateChoice.thisWeek:
        range(weekStart, addDays(weekStart, 6));
      case DateChoice.next7:
        range(today, addDays(today, 6));
      case DateChoice.nextWeek:
        range(addDays(weekStart, 7), addDays(weekStart, 13));
      case DateChoice.thisMonth:
        range(DateTime(today.year, today.month), DateTime(today.year, today.month + 1, 0));
      case DateChoice.overdue || DateChoice.none || null:
        break;
    }
  }
  final none = values.contains(DateChoice.none.name);
  final overdue = values.contains(DateChoice.overdue.name);
  return (t) {
    if (t.dueDate == null) return none;
    if (overdue && isOverdue(t, now)) return true;
    // A span is on every day it covers.
    final first = t.dueDate!, last = lastDueKey(t);
    return ranges.any((r) => first.compareTo(r.$2) <= 0 && last.compareTo(r.$1) >= 0);
  };
}

/// What the picker shows for the chosen values, e.g. `今天、明天`.
String describeValues(
  FilterField field,
  List<String> values, {
  required Map<String, TaskList> lists,
}) {
  if (values.isEmpty) return '所有';
  String one(String v) => switch (field) {
        FilterField.list => v == inboxListId ? '收集箱' : (lists[v]?.name ?? '已删除的清单'),
        FilterField.tag => v == noTag ? '无标签' : v,
        FilterField.date => DateChoice.values.where((d) => d.name == v).firstOrNull?.label ?? v,
        FilterField.priority => priorityChoices.where((c) => c.$1 == v).firstOrNull?.$3 ?? v,
        FilterField.keyword => '“$v”',
      };
  return values.map(one).join('、');
}
