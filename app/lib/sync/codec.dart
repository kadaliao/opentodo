/// Turns local rows into the records the sync server stores, and back.
///
/// The wire format is spelled out field by field instead of relying on
/// drift's toJson, so it stays stable when columns are renamed and old
/// clients can read records written by newer ones (unknown fields are
/// ignored, missing ones fall back to defaults).
library;

import 'package:drift/drift.dart';

import '../data/db.dart';

abstract final class Entity {
  static const list = 'list';
  static const task = 'task';
  static const checklist = 'checklist';
}

/// One record as it travels to and from the server.
class WireRecord {
  const WireRecord({
    required this.entity,
    required this.id,
    required this.updatedAt,
    required this.deletedAt,
    required this.data,
    this.version = 0,
  });

  factory WireRecord.fromJson(Map<String, dynamic> j) => WireRecord(
        entity: j['entity'] as String,
        id: j['id'] as String,
        updatedAt: (j['updatedAt'] as num).toInt(),
        deletedAt: (j['deletedAt'] as num?)?.toInt(),
        data: (j['data'] as Map).cast<String, dynamic>(),
        version: (j['version'] as num?)?.toInt() ?? 0,
      );

  final String entity;
  final String id;
  final int updatedAt;
  final int? deletedAt;
  final Map<String, dynamic> data;
  final int version;

  Map<String, dynamic> toJson() => {
        'entity': entity,
        'id': id,
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
        'data': data,
      };
}

WireRecord listToWire(TaskList l) => WireRecord(
      entity: Entity.list,
      id: l.id,
      updatedAt: l.updatedAt,
      deletedAt: l.deletedAt,
      data: {
        'name': l.name,
        'emoji': l.emoji,
        'color': l.color,
        'sortOrder': l.sortOrder,
        'createdAt': l.createdAt,
      },
    );

WireRecord taskToWire(Task t) => WireRecord(
      entity: Entity.task,
      id: t.id,
      updatedAt: t.updatedAt,
      deletedAt: t.deletedAt,
      data: {
        'listId': t.listId,
        'title': t.title,
        'content': t.content,
        'priority': t.priority,
        'dueDate': t.dueDate,
        'dueTime': t.dueTime,
        'timeZone': t.timeZone,
        'tags': t.tags,
        'status': t.status,
        'completedAt': t.completedAt,
        'trashedAt': t.trashedAt,
        'sortOrder': t.sortOrder,
        'createdAt': t.createdAt,
      },
    );

WireRecord checklistToWire(ChecklistItem c) => WireRecord(
      entity: Entity.checklist,
      id: c.id,
      updatedAt: c.updatedAt,
      deletedAt: c.deletedAt,
      data: {
        'taskId': c.taskId,
        'title': c.title,
        'done': c.done,
        'sortOrder': c.sortOrder,
        'createdAt': c.createdAt,
      },
    );

int? _int(Object? v) => (v as num?)?.toInt();
double _double(Object? v, [double fallback = 0]) => (v as num?)?.toDouble() ?? fallback;

/// The fields every row gets when it arrives from the server: it is now in
/// step with the server, so it isn't dirty.
({Value<int> updatedAt, Value<int?> deletedAt, Value<int> serverVersion, Value<bool> dirty})
    _syncFields(WireRecord r) => (
          updatedAt: Value(r.updatedAt),
          deletedAt: Value(r.deletedAt),
          serverVersion: Value(r.version),
          dirty: const Value(false),
        );

TaskListsCompanion wireToList(WireRecord r) {
  final d = r.data, s = _syncFields(r);
  return TaskListsCompanion(
    id: Value(r.id),
    name: Value(d['name'] as String? ?? ''),
    emoji: Value(d['emoji'] as String?),
    color: Value(_int(d['color'])),
    sortOrder: Value(_double(d['sortOrder'])),
    createdAt: Value(_int(d['createdAt']) ?? r.updatedAt),
    updatedAt: s.updatedAt,
    deletedAt: s.deletedAt,
    serverVersion: s.serverVersion,
    dirty: s.dirty,
  );
}

TasksCompanion wireToTask(WireRecord r) {
  final d = r.data, s = _syncFields(r);
  return TasksCompanion(
    id: Value(r.id),
    listId: Value(d['listId'] as String? ?? inboxListId),
    title: Value(d['title'] as String? ?? ''),
    content: Value(d['content'] as String? ?? ''),
    priority: Value(_int(d['priority']) ?? Priority.none),
    dueDate: Value(d['dueDate'] as String?),
    dueTime: Value(_int(d['dueTime'])),
    timeZone: Value(d['timeZone'] as String?),
    tags: Value((d['tags'] as List?)?.cast<String>() ?? const []),
    status: Value(_int(d['status']) ?? TaskStatus.open),
    completedAt: Value(_int(d['completedAt'])),
    trashedAt: Value(_int(d['trashedAt'])),
    sortOrder: Value(_double(d['sortOrder'])),
    createdAt: Value(_int(d['createdAt']) ?? r.updatedAt),
    updatedAt: s.updatedAt,
    deletedAt: s.deletedAt,
    serverVersion: s.serverVersion,
    dirty: s.dirty,
  );
}

ChecklistItemsCompanion wireToChecklist(WireRecord r) {
  final d = r.data, s = _syncFields(r);
  return ChecklistItemsCompanion(
    id: Value(r.id),
    taskId: Value(d['taskId'] as String? ?? ''),
    title: Value(d['title'] as String? ?? ''),
    done: Value(d['done'] as bool? ?? false),
    sortOrder: Value(_double(d['sortOrder'])),
    createdAt: Value(_int(d['createdAt']) ?? r.updatedAt),
    updatedAt: s.updatedAt,
    deletedAt: s.deletedAt,
    serverVersion: s.serverVersion,
    dirty: s.dirty,
  );
}
