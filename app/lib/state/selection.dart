import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show TargetPlatform;

import 'providers.dart';

/// Several tasks picked at once (多选), to change them together.
class TaskSelection {
  const TaskSelection([this.ids = const {}, this.anchor]);

  final Set<String> ids;

  /// Where a Shift-click range starts: the task picked last.
  final String? anchor;

  bool get active => ids.isNotEmpty;
}

class TaskSelectionNotifier extends Notifier<TaskSelection> {
  @override
  TaskSelection build() {
    // A new view or module starts afresh.
    ref.watch(selectedViewProvider);
    ref.watch(moduleProvider);
    return const TaskSelection();
  }

  /// Starts picking with [id] (from a task's menu).
  void start(String id) => state = TaskSelection({id}, id);

  /// Adds [id] or takes it out. Starting from nothing, the task open in
  /// the detail ([current]) comes along, as a ⌘-click does elsewhere.
  void toggle(String id, {String? current}) {
    final ids = {...state.ids};
    if (ids.isEmpty && current != null && current != id) ids.add(current);
    if (!ids.remove(id)) ids.add(id);
    state = TaskSelection(ids, id);
  }

  /// Adds every task from the anchor (or [current]) to [id], in the
  /// order shown ([order]).
  void extendTo(List<String> order, String id, {String? current}) {
    final from = order.indexOf(state.anchor ?? current ?? id);
    final to = order.indexOf(id);
    if (from < 0 || to < 0) return toggle(id, current: current);
    final range = order.sublist(from < to ? from : to, (from < to ? to : from) + 1);
    state = TaskSelection({...state.ids, ...range}, state.anchor ?? order[from]);
  }

  void selectAll(List<String> order) =>
      state = TaskSelection(order.toSet(), order.isEmpty ? null : order.first);

  void clear() => state = const TaskSelection();
}

final taskSelectionProvider =
    NotifierProvider<TaskSelectionNotifier, TaskSelection>(TaskSelectionNotifier.new);

/// ⌘ on Apple systems, Ctrl elsewhere.
bool get usesCommandKey =>
    defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

/// What a click or tap on a task in a list or on the board does: opens
/// it; with ⌘ (Ctrl) adds it to the selection or takes it out; with Shift
/// selects everything up to it in [order]. While picking on a touch
/// screen, a tap picks or unpicks.
void tapTask(
  WidgetRef ref,
  String id,
  List<String> order,
  void Function(String) open, {
  required bool touch,
}) {
  final keyboard = HardwareKeyboard.instance;
  final selection = ref.read(taskSelectionProvider.notifier);
  final current = ref.read(selectedTaskProvider);
  final picking = ref.read(taskSelectionProvider).active;
  if (touch && picking) {
    selection.toggle(id);
  } else if (usesCommandKey ? keyboard.isMetaPressed : keyboard.isControlPressed) {
    selection.toggle(id, current: current);
  } else if (keyboard.isShiftPressed) {
    selection.extendTo(order, id, current: current);
  } else {
    if (picking) selection.clear();
    open(id);
  }
}
