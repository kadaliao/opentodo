import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/keys.dart';
import '../domain/calendar.dart';
import '../domain/dates.dart';
import 'providers.dart';

/// How the calendar looks, kept on this device (never synced).
class CalendarPrefs {
  const CalendarPrefs({
    this.mode = CalendarMode.month,
    this.showCompleted = true,
    this.showRepeats = true,
    this.hiddenLists = const {},
  });

  final CalendarMode mode;
  final bool showCompleted;
  final bool showRepeats;
  final Set<String> hiddenLists;

  CalendarFilter get filter => CalendarFilter(
        showCompleted: showCompleted,
        showRepeats: showRepeats,
        hiddenLists: hiddenLists,
      );

  CalendarPrefs copyWith({
    CalendarMode? mode,
    bool? showCompleted,
    bool? showRepeats,
    Set<String>? hiddenLists,
  }) =>
      CalendarPrefs(
        mode: mode ?? this.mode,
        showCompleted: showCompleted ?? this.showCompleted,
        showRepeats: showRepeats ?? this.showRepeats,
        hiddenLists: hiddenLists ?? this.hiddenLists,
      );

  Map<String, Object> toJson() => {
        'mode': mode.name,
        'showCompleted': showCompleted,
        'showRepeats': showRepeats,
        'hiddenLists': hiddenLists.toList(),
      };

  /// Unknown or missing values fall back to the defaults.
  factory CalendarPrefs.fromJson(Map<String, dynamic> json) => CalendarPrefs(
        mode: CalendarMode.byName(json['mode'] as String?) ?? CalendarMode.month,
        showCompleted: json['showCompleted'] as bool? ?? true,
        showRepeats: json['showRepeats'] as bool? ?? true,
        hiddenLists: {...?(json['hiddenLists'] as List<dynamic>?)?.whereType<String>()},
      );
}

class CalendarPrefsNotifier extends Notifier<CalendarPrefs> {
  /// Set once the person changes something, so a slow load doesn't undo it.
  bool _changed = false;

  @override
  CalendarPrefs build() {
    _load();
    return const CalendarPrefs();
  }

  Future<void> _load() async {
    final raw = await ref.read(databaseProvider).getValue(Keys.calendarPrefs);
    if (raw == null || _changed || !ref.mounted) return;
    try {
      state = CalendarPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Written by a newer version, or damaged: keep the defaults.
    }
  }

  void set(CalendarPrefs prefs) {
    _changed = true;
    state = prefs;
    ref.read(databaseProvider).setValue(Keys.calendarPrefs, jsonEncode(prefs.toJson()));
  }

  void setMode(CalendarMode mode) => set(state.copyWith(mode: mode));
}

final calendarPrefsProvider =
    NotifierProvider<CalendarPrefsNotifier, CalendarPrefs>(CalendarPrefsNotifier.new);

/// The day the calendar is looking at: the selected day of the month grid,
/// the first column of the 3-day grid, a day in the shown week or month.
class CalendarAnchor extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(DateTime.now());

  void go(DateTime date) => state = dateOnly(date);

  void today() => state = dateOnly(DateTime.now());

  void page(int pages) =>
      state = shiftAnchor(ref.read(calendarPrefsProvider).mode, state, pages);
}

final calendarAnchorProvider =
    NotifierProvider<CalendarAnchor, DateTime>(CalendarAnchor.new);

final calendarRangeProvider = Provider<DayRange>((ref) => visibleRange(
      ref.watch(calendarPrefsProvider.select((p) => p.mode)),
      ref.watch(calendarAnchorProvider),
    ));

/// The calendar's entries for any range: the page on screen, or the small
/// month in the sidebar.
final calendarEntriesProvider = Provider.family<List<CalendarEntry>, DayRange>((ref, range) {
  return calendarEntries(
    ref.watch(tasksProvider).value ?? const [],
    range,
    // Only the date matters; the clock ticks every minute.
    today: parseDateKey(ref.watch(clockProvider.select(dateKey))),
    filter: ref.watch(calendarPrefsProvider).filter,
  );
});
