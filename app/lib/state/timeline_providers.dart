import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/keys.dart';
import '../domain/timeline.dart';
import 'providers.dart';

/// How the timeline looks, the same for every list; kept on this device
/// (never synced).
class TimelinePrefs {
  const TimelinePrefs({this.scale = TimelineScale.day, this.showDone = false, this.trayOpen});

  final TimelineScale scale;

  /// Finished tasks stay on the days they were due, faded.
  final bool showDone;

  /// Whether the tasks without a date (无日期) show beside the timeline;
  /// null until the person chooses: open where there's room.
  final bool? trayOpen;

  TimelinePrefs copyWith({TimelineScale? scale, bool? showDone, bool? trayOpen}) => TimelinePrefs(
        scale: scale ?? this.scale,
        showDone: showDone ?? this.showDone,
        trayOpen: trayOpen ?? this.trayOpen,
      );

  Map<String, Object> toJson() => {
        'scale': scale.name,
        'showDone': showDone,
        'trayOpen': ?trayOpen,
      };

  /// Unknown or missing values fall back to the defaults.
  factory TimelinePrefs.fromJson(Map<String, dynamic> json) => TimelinePrefs(
        scale: TimelineScale.byName(json['scale']) ?? TimelineScale.day,
        showDone: json['showDone'] as bool? ?? false,
        trayOpen: json['trayOpen'] as bool?,
      );
}

class TimelinePrefsNotifier extends Notifier<TimelinePrefs> {
  /// Set once the person changes something, so a slow load doesn't undo it.
  bool _changed = false;

  @override
  TimelinePrefs build() {
    _load();
    return const TimelinePrefs();
  }

  Future<void> _load() async {
    final raw = await ref.read(databaseProvider).getValue(Keys.timelinePrefs);
    if (raw == null || _changed || !ref.mounted) return;
    try {
      state = TimelinePrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Written by a newer version, or damaged: keep the defaults.
    }
  }

  void set(TimelinePrefs prefs) {
    _changed = true;
    state = prefs;
    ref.read(databaseProvider).setValue(Keys.timelinePrefs, jsonEncode(prefs.toJson()));
  }
}

final timelinePrefsProvider =
    NotifierProvider<TimelinePrefsNotifier, TimelinePrefs>(TimelinePrefsNotifier.new);
