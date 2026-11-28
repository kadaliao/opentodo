import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/search.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import 'task_actions.dart';
import 'task_detail.dart';
import 'task_tile.dart' show PriorityCheckbox;
import 'theme.dart';
import '../domain/list_icon.dart';

/// Opens search: a dialog near the top of a computer window, a page on a
/// phone.
Future<void> openSearch(BuildContext context) {
  if (MediaQuery.sizeOf(context).width < Breakpoints.twoPane) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: SafeArea(child: SearchPanel())),
    ));
  }
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      alignment: Alignment(0, -0.5),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 600, height: 520, child: SearchPanel(inDialog: true)),
    ),
  );
}

/// Shows [task] where it lives: switches to the tasks module and a view
/// that lists it, selects it, and on a narrow window opens its page. Closes
/// anything open above the main screen first.
void revealTask(WidgetRef ref, NavigatorState navigator, Task task, {required bool wide}) {
  ref.read(moduleProvider.notifier).select(AppModule.tasks);
  final view = viewForTask(
      task, ref.read(selectedViewProvider), DateTime.now(), ref.read(filterRulesProvider));
  ref.read(selectedViewProvider.notifier).select(view);
  ref.read(selectedTaskProvider.notifier).select(task.id);
  navigator.popUntil((r) => r.isFirst);
  if (!wide) {
    navigator.push(MaterialPageRoute<void>(builder: (_) => TaskDetailPage(taskId: task.id)));
  }
}

/// One row of the results, for moving through them with the arrow keys.
sealed class _Entry {
  const _Entry();
}

final class _ViewEntry extends _Entry {
  const _ViewEntry(this.view, this.leading, this.label);
  final ViewRef view;
  final Widget leading;
  final String label;
}

final class _TaskEntry extends _Entry {
  const _TaskEntry(this.hit);
  final TaskHit hit;
}

class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key, this.inDialog = false});

  final bool inDialog;

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final _controller = TextEditingController();
  final _keys = <int, GlobalKey>{};
  String _query = '';
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Pinyin still being typed isn't part of the query yet.
      final v = _controller.value;
      final q = v.isComposingRangeValid
          ? v.composing.textBefore(v.text) + v.composing.textAfter(v.text)
          : v.text;
      if (q != _query) {
        setState(() {
          _query = q;
          _active = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(_Entry entry) {
    final navigator = Navigator.of(context);
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.threePane;
    switch (entry) {
      case _TaskEntry(:final hit):
        revealTask(ref, navigator, hit.task, wide: wide);
      case _ViewEntry(:final view):
        ref.read(moduleProvider.notifier).select(AppModule.tasks);
        ref.read(selectedViewProvider.notifier).select(view);
        navigator.popUntil((r) => r.isFirst);
    }
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _active = (_active + delta).clamp(0, count - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[_active]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: delta > 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];
    final results = search(
      _query,
      tasks: ref.watch(tasksProvider).value ?? const [],
      checklist: ref.watch(allChecklistProvider).value ?? const {},
      lists: lists,
      tags: ref.watch(tagsProvider),
      filters: ref.watch(filtersProvider).value ?? const [],
    );
    final entries = <_Entry>[
      for (final l in results.lists)
        _ViewEntry(ListViewRef(l.id), Text(listEmoji(l.emoji) ?? '📋', style: const TextStyle(fontSize: 16)), l.name),
      for (final f in results.filters)
        _ViewEntry(FilterViewRef(f.id), const Icon(Icons.filter_alt_outlined, size: 20), f.name),
      for (final t in results.tags)
        _ViewEntry(TagViewRef(t), const Icon(Icons.sell_outlined, size: 20), t),
      for (final h in results.tasks) _TaskEntry(h),
    ];
    final active = _active.clamp(0, entries.isEmpty ? 0 : entries.length - 1);
    final terms = searchTerms(_query);

    final field = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1, entries.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1, entries.length),
      },
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          if (entries.isNotEmpty) _open(entries[active]);
        },
        decoration: const InputDecoration(
          hintText: '搜索',
          border: InputBorder.none,
          isDense: true,
        ),
        style: const TextStyle(fontSize: 16),
      ),
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(children: [
        if (widget.inDialog)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.search, color: scheme.onSurfaceVariant),
          )
        else
          IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        Expanded(child: field),
        if (_controller.text.isNotEmpty)
          IconButton(
            tooltip: '清除',
            icon: const Icon(Icons.cancel, size: 18),
            color: scheme.outline,
            onPressed: _controller.clear,
          ),
        if (widget.inDialog)
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
      ]),
    );

    Widget body;
    if (terms.isEmpty) {
      body = _Placeholder(
        icon: Icons.manage_search,
        title: '搜索任务、清单、标签和过滤器',
        hint: '会查找标题、描述和子任务；多个词用空格隔开',
      );
    } else if (entries.isEmpty) {
      body = _Placeholder(
        icon: Icons.search_off,
        title: '没有找到“${_query.trim()}”',
        hint: '垃圾桶里的任务不在搜索范围内',
      );
    } else {
      final children = <Widget>[];
      var index = 0;
      void section(String title, int count) {
        if (count == 0) return;
        children.add(_SectionTitle(title));
        for (var i = 0; i < count; i++, index++) {
          final key = _keys.putIfAbsent(index, GlobalKey.new);
          final entry = entries[index];
          final i0 = index;
          children.add(KeyedSubtree(
            key: key,
            child: switch (entry) {
              _ViewEntry() => _ViewRow(
                  entry: entry,
                  terms: terms,
                  active: i0 == active,
                  onTap: () => _open(entry),
                ),
              _TaskEntry() => _TaskRow(
                  hit: entry.hit,
                  active: i0 == active,
                  onTap: () => _open(entry),
                ),
            },
          ));
        }
      }

      section('清单', results.lists.length);
      section('过滤器', results.filters.length);
      section('标签', results.tags.length);
      section('任务', results.tasks.length);
      if (results.moreTasks > 0) {
        children.add(Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '还有 ${results.moreTasks} 个任务，多输几个字缩小范围',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ));
      }
      body = ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 16), children: children);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const Divider(height: 1, indent: 16, endIndent: 16),
      Expanded(child: body),
    ]);
  }
}

/// [text] with the parts in [ranges] marked.
TextSpan highlighted(String text, Ranges ranges, TextStyle base, Color mark) {
  final children = <TextSpan>[];
  var pos = 0;
  for (final (start, end) in ranges) {
    if (start < pos || end > text.length) continue;
    if (start > pos) children.add(TextSpan(text: text.substring(pos, start)));
    children.add(TextSpan(
      text: text.substring(start, end),
      style: TextStyle(backgroundColor: mark),
    ));
    pos = end;
  }
  if (pos < text.length) children.add(TextSpan(text: text.substring(pos)));
  return TextSpan(style: base, children: children);
}

Color _markColor(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? const Color(0x80B8860B)
    : const Color(0xFFFFE08A);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(title,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.active, required this.onTap, required this.child});

  final bool active;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.secondaryContainer.withValues(alpha: 0.6) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

class _ViewRow extends StatelessWidget {
  const _ViewRow({required this.entry, required this.terms, required this.active, required this.onTap});

  final _ViewEntry entry;
  final List<String> terms;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ResultRow(
      active: active,
      onTap: onTap,
      child: Row(children: [
        IconTheme(
          data: IconThemeData(color: scheme.onSurfaceVariant),
          child: SizedBox(width: 22, child: Center(child: entry.leading)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            highlighted(entry.label, findRanges(entry.label, terms),
                TextStyle(fontSize: 14, color: scheme.onSurface), _markColor(scheme)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.hit, required this.active, required this.onTap});

  final TaskHit hit;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final task = hit.task;
    final done = task.status != TaskStatus.open;
    final lists = ref.watch(listsByIdProvider);
    final list = lists[task.listId];
    final today = dateOnly(ref.watch(clockProvider));
    final mark = _markColor(scheme);
    final meta = TextStyle(fontSize: 11, color: scheme.outline);

    return _ResultRow(
      active: active,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: PriorityCheckbox(
            checked: done,
            priority: task.priority,
            onChanged: (v) => setTaskDone(context, ref, task, v),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              highlighted(
                task.title.isEmpty ? '无标题' : task.title,
                task.title.isEmpty ? const [] : hit.titleRanges,
                TextStyle(
                  fontSize: 14,
                  color: done ? scheme.outline : scheme.onSurface,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: scheme.outline,
                ),
                mark,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (hit.snippet != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  highlighted(hit.snippet!, hit.snippetRanges,
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), mark),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            task.listId == inboxListId || list == null
                ? '收集箱'
                : '${listEmoji(list.emoji) ?? ''} ${list.name}'.trim(),
            style: meta,
          ),
          if (task.dueDate != null)
            Text(
              dueLabel(task.dueDate!, task.dueTime, today, duration: task.duration),
              style: meta.copyWith(
                color: isOverdue(task, ref.watch(clockProvider)) ? scheme.error : null,
              ),
            ),
        ]),
      ]),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.title, required this.hint});

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.outline)),
        ]),
      ),
    );
  }
}
