import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db.dart';
import '../../domain/calendar.dart';
import '../../domain/dates.dart';
import '../../domain/views.dart';
import '../../state/calendar_providers.dart';
import '../../state/providers.dart';
import '../account_ui.dart';
import '../quick_add_field.dart';
import '../task_actions.dart';
import '../task_detail.dart';
import '../theme.dart';
import 'agenda_view.dart';
import 'entry_chip.dart';
import 'month_view.dart';
import 'time_grid.dart';

/// The calendar module: a header to change mode and page, the mode's view,
/// and on a wide window a sidebar (small month, lists) and the selected
/// task's detail.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, required this.layout});

  final ShellLayout layout;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// Null until the person toggles it: open on a wide window.
  bool? _sidebarOpen;

  bool get _phone => widget.layout == ShellLayout.phone;
  bool get _sidebar => !_phone && (_sidebarOpen ?? widget.layout == ShellLayout.wide);

  late final _callbacks = CalendarCallbacks(
    openTask: _openTask,
    newTask: _newTask,
    showDay: _showDay,
  );

  void _openTask(String id) {
    if (widget.layout == ShellLayout.wide) {
      ref.read(selectedTaskProvider.notifier).select(id);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskDetailPage(taskId: id)));
    }
  }

  void _newTask(DateTime date, int? time) =>
      showNewTaskDialog(context, date: date, time: time, sheet: _phone);

  void _showDay(DateTime date) {
    ref.read(calendarAnchorProvider.notifier).go(date);
    ref.read(calendarPrefsProvider.notifier).setMode(CalendarMode.day);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(calendarPrefsProvider.select((p) => p.mode));
    final body = switch (mode) {
      CalendarMode.month => _phone ? PhoneMonth(callbacks: _callbacks) : MonthBoard(callbacks: _callbacks),
      CalendarMode.agenda => AgendaView(callbacks: _callbacks),
      _ => TimeGrid(key: ValueKey(mode), callbacks: _callbacks),
    };
    final selectedId = widget.layout == ShellLayout.wide ? ref.watch(selectedTaskProvider) : null;
    final selected = selectedId == null ? null : ref.watch(taskByIdProvider(selectedId));

    return Row(children: [
      if (_sidebar) ...[
        SizedBox(width: widget.layout == ShellLayout.wide ? 248 : 220, child: const CalendarSidebar()),
        const VerticalDivider(width: 1),
      ],
      Expanded(
        child: _CalendarShortcuts(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _CalendarHeader(
              layout: widget.layout,
              onToggleSidebar: _phone ? null : () => setState(() => _sidebarOpen = !_sidebar),
              sidebarOpen: _sidebar,
              onNewTask: () => _newTask(_defaultNewDay(), null),
            ),
            Expanded(child: body),
          ]),
        ),
      ),
      if (selected != null) ...[
        const VerticalDivider(width: 1),
        SizedBox(width: 380, child: _DetailPane(task: selected)),
      ],
    ]);
  }

  /// Where the header's + puts a task: today if it's on screen, else the
  /// first day shown (the selected day on the phone's month).
  DateTime _defaultNewDay() {
    final today = dateOnly(DateTime.now());
    final range = ref.read(calendarRangeProvider);
    final mode = ref.read(calendarPrefsProvider).mode;
    if (range.contains(today)) return today;
    if (mode == CalendarMode.month || mode == CalendarMode.agenda) {
      return ref.read(calendarAnchorProvider);
    }
    return range.start;
  }
}

/// Single keys for the calendar on a computer: D 3 W M A for the modes,
/// T for today, ← → to turn pages.
class _CalendarShortcuts extends ConsumerWidget {
  const _CalendarShortcuts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void mode(CalendarMode m) => ref.read(calendarPrefsProvider.notifier).setMode(m);
    final anchor = ref.read(calendarAnchorProvider.notifier);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyD): () => mode(CalendarMode.day),
        const SingleActivator(LogicalKeyboardKey.digit3): () => mode(CalendarMode.threeDays),
        const SingleActivator(LogicalKeyboardKey.keyW): () => mode(CalendarMode.week),
        const SingleActivator(LogicalKeyboardKey.keyM): () => mode(CalendarMode.month),
        const SingleActivator(LogicalKeyboardKey.keyA): () => mode(CalendarMode.agenda),
        const SingleActivator(LogicalKeyboardKey.keyT): anchor.today,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => anchor.page(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => anchor.page(1),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

const _modeKeys = {
  CalendarMode.day: 'D',
  CalendarMode.threeDays: '3',
  CalendarMode.week: 'W',
  CalendarMode.month: 'M',
  CalendarMode.agenda: 'A',
};

class _CalendarHeader extends ConsumerWidget {
  const _CalendarHeader({
    required this.layout,
    required this.onToggleSidebar,
    required this.sidebarOpen,
    required this.onNewTask,
  });

  final ShellLayout layout;
  final VoidCallback? onToggleSidebar;
  final bool sidebarOpen;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = ref.watch(calendarPrefsProvider);
    final anchor = ref.watch(calendarAnchorProvider);
    final anchorNotifier = ref.read(calendarAnchorProvider.notifier);
    final phone = layout == ShellLayout.phone;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 12 : 8, 8, 4, 8),
      child: Row(children: [
        if (onToggleSidebar != null)
          IconButton(
            tooltip: sidebarOpen ? '收起侧栏' : '展开侧栏',
            icon: const Icon(Icons.view_sidebar_outlined),
            onPressed: onToggleSidebar,
          ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            calendarTitle(prefs.mode, anchor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (phone ? textTheme.titleMedium : textTheme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (!phone)
          IconButton(tooltip: '添加任务', icon: const Icon(Icons.add), onPressed: onNewTask),
        PopupMenuButton<CalendarMode>(
          tooltip: '切换视图',
          initialValue: prefs.mode,
          onSelected: ref.read(calendarPrefsProvider.notifier).setMode,
          itemBuilder: (_) => [
            for (final m in CalendarMode.values)
              CheckedPopupMenuItem(
                value: m,
                checked: m == prefs.mode,
                child: Row(children: [
                  Expanded(child: Text(m.label)),
                  if (!phone) Text(_modeKeys[m]!, style: TextStyle(fontSize: 12, color: scheme.outline)),
                ]),
              ),
          ],
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(prefs.mode.label, style: const TextStyle(fontSize: 13)),
              Icon(Icons.arrow_drop_down, size: 18, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
        IconButton(
          tooltip: '上一页',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => anchorNotifier.page(-1),
        ),
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: anchorNotifier.today,
          child: const Text('今天'),
        ),
        IconButton(
          tooltip: '下一页',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right),
          onPressed: () => anchorNotifier.page(1),
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          icon: const Icon(Icons.more_horiz),
          onSelected: (a) {
            final n = ref.read(calendarPrefsProvider.notifier);
            switch (a) {
              case 'completed':
                n.set(prefs.copyWith(showCompleted: !prefs.showCompleted));
              case 'repeats':
                n.set(prefs.copyWith(showRepeats: !prefs.showRepeats));
              case 'lunar':
                n.set(prefs.copyWith(showLunar: !prefs.showLunar));
              case 'lists':
                showListFilterDialog(context);
            }
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: 'completed',
              checked: prefs.showCompleted,
              child: const Text('显示已完成'),
            ),
            CheckedPopupMenuItem(
              value: 'repeats',
              checked: prefs.showRepeats,
              child: const Text('显示重复任务以后的日期'),
            ),
            CheckedPopupMenuItem(
              value: 'lunar',
              checked: prefs.showLunar,
              child: const Text('显示农历和节假日'),
            ),
            if (!sidebarOpen) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'lists', child: Text('选择显示的清单…')),
            ],
          ],
        ),
      ]),
    );
  }
}

/// Left of the calendar on a wide window: a small month to jump to a day,
/// which lists to show, and the account.
class CalendarSidebar extends ConsumerStatefulWidget {
  const CalendarSidebar({super.key});

  @override
  ConsumerState<CalendarSidebar> createState() => _CalendarSidebarState();
}

class _CalendarSidebarState extends ConsumerState<CalendarSidebar> {
  /// The month the person paged the small month to; null follows the
  /// calendar.
  DateTime? _month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anchor = ref.watch(calendarAnchorProvider);
    ref.listen(calendarAnchorProvider, (_, _) {
      if (_month != null) setState(() => _month = null);
    });
    final today = dateOnly(ref.watch(clockProvider));
    final month = _month ?? anchor;
    final marked = entriesByDay(
      ref.watch(calendarEntriesProvider(monthGrid(month.year, month.month))),
    ).keys.toSet();

    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
          child: Row(children: [
            Expanded(
              child: Text('${month.year}年${month.month}月',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: '上个月',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _month = DateTime(month.year, month.month - 1)),
            ),
            IconButton(
              tooltip: '下个月',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _month = DateTime(month.year, month.month + 1)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: MiniMonth(
            month: month,
            selected: anchor,
            today: today,
            marked: marked,
            onTap: ref.read(calendarAnchorProvider.notifier).go,
            rowHeight: 36,
          ),
        ),
        const Divider(height: 24),
        const Expanded(child: SingleChildScrollView(child: ListFilter())),
        const Divider(),
        const AccountTile(),
      ]),
    );
  }
}

/// Which lists the calendar shows, as ticks.
class ListFilter extends ConsumerWidget {
  const ListFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = ref.watch(calendarPrefsProvider);
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];
    final rows = [
      (inboxListId, '📥', '收集箱'),
      for (final l in lists) (l.id, l.emoji ?? '📋', l.name),
    ];
    void toggle(String id, bool show) {
      final hidden = {...prefs.hiddenLists};
      show ? hidden.remove(id) : hidden.add(id);
      ref.read(calendarPrefsProvider.notifier).set(prefs.copyWith(hiddenLists: hidden));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text('显示的清单', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ),
      for (final (id, emoji, name) in rows)
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: !prefs.hiddenLists.contains(id),
          onChanged: (v) => toggle(id, v ?? true),
          title: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
    ]);
  }
}

Future<void> showListFilterDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('显示的清单'),
        contentPadding: const EdgeInsets.only(top: 12),
        content: const SizedBox(width: 320, child: SingleChildScrollView(child: ListFilter())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('完成')),
        ],
      ),
    );

class _DetailPane extends ConsumerWidget {
  const _DetailPane({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
        child: Row(children: [
          Expanded(
            child: Text('任务详情',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
          IconButton(
            tooltip: '关闭',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: () => ref.read(selectedTaskProvider.notifier).select(null),
          ),
        ]),
      ),
      Expanded(child: TaskDetail(key: ValueKey(task.id), task: task)),
    ]);
  }
}

/// A new task on [date] (at [time], or all day): a title field that still
/// understands dates typed into it, and which list it goes to (to start
/// with [listId], in its section [sectionId]). A dialog on a computer, a
/// bottom sheet on a phone.
Future<void> showNewTaskDialog(
  BuildContext context, {
  required DateTime date,
  int? time,
  bool sheet = false,
  String listId = inboxListId,
  String? sectionId,
}) {
  final form = _NewTaskForm(date: dateOnly(date), time: time, listId: listId, sectionId: sectionId);
  if (sheet) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: form,
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 440,
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), child: form),
      ),
    ),
  );
}

class _NewTaskForm extends ConsumerStatefulWidget {
  const _NewTaskForm({required this.date, this.time, required this.listId, this.sectionId});

  final DateTime date;
  final int? time;
  final String listId;

  /// A section of [listId]; dropped if the person picks another list.
  final String? sectionId;

  @override
  ConsumerState<_NewTaskForm> createState() => _NewTaskFormState();
}

class _NewTaskFormState extends ConsumerState<_NewTaskForm> {
  late String _listId = widget.listId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dateOnly(ref.watch(clockProvider));
    final lists = ref.watch(listsByIdProvider);
    final when = [
      daySectionTitle(widget.date, today),
      if (widget.time != null) timeLabel(widget.time!),
    ].join(' ');

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.event_outlined, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(when, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
      ]),
      const SizedBox(height: 12),
      QuickAddField(
        autofocus: true,
        target: QuickAddTarget(
          listId: _listId,
          sectionId: _listId == widget.listId ? widget.sectionId : null,
          date: widget.date,
          time: widget.time,
        ),
        hintText: '准备做什么？回车创建',
        onAdded: () => Navigator.pop(context),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: Text(_listId == inboxListId ? '📥' : (lists[_listId]?.emoji ?? '📋')),
          label: Text(listName(_listId, lists)),
          onPressed: () async {
            final id = await pickList(context, ref, current: _listId);
            if (id != null) setState(() => _listId = id);
          },
        ),
      ),
    ]);
  }
}
