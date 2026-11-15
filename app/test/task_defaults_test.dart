import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/task_defaults.dart';
import 'package:opentodo/state/settings_providers.dart';

void main() {
  test('out of the box: 准时 with a time, nothing all day, spans of an hour', () {
    const d = TaskDefaults.standard;
    expect(d.remindersFor(allDay: false), [0]);
    expect(d.remindersFor(allDay: true), isEmpty);
    expect(d.spanMinutes, 60);
  });

  test('round trip, and bad or missing values fall back', () {
    const d = TaskDefaults(timedReminders: [-30], allDayReminders: [540, -900], spanMinutes: 90);
    final back = AppSettings.fromJson(const AppSettings(defaults: d).toJson()).defaults;
    expect(back.toJson(), d.toJson());

    final odd = TaskDefaults.fromJson({'timedReminders': 'x', 'spanMinutes': -5, 'allDayReminders': [540, 'y']});
    expect(odd.timedReminders, [0]);
    expect(odd.allDayReminders, [540]);
    expect(odd.spanMinutes, 60);
    expect(AppSettings.fromJson(const {}).defaults.toJson(), TaskDefaults.standard.toJson());
  });
}
