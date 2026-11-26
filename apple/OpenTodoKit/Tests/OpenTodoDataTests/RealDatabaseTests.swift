// The person's real Flutter database, upgraded on a copy: skipped unless
// `OT_REAL_DB` is set (to the database's path, or to `1` for the Flutter
// macOS app's own file). The real file is only ever read (a read-only
// SQLite backup into a temporary folder); only counts and yes / no are
// printed, never what the rows hold.
//
//     OT_REAL_DB=1 swift test --filter RealDatabaseTests

import Foundation
import GRDB
import Testing
@testable import OpenTodoData

private let realDatabasePath: String? = {
    guard let v = ProcessInfo.processInfo.environment["OT_REAL_DB"], !v.isEmpty else { return nil }
    if v != "1" { return v }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.liaoxingyi.opentodo/Data/Library/Application Support/com.liaoxingyi.opentodo/opentodo.sqlite")
        .path
}()

@Suite(.enabled(if: realDatabasePath != nil, "set OT_REAL_DB to run against the real database"))
struct RealDatabaseTests {
    /// The tables the Flutter version has, and each one's key.
    static let tables = ["task_lists", "tasks", "checklist_items", "task_filters", "list_sections", "key_values"]

    /// Every row of every table, by primary key, as column → value.
    static func rows(_ db: Database) throws -> [String: [String: [String: DatabaseValue]]] {
        var out: [String: [String: [String: DatabaseValue]]] = [:]
        for table in tables {
            let key = table == "key_values" ? "key" : "id"
            var byKey: [String: [String: DatabaseValue]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM \(table)") {
                var columns: [String: DatabaseValue] = [:]
                for (name, value) in row { columns[name] = value }
                byKey[row[key]] = columns
            }
            out[table] = byKey
        }
        return out
    }

    @Test("the real database upgrades to 8 with every row as it was")
    func upgradeCopy() async throws {
        let source = try #require(realDatabasePath)
        let dir = try TempDir()
        let copy = dir.file()
        // A consistent copy, without writing the original (read-only, so not
        // even a hot journal is rolled back there).
        var config = Configuration()
        config.readonly = true
        let original = try DatabaseQueue(path: source, configuration: config)
        let target = try DatabaseQueue(path: copy.path)
        try original.backup(to: target)
        try original.close()
        try target.close()

        let before = try await DatabaseQueue(path: copy.path).read { db in
            (version: try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0, rows: try Self.rows(db))
        }
        let db = try AppDatabase.open(at: copy)
        // Read everything through the models, the way the app does.
        let models = try await db.writer.read { db in
            (lists: try TaskList.fetchAll(db), tasks: try TodoTask.fetchAll(db), items: try ChecklistItem.fetchAll(db),
             filters: try TaskFilter.fetchAll(db), sections: try ListSection.fetchAll(db),
             version: try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0)
        }
        let after = try await db.writer.read { try Self.rows($0) }
        // Each model written back gives the row it was read from: nothing in
        // the real data is lost the next time the app saves it.
        let roundTrip = try await db.writer.read { db -> Int in
            var lossy = 0
            func check(_ record: some PersistableRecord, _ table: String, _ id: String) throws {
                let written = try record.databaseDictionary
                guard let row = after[table]?[id] else { lossy += 1; return }
                for (column, value) in row where (written[column] ?? .null) != value {
                    // 1.0 stored where the model writes 1 is the same REAL.
                    if let a = Double.fromDatabaseValue(value), let b = written[column].flatMap(Double.fromDatabaseValue), a == b { continue }
                    lossy += 1
                }
            }
            for l in models.lists { try check(l, "task_lists", l.id) }
            for t in models.tasks { try check(t, "tasks", t.id) }
            for i in models.items { try check(i, "checklist_items", i.id) }
            for f in models.filters { try check(f, "task_filters", f.id) }
            for s in models.sections { try check(s, "list_sections", s.id) }
            _ = db
            return lossy
        }
        try db.close()

        var mismatched = 0
        for table in Self.tables where table != "key_values" {
            let b = before.rows[table] ?? [:], a = after[table] ?? [:]
            print("real database: \(table) \(b.count) → \(a.count) rows, \(b == a ? "same" : "DIFFERENT")")
            if b != a { mismatched += 1 }
        }
        // key_values: the cursor goes back to 0 (new kinds of records) and
        // the Swift version leaves its mark; nothing else changes.
        var kv = after["key_values"] ?? [:]
        let marked = kv.removeValue(forKey: Keys.swiftOpenedAt) != nil
        var expected = before.rows["key_values"] ?? [:]
        if expected[Keys.cursor] != nil { expected[Keys.cursor]?["value"] = "0".databaseValue }
        print("real database: key_values \(before.rows["key_values"]?.count ?? 0) → \(kv.count) (+ mark: \(marked)), \(kv == expected ? "same" : "DIFFERENT")")
        print("real database: version \(before.version) → \(models.version); models read: \(models.lists.count) lists, \(models.tasks.count) tasks, \(models.items.count) subtasks, \(models.filters.count) filters, \(models.sections.count) sections; columns lost writing back: \(roundTrip)")

        #expect(mismatched == 0)
        #expect(kv == expected)
        #expect(marked)
        #expect(models.version == Schema.version)
        #expect(models.tasks.count == before.rows["tasks"]?.count)
        #expect(roundTrip == 0)
        // The backup beside the copy is the database as it was.
        let backup = try DatabaseQueue(path: AppDatabase.backupURL(for: copy).path, configuration: config)
        let backedUp = try await backup.read { try Self.rows($0) }
        try backup.close()
        #expect(backedUp == before.rows)
    }
}
