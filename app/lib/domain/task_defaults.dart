/// What a task gets when the person doesn't say: its reminders when it is
/// given a date or a time, and how long a new span lasts. Set in 设置.
library;

import 'dates.dart';

class TaskDefaults {
  const TaskDefaults({
    this.timedReminders = const [0],
    this.allDayReminders = const [],
    this.spanMinutes = defaultSpanMinutes,
  });

  /// For a task with a time: 准时 unless the person chose otherwise.
  final List<int> timedReminders;

  /// For an all-day task: none unless the person chose, say, 当天 09:00.
  final List<int> allDayReminders;

  /// How long a span is when the person first asks for one.
  final int spanMinutes;

  static const standard = TaskDefaults();

  List<int> remindersFor({required bool allDay}) => allDay ? allDayReminders : timedReminders;

  TaskDefaults copyWith({List<int>? timedReminders, List<int>? allDayReminders, int? spanMinutes}) =>
      TaskDefaults(
        timedReminders: timedReminders ?? this.timedReminders,
        allDayReminders: allDayReminders ?? this.allDayReminders,
        spanMinutes: spanMinutes ?? this.spanMinutes,
      );

  Map<String, Object> toJson() => {
        'timedReminders': timedReminders,
        'allDayReminders': allDayReminders,
        'spanMinutes': spanMinutes,
      };

  /// Unknown or missing values fall back to the standard ones.
  factory TaskDefaults.fromJson(Map<String, dynamic> json) {
    List<int>? ints(Object? v) => v is List ? [for (final e in v) if (e is num) e.toInt()] : null;
    final span = json['spanMinutes'];
    return TaskDefaults(
      timedReminders: ints(json['timedReminders']) ?? standard.timedReminders,
      allDayReminders: ints(json['allDayReminders']) ?? standard.allDayReminders,
      spanMinutes: span is num && span > 0 ? span.toInt() : standard.spanMinutes,
    );
  }
}
