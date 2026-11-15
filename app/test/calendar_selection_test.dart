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
import 'package:opentodo/ui/batch_actions.dart';
import 'package:opentodo/ui/calendar/month_view.dart';

import 'reminder_scheduler_test.dart' show FakeBackend;

/// 多选 on the calendar: picking tasks with ⌘ / Shift (or from the menu on a
/// phone), the batch actions, and dragging the picked ones together.
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

  Future<Task> load(AppDatabase db, String title) =>
      (db.select(db.tasks)..where((t) => t.title.equals(title))).getSingle();

  Future<void> withKey(WidgetTester tester, LogicalKeyboardKey key, Future<void> Function() body) async {
    await tester.sendKeyDownEvent(key);
    await body();
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> cmdTap(WidgetTester tester, String title) =>
      withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.tap(find.text(title)));

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

  /// Drags from [from] to [to] in small steps, after a long press when
  /// [hold].
  Future<void> dragSteps(WidgetTester tester, Offset from, Offset to, {bool hold = false, Future<void> Function()? midway}) async {
    final g = await tester.startGesture(from);
    if (hold) await tester.pump(const Duration(milliseconds: 600));
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(from + (to - from) * (i / 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await midway?.call();
    await g.up();
    await tester.pumpAndSettle();
  }

  final today = dateOnly(DateTime.now());
  // A day in the same week row as today.
  final neighbour = today.weekday == DateTime.monday ? addDays(today, 1) : addDays(today, -1);
  final shift = daysBetween(today, neighbour);

  testWidgets('desktop month: ⌘ / Shift pick tasks, the panel shows, a drag moves them together',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(1400, 900));
    await repo.addTask(title: '晨会', dueDate: today, dueTime: 9 * 60);
    await repo.addTask(title: '交房租', dueDate: today);
    await repo.addTask(title: '写周报', dueDate: neighbour, dueTime: 15 * 60);
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();

    await cmdTap(tester, '晨会');
    await cmdTap(tester, '交房租');
    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(find.byType(BatchPanel), findsOneWidget);
    expect(find.text('任务详情'), findsNothing);

    // One dragged to the neighbouring day takes the other along, each
    // keeping its time; the one not picked stays.
    final from = tester.getCenter(find.text('晨会'));
    final to = cellCenter(tester, neighbour, today);
    await dragSteps(tester, from, Offset(to.dx, from.dy));
    expect((await load(db, '晨会')).dueDate, dateKey(neighbour));
    expect((await load(db, '晨会')).dueTime, 9 * 60);
    expect((await load(db, '交房租')).dueDate, dateKey(addDays(today, shift)));
    expect((await load(db, '交房租')).dueTime, isNull);
    expect((await load(db, '写周报')).dueDate, dateKey(neighbour));
    expect(find.text('已选择 2 项'), findsOneWidget); // still picked

    // A click on an empty part of a day stops picking, rather than adding.
    await tester.tapAt(cellCenter(tester, addDays(neighbour, 7), today) + const Offset(0, 20));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选择'), findsNothing);
    expect(find.text('准备做什么？回车创建'), findsNothing);

    // ⌘A picks every task on the page; Esc lets go.
    await withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.sendKeyEvent(LogicalKeyboardKey.keyA));
    expect(find.text('已选择 3 项'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('已选择'), findsNothing);

    // A plain click opens the task; Shift-click from it picks the range in
    // the order shown (交房租 all day, 晨会 9:00, 写周报 15:00).
    await tester.tap(find.text('交房租'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    await withKey(tester, LogicalKeyboardKey.shiftLeft, () => tester.tap(find.text('写周报')));
    expect(find.text('已选择 3 项'), findsOneWidget);

    // The panel acts on them all.
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    for (final t in ['晨会', '交房租', '写周报']) {
      expect((await load(db, t)).status, TaskStatus.done);
    }
    expect(find.textContaining('已选择'), findsNothing);

    // A plain click while picking opens the task and stops picking.
    await repo.setCompleted((await load(db, '晨会')).id, false);
    await repo.setCompleted((await load(db, '写周报')).id, false);
    await tester.pumpAndSettle();
    // (The task open in the detail, 交房租, comes along, as in the lists.)
    await cmdTap(tester, '晨会');
    expect(find.text('已选择 2 项'), findsOneWidget);
    await tester.tap(find.text('写周报'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选择'), findsNothing);
    expect(find.text('任务详情'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('desktop week: picked tasks move by the same minutes; an all-day one only by days',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(1400, 900));
    await repo.addTask(title: '晨会', dueDate: today, dueTime: 9 * 60);
    await repo.addTask(title: '评审', dueDate: today, dueTime: 14 * 60, duration: 60);
    await repo.addTask(title: '交房租', dueDate: today);
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();

    for (final t in ['晨会', '评审', '交房租']) {
      await cmdTap(tester, t);
    }
    expect(find.text('已选择 3 项'), findsOneWidget);

    // Two hours down (48 px an hour), a little extra so it isn't on the
    // edge. While it hovers, the spot says how many go.
    final from = tester.getCenter(find.text('晨会'));
    await dragSteps(tester, from, from + const Offset(0, 2 * 48 + 6), midway: () async {
      expect(find.text('11:00 · 3 项'), findsOneWidget);
    });
    expect((await load(db, '晨会')).dueTime, 11 * 60);
    final review = await load(db, '评审');
    expect(review.dueTime, 16 * 60);
    expect(review.duration, 60);
    expect(review.dueDate, dateKey(today));
    final rent = await load(db, '交房租');
    expect(rent.dueTime, isNull);
    expect(rent.dueDate, dateKey(today));

    // Into the all-day row, led by a timed one: none keep a time.
    final strip = tester.getCenter(find.text('全天'));
    final chip = tester.getCenter(find.text('评审'));
    await dragSteps(tester, chip, Offset(chip.dx, strip.dy));
    for (final t in ['晨会', '评审', '交房租']) {
      expect((await load(db, t)).dueTime, isNull, reason: t);
    }

    await finish(tester);
  });

  testWidgets('narrower window: the bar along the bottom acts on the picked tasks',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(900, 800));
    await repo.addTask(title: '晨会', dueDate: today, dueTime: 9 * 60);
    await repo.addTask(title: '交房租', dueDate: today);
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();

    await cmdTap(tester, '晨会');
    await cmdTap(tester, '交房租');
    expect(find.byType(BatchBar), findsOneWidget);
    expect(find.text('2 项'), findsOneWidget);
    await tester.tap(find.byTooltip('优先级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高优先级').last);
    await tester.pumpAndSettle();
    expect((await load(db, '晨会')).priority, Priority.high);
    expect((await load(db, '交房租')).priority, Priority.high);

    await finish(tester);
  });

  testWidgets('phone: 多选 from the menu, taps pick, a long press drags them together', (tester) async {
    final (db, repo) = await pumpApp(tester, const Size(400, 800));
    await repo.addTask(title: '取快递', dueDate: today);
    await repo.addTask(title: '买菜', dueDate: today);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();

    // The day's list under the small month: a long press opens the menu.
    await tester.longPress(find.text('取快递'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(find.text('1 项'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('买菜'));
    await tester.pumpAndSettle();
    expect(find.text('2 项'), findsOneWidget);
    await tester.tap(find.byTooltip('完成'));
    await tester.pumpAndSettle();
    expect((await load(db, '取快递')).status, TaskStatus.done);
    expect((await load(db, '买菜')).status, TaskStatus.done);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // On the hour grid, a long press let go without moving opens the menu
    // and moves nothing.
    await repo.addTask(title: '晨会', dueDate: today, dueTime: 9 * 60 + 10);
    await repo.addTask(title: '评审', dueDate: today, dueTime: 10 * 60);
    await tester.tap(find.byTooltip('切换视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    // The day opens two hours before now; the morning is up the page.
    await tester.ensureVisible(find.text('晨会'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('晨会'));
    await tester.pumpAndSettle();
    expect((await load(db, '晨会')).dueTime, 9 * 60 + 10);
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('评审'));
    await tester.pumpAndSettle();
    expect(find.text('2 项'), findsOneWidget);

    // A long press and a drag an hour down takes both.
    final from = tester.getCenter(find.text('评审'));
    await dragSteps(tester, from, from + const Offset(0, 48 + 4), hold: true);
    expect((await load(db, '评审')).dueTime, 11 * 60);
    expect((await load(db, '晨会')).dueTime, 10 * 60 + 10);

    await finish(tester);
  });
}
