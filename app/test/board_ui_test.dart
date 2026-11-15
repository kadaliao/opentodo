import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
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
import 'package:opentodo/ui/task_list_pane.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late String work;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeShell)));

  /// The list 工作 with 甲, 乙, 丙 (丙 newest, so on top), open on screen.
  Future<void> pumpApp(WidgetTester tester, Size size) async {
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
    final repo = c.read(repoProvider);
    work = await repo.addList('工作', emoji: '💼');
    for (final t in ['甲', '乙', '丙']) {
      await repo.addTask(title: t, listId: work);
      await tester.pump(const Duration(milliseconds: 5)); // distinct times
    }
    c.read(selectedViewProvider.notifier).select(ListViewRef(work));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<Task> load(String title) =>
      (db.select(db.tasks)..where((t) => t.title.equals(title))).getSingle();

  /// Drags with the mouse from [from]'s middle to [to] (plus [dx], [dy]).
  Future<void> drag(WidgetTester tester, Finder from, Finder to, {double dx = 0, double dy = 0}) async {
    // Positions first: while dragging, the task shows twice.
    final start = tester.getCenter(from);
    final target = tester.getCenter(to) + Offset(dx, dy);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(start + (target - start) * (i / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  Future<void> withKey(WidgetTester tester, LogicalKeyboardKey key, Future<void> Function() body) async {
    await tester.sendKeyDownEvent(key);
    await body();
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  /// The list's sections by name, in order.
  Future<List<String>> sectionNames() async =>
      [for (final s in await db.select(db.listSections).get()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))) s.name];

  Future<void> addSection(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加分组').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), name);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop: sections in a list; drag tasks into them and around',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    await addSection(tester, '进行中');
    expect(find.text('未分组'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);

    // 甲 onto the 进行中 header.
    await drag(tester, find.text('甲'), find.text('进行中'));
    final doing = (await db.select(db.listSections).getSingle()).id;
    expect((await load('甲')).sectionId, doing);

    // 乙 below 甲, in 进行中.
    await drag(tester, find.text('乙'), find.text('甲'), dy: 8);
    final jia = await load('甲'), yi = await load('乙');
    expect(yi.sectionId, doing);
    expect(yi.sortOrder, greaterThan(jia.sortOrder));

    // 丙, the last one without a section, above 甲.
    await drag(tester, find.text('丙'), find.text('甲'), dy: -8);
    final bing = await load('丙');
    expect(bing.sectionId, doing);
    expect(bing.sortOrder, lessThan(jia.sortOrder));
    // 未分组 is empty now, so it's gone.
    expect(find.text('未分组'), findsNothing);

    // Rename and delete from the section's ⋯.
    await tester.tap(find.byTooltip('分组操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '本周');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('本周'), findsOneWidget);
    await tester.tap(find.byTooltip('分组操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect((await load('甲')).sectionId, isNull);
    expect(find.text('本周'), findsNothing);
    // The manual order stays: 丙, 甲, 乙.
    final ys = [for (final t in ['丙', '甲', '乙']) tester.getCenter(find.text(t)).dy];
    expect(ys, orderedEquals([...ys]..sort()));

    await finish(tester);
  });

  testWidgets('desktop: the board — columns, dragging between them, adding in one',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    await addSection(tester, '进行中');
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('看板'));
    await tester.pumpAndSettle();
    final c = container(tester);
    expect(c.read(viewPrefsProvider)[work]?.layout, ListLayout.board);
    expect(await db.getValue('list.layouts'), contains('board'));
    expect(find.text('拖任务到这里'), findsOneWidget); // 进行中 is empty
    expect(find.text('添加分组'), findsOneWidget);

    // 乙 into the empty column.
    await drag(tester, find.text('乙'), find.text('拖任务到这里'));
    final doing = (await db.select(db.listSections).getSingle()).id;
    expect((await load('乙')).sectionId, doing);

    // Add 丁 in 进行中 with its own field.
    await tester.tap(find.byTooltip('在“进行中”里添加任务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '丁');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect((await load('丁')).sectionId, doing);
    expect((await load('丁')).listId, work);

    // Ticking a card off moves it under 已完成 in its column.
    await tester.tap(find.bySemanticsLabel('完成').first);
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsWidgets);

    // Back to the list.
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(c.read(viewPrefsProvider)[work], isNull);
    expect(find.text('拖任务到这里'), findsNothing);

    await finish(tester);
  });

  testWidgets('desktop: in 最近7天, drag tasks to another day, an empty one too; times stay',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    final c = container(tester);
    final repo = c.read(repoProvider);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await repo.addTask(title: '晚上开会', dueDate: day, dueTime: 23 * 60 + 30);
    await repo.addTask(title: '早上跑步', dueDate: day, dueTime: 7 * 60);
    await repo.addTask(title: '后天的', dueDate: day.add(const Duration(days: 2)));
    c.read(selectedViewProvider.notifier).select(const SmartViewRef(SmartKind.next7));
    await tester.pumpAndSettle();
    String key(DateTime d) => dateKey(d);

    // Every day of the seven shows, so the empty ones take drops too.
    expect(find.textContaining(RegExp(r'^\d+月\d+日, 周')), findsNWidgets(5));
    final inTwo = day.add(const Duration(days: 2)), inThree = day.add(const Duration(days: 3));
    await drag(tester, find.text('晚上开会'), find.text(daySectionTitle(inTwo, day)));
    expect((await load('晚上开会')).dueDate, key(inTwo));
    expect((await load('晚上开会')).dueTime, 23 * 60 + 30);

    // Two picked go together onto an empty day, each keeping its time.
    await tester.tap(find.text('晚上开会'));
    await tester.pumpAndSettle();
    await withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.tap(find.text('早上跑步')));
    expect(find.text('已选择 2 项'), findsOneWidget);
    await drag(tester, find.text('早上跑步'), find.text(daySectionTitle(inThree, day)));
    expect([(await load('晚上开会')).dueDate, (await load('早上跑步')).dueDate], [key(inThree), key(inThree)]);
    expect([(await load('晚上开会')).dueTime, (await load('早上跑步')).dueTime], [23 * 60 + 30, 7 * 60]);
    expect((await load('后天的')).dueDate, key(inTwo));
    expect(find.text('已选择 2 项'), findsOneWidget); // still picked

    await finish(tester);
  });

  testWidgets('desktop: picked tasks drag together; sections drag by their headers',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    await addSection(tester, '进行中');
    await addSection(tester, '稍后');
    final doing = (await db.select(db.listSections).get()).firstWhere((s) => s.name == '进行中').id;

    // Pick 甲 and 丙; drag 甲 onto 进行中: both go, 丙 still above 甲.
    await tester.tap(find.text('甲'));
    await tester.pumpAndSettle();
    await withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.tap(find.text('丙')));
    await drag(tester, find.text('甲'), find.text('进行中'));
    final jia = await load('甲'), bing = await load('丙');
    expect([jia.sectionId, bing.sectionId, (await load('乙')).sectionId], [doing, doing, null]);
    expect(bing.sortOrder, lessThan(jia.sortOrder));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // 稍后 dragged onto the top of 进行中 goes before it.
    expect(await sectionNames(), ['进行中', '稍后']);
    await drag(tester, find.text('稍后'), find.text('进行中'), dy: -6);
    expect(await sectionNames(), ['稍后', '进行中']);
    final ys = [for (final t in ['未分组', '稍后', '进行中', '丙', '甲']) tester.getCenter(find.text(t).first).dy];
    expect(ys, orderedEquals([...ys]..sort()));

    // On the board, columns move the same way: 稍后 to the right of 进行中.
    container(tester).read(selectedTaskProvider.notifier).select(null); // the detail has a 更多 too
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('看板'));
    await tester.pumpAndSettle();
    await drag(tester, find.text('稍后'), find.text('进行中'), dx: 200);
    expect(await sectionNames(), ['进行中', '稍后']);
    expect(tester.getCenter(find.text('进行中')).dx, lessThan(tester.getCenter(find.text('稍后')).dx));

    await finish(tester);
  });

  testWidgets('desktop: pin from the menu; order by priority, where drops only change section',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    double y(String t) => tester.getCenter(find.text(t)).dy;
    expect(y('丙'), lessThan(y('甲'))); // newest first

    // Pin 甲: it goes to the top, with a pin.
    await tester.tap(find.text('甲'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect((await load('甲')).pinnedAt, isNotNull);
    expect(y('甲'), lessThan(y('丙')));
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    // Dragging an unpinned task above the pinned one keeps it below.
    await drag(tester, find.text('乙'), find.text('甲'), dy: -8);
    expect(y('甲'), lessThan(y('乙')));
    expect(y('乙'), lessThan(y('丙')));

    // Order by priority: 丙 (high) first after the pinned 甲.
    final c = container(tester);
    await c.read(repoProvider).setPriority((await load('丙')).id, Priority.high);
    await tester.tap(find.byTooltip('分组和排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排序：自定义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按优先级'));
    await tester.pumpAndSettle();
    expect(c.read(viewPrefsProvider)[work]?.sort, TaskSort.priority);
    expect(y('甲'), lessThan(y('丙')));
    expect(y('丙'), lessThan(y('乙')));

    // A drop within the section doesn't change the order now...
    final before = (await load('乙')).sortOrder;
    await drag(tester, find.text('乙'), find.text('丙'), dy: -8);
    expect((await load('乙')).sortOrder, before);
    // ...but a drop into another section moves it there.
    await addSection(tester, '稍后');
    await drag(tester, find.text('乙'), find.text('稍后'));
    final later = (await db.select(db.listSections).getSingle()).id;
    expect((await load('乙')).sectionId, later);
    expect((await load('乙')).sortOrder, before);

    // Unpin from the detail's ⋯.
    await tester.tap(find.text('甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();
    expect((await load('甲')).pinnedAt, isNull);

    await finish(tester);
  });

  testWidgets('phone: a long press without moving opens the menu; with moving, drags',
      (tester) async {
    await pumpApp(tester, const Size(400, 800));
    final g = await tester.startGesture(tester.getCenter(find.text('甲')));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('下周一'), findsOneWidget);
    await tester.tapAt(const Offset(10, 790));
    await tester.pumpAndSettle();

    // Long press 甲 and drag it above 丙 (the top).
    final start = tester.getCenter(find.text('甲'));
    final target = tester.getCenter(find.text('丙')) - const Offset(0, 10);
    final g2 = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 1; i <= 6; i++) {
      await g2.moveTo(start + (target - start) * (i / 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g2.up();
    await tester.pumpAndSettle();
    expect(find.text('下周一'), findsNothing);
    final jia = await load('甲'), bing = await load('丙');
    expect(jia.sortOrder, lessThan(bing.sortOrder));

    await finish(tester);
  });

  /// Picks [choice] in the ⇅ menu's [submenu] (分组 or 排序).
  Future<void> arrange(WidgetTester tester, String submenu, String choice) async {
    await tester.tap(find.byTooltip('分组和排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('$submenu：'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice));
    await tester.pumpAndSettle();
  }

  /// [text] in the middle pane (the sidebar and the detail may show it too).
  Finder inPane(String text) => find.descendant(of: find.byType(TaskListPane), matching: find.text(text));

  testWidgets('desktop: group a list by priority, tag or date; a drop takes on its group',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    final c = container(tester);
    final repo = c.read(repoProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await repo.setPriority((await load('丙')).id, Priority.high);
    await repo.setTags((await load('乙')).id, ['家务', '周末']);
    await repo.setDue((await load('甲')).id, today, 9 * 60);
    await tester.pumpAndSettle();

    await arrange(tester, '分组', '按优先级');
    expect(c.read(viewPrefsProvider)[work]?.grouping, TaskGrouping.priority);
    expect(inPane('高优先级'), findsOneWidget);
    expect(inPane('无优先级'), findsOneWidget);
    await drag(tester, inPane('甲'), inPane('高优先级'));
    expect((await load('甲')).priority, Priority.high);
    expect(inPane('无优先级'), findsOneWidget); // 乙 is still there

    // By tag: filed under the first one; a drop swaps that one.
    await arrange(tester, '分组', '按标签');
    // Rows show their tags too; the header comes first.
    expect(inPane('家务'), findsNWidgets(2));
    expect(inPane('周末'), findsOneWidget); // only 乙's chip
    expect(inPane('无标签'), findsOneWidget);
    await drag(tester, inPane('丙'), inPane('家务').first);
    expect((await load('丙')).tags, ['家务']);
    await drag(tester, inPane('乙'), inPane('无标签'));
    expect((await load('乙')).tags, isEmpty);

    // By date: a day keeps the time; 无日期 clears the date.
    await arrange(tester, '分组', '按时间');
    final todayTitle = daySectionTitle(today, today);
    expect(inPane(todayTitle), findsOneWidget);
    expect(inPane('无日期'), findsOneWidget);
    await drag(tester, inPane('乙'), inPane(todayTitle));
    expect((await load('乙')).dueDate, dateKey(today));
    await drag(tester, inPane('甲'), inPane('无日期'));
    expect((await load('甲')).dueDate, isNull);

    // Sort by tag while grouped by date.
    await arrange(tester, '排序', '按标签');
    expect(c.read(viewPrefsProvider)[work]?.sort, TaskSort.tag);

    // Adding a section goes back to the sections, to show it.
    await addSection(tester, '下周');
    expect(c.read(viewPrefsProvider)[work]?.grouping, isNull);
    expect(inPane('未分组'), findsOneWidget);
    expect(inPane('下周'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('desktop: 今天 grouped by list or not at all; drop on a list moves the task',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    final c = container(tester);
    final repo = c.read(repoProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await repo.addTask(title: '买菜', dueDate: today);
    await repo.addTask(title: '写报告', dueDate: today, listId: work);
    c.read(selectedViewProvider.notifier).select(const SmartViewRef(SmartKind.today));
    await tester.pumpAndSettle();
    // 今天 has no hand-made order to offer.
    await tester.tap(find.byTooltip('分组和排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排序：时间'));
    await tester.pumpAndSettle();
    expect(find.text('自定义（拖动）'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await arrange(tester, '分组', '按清单');
    expect(c.read(viewPrefsProvider)['smart:today']?.grouping, TaskGrouping.list);
    // A row shows its list too; the header comes first.
    expect(inPane('收集箱'), findsWidgets);
    await drag(tester, inPane('买菜'), inPane('工作').first);
    expect((await load('买菜')).listId, work);
    expect(inPane('收集箱'), findsNothing);

    // Not grouped: no headers, only the rows' list names.
    await arrange(tester, '分组', '不分组');
    expect(inPane('工作'), findsNWidgets(2));
    expect(find.text('今天, ${weekdayName(today)}'), findsNothing);
    expect(inPane('买菜'), findsOneWidget);
    // The list keeps its own grouping.
    expect(c.read(viewPrefsProvider)[work], isNull);

    await finish(tester);
  });
}
