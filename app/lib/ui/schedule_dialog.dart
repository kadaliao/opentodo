import 'dart:math' as math;

import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/dates.dart';
import '../domain/recurrence.dart';
import '../domain/reminders.dart';
import '../state/reminder_providers.dart';

/// A task's date, time, span, reminders and repeat, as one choice.
class Schedule {
  const Schedule({
    required this.date,
    this.time,
    this.duration,
    this.reminders = const [],
    this.repeat,
    this.repeatFrom = RepeatFrom.dueDate,
  });

  /// Null: the person cleared the date (and with it everything else).
  final DateTime? date;
  final int? time;

  /// Minutes to the end of a span (时间段); see `domain/dates.dart`.
  final int? duration;
  final List<int> reminders;
  final RepeatRule? repeat;
  final int repeatFrom;
}

Future<Schedule?> showScheduleDialog(BuildContext context, Schedule initial) {
  return showDialog<Schedule>(
    context: context,
    builder: (context) => _ScheduleDialog(initial: initial),
  );
}

class _ScheduleDialog extends ConsumerStatefulWidget {
  const _ScheduleDialog({required this.initial});
  final Schedule initial;

  @override
  ConsumerState<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends ConsumerState<_ScheduleDialog> {
  late DateTime _date = widget.initial.date ?? dateOnly(DateTime.now());
  late int? _time = widget.initial.time;
  late List<int> _reminders = sortedReminders(widget.initial.reminders);
  late RepeatRule? _repeat = widget.initial.repeat;
  late int _repeatFrom = widget.initial.repeatFrom;

  /// 时间段: a start and an end instead of one date.
  late bool _span = widget.initial.date != null && widget.initial.duration != null;

  /// Minutes from the start to the end while picking a span; it may be zero
  /// or less while the end is set before the start. All day, whole days, and
  /// null is the one day.
  late int? _duration = widget.initial.duration;

  bool get _allDay => _time == null;

  bool get _spanValid =>
      !_span || (_allDay ? (_duration ?? minutesPerDay) >= minutesPerDay : (_duration ?? 0) > 0);

  /// The last day of an all-day span, or the end of a timed one.
  DateTime get _end {
    if (_allDay) {
      return addDays(_date, ((_duration ?? minutesPerDay) / minutesPerDay).ceil() - 1);
    }
    return DateTime(_date.year, _date.month, _date.day, 0, _time! + (_duration ?? 0));
  }

  /// Wall-clock minutes from the start to [end].
  int _minutesTo(DateTime end) =>
      DateTime.utc(end.year, end.month, end.day, end.hour, end.minute)
          .difference(DateTime.utc(_date.year, _date.month, _date.day, 0, _time ?? 0))
          .inMinutes;

  void _setSpan(bool on) {
    setState(() => _span = on);
    if (!on) return;
    if (_allDay && _duration == null) {
      // A span is usually a few hours: start at the next hour today, or in
      // the morning another day.
      final now = DateTime.now();
      final start = _date == dateOnly(now) && now.hour < 23 ? (now.hour + 1) * 60 : 9 * 60;
      _setTime(start);
    }
    if (!_allDay) setState(() => _duration ??= defaultSpanMinutes);
  }

  void _setSpanAllDay(bool allDay) {
    if (allDay == _allDay) return;
    if (allDay) {
      final days = daysBetween(_date, dateOnly(_end)) + (_end.hour == 0 && _end.minute == 0 ? 0 : 1);
      _setTime(null);
      setState(() => _duration = math.max(days, 1) * minutesPerDay);
    } else {
      _setTime(9 * 60);
      setState(() => _duration = defaultSpanMinutes);
    }
  }

  Future<DateTime?> _pickDay(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

  Future<int?> _pickClock(int? initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime: initial == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay(hour: initial ~/ 60 % 24, minute: initial % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _pickEndDay() async {
    final end = _end;
    final d = await _pickDay(dateOnly(end));
    if (d == null) return;
    setState(() {
      _duration = _allDay
          ? (daysBetween(_date, d) + 1) * minutesPerDay
          : _minutesTo(DateTime(d.year, d.month, d.day, end.hour, end.minute));
    });
  }

  Future<void> _pickEndTime() async {
    final end = _end;
    final m = await _pickClock(end.hour * 60 + end.minute);
    if (m == null) return;
    setState(() => _duration = _minutesTo(DateTime(end.year, end.month, end.day, 0, m)));
  }

  /// Reminders mean different things with and without a time, so switching
  /// starts them over: 准时 for a timed task, none for an all-day one.
  void _setTime(int? time) {
    setState(() {
      if ((time == null) != (_time == null)) {
        _reminders = time == null ? const [] : defaultTimedReminders;
      }
      _time = time;
    });
  }

  Future<void> _pickTime() async {
    final m = await _pickClock(_time);
    if (m != null) _setTime(m);
  }

  Future<void> _pickReminders() async {
    final picked = await showReminderPicker(context, allDay: _allDay, selected: _reminders);
    if (picked != null) setState(() => _reminders = sortedReminders(picked));
  }

  Future<void> _pickRepeat(BuildContext rowContext) async {
    final box = rowContext.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final presets = <(String, RepeatRule?)>[
      ('不重复', null),
      ('每天', RepeatRule.daily),
      ('每周（${weekdayName(_date)}）', RepeatRule.weekly),
      ('每月（${_date.day}日）', RepeatRule.monthly),
      ('每年（${_date.month}月${_date.day}日）', RepeatRule.yearly),
      ('工作日（周一至周五）', RepeatRule.workdays),
    ];
    final scheme = Theme.of(context).colorScheme;
    final custom = _repeat != null &&
        (_repeatFrom != RepeatFrom.dueDate || !presets.any((p) => p.$2 == _repeat));
    final choice = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(rect.left, rect.bottom, rect.width, 0),
        Offset.zero & overlay.size,
      ),
      constraints: BoxConstraints.tightFor(width: rect.width),
      items: [
        for (final (label, rule) in presets)
          PopupMenuItem<Object>(
            value: rule ?? false,
            height: 40,
            child: _check(label, !custom && rule == _repeat, scheme),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: 'custom',
          height: 40,
          child: _check('自定义…', custom, scheme),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'custom') {
      final r = await showCustomRepeatDialog(
        context,
        date: _date,
        rule: _repeat ?? RepeatRule.weekly,
        repeatFrom: _repeatFrom,
      );
      if (r != null) {
        setState(() {
          _repeat = r.rule;
          _repeatFrom = r.repeatFrom;
        });
      }
      return;
    }
    setState(() {
      _repeat = choice is RepeatRule ? choice : null;
      _repeatFrom = RepeatFrom.dueDate;
    });
  }

  Widget _check(String label, bool on, ColorScheme scheme) => Row(children: [
        Expanded(child: Text(label)),
        if (on) Icon(Icons.check, size: 18, color: scheme.primary),
      ]);

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    final allowed = ref.watch(reminderControllerProvider);

    Widget quick(IconData icon, String label, DateTime d) => Tooltip(
          message: label,
          child: IconButton(
            isSelected: _date == d,
            selectedIcon: Icon(icon, color: scheme.primary),
            icon: Icon(icon),
            onPressed: () => setState(() => _date = d),
          ),
        );

    Widget row({
      required IconData icon,
      required String label,
      required bool set,
      required VoidCallback onTap,
      VoidCallback? onClear,
      String? clearTooltip,
    }) =>
        ListTile(
          leading: Icon(icon, color: set ? scheme.primary : null),
          title: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: set ? scheme.primary : null)),
          trailing: set && onClear != null
              ? IconButton(tooltip: clearTooltip, icon: const Icon(Icons.close), onPressed: onClear)
              : const Icon(Icons.chevron_right),
          onTap: onTap,
        );

    String day(DateTime d) => '${d.year == today.year ? '' : '${d.year}年'}'
        '${d.month}月${d.day}日 ${weekdayName(d)}';

    final compact = OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8));
    Widget spanRow(String label, DateTime date, int? time,
            {required VoidCallback onDate, required VoidCallback onTime}) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 16, 4),
          child: Row(children: [
            SizedBox(width: 40, child: Text(label)),
            Expanded(
              child: OutlinedButton(
                style: compact,
                onPressed: onDate,
                child: Text(day(date), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (time != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: OutlinedButton(
                  style: compact,
                  onPressed: onTime,
                  child: Text(timeLabel(time), maxLines: 1, softWrap: false),
                ),
              ),
            ],
          ]),
        );

    final end = _end;
    final dateSection = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          quick(Icons.today_outlined, '今天', today),
          quick(Icons.wb_twilight_outlined, '明天', addDays(today, 1)),
          quick(Icons.next_week_outlined, '下周一', addDays(startOfWeek(today), 7)),
          quick(Icons.calendar_month_outlined, '下个月',
              DateTime(today.year, today.month + 1, today.day)),
        ]),
      ),
      CalendarDatePicker(
        key: ValueKey(_date),
        initialDate: _date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        onDateChanged: (d) => setState(() => _date = d),
      ),
      row(
        icon: Icons.schedule,
        label: _time == null ? '时间' : timeLabel(_time!),
        set: _time != null,
        onTap: _pickTime,
        onClear: () => _setTime(null),
        clearTooltip: '清除时间',
      ),
    ];
    final spanSection = <Widget>[
      const SizedBox(height: 8),
      spanRow('开始', _date, _time,
          onDate: () async {
            final d = await _pickDay(_date);
            if (d != null) setState(() => _date = d);
          },
          onTime: _pickTime),
      spanRow('结束', dateOnly(end), _allDay ? null : end.hour * 60 + end.minute,
          onDate: _pickEndDay, onTime: _pickEndTime),
      SwitchListTile(
        contentPadding: const EdgeInsets.only(left: 24, right: 16),
        title: const Text('全天'),
        value: _allDay,
        onChanged: _setSpanAllDay,
      ),
      if (!_spanValid)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
          child: Text('结束要晚于开始', style: TextStyle(fontSize: 12, color: scheme.error)),
        ),
      const Divider(height: 1),
    ];

    return Dialog(
      child: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('日期')),
                  ButtonSegment(value: true, label: Text('时间段')),
                ],
                selected: {_span},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (s) => _setSpan(s.single),
              ),
            ),
            ...(_span ? spanSection : dateSection),
            row(
              icon: Icons.alarm,
              label: _reminders.isEmpty ? '提醒' : remindersSummary(_reminders, allDay: _allDay),
              set: _reminders.isNotEmpty,
              onTap: _pickReminders,
              onClear: () => setState(() => _reminders = const []),
              clearTooltip: '清除提醒',
            ),
            if (_reminders.isNotEmpty && allowed == false)
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 4),
                child: Row(children: [
                  Expanded(
                    child: Text('系统通知已关闭，提醒不会弹出',
                        style: TextStyle(fontSize: 12, color: scheme.error)),
                  ),
                  TextButton(
                    onPressed: () => ref.read(reminderControllerProvider.notifier).openSettings(),
                    child: const Text('去开启'),
                  ),
                ]),
              ),
            Builder(
              builder: (rowContext) => row(
                icon: Icons.repeat,
                label: _repeat == null
                    ? '重复'
                    : describeRepeat(_repeat!, _date, repeatFrom: _repeatFrom),
                set: _repeat != null,
                onTap: () => _pickRepeat(rowContext),
                onClear: () => setState(() {
                  _repeat = null;
                  _repeatFrom = RepeatFrom.dueDate;
                }),
                clearTooltip: '不重复',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, const Schedule(date: null)),
                    child: const Text('清除'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: !_spanValid
                        ? null
                        : () => Navigator.pop(
                      context,
                      Schedule(
                        date: _date,
                        time: _time,
                        duration: _span ? normalizeDuration(_time, _duration) : null,
                        reminders: _reminders,
                        repeat: _repeat,
                        repeatFrom: _repeatFrom,
                      ),
                    ),
                    child: const Text('确定'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---- reminders ----

/// Lets the person tick any number of reminders. Null if dismissed.
Future<List<int>?> showReminderPicker(
  BuildContext context, {
  required bool allDay,
  required List<int> selected,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (context) => _ReminderPicker(allDay: allDay, selected: selected),
  );
}

class _ReminderPicker extends StatefulWidget {
  const _ReminderPicker({required this.allDay, required this.selected});
  final bool allDay;
  final List<int> selected;

  @override
  State<_ReminderPicker> createState() => _ReminderPickerState();
}

class _ReminderPickerState extends State<_ReminderPicker> {
  late final _on = {...widget.selected};
  late final _options = sortedReminders([
    ...(widget.allDay ? allDayReminderPresets : timedReminderPresets),
    ...widget.selected,
  ]).reversed.toList();

  Future<void> _custom() async {
    final offset = await showDialog<int>(
      context: context,
      builder: (context) => _CustomReminder(allDay: widget.allDay),
    );
    if (offset == null) return;
    setState(() {
      _on.add(offset);
      if (!_options.contains(offset)) {
        _options
          ..add(offset)
          ..sort((a, b) => b.compareTo(a));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('提醒'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final o in _options)
              CheckboxListTile(
                value: _on.contains(o),
                title: Text(reminderLabel(o, allDay: widget.allDay)),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => v! ? _on.add(o) : _on.remove(o)),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('自定义…'),
              onTap: _custom,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _on.toList()), child: const Text('确定')),
      ],
    );
  }
}

/// 提前 [n] [分钟/小时/天] for a timed task; 提前 [n] 天 at a time of day for an
/// all-day one.
class _CustomReminder extends StatefulWidget {
  const _CustomReminder({required this.allDay});
  final bool allDay;

  @override
  State<_CustomReminder> createState() => _CustomReminderState();
}

class _CustomReminderState extends State<_CustomReminder> {
  final _amount = TextEditingController(text: '10');
  int _unit = 1; // minutes per unit
  int _minuteOfDay = 9 * 60;

  @override
  void initState() {
    super.initState();
    if (widget.allDay) _amount.text = '1';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _offset {
    final n = int.tryParse(_amount.text);
    if (n == null || n < 0 || n > 999) return null;
    return widget.allDay ? -n * 1440 + _minuteOfDay : -n * _unit;
  }

  @override
  Widget build(BuildContext context) {
    final offset = _offset;
    return AlertDialog(
      title: const Text('自定义提醒'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('提前'),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.allDay)
            const Text('天')
          else
            DropdownButton<int>(
              value: _unit,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('分钟')),
                DropdownMenuItem(value: 60, child: Text('小时')),
                DropdownMenuItem(value: 1440, child: Text('天')),
              ],
              onChanged: (v) => setState(() => _unit = v!),
            ),
        ]),
        if (widget.allDay) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(timeLabel(_minuteOfDay)),
            onPressed: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: _minuteOfDay ~/ 60, minute: _minuteOfDay % 60),
              );
              if (t != null) setState(() => _minuteOfDay = t.hour * 60 + t.minute);
            },
          ),
        ],
        const SizedBox(height: 12),
        Text(offset == null ? ' ' : reminderLabel(offset, allDay: widget.allDay),
            style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: offset == null ? null : () => Navigator.pop(context, offset),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

// ---- custom repeat ----

Future<({RepeatRule rule, int repeatFrom})?> showCustomRepeatDialog(
  BuildContext context, {
  required DateTime date,
  required RepeatRule rule,
  required int repeatFrom,
}) {
  return showDialog<({RepeatRule rule, int repeatFrom})>(
    context: context,
    builder: (context) => _CustomRepeat(date: date, rule: rule, repeatFrom: repeatFrom),
  );
}

enum _End { never, until, count }

class _CustomRepeat extends StatefulWidget {
  const _CustomRepeat({required this.date, required this.rule, required this.repeatFrom});
  final DateTime date;
  final RepeatRule rule;
  final int repeatFrom;

  @override
  State<_CustomRepeat> createState() => _CustomRepeatState();
}

class _CustomRepeatState extends State<_CustomRepeat> {
  late int _from = widget.repeatFrom;
  late Freq _freq = widget.rule.freq;
  late final _interval = TextEditingController(text: '${widget.rule.interval}');
  late Set<int> _weekdays = {
    ...(widget.rule.weekdays.isEmpty ? [widget.date.weekday] : widget.rule.weekdays),
  };

  /// Monthly: by day of the month, or by the nth weekday.
  late bool _byWeekday = widget.rule.nthWeekday != null;
  late int _monthDay = widget.rule.monthDays.firstOrNull ?? widget.date.day;
  late int _nth = widget.rule.nthWeekday?.n ?? _nthOf(widget.date);
  late int _nthDay = widget.rule.nthWeekday?.weekday ?? widget.date.weekday;

  late _End _end = widget.rule.until != null
      ? _End.until
      : (widget.rule.count != null ? _End.count : _End.never);
  late DateTime _until = widget.rule.until ?? DateTime(widget.date.year, widget.date.month + 1, widget.date.day);
  late final _count = TextEditingController(text: '${widget.rule.count ?? 10}');

  static int _nthOf(DateTime d) => d.day + 7 > daysInMonth(d.year, d.month) ? -1 : (d.day - 1) ~/ 7 + 1;

  @override
  void dispose() {
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  RepeatRule? get _rule {
    final interval = int.tryParse(_interval.text);
    if (interval == null || interval < 1 || interval > 999) return null;
    final count = int.tryParse(_count.text);
    if (_end == _End.count && (count == null || count < 1)) return null;
    final byDate = _from == RepeatFrom.dueDate;
    return RepeatRule(
      _freq,
      interval: interval,
      weekdays: byDate && _freq == Freq.weekly ? (_weekdays.toList()..sort()) : const [],
      monthDays: byDate && _freq == Freq.monthly && !_byWeekday ? [_monthDay] : const [],
      nthWeekday:
          byDate && _freq == Freq.monthly && _byWeekday ? (n: _nth, weekday: _nthDay) : null,
      until: _end == _End.until ? _until : null,
      count: _end == _End.count ? count : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rule = _rule;
    final byDate = _from == RepeatFrom.dueDate;
    const weekdayShort = ['一', '二', '三', '四', '五', '六', '日'];

    Widget numberField(TextEditingController c) => SizedBox(
          width: 64,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        );

    return AlertDialog(
      title: const Text('自定义重复'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: RepeatFrom.dueDate, label: Text('按到期日期')),
                ButtonSegment(value: RepeatFrom.completion, label: Text('按完成日期')),
              ],
              selected: {_from},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _from = s.single),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('每'),
              const SizedBox(width: 8),
              numberField(_interval),
              const SizedBox(width: 8),
              DropdownButton<Freq>(
                value: _freq,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: Freq.daily, child: Text('天')),
                  DropdownMenuItem(value: Freq.weekly, child: Text('周')),
                  DropdownMenuItem(value: Freq.monthly, child: Text('个月')),
                  DropdownMenuItem(value: Freq.yearly, child: Text('年')),
                ],
                onChanged: (f) => setState(() => _freq = f!),
              ),
            ]),
            if (byDate && _freq == Freq.weekly) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (var wd = 1; wd <= 7; wd++)
                  _DayToggle(
                    label: weekdayShort[wd - 1],
                    on: _weekdays.contains(wd),
                    onTap: () => setState(() {
                      // At least one day stays on.
                      if (_weekdays.contains(wd)) {
                        if (_weekdays.length > 1) _weekdays = {..._weekdays}..remove(wd);
                      } else {
                        _weekdays = {..._weekdays, wd};
                      }
                    }),
                  ),
              ]),
            ],
            if (byDate && _freq == Freq.monthly) ...[
              const SizedBox(height: 8),
              RadioGroup<bool>(
                groupValue: _byWeekday,
                onChanged: (v) => setState(() => _byWeekday = v!),
                child: Column(children: [
                  Row(children: [
                    const Radio<bool>(value: false),
                    const Text('按日期'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: _monthDay,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d日')),
                        const DropdownMenuItem(value: -1, child: Text('最后一天')),
                      ],
                      onChanged: (v) => setState(() {
                        _monthDay = v!;
                        _byWeekday = false;
                      }),
                    ),
                  ]),
                  Row(children: [
                    const Radio<bool>(value: true),
                    const Text('按星期'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: _nth,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final n in [1, 2, 3, 4, 5, -1])
                          DropdownMenuItem(value: n, child: Text(n == -1 ? '最后一个' : '第$n个')),
                      ],
                      onChanged: (v) => setState(() {
                        _nth = v!;
                        _byWeekday = true;
                      }),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _nthDay,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (var wd = 1; wd <= 7; wd++)
                          DropdownMenuItem(value: wd, child: Text('周${weekdayShort[wd - 1]}')),
                      ],
                      onChanged: (v) => setState(() {
                        _nthDay = v!;
                        _byWeekday = true;
                      }),
                    ),
                  ]),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              const Text('结束'),
              const SizedBox(width: 12),
              DropdownButton<_End>(
                value: _end,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: _End.never, child: Text('永不')),
                  DropdownMenuItem(value: _End.until, child: Text('截止日期')),
                  DropdownMenuItem(value: _End.count, child: Text('重复次数')),
                ],
                onChanged: (v) => setState(() => _end = v!),
              ),
              const SizedBox(width: 8),
              if (_end == _End.until)
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _until,
                      firstDate: widget.date,
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _until = d);
                  },
                  child: Text('${_until.year}年${_until.month}月${_until.day}日'),
                ),
              if (_end == _End.count) ...[numberField(_count), const SizedBox(width: 8), const Text('次')],
            ]),
            const SizedBox(height: 12),
            Text(
              rule == null ? '请填写有效的数字' : describeRepeat(rule, widget.date, repeatFrom: _from),
              style: TextStyle(color: rule == null ? scheme.error : scheme.primary),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: rule == null ? null : () => Navigator.pop(context, (rule: rule, repeatFrom: _from)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: on,
      button: true,
      label: '周$label',
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? scheme.primary : scheme.surfaceContainerHighest,
          ),
          child: Text(label,
              style: TextStyle(fontSize: 13, color: on ? scheme.onPrimary : scheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}
