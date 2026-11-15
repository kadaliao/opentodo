import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'db.g.dart';

/// The list every task without a list of its own belongs to. It has no row in
/// [TaskLists]; the sidebar shows it as 收集箱.
const inboxListId = 'inbox';

/// Columns every synced row carries.
///
/// [updatedAt] and [dirty] are set on every local write; the sync engine pushes
/// dirty rows and clears the flag once the server has stored them under
/// [serverVersion]. Rows are never removed locally until the server has seen
/// the tombstone in [deletedAt].
mixin SyncColumns on Table {
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get serverVersion => integer().withDefault(const Constant(0))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
}

class TaskLists extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get emoji => text().nullable()();
  IntColumn get color => integer().nullable()();
  RealColumn get sortOrder => real().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Task status values.
abstract final class TaskStatus {
  static const open = 0;
  static const done = 1;
  static const wontDo = 2;
}

/// Priority values, ordered so a higher number sorts first.
abstract final class Priority {
  static const none = 0;
  static const low = 1;
  static const medium = 2;
  static const high = 3;
}

class Tasks extends Table with SyncColumns {
  TextColumn get id => text()();

  /// [inboxListId] or a [TaskLists] id.
  TextColumn get listId => text()();
  TextColumn get title => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  IntColumn get priority => integer().withDefault(const Constant(0))();

  /// Calendar date in the task's own time zone, `YYYY-MM-DD`. Dates float:
  /// a task due on the 18th stays on the 18th when the device travels.
  TextColumn get dueDate => text().nullable()();

  /// Minutes after midnight; null means all day.
  IntColumn get dueTime => integer().nullable()();
  TextColumn get timeZone => text().nullable()();
  TextColumn get tags => text()
      .withDefault(const Constant('[]'))
      .map(const StringListConverter())();
  IntColumn get status => integer().withDefault(const Constant(0))();
  IntColumn get completedAt => integer().nullable()();

  /// Set when the task is moved to the trash (it can be restored); different
  /// from the sync tombstone [deletedAt], which is permanent.
  IntColumn get trashedAt => integer().nullable()();
  RealColumn get sortOrder => real().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ChecklistItems extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get title => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  RealColumn get sortOrder => real().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local-only settings: the signed-in account, the sync cursor and so on.
/// Never synced.
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List<dynamic>).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

@DriftDatabase(tables: [TaskLists, Tasks, ChecklistItems, KeyValues])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(
        name: 'opentodo',
        native: const DriftNativeOptions(
          databaseDirectory: getApplicationSupportDirectory,
        ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(keyValues);
        },
      );

  Future<String?> getValue(String key) async =>
      (await (select(keyValues)..where((k) => k.key.equals(key))).getSingleOrNull())
          ?.value;

  Future<void> setValue(String key, String? value) async {
    if (value == null) {
      await (delete(keyValues)..where((k) => k.key.equals(key))).go();
    } else {
      await into(keyValues).insertOnConflictUpdate(
          KeyValuesCompanion.insert(key: key, value: value));
    }
  }
}
