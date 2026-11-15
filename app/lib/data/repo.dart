import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/dates.dart';
import 'db.dart';
import 'keys.dart';

/// Every read and write the app makes. Writes stamp `updatedAt` and mark the
/// row dirty so the sync engine knows to push it.
class TaskRepo {
  TaskRepo(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  int get _now => _clock().millisecondsSinceEpoch;
  String newId() => _uuid.v7();

  // ---- reads ----

  Stream<List<TaskList>> watchLists() =>
      (db.select(db.taskLists)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.createdAt),
            ]))
          .watch();

  /// All tasks that aren't permanently deleted, the trash included.
  Stream<List<Task>> watchTasks() =>
      (db.select(db.tasks)..where((t) => t.deletedAt.isNull())).watch();

  Stream<List<ChecklistItem>> watchChecklist(String taskId) =>
      (db.select(db.checklistItems)
            ..where((c) => c.taskId.equals(taskId) & c.deletedAt.isNull())
            ..orderBy([
              (c) => OrderingTerm(expression: c.sortOrder),
              (c) => OrderingTerm(expression: c.createdAt),
            ]))
          .watch();

  Future<Task?> getTask(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ---- tasks ----

  Future<String> addTask({
    String? id,
    required String title,
    String listId = inboxListId,
    DateTime? dueDate,
    int? dueTime,
    List<String> tags = const [],
    int priority = Priority.none,
  }) async {
    id ??= newId();
    final now = _now;
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            listId: listId,
            title: title,
            priority: Value(priority),
            dueDate: Value(dueDate == null ? null : dateKey(dueDate)),
            dueTime: Value(dueDate == null ? null : dueTime),
            tags: Value(tags),
            sortOrder: Value(-now.toDouble()),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateTask(String id, TasksCompanion patch) =>
      (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        patch.copyWith(updatedAt: Value(_now), dirty: const Value(true)),
      );

  Future<void> setTitle(String id, String title) =>
      updateTask(id, TasksCompanion(title: Value(title)));

  Future<void> setContent(String id, String content) =>
      updateTask(id, TasksCompanion(content: Value(content)));

  Future<void> setDue(String id, DateTime? date, int? time) => updateTask(
    id,
    TasksCompanion(
      dueDate: Value(date == null ? null : dateKey(date)),
      dueTime: Value(date == null ? null : time),
    ),
  );

  Future<void> setPriority(String id, int priority) =>
      updateTask(id, TasksCompanion(priority: Value(priority)));

  Future<void> moveToList(String id, String listId) =>
      updateTask(id, TasksCompanion(listId: Value(listId)));

  Future<void> setTags(String id, List<String> tags) =>
      updateTask(id, TasksCompanion(tags: Value(tags)));

  Future<void> setCompleted(String id, bool done) => updateTask(
    id,
    TasksCompanion(
      status: Value(done ? TaskStatus.done : TaskStatus.open),
      completedAt: Value(done ? _now : null),
    ),
  );

  Future<void> trashTask(String id) =>
      updateTask(id, TasksCompanion(trashedAt: Value(_now)));

  Future<void> restoreTask(String id) =>
      updateTask(id, const TasksCompanion(trashedAt: Value(null)));

  /// Permanent delete: leaves tombstones (the task's and its checklist's) for
  /// sync.
  Future<void> purgeTask(String id) => db.transaction(() async {
    await updateTask(id, TasksCompanion(deletedAt: Value(_now)));
    await _tombstoneChecklists([id]);
  });

  Future<void> emptyTrash() => db.transaction(() async {
    final now = _now;
    final trashed =
        await (db.select(db.tasks)
              ..where((t) => t.trashedAt.isNotNull() & t.deletedAt.isNull()))
            .map((t) => t.id)
            .get();
    await (db.update(db.tasks)..where((t) => t.id.isIn(trashed))).write(
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    await _tombstoneChecklists(trashed);
  });

  Future<void> _tombstoneChecklists(List<String> taskIds) {
    final now = _now;
    return (db.update(
      db.checklistItems,
    )..where((c) => c.taskId.isIn(taskIds) & c.deletedAt.isNull())).write(
      ChecklistItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }

  // ---- lists ----

  Future<String> addList(String name, {String? emoji, String? id}) async {
    id ??= newId();
    final now = _now;
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: id,
            name: name,
            emoji: Value(emoji),
            sortOrder: Value(now.toDouble()),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateList(String id, {String? name, String? emoji}) =>
      (db.update(db.taskLists)..where((t) => t.id.equals(id))).write(
        TaskListsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          emoji: emoji == null ? const Value.absent() : Value(emoji),
          updatedAt: Value(_now),
          dirty: const Value(true),
        ),
      );

  /// Deletes the list and moves its tasks to the trash.
  Future<void> deleteList(String id) => db.transaction(() async {
    final now = _now;
    await (db.update(db.taskLists)..where((t) => t.id.equals(id))).write(
      TaskListsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    await (db.update(
      db.tasks,
    )..where((t) => t.listId.equals(id) & t.trashedAt.isNull())).write(
      TasksCompanion(
        trashedAt: Value(now),
        listId: const Value(inboxListId),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  });

  // ---- checklist ----

  Future<String> addChecklistItem(String taskId, String title) async {
    final id = newId();
    final now = _now;
    await db
        .into(db.checklistItems)
        .insert(
          ChecklistItemsCompanion.insert(
            id: id,
            taskId: taskId,
            title: title,
            sortOrder: Value(now.toDouble()),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateChecklistItem(String id, {String? title, bool? done}) =>
      (db.update(db.checklistItems)..where((c) => c.id.equals(id))).write(
        ChecklistItemsCompanion(
          title: title == null ? const Value.absent() : Value(title),
          done: done == null ? const Value.absent() : Value(done),
          updatedAt: Value(_now),
          dirty: const Value(true),
        ),
      );

  Future<void> deleteChecklistItem(String id) =>
      (db.update(db.checklistItems)..where((c) => c.id.equals(id))).write(
        ChecklistItemsCompanion(
          deletedAt: Value(_now),
          updatedAt: Value(_now),
          dirty: const Value(true),
        ),
      );

  // ---- first run ----

  /// A short welcome list on a fresh install, so the app isn't empty.
  Future<void> seedIfEmpty() async {
    final count = await db.tasks.count().getSingle();
    final lists = await db.taskLists.count().getSingle();
    if (count > 0 || lists > 0) return;
    // A signed-in device gets its data from the account instead.
    if (await db.getValue(Keys.token) != null) return;
    final today = dateOnly(_clock());
    // Fixed ids: every install creates the same welcome items, so devices
    // that keep them merge into one copy instead of adding their own.
    final welcome = await addList('欢迎', emoji: '👋', id: 'seed-welcome');
    final ids = [
      welcome,
      await addTask(
        id: 'seed-welcome-1',
        title: '在上方输入框里试试“明天下午3点开会 #工作”',
        listId: welcome,
        priority: Priority.high,
      ),
      await addTask(
        id: 'seed-welcome-2',
        title: '点开任务可以写备注、加子任务',
        listId: welcome,
      ),
      await addTask(
        id: 'seed-welcome-3',
        title: '右键（手机上长按）任务可以改日期、优先级、清单',
        listId: welcome,
      ),
      await addTask(id: 'seed-today', title: '看看“今天”和“最近7天”', dueDate: today),
    ];
    await db.setValue(Keys.seedIds, jsonEncode(ids));
  }
}
