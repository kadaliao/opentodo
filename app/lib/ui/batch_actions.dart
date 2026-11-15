import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../data/repo.dart';
import '../domain/dates.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import '../state/selection.dart';
import 'task_actions.dart' show pickList;
import 'theme.dart';

/// The picked tasks that still exist and aren't in the trash.
List<Task> _picked(WidgetRef ref) {
  final ids = ref.read(taskSelectionProvider).ids;
  return [
    for (final t in ref.read(tasksProvider).value ?? const <Task>[])
      if (ids.contains(t.id) && t.trashedAt == null) t,
  ];
}

void _toast(ScaffoldMessengerState? messenger, String text, {VoidCallback? undo}) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      action: undo == null ? null : SnackBarAction(label: '撤销', onPressed: undo),
      behavior: SnackBarBehavior.floating,
      width: 320,
      duration: const Duration(seconds: 4),
    ));
}

const _dateChoices = [
  ('today', Icons.today_outlined, '今天'),
  ('tomorrow', Icons.wb_twilight_outlined, '明天'),
  ('nextweek', Icons.next_week_outlined, '下周一'),
  ('pick', Icons.edit_calendar_outlined, '选择日期…'),
  ('clear', Icons.event_busy_outlined, '清除日期'),
];

List<PopupMenuEntry<String>> _dateItems() => [
      for (final (value, icon, label) in _dateChoices)
        PopupMenuItem(
          value: value,
          height: 40,
          child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)]),
        ),
    ];

List<PopupMenuEntry<int>> _priorityItems(ColorScheme scheme) => [
      for (final p in [Priority.high, Priority.medium, Priority.low, Priority.none])
        PopupMenuItem(
          value: p,
          height: 40,
          child: Row(children: [
            Icon(p == Priority.none ? Icons.outlined_flag : Icons.flag,
                size: 18, color: priorityColor(p, scheme)),
            const SizedBox(width: 12),
            Text(priorityName(p)),
          ]),
        ),
    ];

/// Moves every picked task to a day (keeping each one's time), or clears
/// their dates.
Future<void> _setDate(BuildContext context, WidgetRef ref, String choice) async {
  final tasks = _picked(ref);
  final repo = ref.read(repoProvider);
  final today = dateOnly(DateTime.now());
  DateTime? date;
  switch (choice) {
    case 'today':
      date = today;
    case 'tomorrow':
      date = addDays(today, 1);
    case 'nextweek':
      date = addDays(startOfWeek(today), 7);
    case 'pick':
      date = await showDatePicker(
        context: context,
        initialDate: today,
        firstDate: DateTime(today.year - 5),
        lastDate: DateTime(today.year + 10),
      );
      if (date == null) return;
    case 'clear':
      date = null;
  }
  for (final t in tasks) {
    await repo.setDue(t.id, date, t.dueTime);
  }
}

Future<void> _setPriority(WidgetRef ref, int priority) async {
  final repo = ref.read(repoProvider);
  for (final t in _picked(ref)) {
    await repo.setPriority(t.id, priority);
  }
}

Future<void> _move(BuildContext context, WidgetRef ref) async {
  final tasks = _picked(ref);
  final lists = {for (final t in tasks) t.listId};
  final listId = await pickList(context, ref, current: lists.length == 1 ? lists.single : null);
  if (listId == null) return;
  final repo = ref.read(repoProvider);
  for (final t in tasks) {
    await repo.moveToList(t.id, listId);
  }
}

Future<void> _editTags(BuildContext context, WidgetRef ref) async {
  final tasks = _picked(ref);
  final result = await showDialog<({Set<String> add, Set<String> remove})>(
    context: context,
    builder: (_) => _TagsDialog(tasks: tasks, known: ref.read(tagsProvider)),
  );
  if (result == null) return;
  final repo = ref.read(repoProvider);
  for (final t in tasks) {
    final tags = [
      for (final tag in t.tags)
        if (!result.remove.contains(tag)) tag,
      for (final tag in result.add)
        if (!t.tags.contains(tag)) tag,
    ];
    if (tags.join('\n') != t.tags.join('\n')) await repo.setTags(t.id, tags);
  }
}

/// Finishes every open picked task, with an undo that puts each back
/// (a repeating one to the occurrence it was on).
Future<void> _complete(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repo = ref.read(repoProvider);
  final tasks = _picked(ref).where(isOpen).toList();
  final undo = <Future<void> Function()>[];
  for (final t in tasks) {
    final repeat = await repo.setCompleted(t.id, true);
    undo.add(repeat == null
        ? () => repo.setCompleted(t.id, false)
        : () => repo.undoRepeatCompletion(repeat));
  }
  ref.read(taskSelectionProvider.notifier).clear();
  _toast(messenger, '已完成 ${tasks.length} 个任务', undo: () async {
    for (final u in undo.reversed) {
      await u();
    }
  });
}

Future<void> _togglePin(WidgetRef ref) async {
  final tasks = _picked(ref).where(isOpen).toList();
  final pin = tasks.any((t) => t.pinnedAt == null);
  final repo = ref.read(repoProvider);
  for (final t in tasks) {
    if ((t.pinnedAt == null) == pin) await repo.setPinned(t.id, pin);
  }
}

Future<void> _copy(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final tasks = _picked(ref);
  await Clipboard.setData(ClipboardData(text: [for (final t in tasks) t.title].join('\n')));
  _toast(messenger, '已复制 ${tasks.length} 个任务的标题');
}

Future<void> _trash(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final TaskRepo repo = ref.read(repoProvider);
  final tasks = _picked(ref);
  for (final t in tasks) {
    await repo.trashTask(t.id);
  }
  ref.read(taskSelectionProvider.notifier).clear();
  _toast(messenger, '已把 ${tasks.length} 个任务移到垃圾桶', undo: () async {
    for (final t in tasks) {
      await repo.restoreTask(t.id);
    }
  });
}

/// The right-hand pane on a wide window while tasks are picked.
class BatchPanel extends ConsumerWidget {
  const BatchPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    ref.watch(tasksProvider);
    final count = ref.watch(taskSelectionProvider).ids.length;
    final tasks = _picked(ref);
    final lists = ref.watch(listsByIdProvider);
    final listIds = {for (final t in tasks) t.listId};
    final tags = {for (final t in tasks) ...t.tags};
    final priorities = {for (final t in tasks) t.priority};
    final allPinned = tasks.where(isOpen).isNotEmpty && tasks.where(isOpen).every((t) => t.pinnedAt != null);

    Widget row(IconData icon, String label, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 20, color: color ?? scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        );

    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(children: [
                Icon(icon, color: color ?? scheme.primary),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(fontSize: 13, color: color)),
              ]),
            ),
          ),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Row(children: [
        Text('已选择 $count 项', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        TextButton(
          onPressed: () => ref.read(taskSelectionProvider.notifier).clear(),
          child: const Text('取消'),
        ),
      ]),
      const SizedBox(height: 12),
      Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          PopupMenuButton<String>(
            tooltip: '设置日期',
            itemBuilder: (_) => _dateItems(),
            onSelected: (c) => _setDate(context, ref, c),
            child: row(Icons.event_outlined, '设置日期'),
          ),
          PopupMenuButton<int>(
            tooltip: '优先级',
            itemBuilder: (_) => _priorityItems(scheme),
            onSelected: (p) => _setPriority(ref, p),
            child: row(
              priorities.length == 1 && priorities.single != Priority.none ? Icons.flag : Icons.outlined_flag,
              priorities.length == 1 ? priorityName(priorities.single) : '多种优先级',
              color: priorities.length == 1 ? priorityColor(priorities.single, scheme) : null,
            ),
          ),
          InkWell(
            onTap: () => _move(context, ref),
            child: row(
              Icons.drive_file_move_outline,
              listIds.length == 1 ? listName(listIds.single, lists) : '${listIds.length} 个清单',
            ),
          ),
          InkWell(
            onTap: () => _editTags(context, ref),
            child: row(Icons.sell_outlined, tags.isEmpty ? '标签' : tags.map((t) => '#$t').join(' ')),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
        children: [
          action(Icons.check_circle_outline, '完成', () => _complete(context, ref)),
          action(allPinned ? Icons.push_pin : Icons.push_pin_outlined, allPinned ? '取消置顶' : '置顶',
              () => _togglePin(ref)),
          action(Icons.copy_all_outlined, '复制标题', () => _copy(context, ref)),
          action(Icons.delete_outline, '删除', () => _trash(context, ref), color: scheme.error),
        ],
      ),
    ]);
  }
}

/// The bar along the bottom of the list on a phone or a narrow window
/// while tasks are picked. [order] is the view's tasks, for 全选.
class BatchBar extends ConsumerWidget {
  const BatchBar({super.key, required this.order});

  final List<String> order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final count = ref.watch(taskSelectionProvider).ids.length;
    const dense = VisualDensity.compact;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(children: [
            IconButton(
              tooltip: '取消选择',
              visualDensity: dense,
              icon: const Icon(Icons.close),
              onPressed: () => ref.read(taskSelectionProvider.notifier).clear(),
            ),
            Text('$count 项', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: '设置日期',
              icon: const Icon(Icons.event_outlined),
              style: const ButtonStyle(visualDensity: dense),
              itemBuilder: (_) => _dateItems(),
              onSelected: (c) => _setDate(context, ref, c),
            ),
            PopupMenuButton<int>(
              tooltip: '优先级',
              icon: const Icon(Icons.outlined_flag),
              style: const ButtonStyle(visualDensity: dense),
              itemBuilder: (_) => _priorityItems(scheme),
              onSelected: (p) => _setPriority(ref, p),
            ),
            IconButton(
              tooltip: '移动到…',
              visualDensity: dense,
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: () => _move(context, ref),
            ),
            IconButton(
              tooltip: '完成',
              visualDensity: dense,
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => _complete(context, ref),
            ),
            IconButton(
              tooltip: '删除',
              visualDensity: dense,
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: () => _trash(context, ref),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_vert),
              style: const ButtonStyle(visualDensity: dense),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('全选')),
                PopupMenuItem(value: 'tags', child: Text('标签…')),
                PopupMenuItem(value: 'pin', child: Text('置顶 / 取消置顶')),
                PopupMenuItem(value: 'copy', child: Text('复制标题')),
              ],
              onSelected: (a) => switch (a) {
                'all' => ref.read(taskSelectionProvider.notifier).selectAll(order),
                'tags' => _editTags(context, ref),
                'pin' => _togglePin(ref),
                _ => _copy(context, ref),
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// Tags for several tasks at once: a tick means all of them have it, a
/// dash some. Ticking adds a tag to all, unticking takes it off all.
class _TagsDialog extends StatefulWidget {
  const _TagsDialog({required this.tasks, required this.known});

  final List<Task> tasks;
  final List<String> known;

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  final _add = <String>{};
  final _remove = <String>{};
  final _extra = <String>[];
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// true: all have it; null: some; false: none.
  bool? _state(String tag) {
    if (_add.contains(tag)) return true;
    if (_remove.contains(tag)) return false;
    final n = widget.tasks.where((t) => t.tags.contains(tag)).length;
    return n == 0 ? false : (n == widget.tasks.length ? true : null);
  }

  void _toggle(String tag) => setState(() {
        if (_state(tag) == true) {
          _add.remove(tag);
          _remove.add(tag);
        } else {
          _remove.remove(tag);
          _add.add(tag);
        }
      });

  void _addNew() {
    final tag = _field.text.trim().replaceFirst(RegExp(r'^#+'), '');
    if (tag.isEmpty) return;
    setState(() {
      if (!widget.known.contains(tag) && !_extra.contains(tag)) _extra.add(tag);
      _remove.remove(tag);
      _add.add(tag);
      _field.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tags = [...widget.known, ..._extra];
    return AlertDialog(
      title: Text('${widget.tasks.length} 个任务的标签'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final tag in tags)
                CheckboxListTile(
                  value: _state(tag),
                  tristate: true,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(tag),
                  onChanged: (_) => _toggle(tag),
                ),
            ]),
          ),
          TextField(
            controller: _field,
            decoration: InputDecoration(
              hintText: '新标签',
              prefixIcon: const Icon(Icons.sell_outlined, size: 18),
              suffixIcon: IconButton(tooltip: '添加标签', icon: const Icon(Icons.add), onPressed: _addNew),
            ),
            onSubmitted: (_) => _addNew(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (add: {..._add}, remove: {..._remove})),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
