import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/keys.dart';
import '../domain/task_defaults.dart';
import 'providers.dart';

/// The person's settings, kept on this device (not synced yet).
class AppSettings {
  const AppSettings({this.defaults = TaskDefaults.standard});

  final TaskDefaults defaults;

  AppSettings copyWith({TaskDefaults? defaults}) => AppSettings(defaults: defaults ?? this.defaults);

  Map<String, Object> toJson() => {'defaults': defaults.toJson()};

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        defaults: json['defaults'] is Map
            ? TaskDefaults.fromJson((json['defaults'] as Map).cast<String, dynamic>())
            : TaskDefaults.standard,
      );
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
    final raw = await ref.read(databaseProvider).getValue(Keys.settings);
    if (raw == null || _changed || !ref.mounted) return;
    try {
      state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Written by a newer version, or damaged: keep the defaults.
    }
  }

  void set(AppSettings settings) {
    _changed = true;
    state = settings;
    ref.read(databaseProvider).setValue(Keys.settings, jsonEncode(settings.toJson()));
  }

  void setDefaults(TaskDefaults defaults) => set(state.copyWith(defaults: defaults));
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
