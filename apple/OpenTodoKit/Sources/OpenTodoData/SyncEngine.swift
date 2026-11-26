// One sync pass, the sign-in clean-up and signing out; ported from
// `app/lib/sync/sync_engine.dart`. The protocol is in docs/architecture.md
// (同步) and `server/internal/api`.
//
// Conflicts go to the newer edit (by `updatedAt`). A local edit made while
// a request is in flight stays dirty and goes out on the next pass.

import Foundation
import GRDB

public struct SyncReport: Sendable, Hashable {
    public let pushed: Int
    public let pulled: Int

    public init(pushed: Int, pulled: Int) {
        self.pushed = pushed
        self.pulled = pulled
    }
}

struct SyncResponse {
    let accepted: [(entity: String, id: String, version: Int)]
    let changes: [WireRecord]
    let cursor: Int
    let hasMore: Bool

    init?(_ j: JSONValue) {
        guard let cursor = j["cursor"]?.intValue else { return nil }
        accepted = (j["accepted"]?.arrayValue ?? []).compactMap { a in
            guard let entity = a["entity"]?.stringValue, let id = a["id"]?.stringValue,
                  let version = a["version"]?.intValue else { return nil }
            return (entity, id, version)
        }
        changes = (j["changes"]?.arrayValue ?? []).compactMap(WireRecord.init(json:))
        self.cursor = cursor
        hasMore = j["hasMore"]?.boolValue ?? false
    }
}

public final class SyncEngine: Sendable {
    public let database: AppDatabase
    public let session: URLSession
    public let tokens: any TokenStore
    public let pageSize: Int

    public init(_ database: AppDatabase, session: URLSession = .shared, tokens: any TokenStore, pageSize: Int = 500) {
        self.database = database
        self.session = session
        self.tokens = tokens
        self.pageSize = pageSize
    }

    private var writer: any DatabaseWriter { database.writer }

    /// Push what changed here, pull what changed elsewhere, until both are
    /// done; then drop the tombstones the server has.
    /// `progress` hears the running totals after each page (for the first
    /// sync after signing in, which can be long).
    @discardableResult
    public func sync(progress: (@Sendable (SyncReport) -> Void)? = nil) async throws -> SyncReport {
        guard let account = try await Account.load(database, tokens: tokens) else {
            throw SyncError("signed_out", "还没有登录")
        }
        var cursor = Int(try await database.getValue(Keys.cursor) ?? "") ?? 0
        var pushed = 0, pulled = 0

        // Bounded so a misbehaving server can't keep us looping.
        for _ in 0 ..< 10000 {
            let pending = try await writer.read { [pageSize] in try dirtyRecords($0, limit: pageSize) }
            let res = try await post(account, cursor, pending)
            try await writer.write { [tokens, database] db in
                try ensureStillSignedIn(db, database, account, tokens)
                // Apply first: the server reads what to send back before
                // storing this push, so a pulled record can be older than
                // one just pushed. While the pushed row is still dirty,
                // `apply` keeps the newer local copy.
                for r in res.changes {
                    try apply(db, r)
                }
                try markAccepted(db, pending, res.accepted)
                try db.setValue(String(res.cursor), forKey: Keys.cursor)
            }
            cursor = res.cursor
            pushed += res.accepted.count
            pulled += res.changes.count
            progress?(SyncReport(pushed: pushed, pulled: pulled))
            if !res.hasMore && pending.count < pageSize { break }
        }

        try await writer.write { [tokens, database] db in
            try ensureStillSignedIn(db, database, account, tokens)
            try purgeSyncedTombstones(db)
            try db.setValue(String(nowMilliseconds()), forKey: Keys.lastSyncedAt)
        }
        return SyncReport(pushed: pushed, pulled: pulled)
    }

    private func post(_ account: Account, _ cursor: Int, _ pending: [WireRecord]) async throws -> SyncResponse {
        let body: JSONValue = .fields([
            ("cursor", .int(cursor)),
            ("limit", .int(pageSize)),
            ("changes", .array(pending.map(\.json))),
        ])
        let (status, data) = try await OpenTodoData.post(
            session, "\(account.serverUrl)/v1/sync", body: body, token: account.token, timeout: 60
        )
        guard status == 200 else { throw errorFrom(status: status, body: data) }
        guard let json = JSONValue(parsing: data), let res = SyncResponse(json) else {
            throw SyncError("bad_response", "服务器出错（\(status)），请稍后再试")
        }
        return res
    }
}

/// Throws unless `account` is still the one signed in here, inside the
/// write that would store what its request brought back. Signing out (or
/// in to another account) while a request is out doesn't wait for it:
/// without this its page, its cursor and every page after it would land on
/// the device after the sign-out cleared it, or in the next account's data.
/// Signing out takes the token first and in stores the user id first, so
/// one of them has changed by the time either clears or resets anything.
func ensureStillSignedIn(_ db: Database, _ database: AppDatabase, _ account: Account, _ tokens: any TokenStore) throws {
    // A token kept in this very database is read in this write (asking the
    // store would open a second, nested access).
    let token = if let kv = tokens as? KeyValueTokenStore, kv.database === database {
        try db.value(forKey: Keys.token)
    } else {
        try tokens.token()
    }
    guard token == account.token, try (db.value(forKey: Keys.userId) ?? "") == account.userId else {
        throw SyncError("signed_out", "还没有登录")
    }
}

/// Dirty rows, in `SyncedTable` order: lists first so a task never
/// arrives before its list.
func dirtyRecords(_ db: Database, limit: Int) throws -> [WireRecord] {
    var out: [WireRecord] = []
    for table in SyncedTable.allCases where out.count < limit {
        out += try table.dirtyRecords(db, limit: limit - out.count)
    }
    return out
}

/// Marks pushed rows clean at the version the server gave them, but only
/// if they haven't been edited again since they were sent.
func markAccepted(_ db: Database, _ pending: [WireRecord], _ accepted: [(entity: String, id: String, version: Int)]) throws {
    var sentAt: [String: Int] = [:]
    for p in pending { sentAt["\(p.entity)/\(p.id)"] = p.updatedAt }
    for a in accepted {
        guard let updatedAt = sentAt["\(a.entity)/\(a.id)"], let table = SyncedTable(entity: a.entity) else { continue }
        try db.execute(
            sql: "UPDATE \(table.rawValue) SET dirty = 0, server_version = ? WHERE id = ? AND updated_at = ?",
            arguments: [a.version, a.id, updatedAt]
        )
    }
}

/// Stores a pulled record, unless the local row is dirty with a newer edit.
/// A kind of record this version doesn't know yet is skipped.
func apply(_ db: Database, _ r: WireRecord) throws {
    guard let table = SyncedTable(entity: r.entity) else { return }
    let local = try Row.fetchOne(
        db, sql: "SELECT updated_at, dirty FROM \(table.rawValue) WHERE id = ?", arguments: [r.id]
    )
    if let local, local["dirty"] as Bool == true, (local["updated_at"] as Int) > r.updatedAt { return }
    try table.store(db, r)
}

/// Deleted rows the server already has can go; it keeps the tombstone for
/// other devices.
func purgeSyncedTombstones(_ db: Database) throws {
    for table in SyncedTable.allCases {
        try db.execute(sql: "DELETE FROM \(table.rawValue) WHERE deleted_at IS NOT NULL AND dirty = 0")
    }
}

/// After signing in: drop the untouched welcome items (the account may
/// already have its own) and start syncing from the beginning.
public func completeSignIn(_ database: AppDatabase, _ account: Account, tokens: any TokenStore) async throws {
    try await database.writer.write { db in
        if let seed = try db.value(forKey: Keys.seedIds) {
            let ids = JSONValue.parse(seed)?.arrayValue?.compactMap(\.stringValue) ?? []
            if !ids.isEmpty {
                let marks = databaseQuestionMarks(count: ids.count)
                let args = StatementArguments(ids)
                try db.execute(sql: "DELETE FROM tasks WHERE id IN (\(marks)) AND updated_at = created_at", arguments: args)
                try db.execute(sql: "DELETE FROM checklist_items WHERE task_id IN (\(marks))", arguments: args)
                // A welcome list goes too, if nothing is left in it.
                let lists = try String.fetchAll(
                    db, sql: "SELECT id FROM task_lists WHERE id IN (\(marks)) AND updated_at = created_at", arguments: args
                )
                for id in lists {
                    let remaining = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE list_id = ?", arguments: [id]) ?? 0
                    if remaining == 0 {
                        try db.execute(sql: "DELETE FROM task_lists WHERE id = ?", arguments: [id])
                    }
                }
            }
            try db.setValue(nil, forKey: Keys.seedIds)
        }
        try account.save(db)
        try db.setValue("0", forKey: Keys.cursor)
        try db.setValue(nil, forKey: Keys.lastSyncedAt)
    }
    try account.saveToken(tokens)
}

/// Signing out removes this account's data from the device: every synced
/// row, the local settings and the token. (The Swift version's own mark,
/// `Keys.swiftOpenedAt`, stays, so the next launch doesn't take this for a
/// Flutter database.)
public func clearLocalData(_ database: AppDatabase, tokens: any TokenStore) async throws {
    try tokens.setToken(nil)
    try await database.writer.write { db in
        for table in SyncedTable.allCases.reversed() {
            try db.execute(sql: "DELETE FROM \(table.rawValue)")
        }
        try db.execute(sql: "DELETE FROM key_values WHERE key <> ?", arguments: [Keys.swiftOpenedAt])
    }
}
