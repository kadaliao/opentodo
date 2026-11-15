import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/views.dart';
import 'package:opentodo/state/providers.dart';
import 'package:opentodo/ui/app.dart';
import 'package:opentodo/ui/home_shell.dart';

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

  /// Drags with the mouse from [from]'s middle to [to] (plus [dy]).
  Future<void> drag(WidgetTester tester, Finder from, Finder to, {double dy = 0}) async {
    // Positions first: while dragging, the task shows twice.
    final start = tester.getCenter(from);
    final target = tester.getCenter(to) + Offset(0, dy);
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
    expect(c.read(listPrefsProvider)[work]?.layout, ListLayout.board);
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
    expect(c.read(listPrefsProvider)[work], isNull);
    expect(find.text('拖任务到这里'), findsNothing);

    await finish(tester);
  });

  testWidgets('desktop: in 最近7天, drag a task to another day; the time stays',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    final c = container(tester);
    final repo = c.read(repoProvider);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await repo.addTask(title: '晚上开会', dueDate: day, dueTime: 23 * 60 + 30);
    await repo.addTask(title: '后天的', dueDate: day.add(const Duration(days: 2)));
    c.read(selectedViewProvider.notifier).select(const SmartViewRef(SmartKind.next7));
    await tester.pumpAndSettle();

    final target = find.textContaining(RegExp(r'^\d+月\d+日, 周'));
    expect(target, findsOneWidget); // the day after tomorrow's header
    await drag(tester, find.text('晚上开会'), target);
    final moved = await load('晚上开会');
    final expected = day.add(const Duration(days: 2));
    expect(moved.dueDate,
        '${expected.year}-${expected.month.toString().padLeft(2, '0')}-${expected.day.toString().padLeft(2, '0')}');
    expect(moved.dueTime, 23 * 60 + 30);

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
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排序：自定义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按优先级'));
    await tester.pumpAndSettle();
    expect(c.read(listPrefsProvider)[work]?.sort, ListSort.priority);
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
}
