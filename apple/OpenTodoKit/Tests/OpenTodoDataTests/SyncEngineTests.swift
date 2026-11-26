// The sync engine against a stand-in server (`StubServer`), for what a real
// one can't be made to do on cue: answer while something else happens on
// the device.

import Foundation
import GRDB
import Synchronization
import Testing
@testable import OpenTodoData

/// Answers `/v1/sync` for one made-up host; `handle` runs on the URL
/// loading thread before the answer goes back, and may block.
final class StubServer: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (_ body: JSONValue) throws -> JSONValue
    private static let handlers = Mutex<[String: Handler]>([:])

    static func session(host: String, _ handle: @escaping Handler) -> URLSession {
        handlers.withLock { $0[host] = handle }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host.map { host in handlers.withLock { $0[host] != nil } } ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let handler = Self.handlers.withLock { $0[host] }
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        } else if let b = request.httpBody {
            body = b
        }
        do {
            let answer = try handler?(JSONValue(parsing: body) ?? .null) ?? .null
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: answer.encodedData)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// A page from the server with one task on it, `version` its cursor.
func onePage(_ id: String, version: Int, hasMore: Bool = false) -> JSONValue {
    let record = TodoTask(id: id, title: "别的账号的任务", createdAt: 1, updatedAt: 1).wire.json
    var change = record.object!
    change["version"] = .int(version)
    return .fields([
        ("accepted", .array([])),
        ("changes", .array([.object(change)])),
        ("cursor", .int(version)),
        ("hasMore", .bool(hasMore)),
    ])
}

@Suite struct SyncEngineTests {
    @Test("signing out while a sync is on its way: what it brings back doesn't land on the cleared device")
    func signOutMidSync() async throws {
        let db = try AppDatabase.inMemory()
        let tokens = KeyValueTokenStore(db)
        let host = "stub-\(UUID().uuidString.lowercased()).invalid"
        let session = StubServer.session(host: host) { _ in
            // The person signs out while this request is out: the token
            // goes, then the data (`clearLocalData`, done here in step).
            try tokens.setToken(nil)
            try db.writer.write { db in
                for table in SyncedTable.allCases { try db.execute(sql: "DELETE FROM \(table.rawValue)") }
                try db.execute(sql: "DELETE FROM key_values WHERE key <> ?", arguments: [Keys.swiftOpenedAt])
            }
            return onePage("theirs", version: 7, hasMore: true)
        }
        try await completeSignIn(db, Account(serverUrl: "http://\(host)", token: "t", email: "a@example.com", userId: "a"), tokens: tokens)
        try await db.writer.write { try TodoTask(id: "mine", title: "本机的", createdAt: 1, updatedAt: 1).insert($0) }

        let engine = SyncEngine(db, session: session, tokens: tokens, pageSize: 1)
        await #expect(throws: SyncError.self) { try await engine.sync() }
        #expect(try await db.observeTasks().first().isEmpty)
        #expect(try await db.getValue(Keys.cursor) == nil)
        #expect(try await db.getValue(Keys.lastSyncedAt) == nil)
    }

    @Test("signing in to another account while a sync for the last one is on its way: its page is dropped")
    func otherAccountMidSync() async throws {
        let db = try AppDatabase.inMemory()
        let tokens = KeyValueTokenStore(db)
        let host = "stub-\(UUID().uuidString.lowercased()).invalid"
        let session = StubServer.session(host: host) { _ in
            // The other account's sign-in is stored (its token last).
            try db.writer.write { db in
                try Account(serverUrl: "http://\(host)", token: "b", email: "b@example.com", userId: "b").save(db)
                try db.setValue("0", forKey: Keys.cursor)
            }
            return onePage("a-task", version: 9)
        }
        try await completeSignIn(db, Account(serverUrl: "http://\(host)", token: "a", email: "a@example.com", userId: "a"), tokens: tokens)
        let engine = SyncEngine(db, session: session, tokens: tokens)
        await #expect(throws: SyncError.self) { try await engine.sync() }
        #expect(try await db.observeTasks().first().isEmpty)
        #expect(try await db.getValue(Keys.cursor) == "0")
    }
}
