import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/providers.dart';
import '../state/reminder_providers.dart';
import '../state/sync_providers.dart';
import 'home_shell.dart';
import 'theme.dart';

class OpenTodoApp extends ConsumerStatefulWidget {
  const OpenTodoApp({super.key, this.seed = true});

  /// Whether a fresh install gets the welcome list.
  final bool seed;

  @override
  ConsumerState<OpenTodoApp> createState() => _OpenTodoAppState();
}

class _OpenTodoAppState extends ConsumerState<OpenTodoApp> {
  @override
  void initState() {
    super.initState();
    if (widget.seed) ref.read(repoProvider).seedIfEmpty();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps background sync and reminders running whatever is on screen.
    ref.listen(syncControllerProvider, (_, _) {});
    ref.listen(reminderControllerProvider, (_, _) {});
    return MaterialApp(
      title: 'OpenTodo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}
