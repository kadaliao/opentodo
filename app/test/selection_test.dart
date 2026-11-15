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
import 'package:opentodo/state/selection.dart';
import 'package:opentodo/ui/app.dart';
import 'package:opentodo/ui/home_shell.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the selection', () {
    late ProviderContainer c;
    setUp(() {
      c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory()))]);
    });
    tearDown(() => c.dispose());
    TaskSelectionNotifier sel() => c.read(taskSelectionProvider.notifier);
    Set<String> ids() => c.read(taskSelectionProvider).ids;

    test('⌘-click brings the open task along; again takes one out', () {
      sel().toggle('b', current: 'a');
      expect(ids(), {'a', 'b'});
      sel().toggle('a');
      expect(ids(), {'b'});
      sel().toggle('b');
      expect(c.read(taskSelectionProvider).active, isFalse);
    });

    test('Shift-click takes the range from the last pick, either way', () {
      const order = ['a', 'b', 'c', 'd', 'e'];
      sel().toggle('b');
      sel().extendTo(order, 'd');
      expect(ids(), {'b', 'c', 'd'});
      sel().extendTo(order, 'a');
      expect(ids(), {'a', 'b', 'c', 'd'});
      sel().clear();
      // Nothing picked yet: from the task open in the detail.
      sel().extendTo(order, 'c', current: 'e');
      expect(ids(), {'c', 'd', 'e'});
    });

    test('a new view starts afresh', () {
      sel().selectAll(['a', 'b']);
      expect(ids(), {'a', 'b'});
      c.read(selectedViewProvider.notifier).select(const SmartViewRef(SmartKind.inbox));
      expect(ids(), isEmpty);
    });
  });

  late AppDatabase db;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeShell)));

  /// 甲 乙 丙 丁 in the inbox (丁 newest, on top), open on screen.
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
    for (final t in ['甲', '乙', '丙', '丁']) {
      await c.read(repoProvider).addTask(title: t);
      await tester.pump(const Duration(milliseconds: 5));
    }
    c.read(selectedViewProvider.notifier).select(const SmartViewRef(SmartKind.inbox));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<Task> load(String title) =>
      (db.select(db.tasks)..where((t) => t.title.equals(title))).getSingle();

  Future<void> withKey(WidgetTester tester, LogicalKeyboardKey key, Future<void> Function() body) async {
    await tester.sendKeyDownEvent(key);
    await body();
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('desktop: ⌘-click and Shift-click pick tasks; the panel changes them all',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    await tester.tap(find.text('丁'));
    await tester.pumpAndSettle();
    await withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.tap(find.text('乙')));
    expect(find.text('已选择 2 项'), findsOneWidget);

    // The inbox shows 丁 丙 乙 甲. Shift-click from 乙 to 甲 adds 甲; ⌘-click
    // adds 丙.
    await withKey(tester, LogicalKeyboardKey.shiftLeft, () => tester.tap(find.text('甲')));
    expect(find.text('已选择 3 项'), findsOneWidget);
    await withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.tap(find.text('丙')));
    expect(find.text('已选择 4 项'), findsOneWidget);

    // High priority for all, from the panel.
    await tester.tap(find.text('无优先级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高优先级').last);
    await tester.pumpAndSettle();
    for (final t in ['甲', '乙', '丙', '丁']) {
      expect((await load(t)).priority, Priority.high);
    }
    expect(find.text('高优先级'), findsOneWidget); // the panel's summary

    // Esc stops picking; ⌘A picks everything again.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('已选择'), findsNothing);
    await withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.sendKeyEvent(LogicalKeyboardKey.keyA));
    expect(find.text('已选择 4 项'), findsOneWidget);

    // Finish them all, then undo.
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect((await load('甲')).status, TaskStatus.done);
    expect(find.text('已完成 4 个任务'), findsOneWidget);
    expect(find.textContaining('已选择'), findsNothing);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect((await load('甲')).status, TaskStatus.open);

    // Pick two and delete them, then undo.
    await tester.tap(find.text('甲'));
    await tester.pumpAndSettle();
    await withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.tap(find.text('乙')));
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect((await load('乙')).trashedAt, isNotNull);
    expect(find.text('乙'), findsNothing);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect((await load('乙')).trashedAt, isNull);

    await finish(tester);
  });

  testWidgets('desktop: tags for several tasks: a dash for some, a tick adds to all',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    final c = container(tester);
    await c.read(repoProvider).setTags((await load('甲')).id, ['工作']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('甲'));
    await tester.pumpAndSettle();
    await withKey(tester, LogicalKeyboardKey.metaLeft, () => tester.tap(find.text('乙')));
    await tester.tap(find.text('#工作'));
    await tester.pumpAndSettle();
    final box = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, '工作'));
    expect(box.value, isNull); // only 甲 has it
    await tester.tap(find.widgetWithText(CheckboxListTile, '工作'));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '本周');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect((await load('甲')).tags, ['工作', '本周']);
    expect((await load('乙')).tags, ['工作', '本周']);
    expect((await load('丙')).tags, isEmpty);

    await finish(tester);
  });

  testWidgets('phone: 多选 from the menu; taps pick; the bar acts on them', (tester) async {
    await pumpApp(tester, const Size(400, 800));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.text('甲'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(find.text('1 项'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    // A tap picks instead of opening.
    await tester.tap(find.text('丙'));
    await tester.pumpAndSettle();
    expect(find.text('2 项'), findsOneWidget);
    await tester.tap(find.byTooltip('完成'));
    await tester.pumpAndSettle();
    expect((await load('甲')).status, TaskStatus.done);
    expect((await load('丙')).status, TaskStatus.done);
    expect((await load('乙')).status, TaskStatus.open);
    expect(find.text('2 项'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await finish(tester);
  });
}
