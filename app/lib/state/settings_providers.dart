import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/keys.dart';
import '../domain/task_defaults.dart';
import 'providers.dart';

/// The person's settings, kept on this device (not synced yet).
class AppSettings {
  const AppSettings({this.defaults = TaskDefaults.standard, this.snoozeMinutes = 15});

  final TaskDefaults defaults;

  /// How long 稍后提醒 on a notification puts the reminder off.
  final int snoozeMinutes;

  AppSettings copyWith({TaskDefaults? defaults, int? snoozeMinutes}) => AppSettings(
        defaults: defaults ?? this.defaults,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      );

  Map<String, Object> toJson() => {'defaults': defaults.toJson(), 'snoozeMinutes': snoozeMinutes};

  /// Unknown or missing values fall back to the defaults.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final snooze = json['snoozeMinutes'];
    return AppSettings(
      defaults: json['defaults'] is Map
          ? TaskDefaults.fromJson((json['defaults'] as Map).cast<String, dynamic>())
          : TaskDefaults.standard,
      snoozeMinutes: snooze is num && snooze > 0 ? snooze.toInt() : 15,
    );
  }
}

/// The settings as stored, for code outside the app's providers (a
/// notification button handled in the background).
Future<AppSettings> loadSettings(AppDatabase db) async {
  final raw = await db.getValue(Keys.settings);
  if (raw == null) return const AppSettings();
  try {
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on Object {
    return const AppSettings();
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  /// Set once the person changes something, so a slow load doesn't undo it.
  bool _changed = false;

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final loaded = await loadSettings(ref.read(databaseProvider));
    if (_changed || !ref.mounted) return;
    state = loaded;
  }

  void set(AppSettings settings) {
    _changed = true;
    state = settings;
    ref.read(databaseProvider).setValue(Keys.settings, jsonEncode(settings.toJson()));
  }

  void setDefaults(TaskDefaults defaults) => set(state.copyWith(defaults: defaults));

  void setSnoozeMinutes(int minutes) => set(state.copyWith(snoozeMinutes: minutes));
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
