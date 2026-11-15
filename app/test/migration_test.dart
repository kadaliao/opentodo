import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/data/db.dart';
import 'package:opentodo/data/keys.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// A database file at an older [version]: today's schema with the later
  /// tables and columns taken out again.
  Future<File> olderDatabase(int version) async {
    final dir = await Directory.systemTemp.createTemp('opentodo-migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    await db.setValue(Keys.cursor, '42');
    await db.setValue(Keys.email, 'a@example.com');
    await db.customStatement(
        "INSERT INTO tasks (id, list_id, title, created_at, updated_at) VALUES ('t', 'inbox', '旧任务', 1, 1)");
    await db.customStatement('ALTER TABLE tasks DROP COLUMN pinned_at');
    if (version < 6) {
      await db.customStatement('DROP TABLE list_sections');
      await db.customStatement('ALTER TABLE tasks DROP COLUMN section_id');
    }
    if (version < 5) await db.customStatement('DROP TABLE task_filters');
    await db.customStatement('PRAGMA user_version = $version');
    await db.close();
    return file;
  }

  for (final version in [4, 5, 6]) {
    test('v$version → v7 adds what is new', () async {
      final db = AppDatabase(NativeDatabase(await olderDatabase(version)));
      addTearDown(db.close);
      expect(await db.select(db.taskFilters).get(), isEmpty);
      expect(await db.select(db.listSections).get(), isEmpty);
      final task = await db.select(db.tasks).getSingle();
      expect((task.title, task.sectionId, task.pinnedAt), ('旧任务', null, null));
      // New kinds of records (filters, sections) mean pulling everything
      // again; a new column alone doesn't.
      expect(await db.getValue(Keys.cursor), version < 6 ? '0' : '42');
      expect(await db.getValue(Keys.email), 'a@example.com');
    });
  }
}
