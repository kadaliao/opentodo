import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/reminders.dart';
import '../domain/task_defaults.dart';
import '../state/reminder_providers.dart';
import '../state/settings_providers.dart';
import 'theme.dart';

/// Opens 设置: a page on a phone, a dialog on a computer.
Future<void> showSettings(BuildContext context) {
  if (MediaQuery.sizeOf(context).width < Breakpoints.twoPane) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 520, height: 600, child: SettingsPage(inDialog: true)),
    ),
  );
}

/// Notifications, and what new tasks get when the person doesn't say.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.inDialog = false});

  final bool inDialog;

  static const _spans = [15, 30, 45, 60, 90, 120, 180];

  static String _spanLabel(int m) {
    if (m < 60) return '$m分钟';
    return m % 60 == 0 ? '${m ~/ 60}小时' : '${m ~/ 60}小时${m % 60}分钟';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final defaults = ref.watch(settingsProvider.select((s) => s.defaults));
    final allowed = ref.watch(reminderControllerProvider);
    void setDefaults(TaskDefaults d) => ref.read(settingsProvider.notifier).setDefaults(d);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        automaticallyImplyLeading: !inDialog,
        actions: [
          if (inDialog)
            IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const _Heading('提醒与通知'),
          _Group(children: [
            ListTile(
              title: const Text('系统通知'),
              subtitle: Text(
                allowed == false ? '已关闭，提醒不会弹出' : '提醒到点时由系统弹出通知',
                style: TextStyle(color: allowed == false ? scheme.error : scheme.outline),
              ),
              trailing: TextButton(
                onPressed: () => ref.read(reminderControllerProvider.notifier).openSettings(),
                child: Text(allowed == false ? '去开启' : '系统设置'),
              ),
            ),
          ]),
          const _Heading('任务默认值'),
          _Group(children: [
            _Choice<List<int>>(
              title: '默认提醒（有时间的任务）',
              value: defaults.timedReminders,
              options: [
                const <int>[],
                for (final o in timedReminderPresets) [o],
              ],
              label: (r) => r.isEmpty ? '无' : remindersSummary(r, allDay: false),
              equals: listEquals,
              onChanged: (r) => setDefaults(defaults.copyWith(timedReminders: r)),
            ),
            _Choice<List<int>>(
              title: '默认提醒（全天任务）',
              value: defaults.allDayReminders,
              options: [
                const <int>[],
                for (final o in allDayReminderPresets) [o],
              ],
              label: (r) => r.isEmpty ? '无' : remindersSummary(r, allDay: true),
              equals: listEquals,
              onChanged: (r) => setDefaults(defaults.copyWith(allDayReminders: r)),
            ),
            _Choice<int>(
              title: '时间段默认时长',
              value: defaults.spanMinutes,
              options: _spans,
              label: _spanLabel,
              onChanged: (m) => setDefaults(defaults.copyWith(spanMinutes: m)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '快速添加、日期对话框和在日历里拖动时，任务新有了日期或时间，就带上这里的提醒。设置只保存在这台设备上。',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

/// A setting with a few choices, picked from a menu. A value that isn't one
/// of [options] (set by a newer version) is shown and kept as it is.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
    this.equals,
  });

  final String title;
  final T value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final bool Function(T, T)? equals;

  bool _same(T a, T b) => equals?.call(a, b) ?? a == b;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = [...options, if (!options.any((o) => _same(o, value))) value];
    return ListTile(
      title: Text(title),
      trailing: PopupMenuButton<int>(
        tooltip: title,
        initialValue: all.indexWhere((o) => _same(o, value)),
        onSelected: (i) => onChanged(all[i]),
        itemBuilder: (_) => [
          for (var i = 0; i < all.length; i++)
            PopupMenuItem(value: i, height: 40, child: Text(label(all[i]))),
        ],
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label(value), style: TextStyle(color: scheme.primary)),
          Icon(Icons.unfold_more, size: 18, color: scheme.primary),
        ]),
      ),
    );
  }
}
