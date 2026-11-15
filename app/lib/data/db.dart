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

  /// For a task that spans a while (时间段), minutes from its start (the
  /// due date and time above) to its end, which is exclusive. An all-day
  /// span is whole days: 2880 covers the due date and the day after. Null
  /// for a task at one moment or on one day; see `domain/dates.dart`.
  IntColumn get duration => integer().nullable()();
  TextColumn get timeZone => text().nullable()();
  TextColumn get tags => text()
      .withDefault(const Constant('[]'))
      .map(const StringListConverter())();
  IntColumn get status => integer().withDefault(const Constant(0))();
  IntColumn get completedAt => integer().nullable()();

  /// Minutes relative to the due moment, negative = before; see
  /// `domain/reminders.dart`.
  TextColumn get reminders => text()
      .withDefault(const Constant('[]'))
      .map(const IntListConverter())();

  /// RRULE text (`domain/recurrence.dart`); null for a one-off task.
  TextColumn get repeatRule => text().nullable()();

  /// A `RepeatFrom` value: count the next date from the due date or from
  /// the day it was completed.
  IntColumn get repeatFrom => integer().withDefault(const Constant(0))();

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

class IntListConverter extends TypeConverter<List<int>, String> {
  const IntListConverter();

  @override
  List<int> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List<dynamic>).map((e) => (e as num).toInt()).toList();

  @override
  String toSql(List<int> value) => jsonEncode(value);
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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // A button on a reminder may be handled in a background isolate with
        // its own connection while the app has one open: wait for the other
        // to finish writing instead of failing.
        beforeOpen: (_) => customStatement('PRAGMA busy_timeout = 5000'),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(keyValues);
          if (from < 3) {
            // Reminders and repeat (M4).
            await m.addColumn(tasks, tasks.reminders);
            await m.addColumn(tasks, tasks.repeatRule);
            await m.addColumn(tasks, tasks.repeatFrom);
          }
          // Time spans.
          if (from < 4) await m.addColumn(tasks, tasks.duration);
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
