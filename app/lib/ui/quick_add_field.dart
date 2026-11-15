import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/quick_add_parser.dart';
import '../domain/recurrence.dart';
import '../domain/reminders.dart';
import '../domain/views.dart';
import '../state/providers.dart';

/// Colours the parts of the text the parser recognised.
class _HighlightController extends TextEditingController {
  List<QuickAddToken> tokens = const [];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Leave IME composition alone so pinyin input renders normally.
    if (tokens.isEmpty || (withComposing && value.isComposingRangeValid)) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final scheme = Theme.of(context).colorScheme;
    final highlight = style?.copyWith(
      color: scheme.primary,
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.5),
    );
    final children = <TextSpan>[];
    var pos = 0;
    for (final t in tokens) {
      if (t.start < pos || t.end > text.length) continue;
      if (t.start > pos) children.add(TextSpan(text: text.substring(pos, t.start)));
      children.add(TextSpan(text: text.substring(t.start, t.end), style: highlight));
      pos = t.end;
    }
    if (pos < text.length) children.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: children);
  }
}

/// Where a task typed into the field goes when the text doesn't say: a
/// calendar slot's day and time, say, instead of the current view's.
class QuickAddTarget {
  const QuickAddTarget({this.listId = inboxListId, this.date, this.time});

  final String listId;
  final DateTime? date;

  /// Used only with [date], and only when the text names no date.
  final int? time;
}

class QuickAddField extends ConsumerStatefulWidget {
  const QuickAddField({
    super.key,
    this.autofocus = false,
    this.onAdded,
    this.target,
    this.hintText,
  });

  final bool autofocus;
  final VoidCallback? onAdded;

  /// Null: the current view decides, and the new task is selected.
  final QuickAddTarget? target;
  final String? hintText;

  @override
  ConsumerState<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends ConsumerState<QuickAddField> {
  final _controller = _HighlightController();
  final _focus = FocusNode();
  QuickAddResult? _parsed;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reparse);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reparse() {
    final text = _controller.text;
    final parsed = text.trim().isEmpty ? null : parseQuickAdd(text, DateTime.now());
    _controller.tokens = parsed?.tokens ?? const [];
    if (parsed?.tokens.length != _parsed?.tokens.length ||
        parsed?.date != _parsed?.date ||
        parsed?.time != _parsed?.time ||
        parsed?.repeat != _parsed?.repeat) {
      setState(() => _parsed = parsed);
    } else {
      _parsed = parsed;
    }
  }

  Future<void> _submit() async {
    final parsed = _parsed;
    if (parsed == null || parsed.title.isEmpty) return;
    final target = widget.target;
    final view = ref.read(selectedViewProvider);
    final defaults = target == null
        ? quickAddDefaults(view, dateOnly(DateTime.now()))
        : (listId: target.listId, date: target.date, tags: const <String>[]);
    final dueDate = parsed.date ?? defaults.date;
    final dueTime = parsed.time ?? (parsed.date == null ? target?.time : null);
    final id = await ref.read(repoProvider).addTask(
          title: parsed.title,
          listId: defaults.listId,
          dueDate: dueDate,
          dueTime: dueTime,
          tags: {...defaults.tags, ...parsed.tags}.toList(),
          priority: parsed.priority ?? 0,
          // A task with a time gets a reminder at that time.
          reminders: dueTime != null ? defaultTimedReminders : const [],
          repeatRule: parsed.repeat?.toString(),
        );
    _controller.clear();
    if (target != null) {
      widget.onAdded?.call();
      return;
    }
    // A task dated outside a date view won't show up in it; say where it went.
    final today = dateOnly(DateTime.now());
    if (dueDate != null && !dateViewShows(view, dueDate, today) && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('已添加到${dateLabel(dueDate, today)}'),
        behavior: SnackBarBehavior.floating,
        width: 280,
        duration: const Duration(seconds: 2),
      ));
    }
    _focus.requestFocus();
    ref.read(selectedTaskProvider.notifier).select(id);
    widget.onAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final view = ref.watch(selectedViewProvider);
    final lists = ref.watch(listsByIdProvider);
    final targetList =
        widget.target?.listId ?? quickAddDefaults(view, dateOnly(DateTime.now())).listId;
    final parsed = _parsed;
    final preview = parsed?.date == null
        ? null
        : [
            fullDueLabel(dateKey(parsed!.date!), parsed.time, dateOnly(DateTime.now())),
            if (parsed.repeat != null) describeRepeat(parsed.repeat!, parsed.date!),
          ].join(' · ');

    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        prefixIcon: Icon(Icons.add, color: scheme.onSurfaceVariant),
        hintText: widget.hintText ?? '添加任务至“${listName(targetList, lists)}”，回车创建',
        hintStyle: TextStyle(color: scheme.outline, fontSize: 14),
        suffixIcon: preview == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: Icon(parsed!.repeat != null ? Icons.repeat : Icons.event,
                      size: 16, color: scheme.primary),
                  label: Text(preview, style: TextStyle(fontSize: 12, color: scheme.primary)),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: scheme.primaryContainer.withValues(alpha: 0.4),
                ),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
}

Future<void> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: QuickAddField(autofocus: true, onAdded: () => Navigator.pop(context)),
    ),
  );
}
