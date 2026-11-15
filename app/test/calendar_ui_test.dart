import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/domain/calendar.dart';
import 'package:opentodo/domain/dates.dart';
import 'package:opentodo/state/providers.dart';
import 'package:opentodo/state/reminder_providers.dart';
import 'package:opentodo/ui/app.dart';
import 'package:opentodo/ui/calendar/entry_chip.dart';
import 'package:opentodo/ui/calendar/month_view.dart';

import 'reminder_scheduler_test.dart' show FakeBackend;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<(AppDatabase, TaskRepo)> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        reminderBackendProvider.overrideWithValue(FakeBackend()),
      ],
      child: const OpenTodoApp(seed: false),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(OpenTodoApp)));
    return (db, container.read(repoProvider));
  }

  // The in-memory database is left open: drift's close() waits on work queued
  // in the test's fake time and never completes there.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<Task> reload(AppDatabase db, String id) async =>
      (await db.select(db.tasks).get()).firstWhere((t) => t.id == id);

  /// The middle of [date]'s cell on the month board showing [anchor]'s month.
  Offset cellCenter(WidgetTester tester, DateTime date, DateTime anchor) {
    final board = tester.getRect(find.byType(MonthBoard));
    final days = monthGrid(anchor.year, anchor.month).days;
    final i = days.indexOf(date);
    const header = 29.0; // weekday names and the line under them
    final rowHeight = (board.height - header) / (days.length ~/ 7);
    final colWidth = board.width / 7;
    return Offset(
      board.left + colWidth * (i % 7 + 0.5),
      board.top + header + rowHeight * (i ~/ 7 + 0.5),
    );
  }

  final today = dateOnly(DateTime.now());
  // A day in the same week row as today.
  final neighbour = today.weekday == DateTime.monday ? addDays(today, 1) : addDays(today, -1);

  testWidgets('desktop: the calendar shows tasks in each mode and opens them', (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(1400, 900));
    await repo.addTask(title: '晨会', dueDate: today, dueTime: 9 * 60);
    await repo.addTask(title: '交房租', dueDate: today);

    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthBoard), findsOneWidget);
    expect(find.text('${today.year}年${today.month}月'), findsWidgets);
    expect(find.text('晨会'), findsOneWidget);
    expect(find.text('上午9:00'), findsOneWidget); // its time on the chip
    expect(find.text('交房租'), findsOneWidget);
    expect(find.text('显示的清单'), findsOneWidget); // the sidebar

    // A click opens the detail beside the calendar.
    await tester.tap(find.text('晨会'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('今天, 上午9:00'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsNothing);

    // Week, from the mode menu.
    await tester.tap(find.byTooltip('切换视图'));
    await tester.pumpAndSettle();
    // Menu items keep pointers away from their text; the tap lands on the item.
    await tester.tap(find.text('周').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(MonthBoard), findsNothing);
    expect(find.text('全天'), findsOneWidget);
    expect(find.text('晨会'), findsOneWidget);
    expect(find.text('交房租'), findsOneWidget);

    // Agenda and day, from the keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('全天'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(find.text('晨会'), findsOneWidget);

    // The mode is remembered on this device.
    await tester.pump(const Duration(milliseconds: 100));
    expect(await db.getValue('calendar.prefs'), contains('"mode":"day"'));

    // Back to the tasks module.
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsWidgets);
    expect(find.byType(MonthBoard), findsNothing);

    await finish(tester);
  });

  testWidgets('desktop: drag a task to another day; click a day to add one', (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(1400, 900));
    final id = await repo.addTask(title: '拖我', dueDate: today, dueTime: 15 * 60, reminders: [0]);
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();

    final from = tester.getCenter(find.text('拖我'));
    final to = cellCenter(tester, neighbour, today);
    await tester.dragFrom(from, Offset(to.dx - from.dx, 0));
    await tester.pumpAndSettle();
    final moved = await reload(db, id);
    expect(moved.dueDate, dateKey(neighbour));
    expect(moved.dueTime, 15 * 60); // keeps its time
    expect(moved.reminders, [0]);

    // A click on an empty part of a day starts a task there.
    await tester.tapAt(cellCenter(tester, today, today));
    await tester.pumpAndSettle();
    expect(find.text('准备做什么？回车创建'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '写日报');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('准备做什么？回车创建'), findsNothing);
    final added = (await db.select(db.tasks).get()).firstWhere((t) => t.title == '写日报');
    expect(added.dueDate, dateKey(today));
    expect(added.dueTime, isNull);
    expect(find.text('写日报'), findsOneWidget);

    await finish(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('desktop: in the week, drag a task to another time or to all day', (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(1400, 900));
    final id = await repo.addTask(title: '晨会', dueDate: today, dueTime: 9 * 60, reminders: [-30]);
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();

    // Two hours down (48 px an hour), a little extra so it isn't on the edge.
    await tester.drag(find.text('晨会'), const Offset(0, 2 * 48 + 6));
    await tester.pumpAndSettle();
    var t = await reload(db, id);
    expect(t.dueDate, dateKey(today));
    expect(t.dueTime, 11 * 60);
    expect(t.reminders, [-30]);

    // Into the all-day strip: no time, and its reminders go with it.
    final strip = tester.getCenter(find.text('全天'));
    final chip = tester.getCenter(find.text('晨会'));
    await tester.dragFrom(chip, Offset(0, strip.dy - chip.dy));
    await tester.pumpAndSettle();
    t = await reload(db, id);
    expect(t.dueTime, isNull);
    expect(t.reminders, isEmpty);

    // A click on an empty hour starts a task at that hour.
    final grid = tester.getRect(find.text('晨会')); // now in the all-day strip
    await tester.tapAt(Offset(grid.center.dx, tester.getCenter(find.text('14:00')).dy + 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('下午2:00'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '评审');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final added = (await db.select(db.tasks).get()).firstWhere((t) => t.title == '评审');
    expect(added.dueTime, 14 * 60);
    expect(added.reminders, [0]);

    await finish(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('desktop: a span is as tall as it is long; its bottom edge sets the end', (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(1400, 900));
    final id = await repo.addTask(title: '评审', dueDate: today, dueTime: 10 * 60, duration: 120);
    final point = await repo.addTask(title: '晨会', dueDate: neighbour, dueTime: 8 * 60);
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();

    Rect chip(String title) =>
        tester.getRect(find.ancestor(of: find.text(title), matching: find.byType(EntryChip)));
    expect(chip('评审').height, closeTo(2 * 48 - 1, 0.5));
    expect(chip('晨会').height, closeTo(48 / 2 - 1, 0.5)); // no span: half an hour

    // An hour more from the bottom edge.
    var r = chip('评审');
    await tester.dragFrom(Offset(r.center.dx, r.bottom - 1), const Offset(0, 48));
    await tester.pumpAndSettle();
    expect((await reload(db, id)).duration, 180);
    expect(chip('评审').height, closeTo(3 * 48 - 1, 0.5));

    // A task without a span gets one.
    r = chip('晨会');
    await tester.dragFrom(Offset(r.center.dx, r.bottom - 1), const Offset(0, 48));
    await tester.pumpAndSettle();
    final t = await reload(db, point);
    expect((t.dueTime, t.duration), (8 * 60, 90));

    // Dragging the task itself moves it, span and all.
    await tester.drag(find.text('评审'), const Offset(0, 48 + 6));
    await tester.pumpAndSettle();
    final moved = await reload(db, id);
    expect((moved.dueTime, moved.duration), (11 * 60, 180));

    await finish(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a span across days shows on each of them', (tester) async {
    final (_, repo) = await pumpApp(tester, const Size(1400, 900));
    await repo.addTask(title: '出差', dueDate: today, duration: 3 * 1440);
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(find.text('出差'), findsNWidgets(3));

    await finish(tester);
  });

  testWidgets('the month shows lunar days and 休 / 班, and they can be turned off', (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    final note = dayNote(today).label;
    expect(find.text(note), findsWidgets);

    await tester.tap(find.byTooltip('更多').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示农历和节假日'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text(note), findsNothing);

    await finish(tester);
  });

  testWidgets('a repeating task shows on its later days, which open the task', (tester) async {
    final (_, repo) = await pumpApp(tester, const Size(1400, 900));
    await repo.addTask(title: '晨跑', dueDate: today, repeatRule: 'FREQ=DAILY');
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();

    expect(find.text('晨跑'), findsNWidgets(3));
    expect(find.byIcon(Icons.repeat), findsNWidgets(2)); // the two later days

    await tester.tap(find.text('晨跑').last);
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('今天'), findsWidgets); // the real date, in the detail

    // Turned off in the more menu, only the task's own date is left.
    await tester.tap(find.byTooltip('更多').first); // the calendar's, not the detail's
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示重复任务以后的日期'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('晨跑'), findsNWidgets(2)); // the calendar and the detail

    await finish(tester);
  });

  testWidgets('phone: the calendar is a tab with a small month and the day below', (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(400, 800));
    await repo.addTask(title: '取快递', dueDate: today);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    expect(find.byType(MiniMonth), findsOneWidget);
    expect(find.text('取快递'), findsOneWidget);
    expect(find.text('今天, ${weekdayName(today)}'), findsOneWidget);

    // + adds to the selected day.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '买菜');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('买菜'), findsOneWidget);
    final added = (await db.select(db.tasks).get()).firstWhere((t) => t.title == '买菜');
    expect(added.dueDate, dateKey(today));

    // A task opens as a page.
    await tester.tap(find.text('买菜'));
    await tester.pumpAndSettle();
    expect(find.text('添加子任务'), findsOneWidget);

    await finish(tester);
  });
}
