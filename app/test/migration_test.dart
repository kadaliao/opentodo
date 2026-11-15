import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/keys.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('v4 → v5 adds filters and pulls everything again', () async {
    final dir = await Directory.systemTemp.createTemp('opentodo-migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // Make a v4 database: today's schema without the filters table.
    final v5 = AppDatabase(NativeDatabase(file));
    await v5.setValue(Keys.cursor, '42');
    await v5.setValue(Keys.email, 'a@example.com');
    await v5.customStatement('DROP TABLE task_filters');
    await v5.customStatement('PRAGMA user_version = 4');
    await v5.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(await db.select(db.taskFilters).get(), isEmpty);
    expect(await db.getValue(Keys.cursor), '0');
    expect(await db.getValue(Keys.email), 'a@example.com');
  });
}
