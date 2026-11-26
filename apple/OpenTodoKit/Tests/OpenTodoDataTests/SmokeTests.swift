import GRDB
import Testing
@testable import OpenTodoData

@Test func opensAnInMemoryDatabase() throws {
    let db = try DatabaseQueue()
    try db.write { db in
        try db.execute(sql: "CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER NOT NULL)")
        try db.execute(sql: "INSERT INTO t VALUES ('a', 1), ('b', 2)")
    }
    let sum = try db.read { try Int.fetchOne($0, sql: "SELECT SUM(n) FROM t") }
    #expect(sum == 3)
    #expect(inboxListId == "inbox") // Domain is re-exported.
}
