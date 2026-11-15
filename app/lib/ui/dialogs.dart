import 'package:material_ui/material_ui.dart';

import '../domain/dates.dart';

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String action = '确定',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

const _emojiChoices = ['📋', '💼', '🏠', '📚', '🏃', '🛒', '✈️', '💡', '🎯', '❤️', '🎨', '💰'];

Future<({String name, String? emoji})?> showListEditor(
  BuildContext context, {
  String? name,
  String? emoji,
}) {
  return showDialog<({String name, String? emoji})>(
    context: context,
    builder: (context) => _ListEditor(name: name, emoji: emoji),
  );
}

class _ListEditor extends StatefulWidget {
  const _ListEditor({this.name, this.emoji});
  final String? name;
  final String? emoji;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  late final _name = TextEditingController(text: widget.name);
  late String? _emoji = widget.emoji ?? _emojiChoices.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, emoji: _emoji));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.name == null ? '添加清单' : '编辑清单'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(hintText: '清单名称', border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _emojiChoices)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _emoji = e),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: _emoji == e ? scheme.secondaryContainer : null,
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 18)),
                ),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// What the date dialog returns. [cleared] means the person removed the date.
class DueChoice {
  const DueChoice(this.date, this.time) : cleared = false;
  const DueChoice.cleared()
      : date = null,
        time = null,
        cleared = true;

  final DateTime? date;
  final int? time;
  final bool cleared;
}

Future<DueChoice?> showDueDateDialog(
  BuildContext context, {
  DateTime? date,
  int? time,
}) {
  return showDialog<DueChoice>(
    context: context,
    builder: (context) => _DueDateDialog(date: date, time: time),
  );
}

class _DueDateDialog extends StatefulWidget {
  const _DueDateDialog({this.date, this.time});
  final DateTime? date;
  final int? time;

  @override
  State<_DueDateDialog> createState() => _DueDateDialogState();
}

class _DueDateDialogState extends State<_DueDateDialog> {
  late DateTime _date = widget.date ?? dateOnly(DateTime.now());
  late int? _time = widget.time;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final scheme = Theme.of(context).colorScheme;

    Widget quick(IconData icon, String label, DateTime d) => Tooltip(
          message: label,
          child: IconButton(
            isSelected: _date == d,
            selectedIcon: Icon(icon, color: scheme.primary),
            icon: Icon(icon),
            onPressed: () => setState(() => _date = d),
          ),
        );

    return Dialog(
      child: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              quick(Icons.today_outlined, '今天', today),
              quick(Icons.wb_twilight_outlined, '明天', addDays(today, 1)),
              quick(Icons.next_week_outlined, '下周一', addDays(startOfWeek(today), 7)),
              quick(Icons.calendar_month_outlined, '下个月', DateTime(today.year, today.month + 1, today.day)),
            ]),
          ),
          CalendarDatePicker(
            key: ValueKey(_date),
            initialDate: _date,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            onDateChanged: (d) => setState(() => _date = d),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(_time == null ? '时间' : timeLabel(_time!)),
            trailing: _time == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: '清除时间',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _time = null),
                  ),
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: _time == null
                    ? const TimeOfDay(hour: 9, minute: 0)
                    : TimeOfDay(hour: _time! ~/ 60, minute: _time! % 60),
              );
              if (t != null) setState(() => _time = t.hour * 60 + t.minute);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, const DueChoice.cleared()),
                  child: const Text('清除'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, DueChoice(_date, _time)),
                  child: const Text('确定'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
