import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../data/repo.dart';
import '../domain/dates.dart';
import '../domain/recurrence.dart';
import '../domain/reminders.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import 'task_actions.dart';
import 'task_tile.dart';
import 'theme.dart';

/// The right pane on a wide window.
class TaskDetailPane extends ConsumerWidget {
  const TaskDetailPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(selectedTaskProvider);
    final task = id == null ? null : ref.watch(taskByIdProvider(id));
    if (task == null) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.description_outlined, size: 48, color: scheme.outlineVariant),
          const SizedBox(height: 8),
          Text('点击任务查看详情', style: TextStyle(color: scheme.outline)),
        ]),
      );
    }
    return TaskDetail(key: ValueKey(task.id), task: task);
  }
}

/// The detail as its own page on a phone or medium window.
class TaskDetailPage extends ConsumerWidget {
  const TaskDetailPage({super.key, required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskByIdProvider(taskId));
    return Scaffold(
      appBar: AppBar(),
      body: task == null
          ? const SizedBox.shrink()
          : SafeArea(child: TaskDetail(key: ValueKey(task.id), task: task, onDeleted: () => Navigator.pop(context))),
    );
  }
}

class TaskDetail extends ConsumerStatefulWidget {
  const TaskDetail({super.key, required this.task, this.onDeleted});

  final Task task;
  final VoidCallback? onDeleted;

  @override
  ConsumerState<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends ConsumerState<TaskDetail> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _content = TextEditingController(text: widget.task.content);
  final _titleFocus = FocusNode();
  final _contentFocus = FocusNode();
  Timer? _debounce;
  late final TaskRepo _repo;

  @override
  void initState() {
    super.initState();
    // Kept so the last edit can still be saved while the widget is disposed.
    _repo = ref.read(repoProvider);
  }

  @override
  void didUpdateWidget(TaskDetail old) {
    super.didUpdateWidget(old);
    // Take changes made elsewhere (the list, another device) unless the
    // person is typing in that field.
    if (!_titleFocus.hasFocus && widget.task.title != _title.text) {
      _title.text = widget.task.title;
    }
    if (!_contentFocus.hasFocus && widget.task.content != _content.text) {
      _content.text = widget.task.content;
    }
  }

  @override
  void dispose() {
    _flush();
    _title.dispose();
    _content.dispose();
    _titleFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _flush);
  }

  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    final t = widget.task;
    if (_title.text != t.title) _repo.setTitle(t.id, _title.text);
    if (_content.text != t.content) _repo.setContent(t.id, _content.text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final task = widget.task;
    final repo = ref.read(repoProvider);
    final today = dateOnly(ref.watch(clockProvider));
    final lists = ref.watch(listsByIdProvider);
    final done = task.status != TaskStatus.open;
    final trashed = task.trashedAt != null;

    final overdue = isOverdue(task, ref.watch(clockProvider));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Top bar: done, date, priority, more.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
        child: Row(children: [
          PriorityCheckbox(
            checked: done,
            priority: task.priority,
            onChanged: trashed ? null : (v) => setTaskDone(context, ref, task, v),
          ),
          const SizedBox(width: 8),
          const SizedBox(height: 20, child: VerticalDivider(width: 16)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: _scheduleTooltip(task),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: task.dueDate == null
                        ? scheme.onSurfaceVariant
                        : (overdue ? scheme.error : scheme.primary),
                  ),
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(
                        task.dueDate == null
                            ? '设置日期'
                            : fullDueLabel(task.dueDate!, task.dueTime, today),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (task.dueDate != null && task.reminders.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.alarm, size: 15, semanticLabel: '有提醒'),
                    ],
                    if (task.dueDate != null && task.repeatRule != null) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.repeat, size: 15, semanticLabel: '重复'),
                    ],
                  ]),
                  onPressed: trashed ? null : () => pickDueDate(context, ref, task),
                ),
              ),
            ),
          ),
          PopupMenuButton<int>(
            tooltip: '优先级',
            icon: Icon(task.priority == Priority.none ? Icons.outlined_flag : Icons.flag,
                color: priorityColor(task.priority, scheme)),
            onSelected: (p) => repo.setPriority(task.id, p),
            itemBuilder: (_) => [
              for (final p in [Priority.high, Priority.medium, Priority.low, Priority.none])
                PopupMenuItem(
                  value: p,
                  child: Row(children: [
                    Icon(p == Priority.none ? Icons.outlined_flag : Icons.flag,
                        size: 18, color: priorityColor(p, scheme)),
                    const SizedBox(width: 12),
                    Text(priorityName(p)),
                  ]),
                ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onSelected: (a) async {
              switch (a) {
                case 'restore':
                  await repo.restoreTask(task.id);
                case 'skip':
                  await skipOccurrence(context, ref, task);
                case 'trash':
                  await repo.trashTask(task.id);
                  ref.read(selectedTaskProvider.notifier).select(null);
                  widget.onDeleted?.call();
                case 'purge':
                  await repo.purgeTask(task.id);
                  ref.read(selectedTaskProvider.notifier).select(null);
                  widget.onDeleted?.call();
              }
            },
            itemBuilder: (_) => trashed
                ? const [
                    PopupMenuItem(value: 'restore', child: Text('恢复')),
                    PopupMenuItem(value: 'purge', child: Text('永久删除')),
                  ]
                : [
                    if (task.repeatRule != null && task.dueDate != null && !done)
                      const PopupMenuItem(value: 'skip', child: Text('跳过此次')),
                    const PopupMenuItem(value: 'trash', child: Text('删除')),
                  ],
          ),
        ]),
      ),
      const Divider(),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            TextField(
              controller: _title,
              focusNode: _titleFocus,
              readOnly: trashed,
              maxLines: null,
              onChanged: (_) => _scheduleSave(),
              onEditingComplete: _flush,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
              decoration: const InputDecoration(
                hintText: '准备做什么？',
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
            if (task.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final tag in task.tags)
                  InputChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onDeleted: trashed
                        ? null
                        : () => repo.setTags(task.id, [...task.tags]..remove(tag)),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              focusNode: _contentFocus,
              readOnly: trashed,
              maxLines: null,
              minLines: 3,
              onChanged: (_) => _scheduleSave(),
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: InputDecoration(
                hintText: '描述',
                hintStyle: TextStyle(color: scheme.outline),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
            const SizedBox(height: 16),
            _Checklist(taskId: task.id, readOnly: trashed),
          ],
        ),
      ),
      const Divider(),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          TextButton.icon(
            icon: Text(task.listId == inboxListId ? '📥' : (lists[task.listId]?.emoji ?? '📋')),
            label: Text(listName(task.listId, lists)),
            onPressed: trashed
                ? null
                : () async {
                    final id = await pickList(context, ref, current: task.listId);
                    if (id != null) await repo.moveToList(task.id, id);
                  },
          ),
          const Spacer(),
          Text(
            '创建于 ${_shortDate(DateTime.fromMillisecondsSinceEpoch(task.createdAt), today)}',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ]),
      ),
    ]);
  }

  /// 提醒：准时 / 重复：每周一, for hovering over the date.
  String _scheduleTooltip(Task task) {
    if (task.dueDate == null) return '设置日期、提醒和重复';
    final lines = [
      if (task.reminders.isNotEmpty)
        '提醒：${remindersSummary(task.reminders, allDay: task.dueTime == null)}',
      if (RepeatRule.tryParse(task.repeatRule) case final rule?)
        '重复：${describeRepeat(rule, parseDateKey(task.dueDate!), repeatFrom: task.repeatFrom)}',
    ];
    return lines.isEmpty ? '修改日期' : lines.join('\n');
  }

  String _shortDate(DateTime at, DateTime today) {
    final date = dateLabel(dateOnly(at), today);
    return '$date ${timeLabel(at.hour * 60 + at.minute)}';
  }
}

class _Checklist extends ConsumerStatefulWidget {
  const _Checklist({required this.taskId, required this.readOnly});

  final String taskId;
  final bool readOnly;

  @override
  ConsumerState<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends ConsumerState<_Checklist> {
  final _add = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    await ref.read(repoProvider).addChecklistItem(widget.taskId, text);
    _add.clear();
    _addFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(checklistProvider(widget.taskId)).value ?? const <ChecklistItem>[];
    final repo = ref.read(repoProvider);
    final doneCount = items.where((i) => i.done).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('子任务 $doneCount/${items.length}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      for (final item in items)
        _ChecklistRow(
          key: ValueKey(item.id),
          item: item,
          readOnly: widget.readOnly,
          onToggle: () => repo.updateChecklistItem(item.id, done: !item.done),
          onRename: (t) => repo.updateChecklistItem(item.id, title: t),
          onDelete: () => repo.deleteChecklistItem(item.id),
        ),
      if (!widget.readOnly)
        Row(children: [
          Icon(Icons.add, size: 18, color: scheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _add,
              focusNode: _addFocus,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '添加子任务',
                hintStyle: TextStyle(color: scheme.outline, fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
            ),
          ),
        ]),
    ]);
  }
}

class _ChecklistRow extends StatefulWidget {
  const _ChecklistRow({
    super.key,
    required this.item,
    required this.readOnly,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  final ChecklistItem item;
  final bool readOnly;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late final _text = TextEditingController(text: widget.item.title);
  final _focus = FocusNode();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text != widget.item.title) {
        widget.onRename(_text.text);
      }
    });
  }

  @override
  void didUpdateWidget(_ChecklistRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.item.title != _text.text) _text.text = widget.item.title;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(children: [
        PriorityCheckbox(
          checked: widget.item.done,
          priority: Priority.none,
          size: 16,
          onChanged: widget.readOnly ? null : (_) => widget.onToggle(),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            readOnly: widget.readOnly,
            onSubmitted: widget.onRename,
            style: TextStyle(
              fontSize: 14,
              color: widget.item.done ? scheme.outline : scheme.onSurface,
              decoration: widget.item.done ? TextDecoration.lineThrough : null,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            ),
          ),
        ),
        if (!widget.readOnly)
          Opacity(
            opacity: _hover || _focus.hasFocus ? 1 : 0,
            child: IconButton(
              tooltip: '删除子任务',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: const Icon(Icons.close),
              onPressed: widget.onDelete,
            ),
          ),
      ]),
    );
  }
}
