import 'package:material_ui/material_ui.dart';

import '../data/db.dart';

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

String priorityName(int priority) => switch (priority) {
      Priority.high => '高优先级',
      Priority.medium => '中优先级',
      Priority.low => '低优先级',
      _ => '无优先级',
    };

/// Width breakpoints.
abstract final class Breakpoints {
  static const threePane = 1000.0;
  static const twoPane = 640.0;
}
