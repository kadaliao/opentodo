import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/dates.dart';
import '../state/providers.dart';
import '../state/sync_providers.dart';
import '../sync/account.dart';
import '../sync/sync_engine.dart';
import 'dialogs.dart';

/// Bottom of the sidebar: sign in, or the account and how syncing is going.
class AccountTile extends ConsumerWidget {
  const AccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final account = ref.watch(accountProvider).value;
    final status = ref.watch(syncControllerProvider);

    if (account == null) {
      return ListTile(
        leading: Icon(Icons.cloud_off_outlined, color: scheme.onSurfaceVariant),
        title: const Text('登录以同步'),
        subtitle: Text('在手机和电脑之间同步任务', style: TextStyle(color: scheme.outline, fontSize: 12)),
        onTap: () => showSignInDialog(context),
      );
    }

    final (icon, color, subtitle) = switch (status.phase) {
      SyncPhase.syncing => (Icons.sync, scheme.primary, '正在同步…'),
      SyncPhase.error => (Icons.sync_problem, scheme.error, status.error?.message ?? '同步失败'),
      _ => (
          Icons.cloud_done_outlined,
          scheme.onSurfaceVariant,
          status.lastSyncedAt == null ? '已登录' : '${_ago(status.lastSyncedAt!)}同步',
        ),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(account.email, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: status.phase == SyncPhase.error ? scheme.error : scheme.outline)),
      trailing: PopupMenuButton<String>(
        tooltip: '账号',
        icon: const Icon(Icons.more_horiz),
        onSelected: (a) async {
          if (a == 'sync') {
            ref.read(syncControllerProvider.notifier).syncNow();
          } else if (a == 'relogin') {
            await showSignInDialog(context, email: account.email, server: account.serverUrl);
          } else if (a == 'signout') {
            await _signOut(context, ref);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'sync', child: Text('立即同步')),
          if (status.error?.isAuth ?? false)
            const PopupMenuItem(value: 'relogin', child: Text('重新登录')),
          const PopupMenuItem(value: 'signout', child: Text('退出登录')),
        ],
      ),
      onTap: () => ref.read(syncControllerProvider.notifier).syncNow(),
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${dateLabel(dateOnly(at), dateOnly(DateTime.now()))} ';
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final pending = await watchDirtyCount(ref.read(databaseProvider)).first;
    if (!context.mounted) return;
    final ok = await confirm(
      context,
      title: '退出登录？',
      message: pending == 0
          ? '这台设备上的任务会被清除，重新登录后会从服务器同步回来。'
          : '还有 $pending 条改动没有同步到服务器，退出后会丢失。确定退出吗？',
      action: '退出',
    );
    if (ok) await ref.read(accountProvider.notifier).signOut();
  }
}

Future<void> showSignInDialog(BuildContext context, {String? email, String? server}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SignInDialog(email: email, server: server),
  );
}

class _SignInDialog extends ConsumerStatefulWidget {
  const _SignInDialog({this.email, this.server});
  final String? email;
  final String? server;

  @override
  ConsumerState<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends ConsumerState<_SignInDialog> {
  late final _email = TextEditingController(text: widget.email);
  final _password = TextEditingController();
  late final _server = TextEditingController(text: widget.server ?? defaultServerUrl);
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '请填写邮箱和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountProvider.notifier).signIn(
            serverUrl: _server.text,
            email: _email.text,
            password: _password.text,
            register: _register,
          );
      if (mounted) Navigator.pop(context);
    } on SyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('登录账号'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('登录')),
              ButtonSegment(value: true, label: Text('注册')),
            ],
            selected: {_register},
            onSelectionChanged: (s) => setState(() => _register = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            autofocus: widget.email == null,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            autofocus: widget.email != null,
            obscureText: true,
            autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(
              labelText: '密码',
              helperText: _register ? '至少 8 位' : null,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('服务器', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              children: [
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
            ),
          if (!_register)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('登录后，这台设备上已有的任务会合并进账号。',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_register ? '注册并登录' : '登录'),
        ),
      ],
    );
  }
}
