import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/repo.dart';
import 'package:opentodo/sync/codec.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a task survives the trip to the server and back', () async {
    final a = AppDatabase(NativeDatabase.memory());
    final b = AppDatabase(NativeDatabase.memory());
    addTearDown(a.close);
    addTearDown(b.close);
    final repo = TaskRepo(a, clock: () => DateTime(2026, 11, 15, 10));
    final id = await repo.addTask(
      title: '开会',
      dueDate: DateTime(2026, 11, 16),
      dueTime: 900,
      duration: 90,
      tags: ['工作', '重要'],
      priority: Priority.high,
      reminders: [0, -30],
      repeatRule: 'FREQ=WEEKLY;BYDAY=MO',
      repeatFrom: 1,
    );
    await repo.setContent(id, '带上电脑');
    final original = (await repo.getTask(id))!;

    // Through JSON, as on the wire, with a version from the server.
    final json = jsonDecode(jsonEncode({...taskToWire(original).toJson(), 'version': 7}));
    final wire = WireRecord.fromJson(json as Map<String, dynamic>);
    await b.into(b.tasks).insert(wireToTask(wire));
    final copy = (await (b.select(b.tasks)..where((t) => t.id.equals(id))).getSingle());

    expect(copy.copyWith(dirty: true, serverVersion: 0).toJson(), original.toJson());
    expect(copy.dirty, isFalse);
    expect(copy.serverVersion, 7);
  });

  test('missing fields fall back to defaults; unknown ones are ignored', () {
    final wire = WireRecord.fromJson({
      'entity': 'task',
      'id': 'x',
      'updatedAt': 5,
      'deletedAt': null,
      'data': {'title': '旧客户端写的', 'someFutureField': 1},
      'version': 1,
    });
    final c = wireToTask(wire);
    expect(c.title.value, '旧客户端写的');
    expect(c.listId.value, inboxListId);
    expect(c.tags.value, isEmpty);
    expect(c.createdAt.value, 5);
    expect(c.reminders.value, isEmpty);
    expect(c.repeatRule.value, isNull);
    expect(c.repeatFrom.value, 0);
    expect(c.duration.value, isNull);
  });
}
