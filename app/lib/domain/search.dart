/// Search across tasks (titles, notes, subtasks, tags), lists, tags and
/// saved filters.
///
/// The query is split on spaces; everything found must contain every word,
/// ignoring case. A leading `#` is dropped, so `#工作` finds the tag 工作.
/// Titles and names can also be typed in pinyin: `zhoubao` or `zb` finds
/// 周报 (two letters at least, so one letter doesn't find half the list).
library;

import '../data/db.dart';
import 'pinyin.dart';

/// Character ranges `[start, end)` to highlight.
typedef Ranges = List<(int, int)>;

List<String> searchTerms(String query) => [
      for (final w in query.trim().split(RegExp(r'\s+')))
        if (w.replaceFirst(RegExp(r'^#+'), '').isNotEmpty)
          w.replaceFirst(RegExp(r'^#+'), '').toLowerCase(),
    ];

/// Where [term] is spelled in pinyin in [text] (see [pinyinRanges]); only
/// for two letters or more.
Ranges _pinyin(String text, String term) =>
    term.length < 2 ? const [] : pinyinRanges(text, term);

/// Whether [text] has [term] as it is or in pinyin.
bool _has(String text, String lower, String term) =>
    lower.contains(term) || _pinyin(text, term).isNotEmpty;

/// Where [terms] occur in [text] (as typed, or in pinyin when [pinyin]),
/// sorted and merged.
Ranges findRanges(String text, List<String> terms, {bool pinyin = true}) {
  final lower = text.toLowerCase();
  // Lowercasing can change the length of a few scripts; positions would
  // then be off, so don't highlight rather than highlight the wrong part.
  if (lower.length != text.length) return const [];
  final found = <(int, int)>[];
  for (final term in terms) {
    for (var i = lower.indexOf(term); i >= 0; i = lower.indexOf(term, i + term.length)) {
      found.add((i, i + term.length));
    }
    if (pinyin) found.addAll(_pinyin(text, term));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in found) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}

bool _hasAll(String text, List<String> terms) {
  final lower = text.toLowerCase();
  return terms.every((w) => _has(text, lower, w));
}

class TaskHit {
  const TaskHit({
    required this.task,
    required this.titleRanges,
    this.snippet,
    this.snippetRanges = const [],
  });

  final Task task;
  final Ranges titleRanges;

  /// A line from the notes, a subtask or the tags, when the title alone
  /// doesn't show why the task was found.
  final String? snippet;
  final Ranges snippetRanges;
}

class SearchResults {
  const SearchResults({
    this.tasks = const [],
    this.lists = const [],
    this.tags = const [],
    this.filters = const [],
    this.moreTasks = 0,
  });

  final List<TaskHit> tasks;
  final List<TaskList> lists;
  final List<String> tags;
  final List<TaskFilter> filters;

  /// Tasks found beyond the ones listed.
  final int moreTasks;

  bool get isEmpty => tasks.isEmpty && lists.isEmpty && tags.isEmpty && filters.isEmpty;
}

/// Finds [query] in everything; tasks in the trash are left out. Open tasks
/// come before finished ones, and within those, title matches first, then
/// the most recently changed.
SearchResults search(
  String query, {
  required List<Task> tasks,
  Map<String, List<ChecklistItem>> checklist = const {},
  List<TaskList> lists = const [],
  List<String> tags = const [],
  List<TaskFilter> filters = const [],
  int taskLimit = 100,
}) {
  final terms = searchTerms(query);
  if (terms.isEmpty) return const SearchResults();

  final hits = <({TaskHit hit, int score})>[];
  for (final t in tasks) {
    if (t.trashedAt != null) continue;
    final items = checklist[t.id] ?? const <ChecklistItem>[];
    final title = t.title.toLowerCase();
    final content = t.content.toLowerCase();
    final inTitle = {for (final w in terms) w: _has(t.title, title, w)};
    final found = terms.every((w) =>
        inTitle[w]! ||
        content.contains(w) ||
        items.any((i) => i.title.toLowerCase().contains(w)) ||
        t.tags.any((tag) => tag.toLowerCase().contains(w)));
    if (!found) continue;
    final titleHasAll = inTitle.values.every((v) => v);
    final snippet = titleHasAll
        ? null
        : _snippet(t, items, [for (final w in terms) if (!inTitle[w]!) w]);
    hits.add((
      hit: TaskHit(
        task: t,
        titleRanges: findRanges(t.title, terms),
        snippet: snippet,
        snippetRanges: snippet == null ? const [] : findRanges(snippet, terms, pinyin: false),
      ),
      score: titleHasAll ? 2 : (inTitle.values.any((v) => v) ? 1 : 0),
    ));
  }
  hits.sort((a, b) {
    final ao = a.hit.task.status == TaskStatus.open, bo = b.hit.task.status == TaskStatus.open;
    if (ao != bo) return ao ? -1 : 1;
    if (a.score != b.score) return b.score.compareTo(a.score);
    return b.hit.task.updatedAt.compareTo(a.hit.task.updatedAt);
  });
  final shown = [for (final h in hits.take(taskLimit)) h.hit];

  return SearchResults(
    tasks: shown,
    moreTasks: hits.length - shown.length,
    lists: [for (final l in lists) if (_hasAll(l.name, terms)) l],
    tags: [for (final tag in tags) if (_hasAll(tag, terms)) tag],
    filters: [for (final f in filters) if (_hasAll(f.name, terms)) f],
  );
}

/// The part of the notes around the first of the words the title lacks
/// ([missing]); else the subtask that has it; else the tags.
String? _snippet(Task t, List<ChecklistItem> items, List<String> missing) {
  final content = t.content.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = content.toLowerCase();
  if (lower.length == content.length) {
    final at = [for (final w in missing) lower.indexOf(w)].where((i) => i >= 0);
    if (at.isNotEmpty) {
      final first = at.reduce((a, b) => a < b ? a : b);
      const before = 12, after = 60;
      final start = first > before ? first - before : 0;
      final end = first + after < content.length ? first + after : content.length;
      return '${start > 0 ? '…' : ''}${content.substring(start, end)}${end < content.length ? '…' : ''}';
    }
  }
  for (final i in items) {
    final lower = i.title.toLowerCase();
    if (missing.any(lower.contains)) return '${i.done ? '☑' : '☐'} ${i.title}';
  }
  final tags = t.tags.where((tag) => missing.any(tag.toLowerCase().contains));
  if (tags.isNotEmpty) return tags.map((tag) => '#$tag').join(' ');
  return null;
}
