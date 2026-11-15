import 'package:material_ui/material_ui.dart';


Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String action = '确定',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

const _emojiChoices = ['📋', '💼', '🏠', '📚', '🏃', '🛒', '✈️', '💡', '🎯', '❤️', '🎨', '💰'];

Future<({String name, String? emoji})?> showListEditor(
  BuildContext context, {
  String? name,
  String? emoji,
}) {
  return showDialog<({String name, String? emoji})>(
    context: context,
    builder: (context) => _ListEditor(name: name, emoji: emoji),
  );
}

class _ListEditor extends StatefulWidget {
  const _ListEditor({this.name, this.emoji});
  final String? name;
  final String? emoji;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  late final _name = TextEditingController(text: widget.name);
  late String? _emoji = widget.emoji ?? _emojiChoices.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, emoji: _emoji));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.name == null ? '添加清单' : '编辑清单'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(hintText: '清单名称', border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _emojiChoices)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _emoji = e),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: _emoji == e ? scheme.secondaryContainer : null,
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 18)),
                ),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
