import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/dates.dart';
import '../domain/recurrence.dart';
import '../domain/task_defaults.dart';
import '../domain/views.dart';
import 'db.dart';
import 'keys.dart';

/// What finishing one occurrence of a repeating task did, so it can be
/// undone.
class RepeatCompletion {
  const RepeatCompletion({
    required this.before,
    required this.copyId,
    required this.next,
    required this.reopenedItemIds,
  });

  /// The task as it was.
  final Task before;

  /// The finished copy left in 已完成.
  final String copyId;

  /// The task's new date.
  final DateTime next;

  /// Subtasks that were ticked and got reset for the next occurrence.
  final List<String> reopenedItemIds;
}

/// Ids of finished occurrences are derived from the task and the date, so
/// two devices finishing the same occurrence offline end up with one copy.
const _occurrenceNamespace = 'b3e0b216-dc4f-4498-98bb-c1e895f8613a';

/// Every read and write the app makes. Writes stamp `updatedAt` and mark the
/// row dirty so the sync engine knows to push it.
class TaskRepo {
  TaskRepo(this.db, {DateTime Function()? clock, TaskDefaults Function()? defaults})
    : _clock = clock ?? DateTime.now,
      _defaults = defaults ?? (() => TaskDefaults.standard);

  final AppDatabase db;
  final DateTime Function() _clock;

  /// The person's defaults, read when a task needs them.
  final TaskDefaults Function() _defaults;
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

  /// Every subtask that isn't deleted (for search).
  Stream<List<ChecklistItem>> watchAllChecklistItems() =>
      (db.select(db.checklistItems)..where((c) => c.deletedAt.isNull())).watch();

  /// Every list's sections, in order.
  Stream<List<ListSection>> watchSections() =>
      (db.select(db.listSections)
            ..where((s) => s.deletedAt.isNull())
            ..orderBy([
              (s) => OrderingTerm(expression: s.sortOrder),
              (s) => OrderingTerm(expression: s.createdAt),
            ]))
          .watch();

  Stream<List<TaskFilter>> watchFilters() =>
      (db.select(db.taskFilters)
            ..where((f) => f.deletedAt.isNull())
            ..orderBy([
              (f) => OrderingTerm(expression: f.sortOrder),
              (f) => OrderingTerm(expression: f.createdAt),
            ]))
          .watch();

  Future<Task?> getTask(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ---- tasks ----

  Future<String> addTask({
    String? id,
    required String title,
    String listId = inboxListId,
    String? sectionId,
    DateTime? dueDate,
    int? dueTime,
    int? duration,
    List<String> tags = const [],
    int priority = Priority.none,
    List<int> reminders = const [],
    String? repeatRule,
    int repeatFrom = RepeatFrom.dueDate,
  }) async {
    id ??= newId();
    final now = _now;
    final dated = dueDate != null;
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            listId: listId,
            sectionId: Value(sectionId),
            title: title,
            priority: Value(priority),
            dueDate: Value(dueDate == null ? null : dateKey(dueDate)),
            dueTime: Value(dated ? dueTime : null),
            duration: Value(dated ? normalizeDuration(dueTime, duration) : null),
            tags: Value(tags),
            reminders: Value(dated ? reminders : const []),
            repeatRule: Value(dated ? repeatRule : null),
            repeatFrom: Value(dated ? repeatFrom : RepeatFrom.dueDate),
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

  /// Moves the task to another day, keeping its time span, reminders and
  /// repeat; clearing the date clears those too. A task getting its first
  /// date gets the default reminders.
  Future<void> setDue(String id, DateTime? date, int? time) async {
    if (date == null) {
      return updateTask(
        id,
        const TasksCompanion(
          dueDate: Value(null),
          dueTime: Value(null),
          duration: Value(null),
          reminders: Value([]),
          repeatRule: Value(null),
          repeatFrom: Value(RepeatFrom.dueDate),
        ),
      );
    }
    final t = await getTask(id);
    if (t == null) return;
    await updateTask(
      id,
      TasksCompanion(
        dueDate: Value(dateKey(date)),
        dueTime: Value(time),
        reminders: t.dueDate == null
            ? Value(_defaults().remindersFor(allDay: time == null))
            : const Value.absent(),
      ),
    );
  }

  /// Moves the task to start on [date] at [time] (null: all day), as
  /// dragging it on the calendar does; a span moves as a whole. Reminders
  /// count from the due time, so going between timed and all-day starts them
  /// over with the defaults for the new kind (out of the box 准时 for a timed
  /// task, none for an all-day one), as the date dialog does. A span keeps
  /// the days it covered when it loses its time.
  Future<void> moveTo(String id, DateTime date, int? time) async {
    final t = await getTask(id);
    if (t == null) return;
    final key = dateKey(date);
    if (t.dueDate == key && t.dueTime == time) return;
    final wasTimed = t.dueDate != null && t.dueTime != null;
    final reminders = t.dueDate == null || wasTimed != (time != null)
        ? _defaults().remindersFor(allDay: time == null)
        : t.reminders;
    await updateTask(
      id,
      TasksCompanion(
        dueDate: Value(key),
        dueTime: Value(time),
        duration: Value(
          t.dueDate == null ? null : durationForTimeChange(t.dueDate!, t.dueTime, time, t.duration),
        ),
        reminders: Value(reminders),
      ),
    );
  }

  /// [moveTo] for several tasks dragged together on the calendar, in one
  /// transaction.
  Future<void> moveAll(Iterable<({String id, DateTime date, int? time})> moves) => db.transaction(() async {
        for (final m in moves) {
          await moveTo(m.id, m.date, m.time);
        }
      });

  /// Sets how long a task with a date lasts (null: no span), as dragging the
  /// bottom edge of a task on the calendar does.
  Future<void> setDuration(String id, int? duration) async {
    final t = await getTask(id);
    if (t == null || t.dueDate == null) return;
    final d = normalizeDuration(t.dueTime, duration);
    if (d == t.duration) return;
    await updateTask(id, TasksCompanion(duration: Value(d)));
  }

  /// Date, time, span, reminders and repeat together, as the date dialog
  /// sets them.
  Future<void> setSchedule(
    String id, {
    required DateTime? date,
    int? time,
    int? duration,
    List<int> reminders = const [],
    String? repeatRule,
    int repeatFrom = RepeatFrom.dueDate,
  }) {
    if (date == null) return setDue(id, null, null);
    return updateTask(
      id,
      TasksCompanion(
        dueDate: Value(dateKey(date)),
        dueTime: Value(time),
        duration: Value(normalizeDuration(time, duration)),
        reminders: Value(reminders),
        repeatRule: Value(repeatRule),
        repeatFrom: Value(repeatFrom),
      ),
    );
  }

  /// Pins the task to the top of its list (置顶), or unpins it.
  Future<void> setPinned(String id, bool pinned) =>
      updateTask(id, TasksCompanion(pinnedAt: Value(pinned ? _now : null)));

  Future<void> setPriority(String id, int priority) =>
      updateTask(id, TasksCompanion(priority: Value(priority)));

  /// Sections belong to a list, so a task changing list leaves its section.
  Future<void> moveToList(String id, String listId) async {
    final t = await getTask(id);
    if (t == null || t.listId == listId) return;
    await updateTask(id, TasksCompanion(listId: Value(listId), sectionId: const Value(null)));
  }

  /// Drops a task into [sectionId] (null: 未分组) of its list, with the new
  /// order numbers from `planMove` (the moved task's, and its neighbours'
  /// when the section had to be numbered afresh).
  Future<void> placeTask(String id, String? sectionId, Map<String, double> orders) =>
      placeTasks([id], sectionId, orders);

  /// [placeTask] for several tasks dragged together, in one transaction.
  Future<void> placeTasks(List<String> ids, String? sectionId, Map<String, double> orders) =>
      db.transaction(() async {
        final moving = ids.toSet();
        for (final e in orders.entries) {
          await updateTask(
            e.key,
            TasksCompanion(
              sortOrder: Value(e.value),
              sectionId: moving.contains(e.key) ? Value(sectionId) : const Value.absent(),
            ),
          );
        }
        for (final id in ids) {
          if (!orders.containsKey(id)) {
            final t = await getTask(id);
            if (t != null && t.sectionId != sectionId) {
              await updateTask(id, TasksCompanion(sectionId: Value(sectionId)));
            }
          }
        }
      });

  /// Tasks dragged into a group of a view, in one transaction: each takes
  /// on what [target] stands for (a section, a day keeping its time, no
  /// date, a priority, a list, a tag), and [orders] gives the new order
  /// numbers from `planMoveMany` when the view is in manual order.
  Future<void> dropInto(List<String> ids, GroupTarget target, Map<String, double> orders) =>
      db.transaction(() async {
        for (final id in ids) {
          final t = await getTask(id);
          if (t == null || target.has(t)) continue;
          switch (target) {
            case SectionTarget(:final sectionId):
              await updateTask(id, TasksCompanion(sectionId: Value(sectionId)));
            case DateTarget(:final day?):
              await moveTo(id, day, t.dueTime);
            case DateTarget(day: null):
              await setDue(id, null, null);
            case PriorityTarget(:final priority):
              await setPriority(id, priority);
            case ListTarget(:final listId):
              await moveToList(id, listId);
            case TagTarget():
              await setTags(id, target.retag(t.tags));
            case OrderTarget():
              break;
          }
        }
        for (final e in orders.entries) {
          await updateTask(e.key, TasksCompanion(sortOrder: Value(e.value)));
        }
      });

  /// Tasks dragged on the timeline, in one transaction: dated ones move by
  /// [days] (each keeping its time and span), undated ones go on [day] all
  /// day, and all of them into [sectionId] (null: 未分组) of their list.
  Future<void> placeOnTimeline(List<String> ids, {required int days, required DateTime day, String? sectionId}) =>
      db.transaction(() async {
        for (final id in ids) {
          final t = await getTask(id);
          if (t == null) continue;
          if (t.dueDate == null) {
            await moveTo(id, day, null);
          } else if (days != 0) {
            await moveTo(id, addDays(parseDateKey(t.dueDate!), days), t.dueTime);
          }
          if (t.sectionId != sectionId) {
            await updateTask(id, TasksCompanion(sectionId: Value(sectionId)));
          }
        }
      });

  Future<void> setTags(String id, List<String> tags) =>
      updateTask(id, TasksCompanion(tags: Value(tags)));

  /// Ticks a task off or back on. A repeating task isn't closed: it moves
  /// to its next date and a finished copy of this occurrence is left behind
  /// (returned, for undo). The last occurrence of a series closes as usual.
  Future<RepeatCompletion?> setCompleted(String id, bool done) async {
    if (done) {
      final t = await getTask(id);
      if (t != null && t.status == TaskStatus.open) {
        final advance = _advance(t);
        if (advance != null) return _finishOccurrence(t, advance);
      }
    }
    await updateTask(
      id,
      TasksCompanion(
        status: Value(done ? TaskStatus.done : TaskStatus.open),
        completedAt: Value(done ? _now : null),
      ),
    );
    return null;
  }

  RepeatAdvance? _advance(Task t) {
    final rule = RepeatRule.tryParse(t.repeatRule);
    if (rule == null || t.dueDate == null) return null;
    return advanceRepeat(
      rule,
      parseDateKey(t.dueDate!),
      today: _clock(),
      repeatFrom: t.repeatFrom,
    );
  }

  Future<RepeatCompletion> _finishOccurrence(Task t, RepeatAdvance advance) =>
      db.transaction(() async {
        final now = _now;
        String occurrenceId(String of) =>
            _uuid.v5(_occurrenceNamespace, '$of/${t.dueDate}');
        final copyId = occurrenceId(t.id);
        // Upsert: undo leaves a tombstone under the same id. Companions keep
        // nulls (deletedAt) instead of skipping them.
        await db.into(db.tasks).insertOnConflictUpdate(
          t.copyWith(
            id: copyId,
            status: TaskStatus.done,
            completedAt: Value(now),
            reminders: const [],
            repeatRule: const Value(null),
            repeatFrom: RepeatFrom.dueDate,
            createdAt: now,
            updatedAt: now,
            deletedAt: const Value(null),
            trashedAt: const Value(null),
            pinnedAt: const Value(null),
            serverVersion: 0,
            dirty: true,
          ).toCompanion(false),
        );
        final items = await (db.select(
          db.checklistItems,
        )..where((c) => c.taskId.equals(t.id) & c.deletedAt.isNull())).get();
        for (final item in items) {
          await db.into(db.checklistItems).insertOnConflictUpdate(
            item.copyWith(
              id: occurrenceId(item.id),
              taskId: copyId,
              createdAt: now,
              updatedAt: now,
              deletedAt: const Value(null),
              serverVersion: 0,
              dirty: true,
            ).toCompanion(false),
          );
        }
        final reopened = [for (final i in items) if (i.done) i.id];
        await _setChecklistDone(reopened, false);
        await updateTask(
          t.id,
          TasksCompanion(
            dueDate: Value(dateKey(advance.date)),
            repeatRule: Value(advance.rule.toString()),
          ),
        );
        return RepeatCompletion(
          before: t,
          copyId: copyId,
          next: advance.date,
          reopenedItemIds: reopened,
        );
      });

  /// Puts a repeating task back the way it was before [c].
  Future<void> undoRepeatCompletion(RepeatCompletion c) => db.transaction(() async {
    await updateTask(
      c.before.id,
      TasksCompanion(
        dueDate: Value(c.before.dueDate),
        repeatRule: Value(c.before.repeatRule),
      ),
    );
    await _setChecklistDone(c.reopenedItemIds, true);
    await updateTask(c.copyId, TasksCompanion(deletedAt: Value(_now)));
    await _tombstoneChecklists([c.copyId]);
  });

  /// Skips this occurrence of a repeating task: it moves to the next date
  /// without a finished copy. Skipping the last one gives the task up.
  /// Returns the new date, or null if the series is over.
  Future<DateTime?> skipOccurrence(String id) async {
    final t = await getTask(id);
    if (t == null) return null;
    final advance = _advance(t);
    if (advance == null) {
      await updateTask(
        id,
        TasksCompanion(status: const Value(TaskStatus.wontDo), completedAt: Value(_now)),
      );
      return null;
    }
    await db.transaction(() async {
      final items = await (db.select(db.checklistItems)
            ..where((c) => c.taskId.equals(id) & c.deletedAt.isNull() & c.done.equals(true)))
          .map((c) => c.id)
          .get();
      await _setChecklistDone(items, false);
      await updateTask(
        id,
        TasksCompanion(
          dueDate: Value(dateKey(advance.date)),
          repeatRule: Value(advance.rule.toString()),
        ),
      );
    });
    return advance.date;
  }

  Future<void> _setChecklistDone(List<String> ids, bool done) async {
    if (ids.isEmpty) return;
    await (db.update(db.checklistItems)..where((c) => c.id.isIn(ids))).write(
      ChecklistItemsCompanion(
        done: Value(done),
        updatedAt: Value(_now),
        dirty: const Value(true),
      ),
    );
  }

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

  /// Deletes the list and its sections, and moves its tasks to the trash.
  Future<void> deleteList(String id) => db.transaction(() async {
    final now = _now;
    await (db.update(db.listSections)..where((s) => s.listId.equals(id) & s.deletedAt.isNull()))
        .write(ListSectionsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(true),
    ));
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
        sectionId: const Value(null),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  });

  // ---- sections ----

  /// Adds a section at the end of [listId]'s.
  Future<String> addSection(String listId, String name, {String? id}) async {
    id ??= newId();
    final now = _now;
    final last = await (db.select(db.listSections)
          ..where((s) => s.listId.equals(listId) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm(expression: s.sortOrder, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    await db.into(db.listSections).insert(ListSectionsCompanion.insert(
          id: id,
          listId: listId,
          name: name,
          sortOrder: Value(last == null ? 0 : last.sortOrder + 1024),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  Future<void> updateSection(String id, {String? name, double? sortOrder}) =>
      (db.update(db.listSections)..where((s) => s.id.equals(id))).write(
        ListSectionsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
          updatedAt: Value(_now),
          dirty: const Value(true),
        ),
      );

  /// Deletes the section; its tasks stay in the list, under 未分组.
  Future<void> deleteSection(String id) => db.transaction(() async {
    final now = _now;
    await (db.update(db.listSections)..where((s) => s.id.equals(id))).write(
      ListSectionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    await (db.update(db.tasks)..where((t) => t.sectionId.equals(id))).write(
      TasksCompanion(
        sectionId: const Value(null),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  });

  // ---- filters ----

  /// [rule] is the JSON from `FilterRule.encode`.
  Future<String> addFilter(String name, String rule, {String? id}) async {
    id ??= newId();
    final now = _now;
    await db.into(db.taskFilters).insert(TaskFiltersCompanion.insert(
          id: id,
          name: name,
          rule: Value(rule),
          sortOrder: Value(now.toDouble()),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  Future<void> updateFilter(String id, {String? name, String? rule}) =>
      (db.update(db.taskFilters)..where((f) => f.id.equals(id))).write(
        TaskFiltersCompanion(
          name: name == null ? const Value.absent() : Value(name),
          rule: rule == null ? const Value.absent() : Value(rule),
          updatedAt: Value(_now),
          dirty: const Value(true),
        ),
      );

  /// Deletes the filter; its tasks stay where they are.
  Future<void> deleteFilter(String id) {
    final now = _now;
    return (db.update(db.taskFilters)..where((f) => f.id.equals(id))).write(
      TaskFiltersCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }

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
