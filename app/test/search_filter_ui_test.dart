import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/domain/views.dart';
import 'package:opentodo/state/providers.dart';
import 'package:opentodo/ui/app.dart';
import 'package:opentodo/ui/home_shell.dart';
import 'package:opentodo/ui/task_detail.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late String work;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeShell)));

  /// Two lists and a few tasks: 写周报 (工作, high), 整理桌面 (工作), 交房租
  /// (家里, high), 读书 (收集箱), and 开会 whose subtask mentions 周报.
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
    final repo = container(tester).read(repoProvider);
    work = await repo.addList('工作', emoji: '💼');
    final home = await repo.addList('家里', emoji: '🏠');
    await repo.addTask(title: '写周报', listId: work, priority: Priority.high);
    await repo.addTask(title: '整理桌面', listId: work);
    await repo.addTask(title: '交房租', listId: home, priority: Priority.high);
    await repo.addTask(title: '读书');
    final meeting = await repo.addTask(title: '开会', listId: home);
    await repo.addChecklistItem(meeting, '带上周报模板');
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder inDialog(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

  testWidgets('desktop: make a filter, add to it, change it, delete it', (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    expect(find.textContaining('按清单、日期、优先级、标签筛出任务'), findsOneWidget);

    await tester.tap(find.byTooltip('添加过滤器'));
    await tester.pumpAndSettle();
    expect(find.text('添加过滤器'), findsWidgets);
    expect(find.text('现在有 5 个未完成任务符合条件'), findsOneWidget);
    // 保存 waits for a name.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, isNull);
    await tester.enterText(inDialog(find.byType(TextField)).first, '重要工作');

    // 清单: tick 工作 in the menu.
    await tester.tap(inDialog(find.text('所有')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('💼 工作'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('普通'))); // closes the menu
    await tester.pumpAndSettle();
    expect(inDialog(find.text('工作')), findsOneWidget); // the picker's summary
    expect(find.text('现在有 2 个未完成任务符合条件'), findsOneWidget);
    await tester.tap(inDialog(find.text('高')));
    await tester.pumpAndSettle();
    expect(find.text('现在有 1 个未完成任务符合条件'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final c = container(tester);
    final id = (await db.select(db.taskFilters).getSingle()).id;
    expect(c.read(selectedViewProvider), FilterViewRef(id));
    expect(find.text('重要工作'), findsNWidgets(2)); // the sidebar and the title
    expect(find.text('写周报'), findsOneWidget);
    expect(find.text('整理桌面'), findsNothing);

    // A task added here gets the filter's list and priority.
    await tester.enterText(find.byType(TextField).first, '准备材料');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final added =
        await (db.select(db.tasks)..where((t) => t.title.equals('准备材料'))).getSingle();
    expect((added.listId, added.priority), (work, Priority.high));
    expect(find.text('准备材料'), findsWidgets);

    // In 高级, turn the priority around: 工作 tasks that are not high.
    await tester.tap(find.byTooltip('编辑过滤器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高级'));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('包含')), findsNWidgets(2));
    await tester.tap(inDialog(find.text('包含')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('不包含').last);
    await tester.pumpAndSettle();
    expect(find.text('现在有 1 个未完成任务符合条件'), findsOneWidget);
    // The simple form can't show that.
    final segments = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(segments.segments.first.enabled, isFalse);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('整理桌面'), findsOneWidget);
    expect(find.text('写周报'), findsNothing);

    // Delete it from the sidebar's menu.
    await tester.tap(find.text('重要工作').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除过滤器'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(c.read(selectedViewProvider), const SmartViewRef(SmartKind.today));
    expect(find.text('重要工作'), findsNothing);

    await finish(tester);
  });

  testWidgets('a filter deleted elsewhere while on screen goes back to 今天', (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    final c = container(tester);
    final id = await c.read(repoProvider).addFilter('远程', '{}');
    await tester.pumpAndSettle();
    c.read(selectedViewProvider.notifier).select(FilterViewRef(id));
    await tester.pumpAndSettle();
    expect(find.text('远程'), findsNWidgets(2));
    await c.read(repoProvider).deleteFilter(id); // as a sync would
    await tester.pumpAndSettle();
    expect(c.read(selectedViewProvider), const SmartViewRef(SmartKind.today));
    await finish(tester);
  });

  testWidgets('desktop: ⌘F searches; arrows and return open a task',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('搜索任务、清单、标签和过滤器'), findsOneWidget);

    await tester.enterText(inDialog(find.byType(TextField)), '周报');
    await tester.pumpAndSettle();
    expect(inDialog(find.text('写周报')), findsOneWidget);
    expect(inDialog(find.text('☐ 带上周报模板')), findsOneWidget); // found in a subtask
    expect(inDialog(find.text('💼 工作')), findsOneWidget); // where it lives

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    final c = container(tester);
    final meeting = c.read(tasksProvider).value!.firstWhere((t) => t.title == '开会');
    expect(c.read(selectedTaskProvider), meeting.id);
    expect(c.read(selectedViewProvider), ListViewRef(meeting.listId));

    // A list opens as a view.
    await tester.tap(find.byTooltip('搜索（⌘F）'));
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)), '工作');
    await tester.pumpAndSettle();
    expect(inDialog(find.text('清单')), findsOneWidget);
    await tester.tap(inDialog(find.text('工作')).last); // not the text being typed
    await tester.pumpAndSettle();
    expect(c.read(selectedViewProvider), ListViewRef(work));

    // Nothing found.
    await tester.tap(find.byTooltip('搜索（⌘F）'));
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)), '火星');
    await tester.pumpAndSettle();
    expect(find.text('没有找到“火星”'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('phone: search is a page; a task opens as its own page', (tester) async {
    await pumpApp(tester, const Size(400, 800));
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '房租');
    await tester.pumpAndSettle();
    await tester.tap(find.text('交房租'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPage), findsOneWidget);
    // Back goes to the list, not to search.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPage), findsNothing);
    expect(find.text('搜索任务、清单、标签和过滤器'), findsNothing);

    await finish(tester);
  });
}
