import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/filters.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import 'dialogs.dart';

/// Asks for a new filter and saves it; returns its id.
Future<String?> addFilter(BuildContext context, WidgetRef ref) async {
  final result = await showFilterEditor(context);
  if (result == null) return null;
  return ref.read(repoProvider).addFilter(result.name, result.rule.encode());
}

Future<void> editFilter(BuildContext context, WidgetRef ref, TaskFilter filter) async {
  final result = await showFilterEditor(context, filter: filter);
  if (result == null) return;
  await ref
      .read(repoProvider)
      .updateFilter(filter.id, name: result.name, rule: result.rule.encode());
}

Future<void> deleteFilter(BuildContext context, WidgetRef ref, TaskFilter filter) async {
  final ok = await confirm(
    context,
    title: '删除过滤器“${filter.name}”？',
    message: '只删除过滤器，里面的任务不受影响。',
    action: '删除',
  );
  if (!ok) return;
  await ref.read(repoProvider).deleteFilter(filter.id);
  if (ref.read(selectedViewProvider) == FilterViewRef(filter.id)) {
    ref.read(selectedViewProvider.notifier).select(const SmartViewRef(SmartKind.today));
  }
}

Future<({String name, FilterRule rule})?> showFilterEditor(
  BuildContext context, {
  TaskFilter? filter,
}) {
  return showDialog<({String name, FilterRule rule})>(
    context: context,
    builder: (_) => _FilterEditor(filter: filter),
  );
}

class _FilterEditor extends ConsumerStatefulWidget {
  const _FilterEditor({this.filter});
  final TaskFilter? filter;

  @override
  ConsumerState<_FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends ConsumerState<_FilterEditor> {
  late final _name = TextEditingController(text: widget.filter?.name);
  late FilterRule _rule = widget.filter == null ? const FilterRule() : FilterRule.parse(widget.filter!.rule);
  late bool _advanced = !_rule.isSimple;

  /// Stable keys for the advanced rows, parallel to the conditions, so a
  /// text field keeps its state when a row above it goes.
  late List<int> _rowKeys = [for (var i = 0; i < _rule.conditions.length; i++) i];
  late int _nextKey = _rowKeys.length;

  /// Bumped when the simple form's keyword field must show new text.
  int _simpleGeneration = 0;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setAdvanced(bool advanced) {
    setState(() {
      if (advanced) {
        if (_rule.conditions.isEmpty) {
          _setConditions([const FilterCondition(FilterField.list, [])]);
        }
      } else {
        _setConditions(_rule.tidy().conditions);
        _simpleGeneration++;
      }
      _advanced = advanced;
    });
  }

  void _setConditions(List<FilterCondition> conditions, {List<int>? keys}) {
    _rule = _rule.copyWith(conditions: conditions);
    _rowKeys = keys ?? [for (var i = 0; i < conditions.length; i++) _nextKey++];
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final rule = FilterRule(
      matchAll: _rule.matchAll,
      conditions: [
        for (final c in _rule.tidy().conditions)
          c.field == FilterField.keyword
              ? c.copyWith(values: [for (final v in c.values) if (v.trim().isNotEmpty) v.trim()])
              : c,
      ],
    );
    Navigator.pop(context, (name: name, rule: rule));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final matches = _rule.tidy().matcher(ref.watch(clockProvider));
    final count = tasks.where((t) => isOpen(t) && matches(t)).length;
    final canSimple = _rule.tidy().isSimple;

    final narrow = MediaQuery.sizeOf(context).width < 560;
    return AlertDialog(
      title: Text(widget.filter == null ? '添加过滤器' : '编辑过滤器'),
      scrollable: true,
      insetPadding: narrow
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: const Text('普通'),
                    enabled: canSimple,
                    tooltip: canSimple ? null : '这些条件只能在“高级”里编辑',
                  ),
                  const ButtonSegment(value: true, label: Text('高级')),
                ],
                selected: {_advanced},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (s) => _setAdvanced(s.single),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.filter == null,
              decoration: const InputDecoration(
                hintText: '过滤器名称',
                prefixIcon: Icon(Icons.filter_alt_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            if (_advanced) ..._advancedForm(scheme, narrow: narrow) else ..._simpleForm(),
            const SizedBox(height: 12),
            Text(
              count == 0 ? '现在没有符合条件的未完成任务' : '现在有 $count 个未完成任务符合条件',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  List<Widget> _simpleForm() {
    Widget row(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(width: 64, child: Text(label)),
            Expanded(child: child),
          ]),
        );
    final keyword = _rule.valuesOf(FilterField.keyword);
    final priorities = _rule.valuesOf(FilterField.priority);
    return [
      for (final f in [FilterField.list, FilterField.tag, FilterField.date])
        row(
          f.label,
          _ValuePicker(
            field: f,
            values: _rule.valuesOf(f),
            onChanged: (v) => setState(() => _rule = _rule.withValues(f, v)),
          ),
        ),
      row(
        '优先级',
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(
            label: const Text('所有'),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selected: priorities.isEmpty,
            onSelected: (_) => setState(() => _rule = _rule.withValues(FilterField.priority, [])),
          ),
          for (final (key, _, label) in priorityChoices)
            FilterChip(
              label: Text(label),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              selected: priorities.contains(key),
              onSelected: (on) => setState(() {
                final next = [
                  for (final (k, _, _) in priorityChoices)
                    if (k == key ? on : priorities.contains(k)) k,
                ];
                _rule = _rule.withValues(FilterField.priority, next);
              }),
            ),
        ]),
      ),
      row(
        '内容包含',
        TextFormField(
          key: ValueKey('keyword-$_simpleGeneration'),
          initialValue: keyword.firstOrNull ?? '',
          decoration: const InputDecoration(
            hintText: '标题或描述里的文字',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(
              () => _rule = _rule.withValues(FilterField.keyword, v.trim().isEmpty ? [] : [v])),
        ),
      ),
    ];
  }

  List<Widget> _advancedForm(ColorScheme scheme, {required bool narrow}) {
    final conditions = _rule.conditions;
    void replace(int i, FilterCondition c) =>
        setState(() => _setConditions([...conditions]..[i] = c, keys: _rowKeys));
    void remove(int i) => setState(() => _setConditions(
          [...conditions]..removeAt(i),
          keys: [..._rowKeys]..removeAt(i),
        ));

    return [
      Row(children: [
        const Text('满足'),
        const SizedBox(width: 8),
        DropdownButton<bool>(
          value: _rule.matchAll,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: true, child: Text('全部')),
            DropdownMenuItem(value: false, child: Text('任一')),
          ],
          onChanged: (v) => setState(() => _rule = _rule.copyWith(matchAll: v)),
        ),
        const SizedBox(width: 8),
        const Text('条件'),
      ]),
      const SizedBox(height: 4),
      for (var i = 0; i < conditions.length; i++)
        Padding(
          key: ValueKey(_rowKeys[i]),
          padding: const EdgeInsets.only(bottom: 8),
          child: _conditionRow(conditions[i], scheme,
              narrow: narrow, replace: (c) => replace(i, c), remove: () => remove(i)),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加条件'),
          onPressed: () => setState(() {
            final used = {for (final c in conditions) c.field};
            final field =
                FilterField.values.where((f) => !used.contains(f)).firstOrNull ?? FilterField.list;
            _setConditions(
              [...conditions, FilterCondition(field, const [])],
              keys: [..._rowKeys, _nextKey++],
            );
          }),
        ),
      ),
    ];
  }
}

Widget _conditionRow(
  FilterCondition c,
  ColorScheme scheme, {
  required bool narrow,
  required ValueChanged<FilterCondition> replace,
  required VoidCallback remove,
}) {
  final removeButton = IconButton(
    tooltip: '删除条件',
    visualDensity: VisualDensity.compact,
    icon: const Icon(Icons.close, size: 18),
    onPressed: remove,
  );
  if (!c.isKnown) {
    return Row(children: [
      Expanded(
        child: Text('新版本加的条件，这个版本不能编辑', style: TextStyle(color: scheme.onSurfaceVariant)),
      ),
      removeButton,
    ]);
  }
  final field = SizedBox(
    width: 80,
    child: DropdownButton<FilterField>(
      value: c.field,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: [
        for (final f in FilterField.values) DropdownMenuItem(value: f, child: Text(f.label)),
      ],
      onChanged: (f) {
        if (f != c.field) replace(FilterCondition(f!, const [], exclude: c.exclude));
      },
    ),
  );
  final op = SizedBox(
    width: 80,
    child: DropdownButton<bool>(
      value: c.exclude,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: false, child: Text('包含')),
        DropdownMenuItem(value: true, child: Text('不包含')),
      ],
      onChanged: (v) => replace(c.copyWith(exclude: v)),
    ),
  );
  final value = c.field == FilterField.keyword
      ? TextFormField(
          initialValue: c.values.firstOrNull ?? '',
          decoration: const InputDecoration(
            hintText: '文字',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => replace(c.copyWith(values: [v])),
        )
      : _ValuePicker(
          field: c.field!,
          values: c.values,
          onChanged: (v) => replace(c.copyWith(values: v)),
        );
  // On a phone the values get a line of their own.
  if (narrow) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [field, const SizedBox(width: 12), op, const Spacer(), removeButton]),
      value,
    ]);
  }
  return Row(children: [
    field,
    const SizedBox(width: 12),
    op,
    const SizedBox(width: 12),
    Expanded(child: value),
    removeButton,
  ]);
}

/// A box that shows the chosen values and opens a menu of checkboxes.
class _ValuePicker extends ConsumerWidget {
  const _ValuePicker({required this.field, required this.values, required this.onChanged});

  final FilterField field;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(listsByIdProvider);
    final options = <(String, String)>[
      ...switch (field) {
        FilterField.list => [
            (inboxListId, '收集箱'),
            for (final l in lists.values) (l.id, '${l.emoji ?? ''} ${l.name}'.trim()),
          ],
        FilterField.tag => [
            (noTag, '无标签'),
            for (final t in ref.watch(tagsProvider)) (t, t),
          ],
        FilterField.date => [for (final d in DateChoice.values) (d.name, d.label)],
        FilterField.priority => [for (final (k, _, label) in priorityChoices) (k, label)],
        FilterField.keyword => const <(String, String)>[],
      },
    ];
    // Something chosen earlier that's gone now (a deleted list, a tag no
    // task uses any more) stays, so it can be unticked.
    for (final v in values) {
      if (!options.any((o) => o.$1 == v)) {
        options.add((v, describeValues(field, [v], lists: lists)));
      }
    }
    void toggle(String v) => onChanged([
          for (final o in options)
            if (o.$1 == v ? !values.contains(v) : values.contains(o.$1)) o.$1,
        ]);

    return MenuAnchor(
      menuChildren: [
        for (final (value, label) in options)
          CheckboxMenuButton(
            value: values.contains(value),
            closeOnActivate: false,
            onChanged: (_) => toggle(value),
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            suffixIcon: Icon(Icons.expand_more, size: 20),
          ),
          child: Text(
            describeValues(field, values, lists: lists),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
