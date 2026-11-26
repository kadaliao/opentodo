// Port of app/test/sync_integration_test.dart: two simulated devices sync
// through the real Go server, built from server/ and started by this suite
// (temporary database, a free port, `-auth-per-minute 1000`). Skipped when
// Go isn't installed.

import Foundation
import Testing
@testable import OpenTodoData

// MARK: - The server

/// The `go` binary, from PATH or the usual install places.
let goBinary: String? = {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let dirs = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/go/bin"]
    return dirs.map { $0 + "/go" }.first { FileManager.default.isExecutableFile(atPath: $0) }
}()

/// The repository root, from this file's place in it.
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // OpenTodoDataTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // OpenTodoKit
    .deletingLastPathComponent() // apple
    .deletingLastPathComponent()

final class GoServer: @unchecked Sendable {
    @TaskLocal static var current: GoServer?

    let url: String
    private let process: Process
    private let dir: URL

    private init(url: String, process: Process, dir: URL) {
        self.url = url
        self.process = process
        self.dir = dir
    }

    static func start() async throws -> GoServer {
        let go = try #require(goBinary)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("opentodo-sync-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bin = dir.appendingPathComponent("opentodo-server").path

        let build = Process()
        build.executableURL = URL(fileURLWithPath: go)
        build.arguments = ["build", "-o", bin, "./cmd/opentodo-server"]
        build.currentDirectoryURL = repoRoot.appendingPathComponent("server")
        let errors = Pipe()
        build.standardError = errors
        build.standardOutput = FileHandle.nullDevice
        try build.run()
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        build.waitUntilExit()
        guard build.terminationStatus == 0 else {
            throw ServerError("go build failed:\n" + String(decoding: message, as: UTF8.self))
        }

        let port = try freePort()
        let server = Process()
        server.executableURL = URL(fileURLWithPath: bin)
        // Every test signs devices in afresh; more than the default limit allows.
        server.arguments = ["-addr", "127.0.0.1:\(port)", "-db", dir.appendingPathComponent("test.db").path, "-auth-per-minute", "1000"]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        let running = GoServer(url: "http://127.0.0.1:\(port)", process: server, dir: dir)

        let session = URLSession(configuration: .ephemeral)
        for _ in 0 ..< 100 {
            if let (_, response) = try? await session.data(from: URL(string: running.url + "/v1/health")!),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return running
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        running.stop()
        throw ServerError("server did not start")
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: dir)
    }

    /// A port nobody is listening on right now.
    private static func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError("socket failed") }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { p in
                bind(fd, p, len) == 0 && getsockname(fd, p, &len) == 0
            }
        }
        guard bound else { throw ServerError("bind failed") }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

struct ServerError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Starts the server once for the suite and stops it afterwards.
struct WithGoServer: SuiteTrait, TestScoping {
    var isRecursive: Bool { false }

    @concurrent func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        let server = try await GoServer.start()
        defer { server.stop() }
        try await GoServer.$current.withValue(server) { try await function() }
    }
}

// MARK: - Devices

final class Device: Sendable {
    let db: AppDatabase
    let tokens: KeyValueTokenStore
    let session = URLSession(configuration: .ephemeral)
    let clock = TestClock()
    let repo: TaskRepo
    let engine: SyncEngine

    init() throws {
        db = try AppDatabase.inMemory()
        tokens = KeyValueTokenStore(db)
        repo = TaskRepo(db, clock: { [clock] in clock.now }, tokens: tokens)
        engine = SyncEngine(db, session: session, tokens: tokens)
    }

    func advance(minutes: Int = 1) { clock.advance(minutes: minutes) }

    func signIn(_ email: String, register: Bool = false) async throws {
        let server = try #require(GoServer.current)
        let account = try await AuthApi(session: session).signIn(
            serverUrl: server.url, email: email, password: "correct horse", register: register
        )
        try await completeSignIn(db, account, tokens: tokens)
    }

    @discardableResult
    func sync() async throws -> SyncReport { try await engine.sync() }

    func tasks() async throws -> [TodoTask] { try await db.observeTasks().first() }
    func task(_ id: String) async throws -> TodoTask? { try await tasks().first { $0.id == id } }
    func lists() async throws -> [TaskList] { try await db.observeLists().first() }
    func checklist(_ taskId: String) async throws -> [ChecklistItem] { try await db.observeChecklist(taskId: taskId).first() }
    func sections() async throws -> [ListSection] { try await db.observeSections().first() }
    func filters() async throws -> [TaskFilter] { try await db.observeFilters().first() }
    func dirtyCount() async throws -> Int { try await db.observeDirtyCount().first() }

    deinit { session.invalidateAndCancel() }
}

func newEmail() -> String { "user-\(UUID().uuidString.lowercased())@example.com" }

// MARK: - Tests

@Suite(.enabled(if: goBinary != nil, "Go is not installed"), .serialized, WithGoServer())
struct SyncIntegrationTests {
    let phone: Device
    let mac: Device

    init() throws {
        phone = try Device()
        mac = try Device()
    }

    @Test("two devices converge: create, edit, delete")
    func converge() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)

        let listId = try await phone.repo.addList("工作", emoji: "💼")
        let taskId = try await phone.repo.addTask(title: "写周报", listId: listId)
        try await phone.repo.addChecklistItem(taskId, "整理数据")
        #expect(try await phone.sync().pushed == 3)

        try await mac.sync()
        #expect(try await mac.lists().map(\.name) == ["工作"])
        #expect(try await mac.task(taskId)?.title == "写周报")
        #expect(try await mac.checklist(taskId).map(\.title) == ["整理数据"])

        // Everything the Mac received is clean; nothing to push back.
        #expect(try await mac.dirtyCount() == 0)

        mac.advance()
        try await mac.repo.setTitle(taskId, "写周报（周五前）")
        try await mac.repo.setCompleted(taskId, true)
        try await mac.sync()
        try await phone.sync()
        let onPhone = try #require(try await phone.task(taskId))
        #expect(onPhone.title == "写周报（周五前）")
        #expect(onPhone.status == .done)

        phone.advance()
        try await phone.repo.trashTask(taskId)
        try await phone.repo.emptyTrash()
        try await phone.sync()
        try await mac.sync()
        #expect(try await mac.task(taskId) == nil)
        #expect(try await mac.checklist(taskId).isEmpty)
        // Tombstones the server has are purged locally.
        #expect(try await mac.repo.getTask(taskId) == nil)
    }

    @Test("the newer edit wins a conflict")
    func newerWins() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)
        let id = try await phone.repo.addTask(title: "原标题")
        try await phone.sync()
        try await mac.sync()

        // Both edit offline; the Mac's edit is later but the phone syncs first.
        phone.advance(minutes: 1)
        try await phone.repo.setTitle(id, "手机改的")
        mac.advance(minutes: 2)
        try await mac.repo.setTitle(id, "电脑改的")

        try await phone.sync()
        try await mac.sync() // later edit: accepted
        try await phone.sync() // phone takes it
        #expect(try await phone.task(id)?.title == "电脑改的")
        #expect(try await mac.task(id)?.title == "电脑改的")

        // Now the reverse: the phone's stale edit is pushed after a newer one.
        mac.advance(minutes: 5)
        try await mac.repo.setPriority(id, .high)
        try await mac.sync()
        try await phone.repo.setPriority(id, .low) // phone clock is behind
        try await phone.sync()
        let p = try #require(try await phone.task(id))
        #expect(p.priority == .high)
        #expect(!p.dirty)
    }

    @Test("signing in drops untouched welcome items but keeps real work")
    func welcomeDropped() async throws {
        let email = newEmail()
        try await mac.signIn(email, register: true)
        try await mac.repo.addTask(title: "已有的任务")
        try await mac.sync()

        // A fresh install: welcome items, plus one the person ticked off and
        // one they wrote themselves.
        try await phone.repo.seedIfEmpty()
        let seeded = try await phone.tasks()
        let first = try #require(seeded.first)
        phone.advance()
        try await phone.repo.setCompleted(first.id, true)
        try await phone.repo.addTask(title: "离线时记的")

        try await phone.signIn(email)
        try await phone.sync()
        let titles = Set(try await phone.tasks().map(\.title))
        #expect(titles.isSuperset(of: ["已有的任务", "离线时记的", first.title]))
        #expect(titles.count == 3)

        try await mac.sync()
        #expect(try await mac.tasks().count == 3)
    }

    @Test("two installs that both kept the welcome items share one copy")
    func welcomeShared() async throws {
        let email = newEmail()
        try await phone.repo.seedIfEmpty()
        try await mac.repo.seedIfEmpty()
        // Both tick off the same welcome task, so neither drops it on sign-in.
        phone.advance()
        mac.advance(minutes: 2)
        try await phone.repo.setCompleted("seed-today", true)
        try await mac.repo.setCompleted("seed-today", true)

        try await phone.signIn(email, register: true)
        try await phone.sync()
        try await mac.signIn(email)
        try await mac.sync()
        try await phone.sync()
        for d in [phone, mac] {
            #expect(try await d.tasks().map(\.title) == ["看看“今天”和“最近7天”"])
        }
    }

    @Test("a repeating task: reminders and repeat travel, finishing it moves it on everywhere")
    func repeating() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)
        let id = try await phone.repo.addTask(
            title: "吃药",
            dueDate: Day(2026, 11, 15),
            dueTime: 8 * 60,
            reminders: [0, -10],
            repeatRule: "FREQ=DAILY;INTERVAL=2",
            repeatFrom: .completion
        )
        try await phone.sync()
        try await mac.sync()
        var t = try #require(try await mac.task(id))
        #expect(t.reminders == [0, -10])
        #expect(t.repeatRule == "FREQ=DAILY;INTERVAL=2")
        #expect(t.repeatFrom == .completion)

        mac.advance()
        let copyId = try #require(try await mac.repo.setCompleted(id, true)).copyId
        try await mac.sync()
        try await phone.sync()
        t = try #require(try await phone.task(id))
        #expect(t.dueDate == Day(2026, 11, 17))
        #expect(t.status == .open)
        let copy = try #require(try await phone.task(copyId))
        #expect(copy.status == .done)
        #expect(copy.dueDate == Day(2026, 11, 15))
    }

    @Test("both devices finishing the same occurrence offline leave one copy")
    func sameOccurrence() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)
        let id = try await phone.repo.addTask(title: "打卡", dueDate: Day(2026, 11, 15), repeatRule: "FREQ=DAILY")
        try await phone.sync()
        try await mac.sync()

        phone.advance()
        mac.advance(minutes: 2)
        try await phone.repo.setCompleted(id, true)
        try await mac.repo.setCompleted(id, true)
        try await phone.sync()
        try await mac.sync()
        try await phone.sync()

        for d in [phone, mac] {
            let tasks = try await d.tasks()
            #expect(tasks.count == 2, "the task and one finished copy")
            #expect(try await d.task(id)?.dueDate == Day(2026, 11, 16))
            #expect(tasks.filter { $0.status == .done }.count == 1)
        }
    }

    @Test("filters sync: create, edit, delete")
    func filters() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)

        let id = try await phone.repo.addFilter("本周重要", #"{"match":"all","conditions":[{"field":"date","values":["thisWeek"]}]}"#)
        #expect(try await phone.dirtyCount() == 1)
        try await phone.sync()
        try await mac.sync()
        let onMac = try #require(try await mac.filters().first)
        #expect(onMac.name == "本周重要")
        #expect(onMac.rule.contains("thisWeek"))
        #expect(try await mac.dirtyCount() == 0)

        mac.advance()
        try await mac.repo.updateFilter(id, name: "本周", rule: #"{"match":"any","conditions":[]}"#)
        try await mac.sync()
        try await phone.sync()
        let onPhone = try #require(try await phone.filters().first)
        #expect(onPhone.name == "本周")
        #expect(onPhone.rule == #"{"match":"any","conditions":[]}"#)

        phone.advance()
        try await phone.repo.deleteFilter(id)
        try await phone.sync()
        try await mac.sync()
        #expect(try await mac.filters().isEmpty)
        // Tombstone purged.
        #expect(try await mac.db.writer.read { try TaskFilter.fetchCount($0) } == 0)
    }

    @Test("sections and the order of tasks sync")
    func sections() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)

        let listId = try await phone.repo.addList("工作")
        let doing = try await phone.repo.addSection(listId, "进行中")
        let taskId = try await phone.repo.addTask(title: "写周报", listId: listId)
        phone.advance()
        try await phone.repo.placeTask(taskId, doing, [taskId: 512])
        try await phone.sync()
        try await mac.sync()
        #expect(try await mac.sections().map(\.name) == ["进行中"])
        let onMac = try #require(try await mac.task(taskId))
        #expect(onMac.sectionId == doing)
        #expect(onMac.sortOrder == 512.0)
        #expect(try await mac.dirtyCount() == 0)

        mac.advance()
        try await mac.repo.deleteSection(doing)
        try await mac.sync()
        try await phone.sync()
        #expect(try await phone.sections().isEmpty)
        #expect(try await phone.task(taskId)?.sectionId == nil)
        // Tombstone purged.
        #expect(try await phone.db.writer.read { try ListSection.fetchCount($0) } == 0)
    }

    @Test("a bad token reports that sign-in is needed")
    func badToken() async throws {
        try await phone.signIn(newEmail(), register: true)
        try phone.tokens.setToken("expired")
        await #expect {
            try await phone.sync()
        } throws: { error in
            (error as? SyncError)?.isAuth == true
        }
    }

    // MARK: Swift version only

    @Test("signing in with the wrong password, or to a server that isn't there")
    func signInErrors() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        await #expect(throws: SyncError("invalid_credentials", "邮箱或密码不正确")) {
            _ = try await AuthApi(session: mac.session).signIn(
                serverUrl: GoServer.current!.url, email: email, password: "wrong password", register: false
            )
        }
        await #expect(throws: SyncError("email_taken", "这个邮箱已经注册过，请直接登录")) {
            try await mac.signIn(email, register: true)
        }
        await #expect {
            _ = try await AuthApi(session: mac.session).signIn(serverUrl: "http://127.0.0.1:1", email: email, password: "x", register: false)
        } throws: { ($0 as? SyncError)?.code == "network" }
        await #expect(throws: SyncError("signed_out", "还没有登录")) { try await mac.sync() }
    }

    @Test("pages: more than one request's worth goes out and comes back")
    func paging() async throws {
        let email = newEmail()
        try await phone.signIn(email, register: true)
        try await mac.signIn(email)
        let small = SyncEngine(phone.db, session: phone.session, tokens: phone.tokens, pageSize: 3)
        for i in 0 ..< 7 { try await phone.repo.addTask(id: "t\(i)", title: "任务\(i)") }
        #expect(try await small.sync().pushed == 7)
        #expect(try await phone.dirtyCount() == 0)
        let report = try await SyncEngine(mac.db, session: mac.session, tokens: mac.tokens, pageSize: 2).sync()
        #expect(report.pulled == 7)
        #expect(try await mac.tasks().count == 7)
        #expect(try await mac.db.getValue(Keys.lastSyncedAt) != nil)
    }

    @Test("signing out clears the device")
    func signOut() async throws {
        try await phone.signIn(newEmail(), register: true)
        try await phone.repo.addTask(title: "x")
        try await phone.sync()
        let account = try #require(try await Account.load(phone.db, tokens: phone.tokens))
        await AuthApi(session: phone.session).signOut(account)
        try await clearLocalData(phone.db, tokens: phone.tokens)
        #expect(try await phone.tasks().isEmpty)
        #expect(try await Account.load(phone.db, tokens: phone.tokens) == nil)
    }
}
