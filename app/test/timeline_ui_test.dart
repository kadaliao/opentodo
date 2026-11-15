import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/dates.dart';
import 'package:opentodo/domain/views.dart';
import 'package:opentodo/state/providers.dart';
import 'package:opentodo/ui/app.dart';
import 'package:opentodo/ui/home_shell.dart';
import 'package:opentodo/ui/task_tile.dart' show PriorityCheckbox;
import 'package:opentodo/ui/timeline_view.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late String work;
  final today = dateOnly(DateTime.now());
  String day(int d) => dateKey(addDays(today, d));
  const dayWidth = 96.0;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeShell)));

  /// The list 工作, open on screen, with what [fill] adds to it.
  Future<void> pumpApp(WidgetTester tester, Size size, Future<void> Function(String list) fill) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const OpenTodoApp(seed: false),
    ));
    await tester.pumpAndSettle();
    final c = container(tester);
    work = await c.read(repoProvider).addList('工作', emoji: '💼');
    await fill(work);
    c.read(selectedViewProvider.notifier).select(ListViewRef(work));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<Task> load(String title) =>
      (db.select(db.tasks)..where((t) => t.title.equals(title))).getSingle();

  Future<void> showTimeline(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('时间线'));
    await tester.pumpAndSettle();
  }

  /// [title] on the timeline (the tray and the detail may show it too).
  Finder onTimeline(String title) => find.descendant(of: find.byType(TimelineView), matching: find.text(title));

  /// Drags with the mouse from [start] to [target] in steps.
  Future<void> dragFrom(WidgetTester tester, Offset start, Offset target) async {
    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(4, 0));
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(start + (target - start) * (i / 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('desktop: move tasks along the days, onto it and off it, stretch them',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900), (list) async {
      final repo = container(tester).read(repoProvider);
      await repo.addTask(title: '甲', listId: list, dueDate: today);
      await repo.addTask(title: '乙', listId: list, dueDate: addDays(today, 1), dueTime: 9 * 60);
      await repo.addTask(title: '丙', listId: list);
    });
    await showTimeline(tester);
    expect(onTimeline('甲'), findsOneWidget);
    expect(onTimeline('乙'), findsOneWidget);
    expect(find.text('无日期 1'), findsOneWidget);
    // The list menu marks the timeline.
    expect(container(tester).read(viewPrefsProvider)[work]?.layout, ListLayout.timeline);

    // 甲 two days on.
    final jia = tester.getCenter(onTimeline('甲'));
    await dragFrom(tester, jia, jia + const Offset(2 * dayWidth, 0));
    expect((await load('甲')).dueDate, day(2));

    // 乙 a day back, keeping its time.
    final yi = tester.getCenter(onTimeline('乙'));
    await dragFrom(tester, yi, yi - const Offset(dayWidth, 0));
    final moved = await load('乙');
    expect((moved.dueDate, moved.dueTime), (day(0), 9 * 60));

    // 丙 from 无日期 onto 甲's day.
    await dragFrom(tester, tester.getCenter(find.text('丙')), tester.getCenter(onTimeline('甲')) + const Offset(0, 40));
    final bing = await load('丙');
    expect((bing.dueDate, bing.dueTime), (day(2), null));
    expect(find.text('无日期 0'), findsOneWidget);

    // 甲 back to 无日期.
    await dragFrom(tester, tester.getCenter(onTimeline('甲')), tester.getCenter(find.textContaining('没有无日期的任务')));
    expect((await load('甲')).dueDate, isNull);
    expect(find.text('无日期 1'), findsOneWidget);

    // 乙's right edge two days on: 9:00 to 9:00 two days later.
    final bar = tester.getRect(find.byKey(ValueKey('bar-${(await load('乙')).id}')));
    await dragFrom(tester, bar.centerRight - const Offset(1, 0), bar.centerRight + const Offset(2 * dayWidth, 0));
    expect((await load('乙')).duration, 2 * minutesPerDay);

    // Its left edge a day on: it starts a day later and still ends there,
    // the pill saying where it will start.
    final from = tester.getRect(find.byKey(ValueKey('bar-${(await load('乙')).id}'))).centerLeft + const Offset(1, 0);
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(from + Offset(dayWidth * i / 6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final starts = addDays(today, 1);
    expect(find.text('从${starts.month}月${starts.day}日'), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    final restarted = await load('乙');
    expect((restarted.dueDate, restarted.dueTime, restarted.duration), (day(1), 9 * 60, minutesPerDay));

    await finish(tester);
  });

  testWidgets('desktop: 今天 and a tag as a timeline, with lanes by list',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900), (list) async {
      final repo = container(tester).read(repoProvider);
      await repo.addTask(title: '晨会', listId: list, dueDate: today, tags: ['会']);
      await repo.addTask(title: '交房租', dueDate: addDays(today, -1));
      await repo.addTask(title: '周会', listId: list, tags: ['会']);
    });
    container(tester).read(selectedViewProvider.notifier).select(const SmartViewRef(SmartKind.today));
    await tester.pumpAndSettle();
    await showTimeline(tester);
    expect(onTimeline('晨会'), findsOneWidget);
    expect(onTimeline('交房租'), findsOneWidget);
    // A lane per list; nothing undated in 今天.
    expect(onTimeline('收集箱'), findsOneWidget);
    expect(onTimeline('工作'), findsOneWidget);
    expect(find.textContaining('无日期'), findsNothing);
    expect(container(tester).read(viewPrefsProvider)['smart:today']?.layout, ListLayout.timeline);

    // 交房租 down into 工作's lane: it moves to that list, on the same day.
    final rent = tester.getCenter(onTimeline('交房租'));
    await dragFrom(tester, rent, Offset(rent.dx, tester.getCenter(onTimeline('晨会')).dy));
    final moved = await load('交房租');
    expect((moved.listId, moved.dueDate), (work, day(-1)));

    // A click on tomorrow adds nothing (今天 wouldn't show it); on today it
    // adds to the lane's list.
    final lane = tester.getCenter(onTimeline('晨会'));
    await tester.tapAt(Offset(lane.dx + dayWidth, lane.dy + 40));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tapAt(Offset(lane.dx, lane.dy + 40));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), '午饭');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final added = await load('午饭');
    expect((added.listId, added.dueDate), (work, day(0)));

    // ⇅ offers lanes by list, tag, priority or none; not by date.
    await tester.tap(find.byTooltip('分组和排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分组：清单'));
    await tester.pumpAndSettle();
    expect(find.text('按时间'), findsNothing);
    await tester.tap(find.text('不分组'));
    await tester.pumpAndSettle();
    expect(onTimeline('工作'), findsNothing);
    expect(onTimeline('晨会'), findsOneWidget);

    // A tag: its undated task waits beside, and dragged on keeps its list
    // and tag.
    container(tester).read(selectedViewProvider.notifier).select(const TagViewRef('会'));
    await tester.pumpAndSettle();
    await showTimeline(tester);
    expect(find.text('无日期 1'), findsOneWidget);
    await dragFrom(tester, tester.getCenter(find.text('周会')), tester.getCenter(onTimeline('晨会')) + const Offset(dayWidth, 0));
    final weekly = await load('周会');
    expect((weekly.listId, weekly.tags.join(), weekly.dueDate), (work, '会', day(1)));

    // Back to the list, from the same menu.
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineView), findsNothing);

    await finish(tester);
  });

  testWidgets('desktop: lanes for sections, a click adds, picked tasks move together, scales',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    late String design, build;
    await pumpApp(tester, const Size(1400, 900), (list) async {
      final repo = container(tester).read(repoProvider);
      design = await repo.addSection(list, '设计');
      build = await repo.addSection(list, '开发');
      await repo.addTask(title: '甲', listId: list, sectionId: design, dueDate: today);
      await repo.addTask(title: '乙', listId: list, sectionId: build, dueDate: addDays(today, 1));
      await repo.addTask(title: '丙', listId: list, sectionId: build);
    });
    await showTimeline(tester);
    // A lane per section; 未分组 has nothing dated, so isn't one.
    expect(onTimeline('设计'), findsOneWidget);
    expect(onTimeline('未分组'), findsNothing);
    // 无日期 says which section a task is in: 开发 there and on its lane.
    expect(onTimeline('开发'), findsNWidgets(2));

    // 甲 down into 开发, on the same day.
    final jia = tester.getCenter(onTimeline('甲'));
    await dragFrom(tester, jia, Offset(jia.dx, tester.getCenter(onTimeline('乙')).dy));
    final moved = await load('甲');
    expect((moved.sectionId, moved.dueDate), (build, day(0)));

    // A click on 设计's empty lane under 乙's day adds a task there.
    final lane = tester.getBottomLeft(onTimeline('设计'));
    await tester.tapAt(Offset(tester.getCenter(onTimeline('乙')).dx, lane.dy + 20));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), '新任务');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final added = await load('新任务');
    expect((added.listId, added.sectionId, added.dueDate), (work, design, day(1)));

    // ⌘-click 甲 and 乙, then drag 甲 a day on: both go.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(onTimeline('甲'));
    await tester.tap(onTimeline('乙'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    final start = tester.getCenter(onTimeline('甲'));
    await dragFrom(tester, start, start + const Offset(dayWidth, 0));
    expect([(await load('甲')).dueDate, (await load('乙')).dueDate], [day(1), day(2)]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // By week: still there; 今天 and the arrows don't lose it.
    await tester.tap(find.widgetWithText(TextButton, '日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按周'));
    await tester.pumpAndSettle();
    expect(onTimeline('甲'), findsOneWidget);
    await tester.tap(find.byTooltip('往后'));
    await tester.pumpAndSettle();
    await tester.tap(onTimeline('今天'));
    await tester.pumpAndSettle();
    expect(onTimeline('甲'), findsOneWidget);

    // Folding a lane hides its tasks.
    await tester.tap(onTimeline('开发').last);
    await tester.pumpAndSettle();
    expect(onTimeline('甲'), findsNothing);

    await finish(tester);
  });

  testWidgets('finished tasks show when asked', variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
    await pumpApp(tester, const Size(1400, 900), (list) async {
      final repo = container(tester).read(repoProvider);
      final id = await repo.addTask(title: '做完了', listId: list, dueDate: today);
      await repo.setCompleted(id, true);
    });
    await showTimeline(tester);
    expect(onTimeline('做完了'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示已完成'));
    await tester.pumpAndSettle();
    expect(onTimeline('做完了'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('phone: a long press drags a task to another day; 无日期 opens below', (tester) async {
    await pumpApp(tester, const Size(400, 800), (list) async {
      final repo = container(tester).read(repoProvider);
      await repo.addTask(title: '甲', listId: list, dueDate: today);
      await repo.addTask(title: '丙', listId: list);
    });
    await showTimeline(tester);
    // No room for 无日期 beside it: closed until asked for.
    expect(find.text('丙'), findsNothing);

    final start = tester.getCenter(onTimeline('甲'));
    final target = start + const Offset(dayWidth, 0);
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(start + (target - start) * (i / 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect((await load('甲')).dueDate, day(1));

    await tester.tap(find.text('无日期 1'));
    await tester.pumpAndSettle();
    expect(find.text('丙'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('phone: a long press on an end of a bar drags that end', (tester) async {
    await pumpApp(tester, const Size(400, 800), (list) async {
      final repo = container(tester).read(repoProvider);
      await repo.addTask(title: '甲', listId: list, dueDate: today);
    });
    await showTimeline(tester);
    final id = (await load('甲')).id;
    Rect bar() => tester.getRect(find.byKey(ValueKey('bar-$id')));

    Future<void> longDrag(Offset start, Offset by) async {
      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(start + by * (i / 6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    // The right end two days on.
    await longDrag(bar().centerRight - const Offset(6, 0), const Offset(2 * dayWidth, 0));
    var jia = await load('甲');
    expect((jia.dueDate, jia.duration), (day(0), 3 * minutesPerDay));

    // The left end a day on: it still ends on the same day.
    await longDrag(bar().centerLeft + const Offset(6, 0), const Offset(dayWidth, 0));
    jia = await load('甲');
    expect((jia.dueDate, jia.duration), (day(1), 2 * minutesPerDay));

    // A long press there that doesn't move opens the menu, and moves nothing.
    await tester.longPress(find.byKey(ValueKey('end-$id')));
    await tester.pumpAndSettle();
    expect(find.text('多选'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect((await load('甲')).duration, 2 * minutesPerDay);

    // A tap on an end still reaches the bar: its checkbox finishes it.
    await tester.tap(find.descendant(of: find.byKey(ValueKey('bar-$id')), matching: find.byType(PriorityCheckbox)));
    await tester.pumpAndSettle();
    expect((await load('甲')).status, TaskStatus.done);

    await finish(tester);
  });
}
