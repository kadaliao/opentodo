// Port of app/test/migration_test.dart, plus: databases made by each older
// Flutter version (1–6) upgrade to the same tables a new one has, a version-7
// database is used as it is, and the Flutter database is backed up the first
// time the Swift version opens it.

import Foundation
import GRDB
import Testing
@testable import OpenTodoData

// MARK: - Fixtures

/// A temporary folder, removed when the value goes.
final class TempDir: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("opentodo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String = "opentodo.sqlite") -> URL { url.appendingPathComponent(name) }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// The tables a fresh install of Flutter version `version` created, in
/// drift's SQL (from `git show <commit>:app/lib/data/db.dart` of each
/// release; v1 is v2 without `key_values`).
func driftSchema(version: Int) -> [String] {
    let sync = #""created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1))"#
    var task: [String] = [#""id" TEXT NOT NULL"#, #""list_id" TEXT NOT NULL"#]
    if version >= 6 { task.append(#""section_id" TEXT NULL"#) }
    task += [#""title" TEXT NOT NULL"#, #""content" TEXT NOT NULL DEFAULT ''"#, #""priority" INTEGER NOT NULL DEFAULT 0"#,
             #""due_date" TEXT NULL"#, #""due_time" INTEGER NULL"#]
    if version >= 4 { task.append(#""duration" INTEGER NULL"#) }
    task += [#""time_zone" TEXT NULL"#, #""tags" TEXT NOT NULL DEFAULT '[]'"#, #""status" INTEGER NOT NULL DEFAULT 0"#,
             #""completed_at" INTEGER NULL"#]
    if version >= 3 {
        task += [#""reminders" TEXT NOT NULL DEFAULT '[]'"#, #""repeat_rule" TEXT NULL"#, #""repeat_from" INTEGER NOT NULL DEFAULT 0"#]
    }
    if version >= 7 { task.append(#""pinned_at" INTEGER NULL"#) }
    task += [#""trashed_at" INTEGER NULL"#, #""sort_order" REAL NOT NULL DEFAULT 0.0"#]

    func table(_ name: String, _ columns: [String]) -> String {
        #"CREATE TABLE IF NOT EXISTS "\#(name)" (\#(sync), \#(columns.joined(separator: ", ")), PRIMARY KEY ("id"));"#
    }
    var sql = [
        table("task_lists", [#""id" TEXT NOT NULL"#, #""name" TEXT NOT NULL"#, #""emoji" TEXT NULL"#, #""color" INTEGER NULL"#,
                             #""sort_order" REAL NOT NULL DEFAULT 0.0"#]),
        table("tasks", task),
        table("checklist_items", [#""id" TEXT NOT NULL"#, #""task_id" TEXT NOT NULL"#, #""title" TEXT NOT NULL"#,
                                  #""done" INTEGER NOT NULL DEFAULT 0 CHECK ("done" IN (0, 1))"#, #""sort_order" REAL NOT NULL DEFAULT 0.0"#]),
    ]
    if version >= 5 {
        sql.append(table("task_filters", [#""id" TEXT NOT NULL"#, #""name" TEXT NOT NULL"#, #""rule" TEXT NOT NULL DEFAULT '{}'"#,
                                          #""sort_order" REAL NOT NULL DEFAULT 0.0"#]))
    }
    if version >= 6 {
        sql.append(table("list_sections", [#""id" TEXT NOT NULL"#, #""list_id" TEXT NOT NULL"#, #""name" TEXT NOT NULL"#,
                                           #""sort_order" REAL NOT NULL DEFAULT 0.0"#]))
    }
    if version >= 2 {
        sql.append(#"CREATE TABLE IF NOT EXISTS "key_values" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"));"#)
    }
    return sql
}

/// A database file as a fresh install of Flutter version `version` would
/// have left it, with a list, a task, a subtask and (from v2) a cursor and
/// an email in it.
func flutterDatabase(version: Int, at url: URL) throws {
    let q = try DatabaseQueue(path: url.path)
    try q.write { db in
        for sql in driftSchema(version: version) { try db.execute(sql: sql) }
        try db.execute(sql: "INSERT INTO task_lists (id, name, created_at, updated_at) VALUES ('work', '工作', 1, 1)")
        try db.execute(sql: "INSERT INTO tasks (id, list_id, title, tags, created_at, updated_at) VALUES ('t', 'work', '旧任务', '[\"家\"]', 1, 1)")
        try db.execute(sql: "INSERT INTO checklist_items (id, task_id, title, done, created_at, updated_at, dirty) VALUES ('c', 't', '子任务', 1, 1, 2, 0)")
        if version >= 2 {
            try db.execute(sql: "INSERT INTO key_values VALUES ('sync.cursor', '42'), ('account.email', 'a@example.com')")
        }
        try db.execute(sql: "PRAGMA user_version = \(version)")
    }
    try q.close()
}

/// Each table's columns: name, type, not null, default, primary key.
func columns(_ db: Database) throws -> [String: Set<String>] {
    var out: [String: Set<String>] = [:]
    for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
        out[table] = Set(rows.map { r in
            "\(r["name"] as String) \(r["type"] as String) \(r["notnull"] as Int) \(r["dflt_value"] as String? ?? "-") \(r["pk"] as Int)"
        })
    }
    return out
}

/// Every row of every table, and the SQL of the tables.
func snapshot(_ db: Database) throws -> [String: [[DatabaseValue]]] {
    var out: [String: [[DatabaseValue]]] = [:]
    for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") {
        out[table] = try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY rowid").map { Array($0.databaseValues) }
    }
    out["sqlite_master"] = try Row.fetchAll(db, sql: "SELECT type, name, sql FROM sqlite_master ORDER BY name").map { Array($0.databaseValues) }
    return out
}

func raw<T>(_ url: URL, _ body: (Database) throws -> T) throws -> T {
    let q = try DatabaseQueue(path: url.path)
    defer { try? q.close() }
    return try q.read(body)
}

// MARK: - Ported from migration_test.dart

@Suite struct MigrationTests {
    /// `olderDatabase`: today's schema with the later tables and columns
    /// taken out again.
    func olderDatabase(_ version: Int, in dir: TempDir) async throws -> URL {
        let url = dir.file()
        let db = try AppDatabase.open(at: url)
        try await db.setValue(Keys.cursor, "42")
        try await db.setValue(Keys.email, "a@example.com")
        try await db.writer.write { db in
            try db.execute(sql: "INSERT INTO tasks (id, list_id, title, created_at, updated_at) VALUES ('t', 'inbox', '旧任务', 1, 1)")
            try db.execute(sql: "ALTER TABLE tasks DROP COLUMN pinned_at")
            if version < 6 {
                try db.execute(sql: "DROP TABLE list_sections")
                try db.execute(sql: "ALTER TABLE tasks DROP COLUMN section_id")
            }
            if version < 5 { try db.execute(sql: "DROP TABLE task_filters") }
            try db.execute(sql: "PRAGMA user_version = \(version)")
        }
        try db.close()
        return url
    }

    @Test("v → v7 adds what is new", arguments: [4, 5, 6])
    func addsWhatIsNew(version: Int) async throws {
        let dir = try TempDir()
        let db = try AppDatabase.open(at: try await olderDatabase(version, in: dir))
        defer { try? db.close() }
        #expect(try await db.observeFilters().first().isEmpty)
        #expect(try await db.observeSections().first().isEmpty)
        let task = try #require(try await db.observeTasks().first().first)
        #expect(task.title == "旧任务")
        #expect(task.sectionId == nil)
        #expect(task.pinnedAt == nil)
        // New kinds of records (filters, sections) mean pulling everything
        // again; a new column alone doesn't. (Dart: "42" for 6. Here the
        // upgrade goes on to 8, which adds the efficiency records, so every
        // version pulls again; `upToSeven` checks the Dart behaviour.)
        #expect(try await db.getValue(Keys.cursor) == "0")
        #expect(try await db.getValue(Keys.email) == "a@example.com")
    }

    @Test("up to 7, the steps reset the cursor only for new kinds of records, as db.dart's onUpgrade", arguments: [4, 5, 6])
    func upToSeven(version: Int) async throws {
        let q = try DatabaseQueue()
        try await q.write { db in
            for sql in driftSchema(version: version) { try db.execute(sql: sql) }
            try db.execute(sql: "INSERT INTO key_values VALUES ('sync.cursor', '42')")
            for step in (version + 1) ... 7 { try Schema.migrations[step]?(db) }
        }
        #expect(try await q.read { try String.fetchOne($0, sql: "SELECT value FROM key_values") } == (version < 6 ? "0" : "42"))
    }

    // MARK: Swift version only

    @Test("a new database has drift's tables and the efficiency ones, at version 8")
    func newDatabase() async throws {
        let db = try AppDatabase.inMemory()
        let (version, sql) = try await db.writer.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version"),
             try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'tasks'"))
        }
        #expect(version == 8)
        // As `sqlite3 opentodo.sqlite .schema` prints it for a database the
        // Flutter version created.
        #expect(sql == #"CREATE TABLE "tasks" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "list_id" TEXT NOT NULL, "section_id" TEXT NULL, "title" TEXT NOT NULL, "content" TEXT NOT NULL DEFAULT '', "priority" INTEGER NOT NULL DEFAULT 0, "due_date" TEXT NULL, "due_time" INTEGER NULL, "duration" INTEGER NULL, "time_zone" TEXT NULL, "tags" TEXT NOT NULL DEFAULT '[]', "status" INTEGER NOT NULL DEFAULT 0, "completed_at" INTEGER NULL, "reminders" TEXT NOT NULL DEFAULT '[]', "repeat_rule" TEXT NULL, "repeat_from" INTEGER NOT NULL DEFAULT 0, "pinned_at" INTEGER NULL, "trashed_at" INTEGER NULL, "sort_order" REAL NOT NULL DEFAULT 0.0, PRIMARY KEY ("id"))"#)
        let fresh = try DatabaseQueue()
        try await fresh.write { db in for s in driftSchema(version: 7) { try db.execute(sql: s) } }
        let drift = try await fresh.read(columns)
        let ours = try await db.writer.read(columns)
        #expect(ours.filter { drift[$0.key] != nil } == drift)
        #expect(Set(ours.keys).subtracting(drift.keys) == ["habits", "habit_checkins", "focus_sessions", "countdowns"])
        #expect(ours["habit_checkins"] == [
            "created_at INTEGER 1 - 0", "updated_at INTEGER 1 - 0", "deleted_at INTEGER 0 - 0", "server_version INTEGER 1 0 0",
            "dirty INTEGER 1 1 0", "id TEXT 1 - 1", "habit_id TEXT 1 - 0", "day TEXT 1 - 0", "value REAL 1 0.0 0", "status INTEGER 1 0 0",
        ])
    }

    @Test("a database from Flutter version 1–6 upgrades to the same tables", arguments: 1 ... 6)
    func upgradesFromFlutter(version: Int) async throws {
        let dir = try TempDir()
        let url = dir.file()
        try flutterDatabase(version: version, at: url)
        let db = try AppDatabase.open(at: url)
        defer { try? db.close() }

        let fresh = try AppDatabase.inMemory()
        #expect(try await db.writer.read(columns) == fresh.writer.read(columns))
        #expect(try await db.writer.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 8)

        let task = try #require(try await db.observeTasks().first().first)
        #expect(task.title == "旧任务")
        #expect(task.listId == "work")
        #expect(task.tags == ["家"])
        #expect(task.reminders == [])
        #expect(task.repeatRule == nil)
        #expect(task.repeatFrom == .dueDate)
        #expect(task.duration == nil)
        #expect(task.sectionId == nil)
        #expect(task.pinnedAt == nil)
        let item = try #require(try await db.observeChecklist(taskId: "t").first().first)
        #expect(item.done && !item.dirty && item.updatedAt == 2)
        #expect(try await db.observeLists().first().map(\.name) == ["工作"])
        #expect(try await db.observeFilters().first().isEmpty)
        #expect(try await db.observeSections().first().isEmpty)
        if version >= 2 {
            // New kinds of records since (efficiency in 8, sections in 6, filters in 5): pull again.
            #expect(try await db.getValue(Keys.cursor) == "0")
            #expect(try await db.getValue(Keys.email) == "a@example.com")
        }
        // It can be written like a new one.
        try await db.writer.write { db in
            try TodoTask(id: "n", title: "新的", reminders: [5], pinnedAt: 3, createdAt: 1, updatedAt: 1).insert(db)
            try ListSection(id: "s", name: "进行中").insert(db)
            try TaskFilter(id: "f", name: "重要").insert(db)
        }
        #expect(try await db.observeTasks().first().count == 2)
        // The copy left beside it is the old version, untouched.
        let backup = AppDatabase.backupURL(for: url)
        #expect(try raw(backup) { try Int.fetchOne($0, sql: "PRAGMA user_version") } == version)
        #expect(try raw(backup) { try String.fetchAll($0, sql: "SELECT title FROM tasks") } == ["旧任务"])
    }

    @Test("7 → 8: the data stays as it was, the efficiency tables come, the cursor goes back to 0")
    func sevenToEight() async throws {
        let dir = try TempDir()
        let url = dir.file()
        try flutterDatabase(version: 7, at: url)
        try await DatabaseQueue(path: url.path).write { db in
            try db.execute(sql: "INSERT INTO task_filters (id, name, rule, created_at, updated_at) VALUES ('f', '重要', '{\"match\":\"all\"}', 3, 4)")
            try db.execute(sql: "INSERT INTO list_sections (id, list_id, name, created_at, updated_at, dirty) VALUES ('s', 'work', '进行中', 5, 6, 0)")
            try db.execute(sql: "INSERT INTO key_values VALUES ('settings', '{\"weekStart\":1}')")
        }
        let before = try raw(url, snapshot)

        let db = try AppDatabase.open(at: url)
        #expect(try await db.observeTasks().first().map(\.title) == ["旧任务"])
        #expect(try await db.observeHabits().first().isEmpty)
        try await db.writer.write { db in
            try Habit(id: "h", name: "喝水", startDate: Day(2026, 11, 1)).insert(db)
            try HabitCheckin(habitId: "h", day: Day(2026, 11, 2), value: 1, status: .done).insert(db)
            try FocusSession(startedAt: 1000, endedAt: 2000, duration: 1).insert(db)
            try Countdown(id: "c", title: "生日", date: Day(2027, 3, 1)).insert(db)
        }
        #expect(try await db.observeCheckins(habitId: "h").first().count == 1)
        try db.close()

        var after = try raw(url, snapshot)
        let mark = try #require(after["key_values"]?.firstIndex { $0[0] == Keys.swiftOpenedAt.databaseValue })
        after["key_values"]?.remove(at: mark)
        // The old tables' rows are as they were, but for the cursor.
        for table in ["task_lists", "tasks", "checklist_items", "task_filters", "list_sections"] {
            #expect(after[table] == before[table], "\(table)")
        }
        let cursor = try #require(after["key_values"]?.first { $0[0] == "sync.cursor".databaseValue })
        #expect(cursor[1] == "0".databaseValue)
        #expect(after["key_values"]?.count == before["key_values"]?.count)
        #expect(try raw(url) { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 8)
    }

    @Test("a version-8 database the Flutter version opened (it writes back 7) comes back as it was")
    func flutterWroteSevenBack() async throws {
        let dir = try TempDir()
        let url = dir.file()
        let first = try AppDatabase.open(at: url)
        try await first.writer.write { db in
            try Habit(id: "h", name: "喝水").insert(db)
            try db.execute(sql: "INSERT INTO key_values VALUES ('sync.cursor', '42')")
        }
        try first.close()
        try await DatabaseQueue(path: url.path).write { try $0.execute(sql: "PRAGMA user_version = 7") }

        let db = try AppDatabase.open(at: url)
        defer { try? db.close() }
        #expect(try await db.observeHabits().first().map(\.name) == ["喝水"])
        #expect(try await db.writer.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 8)
        #expect(try await db.getValue(Keys.cursor) == "0")
    }

    @Test("opening a database from a newer Swift version leaves it as it is")
    func newerVersion() async throws {
        let dir = try TempDir()
        let url = dir.file()
        _ = try AppDatabase.open(at: url).close()
        try await DatabaseQueue(path: url.path).write { try $0.execute(sql: "PRAGMA user_version = 9") }
        let db = try AppDatabase.open(at: url)
        #expect(try await db.writer.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 9)
        try db.close()
    }
}

// MARK: - Backup, location, connection

@Suite struct OpeningTests {
    @Test("the first Swift open of a Flutter database leaves a copy beside it, once")
    func backup() async throws {
        let dir = try TempDir()
        let url = dir.file()
        try flutterDatabase(version: 7, at: url)
        let original = try raw(url, snapshot)
        let backup = AppDatabase.backupURL(for: url)
        #expect(backup.lastPathComponent == "opentodo.sqlite.before-swift")

        let db = try AppDatabase.open(at: url)
        try db.close()
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(try raw(backup, snapshot) == original)
        #expect(try raw(backup) { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 7)
        #expect(!FileManager.default.fileExists(atPath: backup.path + ".partial"))

        // The Swift version has opened it now: no new copy.
        try FileManager.default.removeItem(at: backup)
        try AppDatabase.open(at: url).close()
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }

    @Test("an earlier copy is never overwritten")
    func keepsEarlierBackup() throws {
        let dir = try TempDir()
        let url = dir.file()
        try flutterDatabase(version: 5, at: url)
        let backup = AppDatabase.backupURL(for: url)
        try Data("older copy".utf8).write(to: backup)
        try AppDatabase.open(at: url).close()
        #expect(try Data(contentsOf: backup) == Data("older copy".utf8))
    }

    @Test("a database the Swift version creates needs no copy")
    func newDatabaseNoBackup() throws {
        let dir = try TempDir()
        let url = dir.file("sub/opentodo.sqlite")
        try AppDatabase.open(at: url).close()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: AppDatabase.backupURL(for: url).path))
        // Nor after signing out cleared key_values.
        let db = try AppDatabase.open(at: url)
        try db.setValueNow(Keys.email, "a@example.com")
        try db.writer.write { try $0.execute(sql: "DELETE FROM key_values WHERE key <> 'swift.openedAt'") }
        try db.close()
        try AppDatabase.open(at: url).close()
        #expect(!FileManager.default.fileExists(atPath: AppDatabase.backupURL(for: url).path))
    }

    @Test("WAL and a 5-second busy timeout")
    func connection() async throws {
        let dir = try TempDir()
        let db = try AppDatabase.open(at: dir.file())
        defer { try? db.close() }
        let (mode, timeout) = try await db.writer.write { db in
            (try String.fetchOne(db, sql: "PRAGMA journal_mode"), try Int.fetchOne(db, sql: "PRAGMA busy_timeout"))
        }
        #expect(mode == "wal")
        #expect(timeout == 5000)
        #expect(try await db.writer.read { try Int.fetchOne($0, sql: "PRAGMA busy_timeout") } == 5000)
    }

    @Test("where the file goes")
    func location() {
        let support = URL(fileURLWithPath: "/Support")
        let url = AppDatabase.location(applicationSupport: support, bundleIdentifier: "com.liaoxingyi.opentodo")
        #if os(macOS)
        #expect(url.path == "/Support/com.liaoxingyi.opentodo/opentodo.sqlite")
        #expect(AppDatabase.location(applicationSupport: support, bundleIdentifier: "com.liaoxingyi.opentodo.dev").path
            == "/Support/com.liaoxingyi.opentodo.dev/opentodo.sqlite")
        #else
        #expect(url.path == "/Support/opentodo.sqlite")
        #endif
    }
}
