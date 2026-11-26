// The snapshot (`observeTaskData`) reads tasks and subtasks by column
// position for speed; what it reads must be exactly what the records'
// `init(row:)` reads by name, odd rows included.

import Foundation
import GRDB
import OpenTodoDomain
import Testing
@testable import OpenTodoData

@Suite("snapshot decoding")
struct SnapshotDecodeTests {
    @Test("by position is the same as by name")
    func samePositionalAndNamed() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { d in
            try TodoTask(id: "full", listId: "l", sectionId: "s", title: "全的", content: "备注", priority: .high,
                         dueDate: Day(2026, 11, 26), dueTime: 540, duration: 90, timeZone: "Asia/Shanghai",
                         tags: ["工作", "会议"], status: .done, completedAt: 5, reminders: [0, -15],
                         repeatRule: "FREQ=DAILY", repeatFrom: .completion, pinnedAt: 6, trashedAt: 7,
                         sortOrder: 1.5, createdAt: 1, updatedAt: 2, deletedAt: nil, serverVersion: 3, dirty: true).insert(d)
            try TodoTask(id: "bare").insert(d)
            try TodoTask(id: "gone", deletedAt: 9).insert(d)
            // Rows another version (or a damaged file) could have.
            try d.execute(sql: """
                INSERT INTO tasks (id, list_id, title, content, priority, tags, status, reminders, repeat_from,
                                   sort_order, created_at, updated_at, server_version, dirty, due_date)
                VALUES ('odd', 'inbox', '奇怪', '', 7, 'not json', 9, '[1.5, "x", 2]', 5, 0, 0, 0, 0, 0, '2026-13-40')
                """)
            try d.execute(sql: """
                INSERT INTO tasks (id, list_id, title, content, priority, tags, status, reminders, repeat_from,
                                   sort_order, created_at, updated_at, server_version, dirty)
                VALUES ('mixed', 'inbox', '混', '', -1, '["a", 1, "b"]', 1, '[]', 1, 0, 0, 0, 0, 1)
                """)
            try ChecklistItem(id: "c1", taskId: "full", title: "一", done: true, sortOrder: 2, createdAt: 1).insert(d)
            try ChecklistItem(id: "c2", taskId: "full", title: "二", sortOrder: 1, createdAt: 2, dirty: false).insert(d)
            try ChecklistItem(id: "c3", taskId: "bare", title: "删了", deletedAt: 4).insert(d)
        }
        let snapshot = try await db.observeTaskData().first()
        let (tasks, items) = try await db.writer.read { d in
            (try TodoTask.fetchAll(d, sql: "SELECT * FROM tasks WHERE deleted_at IS NULL"),
             try ChecklistItem.fetchAll(d, sql: "SELECT * FROM checklist_items WHERE deleted_at IS NULL ORDER BY sort_order, created_at"))
        }
        #expect(snapshot.tasks.sorted { $0.id < $1.id } == tasks.sorted { $0.id < $1.id })
        #expect(snapshot.checklistItems == items)
        #expect(snapshot.tasks.count == 4)
        let odd = try #require(snapshot.tasks.first { $0.id == "odd" })
        #expect(odd.tags == [] && odd.reminders == [1, 2] && odd.status == .open && odd.priority == .high && odd.dueDate == nil)
        #expect(snapshot.tasks.first { $0.id == "mixed" }?.tags == ["a", "b"])
    }
}
