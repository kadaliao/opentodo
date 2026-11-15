import 'package:material_ui/material_ui.dart';

import '../data/db.dart';

export '../domain/views.dart' show priorityName;

/// The app's own accent: a calm teal, so it doesn't look like anyone else's.
const seedColor = Color(0xFF14A38B);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
    inputDecorationTheme: const InputDecorationTheme(isDense: true),
    listTileTheme: const ListTileThemeData(dense: true),
  );
}

Color priorityColor(int priority, ColorScheme scheme) => switch (priority) {
      Priority.high => const Color(0xFFE5484D),
      Priority.medium => const Color(0xFFF2A516),
      Priority.low => const Color(0xFF3E8BFF),
      _ => scheme.outline,
    };

/// Width breakpoints.
abstract final class Breakpoints {
  static const threePane = 1000.0;
  static const twoPane = 640.0;
}

/// Which of the three layouts a window width gets.
enum ShellLayout {
  /// One pane, lists in a drawer, modules in a bottom bar.
  phone,

  /// Two panes; a task opens as its own page.
  medium,

  /// Three panes; a task opens beside the list.
  wide;

  static ShellLayout of(double width) => width >= Breakpoints.threePane
      ? wide
      : (width >= Breakpoints.twoPane ? medium : phone);
}

/// A task bar or chip that's picked (or open in the detail): a deeper shade
/// of the usual fill, so it stands out rather than fading.
Color pickedFill(ColorScheme scheme) =>
    Color.alphaBlend(scheme.primary.withValues(alpha: 0.28), scheme.primaryContainer);
