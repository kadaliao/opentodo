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

  testWidgets('desktop: the date dialog sets a time span', (tester) async {
    final db = await pumpApp(tester, const Size(1400, 900));
    await tester.enterText(find.byType(TextField).first, '上午10点评审');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    Future<Task> reload() async => (await db.select(db.tasks).get()).single;

    // 时间段 starts from the task's time and lasts an hour.
    await tester.tap(find.text('今天, 上午10:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('时间段'));
    await tester.pumpAndSettle();
    Finder inDialog(String text) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(text));
    expect(find.text('开始'), findsOneWidget);
    expect(inDialog('上午10:00'), findsOneWidget);
    expect(inDialog('上午11:00'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    var t = await reload();
    expect((t.dueTime, t.duration, t.reminders.toString()), (600, 60, '[0]'));
    expect(find.text('今天, 上午10:00-11:00'), findsOneWidget); // the detail
    expect(find.text('上午10:00-11:00'), findsOneWidget); // the row

    // All day: the dates stay, the times go.
    await tester.tap(find.text('今天, 上午10:00-11:00'));
    await tester.pumpAndSettle();
    expect(find.text('结束'), findsOneWidget); // opens on 时间段
    await tester.tap(find.text('全天'));
    await tester.pumpAndSettle();
    expect(inDialog('上午10:00'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    t = await reload();
    expect((t.dueTime, t.duration, t.reminders.toString()), (null, null, '[]'));

    // Back to one date drops the span.
    await tester.enterText(find.byType(TextField).first, '明天下午3点到5点 培训');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('明天, 下午3:00-5:00'), findsOneWidget);
    await tester.tap(find.text('明天, 下午3:00-5:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final trained = (await db.select(db.tasks).get()).firstWhere((t) => t.title == '培训');
    expect((trained.dueTime, trained.duration), (900, null));

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

  testWidgets('overdue tasks show in red, in the list and the detail', (tester) async {
    final db = await pumpApp(tester, const Size(1400, 900));
    final container = ProviderScope.containerOf(tester.element(find.byType(OpenTodoApp)));
    final repo = container.read(repoProvider);
    final today = dateOnly(DateTime.now());
    // Midnight today has always passed; tomorrow hasn't.
    await repo.addTask(title: '今天零点', dueDate: today, dueTime: 0, reminders: [0]);
    await repo.addTask(title: '昨天的', dueDate: addDays(today, -1));
    await repo.addTask(title: '今天全天', dueDate: today);
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.text('今天零点'))).colorScheme;
    Color? colorOf(Finder f) => tester.widget<Text>(f).style?.color;

    expect(colorOf(find.text('已过期')), scheme.error);
    expect(colorOf(find.text('上午12:00')), scheme.error);
    expect(colorOf(find.text('昨天')), scheme.error);
    expect(colorOf(find.text('今天').last), scheme.primary); // the all-day one, not yet
    expect(
      tester.widget<Icon>(find.byIcon(Icons.alarm)).color,
      scheme.error,
    );

    await tester.tap(find.text('今天零点'));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
        find.ancestor(of: find.text('今天, 上午12:00'), matching: find.byType(TextButton)));
    expect(button.style?.foregroundColor?.resolve({}), scheme.error);

    await finish(tester, db);
  });
}
