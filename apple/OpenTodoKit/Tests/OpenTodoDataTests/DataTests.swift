// The rest of the data layer: rows, key_values, observations, tokens,
// and the account helpers.

import Foundation
import GRDB
import Synchronization
import Testing
@testable import OpenTodoData

@Suite struct RecordTests {
    @Test("rows are stored the way drift stores them")
    func columns() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try TodoTask(id: "t", title: "开会", dueDate: Day(2026, 11, 16), tags: ["工作", "a/b"], reminders: [0, -30],
                         repeatFrom: .completion, createdAt: 1, updatedAt: 2).insert(db)
            try ChecklistItem(id: "c", taskId: "t", done: true, dirty: false).insert(db)
        }
        let row = try await db.writer.read { db in
            try String.fetchAll(db, sql: "SELECT due_date || '|' || tags || '|' || reminders || '|' || repeat_from || '|' || dirty FROM tasks")
        }
        #expect(row == [#"2026-11-16|["工作","a/b"]|[0,-30]|1|1"#])
        let item = try await db.writer.read { try String.fetchAll($0, sql: "SELECT done || '|' || dirty FROM checklist_items") }
        #expect(item == ["1|0"])
    }

    @Test("odd values in a row read as defaults")
    func lenient() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO tasks (id, list_id, title, tags, reminders, status, priority, due_date, created_at, updated_at)
                VALUES ('t', 'inbox', 'x', 'oops', '[1.0, "a", -5]', 7, 9, 'soon', 1, 1)
                """)
        }
        let t = try #require(try await db.observeTasks().first().first)
        #expect(t.tags == [])
        #expect(t.reminders == [1, -5])
        #expect(t.status == .open)
        #expect(t.priority == .high)
        #expect(t.dueDate == nil)
    }
}

@Suite struct KeyValueTests {
    @Test("get, set, overwrite and delete")
    func roundTrip() async throws {
        let db = try AppDatabase.inMemory()
        #expect(try await db.getValue(Keys.settings) == nil)
        try await db.setValue(Keys.settings, "{}")
        try await db.setValue(Keys.settings, #"{"a":1}"#)
        #expect(try await db.getValue(Keys.settings) == #"{"a":1}"#)
        try await db.setValue(Keys.settings, nil)
        #expect(try await db.getValue(Keys.settings) == nil)
        #expect(try db.getValueNow(Keys.swiftOpenedAt) != nil)
    }

    @Test("watching a key")
    func observe() async throws {
        let db = try AppDatabase.inMemory()
        var seen: [String?] = []
        for try await value in db.observeValue(Keys.cursor).values() {
            seen.append(value)
            switch seen.count {
            case 1: try await db.setValue(Keys.email, "unrelated") // no new value
                    try await db.setValue(Keys.cursor, "1")
            case 2: try await db.setValue(Keys.cursor, nil)
            default: break
            }
            if seen.count == 3 { break }
        }
        #expect(seen == [nil, "1", nil])
    }
}

@Suite struct ObservationTests {
    @Test("lists in order, without tombstones")
    func lists() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try TaskList(id: "b", name: "B", sortOrder: 2, createdAt: 1).insert(db)
            try TaskList(id: "a", name: "A", sortOrder: 1, createdAt: 2).insert(db)
            try TaskList(id: "a2", name: "A2", sortOrder: 1, createdAt: 3).insert(db)
            try TaskList(id: "x", name: "X", sortOrder: 0, deletedAt: 9).insert(db)
        }
        #expect(try await db.observeLists().first().map(\.id) == ["a", "a2", "b"])
    }

    @Test("tasks keep the trash but not tombstones; subtasks by task")
    func tasks() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try TodoTask(id: "a").insert(db)
            try TodoTask(id: "trashed", trashedAt: 5).insert(db)
            try TodoTask(id: "gone", deletedAt: 5).insert(db)
            try ChecklistItem(id: "2", taskId: "a", sortOrder: 2).insert(db)
            try ChecklistItem(id: "1", taskId: "a", sortOrder: 1).insert(db)
            try ChecklistItem(id: "x", taskId: "a", deletedAt: 1).insert(db)
            try ChecklistItem(id: "o", taskId: "other").insert(db)
        }
        #expect(try await db.observeTasks().first().map(\.id) == ["a", "trashed"])
        #expect(try await db.observeChecklist(taskId: "a").first().map(\.id) == ["1", "2"])
        #expect(try await db.observeAllChecklistItems().first().count == 3)
    }

    @Test("the dirty count follows writes")
    func dirtyCount() async throws {
        let db = try AppDatabase.inMemory()
        var seen: [Int] = []
        for try await n in db.observeDirtyCount().values() {
            seen.append(n)
            switch seen.count {
            case 1: try await db.writer.write { db in
                    try TodoTask(id: "a").insert(db)
                    try TaskFilter(id: "f").insert(db)
                    try ListSection(id: "s", dirty: false).insert(db)
                }
            case 2: try await db.writer.write { try $0.execute(sql: "UPDATE tasks SET dirty = 0") }
            default: break
            }
            if seen.count == 3 { break }
        }
        #expect(seen == [0, 2, 1])
    }

    @Test("callbacks on the main actor, until cancelled")
    @MainActor
    func callbacks() async throws {
        let db = try AppDatabase.inMemory()
        var seen: [[String]] = []
        let handle = db.observeSections().start { seen.append($0.map(\.name)) }
        #expect(seen == [[]]) // the current value, right away
        try await db.writer.write { try ListSection(id: "s", name: "进行中").insert($0) }
        for _ in 0 ..< 200 where seen.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(seen == [[], ["进行中"]])
        handle.cancel()
        try await db.writer.write { try ListSection(id: "t", name: "已完成").insert($0) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(seen.count == 2)
    }
}

/// A token store in memory, standing in for the keychain.
final class MemoryTokenStore: TokenStore {
    let value = Mutex<String?>(nil)
    init(_ token: String? = nil) { value.withLock { $0 = token } }
    func token() throws -> String? { value.withLock { $0 } }
    func setToken(_ token: String?) throws { value.withLock { $0 = token } }
}

@Suite struct TokenStoreTests {
    @Test("the database store keeps it under account.token")
    func keyValueStore() throws {
        let db = try AppDatabase.inMemory()
        let store = KeyValueTokenStore(db)
        #expect(try store.token() == nil)
        try store.setToken("abc")
        #expect(try db.getValueNow(Keys.token) == "abc")
        try store.setToken(nil)
        #expect(try db.getValueNow(Keys.token) == nil)
    }

    @Test("a token the Flutter version left moves out of the database")
    func moveLegacy() throws {
        let db = try AppDatabase.inMemory()
        try db.setValueNow(Keys.token, "old")
        let keychain = MemoryTokenStore()
        try moveLegacyToken(from: db, into: keychain)
        #expect(try keychain.token() == "old")
        #expect(try db.getValueNow(Keys.token) == nil)
        try moveLegacyToken(from: db, into: keychain) // nothing left: no-op
        #expect(try keychain.token() == "old")

        // A token in the database is always the newer sign-in (the Flutter
        // version, or a launch without the keychain, signed in after the
        // keychain's was written), and the account fields beside it are
        // that sign-in's: it replaces the keychain's.
        try db.setValueNow(Keys.token, "newer")
        let signedIn = MemoryTokenStore("older")
        try moveLegacyToken(from: db, into: signedIn)
        #expect(try signedIn.token() == "newer")
        #expect(try db.getValueNow(Keys.token) == nil)

        // The database store is where it already is.
        try db.setValueNow(Keys.token, "here")
        try moveLegacyToken(from: db, into: KeyValueTokenStore(db))
        #expect(try db.getValueNow(Keys.token) == "here")
    }

    @Test("going back to the Flutter version and signing in to another account there: the Swift version follows it")
    func flutterSignedInElsewhere() async throws {
        let db = try AppDatabase.inMemory()
        let keychain = MemoryTokenStore()
        try await completeSignIn(db, Account(serverUrl: "http://x", token: "a-token", email: "a@example.com", userId: "a"), tokens: keychain)
        // The Flutter version signs out (clearing key_values) and in as b.
        try await db.writer.write { db in
            try db.execute(sql: "DELETE FROM key_values")
            for (k, v) in [(Keys.server, "http://x"), (Keys.token, "b-token"), (Keys.email, "b@example.com"), (Keys.userId, "b")] {
                try db.setValue(v, forKey: k)
            }
        }
        try moveLegacyToken(from: db, into: keychain)
        let account = try #require(try await Account.load(db, tokens: keychain))
        #expect(account == Account(serverUrl: "http://x", token: "b-token", email: "b@example.com", userId: "b"))
    }

    @Test("a token left in the keychain after the database was cleared (signed out in the Flutter version) isn't a sign-in")
    func staleKeychainToken() async throws {
        let db = try AppDatabase.inMemory()
        let keychain = MemoryTokenStore()
        try await completeSignIn(db, Account(serverUrl: "http://self-hosted", token: "t", email: "a@example.com", userId: "a"), tokens: keychain)
        try await db.writer.write { try $0.execute(sql: "DELETE FROM key_values") }
        try moveLegacyToken(from: db, into: keychain)
        #expect(try await Account.load(db, tokens: keychain) == nil)
    }

    @Test("the account reads its token from the store", .timeLimit(.minutes(1)))
    func account() async throws {
        let db = try AppDatabase.inMemory()
        let tokens = MemoryTokenStore()
        #expect(try await Account.load(db, tokens: tokens) == nil)
        try await completeSignIn(db, Account(serverUrl: "http://x", token: "t", email: "a@example.com", userId: "u"), tokens: tokens)
        #expect(try await Account.load(db, tokens: tokens) == Account(serverUrl: "http://x", token: "t", email: "a@example.com", userId: "u"))
        #expect(try await db.getValue(Keys.token) == nil)
        #expect(try await db.getValue(Keys.cursor) == "0")

        try await db.writer.write { try TodoTask(id: "a").insert($0) }
        try await clearLocalData(db, tokens: tokens)
        #expect(try tokens.token() == nil)
        #expect(try await db.observeTasks().first().isEmpty)
        #expect(try await db.getValue(Keys.email) == nil)
        #expect(try await db.getValue(Keys.swiftOpenedAt) != nil)
    }

    /// In the signed app this is the keychain; `swift test` runs unsigned,
    /// without the keychain entitlement, so there it is the database. Either
    /// way the token goes in and out.
    @Test("the keychain store, or the database where the keychain can't be used")
    func keychain() throws {
        let db = try AppDatabase.inMemory()
        let store = defaultTokenStore(for: db, keychain: KeychainTokenStore(service: "com.liaoxingyi.opentodo.tests.\(UUID().uuidString)"))
        defer { try? store.setToken(nil) }
        #expect(try store.token() == nil)
        try store.setToken("one")
        try store.setToken("two")
        #expect(try store.token() == "two")
        #expect(try db.getValueNow(Keys.token) == (store is KeyValueTokenStore ? "two" : nil))
        try store.setToken(nil)
        #expect(try store.token() == nil)
    }
}

@Suite struct AccountTests {
    @Test("server addresses are tidied")
    func normalize() {
        #expect(normalizeServerUrl("") == defaultServerUrl)
        #expect(normalizeServerUrl("  ") == defaultServerUrl)
        #expect(normalizeServerUrl("todo.example.com/") == "https://todo.example.com")
        #expect(normalizeServerUrl(" http://127.0.0.1:8686// ") == "http://127.0.0.1:8686")
    }

    @Test("errors in the person's words")
    func errors() {
        let body = Data(#"{"error":{"code":"email_taken","message":"email is already registered"}}"#.utf8)
        #expect(errorFrom(status: 409, body: body) == SyncError("email_taken", "这个邮箱已经注册过，请直接登录"))
        #expect(errorFrom(status: 401, body: Data(#"{"error":{"code":"unauthorized"}}"#.utf8)).isAuth)
        #expect(errorFrom(status: 502, body: Data("<html>".utf8)) == SyncError("http_502", "服务器出错（502），请稍后再试"))
        #expect(errorFrom(status: 400, body: Data(#"{"error":{"code":"new_code"}}"#.utf8)).message == "服务器出错（400），请稍后再试")
    }
}
