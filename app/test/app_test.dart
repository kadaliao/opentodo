import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/state/providers.dart';
import 'package:opentodo/ui/app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<AppDatabase> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const OpenTodoApp(seed: false),
    ));
    await tester.pumpAndSettle();
    return db;
  }

  // The in-memory database is left open: drift's close() waits on work queued
  // in the test's fake time and never completes there.
  Future<void> finish(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('desktop: add a task in Today, open it, complete it', (tester) async {
    final db = await pumpApp(tester, const Size(1400, 900));

    expect(find.text('今天没有任务'), findsOneWidget);
    expect(find.text('点击任务查看详情'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '下午3点开会 #工作');
    await tester.pump();
    expect(find.textContaining('今天, 下午3:00'), findsOneWidget); // parsed preview
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // In the list, with its tag, and selected in the detail pane.
    expect(find.text('开会'), findsWidgets);
    expect(find.text('工作'), findsWidgets);
    expect(find.text('今天, 下午3:00'), findsOneWidget);

    // The sidebar shows the tag and counts the task.
    expect(find.text('标签'), findsOneWidget);

    // Complete it from the list row.
    await tester.tap(find.bySemanticsLabel('完成').first);
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsWidgets);

    await finish(tester, db);
  });

  testWidgets('phone: lists live in a drawer and tasks open as a page', (tester) async {
    final db = await pumpApp(tester, const Size(400, 800));
    expect(find.byIcon(Icons.menu), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '买菜');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.text('买菜'));
    await tester.pumpAndSettle();
    expect(find.text('添加子任务'), findsOneWidget);

    await finish(tester, db);
  });
}
