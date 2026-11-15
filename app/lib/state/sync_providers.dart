import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart' show AppLifecycleListener;

import '../sync/account.dart';
import '../sync/sync_engine.dart';
import 'providers.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final syncEngineProvider = Provider<SyncEngine>(
    (ref) => SyncEngine(ref.watch(databaseProvider), ref.watch(httpClientProvider)));

/// The signed-in account, or null.
class AccountNotifier extends AsyncNotifier<Account?> {
  @override
  Future<Account?> build() => Account.load(ref.watch(databaseProvider));

  /// Throws [SyncException] with a message for the person.
  Future<void> signIn({
    required String serverUrl,
    required String email,
    required String password,
    required bool register,
  }) async {
    final account = await AuthApi(ref.read(httpClientProvider)).signIn(
      serverUrl: serverUrl,
      email: email,
      password: password,
      register: register,
    );
    await completeSignIn(ref.read(databaseProvider), account);
    state = AsyncData(account);
  }

  Future<void> signOut() async {
    final account = state.value;
    if (account != null) await AuthApi(ref.read(httpClientProvider)).signOut(account);
    await clearLocalData(ref.read(databaseProvider));
    ref.read(selectedTaskProvider.notifier).select(null);
    state = const AsyncData(null);
  }
}

final accountProvider = AsyncNotifierProvider<AccountNotifier, Account?>(AccountNotifier.new);

enum SyncPhase { signedOut, idle, syncing, error }

class SyncStatus {
  const SyncStatus(this.phase, {this.lastSyncedAt, this.error});

  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final SyncException? error;
}

/// Runs a sync after local changes settle, every minute, when the app comes
/// back to the foreground, and on demand.
class SyncController extends Notifier<SyncStatus> {
  static const debounce = Duration(seconds: 2);
  static const interval = Duration(minutes: 1);

  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  @override
  SyncStatus build() {
    final account = ref.watch(accountProvider).value;
    if (account == null) return const SyncStatus(SyncPhase.signedOut);
    final db = ref.watch(databaseProvider);

    final dirty = watchDirtyCount(db).listen((n) {
      if (n > 0) {
        _debounce?.cancel();
        _debounce = Timer(debounce, syncNow);
      }
    });
    final periodic = Timer.periodic(interval, (_) => syncNow());
    final lifecycle = AppLifecycleListener(onResume: syncNow);
    ref.onDispose(() {
      dirty.cancel();
      periodic.cancel();
      lifecycle.dispose();
      _debounce?.cancel();
    });

    db.getValue(Keys.lastSyncedAt).then((v) {
      final ms = int.tryParse(v ?? '');
      if (ref.mounted && ms != null && state.lastSyncedAt == null && state.phase == SyncPhase.idle) {
        state = SyncStatus(SyncPhase.idle, lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(ms));
      }
    });
    Future.microtask(syncNow);
    return const SyncStatus(SyncPhase.idle);
  }

  Future<void> syncNow() async {
    if (!ref.mounted || state.phase == SyncPhase.signedOut) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    final last = state.lastSyncedAt;
    state = SyncStatus(SyncPhase.syncing, lastSyncedAt: last);
    try {
      do {
        _again = false;
        await ref.read(syncEngineProvider).sync();
      } while (_again && ref.mounted);
      if (ref.mounted) state = SyncStatus(SyncPhase.idle, lastSyncedAt: DateTime.now());
    } on SyncException catch (e) {
      if (ref.mounted) state = SyncStatus(SyncPhase.error, lastSyncedAt: last, error: e);
    } catch (e) {
      if (ref.mounted) {
        state = SyncStatus(SyncPhase.error,
            lastSyncedAt: last, error: SyncException('unknown', '同步出错：$e'));
      }
    } finally {
      _running = false;
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
