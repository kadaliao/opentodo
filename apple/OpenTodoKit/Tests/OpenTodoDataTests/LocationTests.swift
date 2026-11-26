// Where the database goes: an App Group container when there is one, the
// old place's database copied in the first time; and several connections
// (the app, a widget) on one file.

import Foundation
import GRDB
import Testing
@testable import OpenTodoData

@Suite struct LocationTests {
    @Test("no App Group: the old place")
    func noGroup() throws {
        let url = try AppDatabase.defaultURL(bundleIdentifier: "com.liaoxingyi.opentodo.tests", appGroup: nil)
        #expect(url.lastPathComponent == "opentodo.sqlite")
        // A group this process isn't entitled to is no group either.
        let same = try AppDatabase.defaultURL(bundleIdentifier: "com.liaoxingyi.opentodo.tests", appGroup: "group.example.nobody")
        #if os(macOS)
        // (macOS hands any process a container path for a group; the app's
        // sandbox decides whether it can use it, so only check iOS here.)
        _ = same
        #else
        #expect(same == url)
        #endif
        #expect(AppDatabase.appGroupFromInfoPlist(Bundle(for: BundleToken.self)) == nil)
        let group = AppDatabase.groupLocation(container: URL(fileURLWithPath: "/G"))
        #expect(group.path == "/G/Library/Application Support/opentodo.sqlite")
    }

    @Test("a group with nothing in it, and nothing at the old place: a new database in the group")
    func fresh() throws {
        let old = try TempDir(), container = try TempDir()
        let group = AppDatabase.groupLocation(container: container.url)
        #expect(try AppDatabase.moveIntoGroup(legacy: old.file(), group: group) == group)
        #expect(!FileManager.default.fileExists(atPath: group.path))
        try AppDatabase.open(at: group).close()
        #expect(FileManager.default.fileExists(atPath: group.path))
    }

    @Test("the old database is copied in, everything in it, and left where it was")
    func copiedIn() async throws {
        let old = try TempDir(), container = try TempDir()
        let legacy = old.file()
        // What the Flutter version left (a backup comes with the first open).
        try flutterDatabase(version: 7, at: legacy)
        // And writes still in the WAL: a connection that hasn't checkpointed.
        let writer = try DatabaseQueue(path: legacy.path)
        try await writer.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        try await writer.write { db in
            try db.execute(sql: "INSERT INTO tasks (id, list_id, title, created_at, updated_at) VALUES ('w', 'inbox', '在 WAL 里', 2, 2)")
        }

        let group = AppDatabase.groupLocation(container: container.url)
        #expect(try AppDatabase.moveIntoGroup(legacy: legacy, group: group) == group)
        try writer.close()
        let db = try AppDatabase.open(at: group)
        #expect(Set(try await db.observeTasks().first().map(\.title)) == ["旧任务", "在 WAL 里"])
        #expect(try await db.writer.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 8)
        try db.close()

        // The old one is still there, still at 7, nothing of the Swift version's in it.
        #expect(try raw(legacy) { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 7)
        #expect(try raw(legacy) { try String.fetchAll($0, sql: "SELECT title FROM tasks ORDER BY rowid") } == ["旧任务", "在 WAL 里"])
        #expect(try raw(legacy) { try String.fetchOne($0, sql: "SELECT value FROM key_values WHERE key = 'swift.openedAt'") } == nil)
        // The Flutter database got its own copy beside it in the group too.
        #expect(FileManager.default.fileExists(atPath: AppDatabase.backupURL(for: group).path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: group.deletingLastPathComponent().path).filter { $0.contains(".copy-") }
        #expect(leftovers.isEmpty)
    }

    @Test("once the group has a database, the old one isn't copied again")
    func notTwice() async throws {
        let old = try TempDir(), container = try TempDir()
        let group = AppDatabase.groupLocation(container: container.url)
        let inGroup = try AppDatabase.open(at: try AppDatabase.moveIntoGroup(legacy: old.file(), group: group))
        try await inGroup.setValue(Keys.email, "group@example.com")
        try inGroup.close()
        let legacy = try AppDatabase.open(at: old.file())
        try await legacy.setValue(Keys.email, "old@example.com")
        try legacy.close()

        let db = try AppDatabase.open(at: try AppDatabase.moveIntoGroup(legacy: old.file(), group: group))
        #expect(try await db.getValue(Keys.email) == "group@example.com")
        try db.close()
    }

    @Test("a widget reads what the app writes, and can't write")
    func readOnly() async throws {
        let dir = try TempDir()
        let url = dir.file()
        #expect(throws: (any Error).self) { try AppDatabase.openReadOnly(at: url) }
        let app = try AppDatabase.open(at: url)
        let widget = try AppDatabase.openReadOnly(at: url)
        let repo = TaskRepo(app)
        try await repo.addTask(title: "给小组件看")
        #expect(try await widget.observeTasks().first().map(\.title) == ["给小组件看"])
        await #expect(throws: (any Error).self) { try await widget.setValue(Keys.email, "x") }
        try widget.close()
        try app.close()
    }

    @Test("two processes' worth of connections writing at once take turns")
    func twoWriters() async throws {
        let dir = try TempDir()
        let url = dir.file()
        let a = try AppDatabase.open(at: url)
        let b = try AppDatabase.open(at: url) // as a second process would
        let ra = TaskRepo(a), rb = TaskRepo(b)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { for i in 0 ..< 50 { try await ra.addTask(title: "a\(i)") } }
            group.addTask { for i in 0 ..< 50 { try await rb.addTask(title: "b\(i)") } }
            try await group.waitForAll()
        }
        #expect(try await a.observeTasks().first().count == 100)
        try a.close()
        try b.close()
    }
}

private final class BundleToken {}
