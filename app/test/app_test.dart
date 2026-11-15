import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/dates.dart';
import 'package:opentodo/state/providers.dart';
import 'package:opentodo/state/reminder_providers.dart';
import 'package:opentodo/ui/app.dart';

import 'reminder_scheduler_test.dart' show FakeBackend;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeBackend notifications;

  Future<AppDatabase> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    notifications = FakeBackend();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        reminderBackendProvider.overrideWithValue(notifications),
      ],
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

  testWidgets('a repeating task moves on when done, with undo, and its reminder follows',
      (tester) async {
    final db = await pumpApp(tester, const Size(1400, 900));
    final today = dateOnly(DateTime.now());
    final tomorrow = addDays(today, 1);

    await tester.tap(find.text('明天').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '明天上午9点每天吃药');
    await tester.pump();
    expect(find.textContaining('每天'), findsWidgets); // parsed preview
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    var task = (await db.select(db.tasks).get()).single;
    expect(task.repeatRule, 'FREQ=DAILY');
    expect(task.reminders, [0]); // a time comes with 准时
    expect(find.byIcon(Icons.repeat), findsWidgets);

    // The reminder is handed to the system.
    await tester.pump(const Duration(seconds: 1));
    expect(notifications.pendingById.values.single.at,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9));

    await tester.tap(find.bySemanticsLabel('完成').first);
    await tester.pumpAndSettle();
    expect(find.text('已完成，下次：后天'), findsOneWidget);
    task = (await db.select(db.tasks).get()).firstWhere((t) => t.id == task.id);
    expect(task.dueDate, dateKey(addDays(today, 2)));
    expect(task.status, TaskStatus.open);
    await tester.pump(const Duration(seconds: 1));
    expect(notifications.pendingById.values.single.at.day, addDays(today, 2).day);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    task = (await db.select(db.tasks).get()).firstWhere((t) => t.id == task.id);
    expect(task.dueDate, dateKey(tomorrow));
    expect((await db.select(db.tasks).get()).where((t) => t.deletedAt == null).length, 1);

    await finish(tester, db);
  });

  testWidgets('the date dialog sets reminders and repeat', (tester) async {
    final db = await pumpApp(tester, const Size(1400, 900));
    await tester.enterText(find.byType(TextField).first, '写周报');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The detail pane's date button opens the dialog.
    await tester.tap(find.text('今天').last);
    await tester.pumpAndSettle();
    expect(find.text('提醒'), findsOneWidget);

    await tester.tap(find.text('重复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每天'));
    await tester.pumpAndSettle();
    expect(find.text('每天'), findsOneWidget);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('当天 09:00'));
    await tester.pump();
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();
    expect(find.text('当天 09:00'), findsOneWidget);

    // A custom rule: every other day.
    await tester.tap(find.text('每天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义…'));
    await tester.pumpAndSettle();
    expect(find.text('自定义重复'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '1'), '2');
    await tester.pump();
    expect(find.text('每2天'), findsOneWidget); // preview
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();
    expect(find.text('每2天'), findsOneWidget);

    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();
    final task = (await db.select(db.tasks).get()).single;
    expect(task.repeatRule, 'FREQ=DAILY;INTERVAL=2');
    expect(task.reminders, [540]);
    expect(task.dueTime, isNull);

    await finish(tester, db);
  });
}
