import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../data/db.dart';
import 'account.dart';
import 'codec.dart';

class SyncReport {
  const SyncReport({required this.pushed, required this.pulled});
  final int pushed;
  final int pulled;
}

class _Response {
  _Response(Map<String, dynamic> j)
      : accepted = [
          for (final a in (j['accepted'] as List? ?? const []))
            (
              entity: (a as Map)['entity'] as String,
              id: a['id'] as String,
              version: (a['version'] as num).toInt(),
            ),
        ],
        changes = [
          for (final c in (j['changes'] as List? ?? const []))
            WireRecord.fromJson((c as Map).cast<String, dynamic>()),
        ],
        cursor = (j['cursor'] as num).toInt(),
        hasMore = j['hasMore'] as bool? ?? false;

  final List<({String entity, String id, int version})> accepted;
  final List<WireRecord> changes;
  final int cursor;
  final bool hasMore;
}

/// One sync pass: push what changed here, pull what changed elsewhere.
///
/// Conflicts go to the newer edit (by `updatedAt`). A local edit made while a
/// request is in flight stays dirty and goes out on the next pass.
class SyncEngine {
  SyncEngine(this.db, this.client, {this.pageSize = 500});

  final AppDatabase db;
  final http.Client client;
  final int pageSize;

  Future<SyncReport> sync() async {
    final account = await Account.load(db);
    if (account == null) throw const SyncException('signed_out', '还没有登录');
    var cursor = int.tryParse(await db.getValue(Keys.cursor) ?? '') ?? 0;
    var pushed = 0, pulled = 0;

    // Bounded so a misbehaving server can't keep us looping.
    for (var round = 0; round < 10000; round++) {
      final pending = await _dirty(pageSize);
      final res = await _post(account, cursor, pending);
      await db.transaction(() async {
        // Apply first: the server reads what to send back before storing this
        // push, so a pulled record can be older than one just pushed. While
        // the pushed row is still dirty, _apply keeps the newer local copy.
        for (final r in res.changes) {
          await _apply(r);
        }
        await _markAccepted(pending, res.accepted);
        cursor = res.cursor;
        await db.setValue(Keys.cursor, '$cursor');
      });
      pushed += res.accepted.length;
      pulled += res.changes.length;
      if (!res.hasMore && pending.length < pageSize) break;
    }

    await _purgeSyncedTombstones();
    await db.setValue(Keys.lastSyncedAt, '${DateTime.now().millisecondsSinceEpoch}');
    return SyncReport(pushed: pushed, pulled: pulled);
  }

  /// Dirty rows, lists first so a task never arrives before its list.
  Future<List<WireRecord>> _dirty(int limit) async {
    final out = <WireRecord>[];
    final lists = await (db.select(db.taskLists)
          ..where((t) => t.dirty.equals(true))
          ..limit(limit))
        .get();
    out.addAll(lists.map(listToWire));
    if (out.length < limit) {
      final tasks = await (db.select(db.tasks)
            ..where((t) => t.dirty.equals(true))
            ..limit(limit - out.length))
          .get();
      out.addAll(tasks.map(taskToWire));
    }
    if (out.length < limit) {
      final items = await (db.select(db.checklistItems)
            ..where((t) => t.dirty.equals(true))
            ..limit(limit - out.length))
          .get();
      out.addAll(items.map(checklistToWire));
    }
    return out;
  }

  Future<_Response> _post(Account account, int cursor, List<WireRecord> pending) async {
    final http.Response r;
    try {
      r = await client
          .post(
            Uri.parse('${account.serverUrl}/v1/sync'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${account.token}',
            },
            body: jsonEncode({
              'cursor': cursor,
              'limit': pageSize,
              'changes': [for (final p in pending) p.toJson()],
            }),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw networkError(e);
    }
    if (r.statusCode != 200) throw errorFrom(r);
    return _Response(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> _markAccepted(
    List<WireRecord> pending,
    List<({String entity, String id, int version})> accepted,
  ) async {
    final sentAt = {for (final p in pending) '${p.entity}/${p.id}': p.updatedAt};
    for (final a in accepted) {
      final updatedAt = sentAt['${a.entity}/${a.id}'];
      if (updatedAt == null) continue;
      // Only if it hasn't been edited again since it was sent.
      switch (a.entity) {
        case Entity.list:
          await (db.update(db.taskLists)
                ..where((t) => t.id.equals(a.id) & t.updatedAt.equals(updatedAt)))
              .write(TaskListsCompanion(dirty: const Value(false), serverVersion: Value(a.version)));
        case Entity.task:
          await (db.update(db.tasks)
                ..where((t) => t.id.equals(a.id) & t.updatedAt.equals(updatedAt)))
              .write(TasksCompanion(dirty: const Value(false), serverVersion: Value(a.version)));
        case Entity.checklist:
          await (db.update(db.checklistItems)
                ..where((t) => t.id.equals(a.id) & t.updatedAt.equals(updatedAt)))
              .write(ChecklistItemsCompanion(dirty: const Value(false), serverVersion: Value(a.version)));
      }
    }
  }

  Future<void> _apply(WireRecord r) async {
    bool keepLocal(int? localUpdatedAt, bool? localDirty) =>
        localDirty == true && localUpdatedAt != null && localUpdatedAt > r.updatedAt;

    switch (r.entity) {
      case Entity.list:
        final local = await (db.select(db.taskLists)..where((t) => t.id.equals(r.id))).getSingleOrNull();
        if (keepLocal(local?.updatedAt, local?.dirty)) return;
        await db.into(db.taskLists).insertOnConflictUpdate(wireToList(r));
      case Entity.task:
        final local = await (db.select(db.tasks)..where((t) => t.id.equals(r.id))).getSingleOrNull();
        if (keepLocal(local?.updatedAt, local?.dirty)) return;
        await db.into(db.tasks).insertOnConflictUpdate(wireToTask(r));
      case Entity.checklist:
        final local =
            await (db.select(db.checklistItems)..where((t) => t.id.equals(r.id))).getSingleOrNull();
        if (keepLocal(local?.updatedAt, local?.dirty)) return;
        await db.into(db.checklistItems).insertOnConflictUpdate(wireToChecklist(r));
      default:
      // A kind of record this version doesn't know yet: skip it.
    }
  }

  /// Deleted rows the server already has can go; it keeps the tombstone for
  /// other devices.
  Future<void> _purgeSyncedTombstones() async {
    await (db.delete(db.taskLists)..where((t) => t.deletedAt.isNotNull() & t.dirty.equals(false))).go();
    await (db.delete(db.tasks)..where((t) => t.deletedAt.isNotNull() & t.dirty.equals(false))).go();
    await (db.delete(db.checklistItems)..where((t) => t.deletedAt.isNotNull() & t.dirty.equals(false))).go();
  }
}

/// Number of rows waiting to be pushed, as a stream (for the sync scheduler).
Stream<int> watchDirtyCount(AppDatabase db) => db
    .customSelect(
      'SELECT (SELECT COUNT(*) FROM task_lists WHERE dirty)'
      ' + (SELECT COUNT(*) FROM tasks WHERE dirty)'
      ' + (SELECT COUNT(*) FROM checklist_items WHERE dirty) AS n',
      readsFrom: {db.taskLists, db.tasks, db.checklistItems},
    )
    .watchSingle()
    .map((row) => row.read<int>('n'));

/// After signing in: drop the untouched welcome items (the account may
/// already have its own) and start syncing from the beginning.
Future<void> completeSignIn(AppDatabase db, Account account) => db.transaction(() async {
      final seed = await db.getValue(Keys.seedIds);
      if (seed != null) {
        final ids = (jsonDecode(seed) as List).cast<String>();
        await (db.delete(db.tasks)
              ..where((t) => t.id.isIn(ids) & t.updatedAt.equalsExp(t.createdAt)))
            .go();
        await (db.delete(db.checklistItems)..where((c) => c.taskId.isIn(ids))).go();
        // A welcome list goes too, if nothing is left in it.
        final lists = await (db.select(db.taskLists)
              ..where((t) => t.id.isIn(ids) & t.updatedAt.equalsExp(t.createdAt)))
            .get();
        for (final l in lists) {
          final remaining = await (db.select(db.tasks)..where((t) => t.listId.equals(l.id))).get();
          if (remaining.isEmpty) {
            await (db.delete(db.taskLists)..where((t) => t.id.equals(l.id))).go();
          }
        }
        await db.setValue(Keys.seedIds, null);
      }
      await account.save(db);
      await db.setValue(Keys.cursor, '0');
      await db.setValue(Keys.lastSyncedAt, null);
    });

/// Signing out removes this account's data from the device.
Future<void> clearLocalData(AppDatabase db) => db.transaction(() async {
      await db.delete(db.checklistItems).go();
      await db.delete(db.tasks).go();
      await db.delete(db.taskLists).go();
      await db.delete(db.keyValues).go();
    });
