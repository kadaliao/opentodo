// `-OTOpen selftest:<name>` (debug builds): runs a check on the real
// services (AppServices with the system's notifications and the keychain)
// in the running app, prints `OT-SELFTEST …` lines and quits with 0 when
// it passed, 1 when not. For the simulator and the signed macOS build,
// where `swift test` can't reach (no app bundle, no keychain entitlement):
//
//     selftest:reminders                 a reminder a minute ahead is delivered
//                                        (provisional permission, no prompt);
//                                        稍后提醒 schedules it again, 完成 ticks it off
//     selftest:signin,<server>           registers on <server>; the token is in the
//                                        keychain, not in the database
//     selftest:signedin                  (next launch) still signed in, from the keychain
//     selftest:signout                   signs out; the keychain has no token left
//     selftest:signedout                 (next launch) still signed out
//     selftest:suspend                   the database really suspended in the background
//                                        (GRDB's notifications), and a 完成 pressed there
//                                        still written, inside `AppLifecycle.awake`
//
// The database is the one `-OTDatabasePath` names (use the same one across
// the keychain steps).

import Foundation
import OpenTodoData
import OpenTodoDomain
import Synchronization
import SwiftUI

struct ServicesSelfTestScreen: View {
    let name: String
    let databaseURL: URL?
    @State private var lines: [String] = []

    var body: some View {
        List(lines, id: \.self) { Text($0).uiFont(.caption) { $0.monospaced() } }
            .task { await run() }
    }

    /// Printed, shown, and appended to `tmp/selftest.log` in the app's
    /// container (stdout is buffered when it isn't a terminal).
    private func say(_ s: String) {
        print("OT-SELFTEST \(s)")
        lines.append(s)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "selftest.log")
        let line = Data("OT-SELFTEST \(s)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line)
            try? h.close()
        } else {
            try? line.write(to: url)
        }
    }

    private func finish(_ ok: Bool) async {
        say(ok ? "PASS \(name)" : "FAIL \(name)")
        try? await Task.sleep(for: .milliseconds(300))
        exit(ok ? 0 : 1)
    }

    private func check(_ ok: Bool, _ what: String) -> Bool {
        say("\(ok ? "ok  " : "BAD ") \(what)")
        return ok
    }

    private func run() async {
        let parts = name.split(separator: ",", maxSplits: 1).map(String.init)
        do {
            switch parts[0] {
            case "reminders": await finish(try await reminders())
            case "signin": await finish(try await signIn(server: parts.count > 1 ? parts[1] : "http://127.0.0.1:8686"))
            case "signedin": await finish(try await signedIn())
            case "signout": await finish(try await signOut())
            case "signedout": await finish(try await signedOut())
            case "suspend": await finish(try await suspension())
            default:
                say("unknown self-test \(name)")
                await finish(false)
            }
        } catch {
            say("error: \(error)")
            await finish(false)
        }
    }

    // MARK: Reminders

    private func reminders() async throws -> Bool {
        let shown = ShownTitles()
        let backend = SystemReminderBackend(provisional: true) { title in shown.add(title) }
        let services = try AppServices.launch(databaseURL: databaseURL, reminderBackend: backend, tokens: KeyValueTokenStore(try AppDatabase.inMemory()))
        await services.start(seed: false)
        var ok = true

        // Due at the next whole minute that is at least 20 s away.
        let now = Date()
        let next = LocalDateTime(now.addingTimeInterval(80))
        let at = LocalDateTime(next.day, minute: next.minuteOfDay)
        let id = try await services.repo.addTask(title: "自检提醒", dueDate: at.day, dueTime: at.minuteOfDay, reminders: [0])
        say("task due \(at.key), now \(LocalDateTime(now).key):\(Calendar.current.component(.second, from: now))")
        // The simulator's notification service can stop answering (seen on
        // iOS 27 under heavy load, `simctl push` hanging too): say so
        // rather than wait for ever.
        guard let before = await within(.seconds(20), { await backend.permission() }) else {
            say("BLOCKED the system's notification service doesn't answer (UNUserNotificationCenter.notificationSettings)")
            return false
        }
        say("permission before: \(before)")

        // Scheduled (permission asked for the first time, provisionally).
        var pending: [PendingReminder] = []
        for _ in 0 ..< 50 where pending.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
            pending = await within(.seconds(10)) { await backend.pending() } ?? []
        }
        ok = check(pending.map(\.title) == ["自检提醒"], "scheduled with the system: \(pending.map { $0.title ?? "" })") && ok
        let permission = await within(.seconds(10)) { await backend.permission() }
        say("permission after asking: \(String(describing: permission)); the controller says \(String(describing: services.reminders.allowed))")

        if permission == .denied {
            // Turned off for this app in System Settings: the system keeps
            // the request but shows nothing. Nothing to wait for.
            ok = check(services.reminders.allowed == false, "the controller knows they're off (设置 shows 去开启)") && ok
            say("SKIP delivery: notifications are turned off for this app in System Settings")
        } else {
            ok = check(services.reminders.allowed == true, "permission given") && ok
            // Delivered at its time, shown while the app is in front.
            let deadline = at.date().addingTimeInterval(15)
            while Date() < deadline && !shown.contains("自检提醒") { try await Task.sleep(for: .milliseconds(250)) }
            ok = check(shown.contains("自检提醒"), "delivered at \(LocalDateTime(Date()).key) (willPresent)") && ok
            let delivered = await within(.seconds(10)) { await backend.delivered() } ?? []
            ok = check(delivered.contains { $0.title == "自检提醒" }, "in the notification centre: \(delivered.map { $0.title ?? "" })") && ok
        }

        // 稍后提醒: handed over again, 15 minutes on.
        await services.reminders.handle(ReminderResponse(taskId: id, action: .snooze))
        var later: Date?
        for _ in 0 ..< 30 where later == nil {
            try await Task.sleep(for: .milliseconds(200))
            if let snoozes = try? await Snoozes(services.database).load() { later = snoozes[id] }
        }
        ok = check(later.map { abs($0.timeIntervalSinceNow - 15 * 60) < 60 } == true, "snoozed until \(later.map { LocalDateTime($0).key } ?? "-")") && ok
        try await Task.sleep(for: .seconds(1.5))
        let snoozed = await within(.seconds(10)) { await backend.pending() } ?? []
        // The snooze, and the original one too if it hasn't gone off (it
        // hasn't when delivery was skipped).
        let expected = permission == .denied ? 2 : 1
        ok = check(snoozed.count == expected && snoozed.allSatisfy { $0.title == "自检提醒" },
                   "the snoozed reminder is with the system: \(snoozed.map { $0.title ?? "" })") && ok

        // 完成: ticked off, nothing pending any more.
        await services.reminders.handle(ReminderResponse(taskId: id, action: .done))
        var status: TaskStatus = .open
        for _ in 0 ..< 30 where status != .done {
            try await Task.sleep(for: .milliseconds(200))
            status = try await services.repo.getTask(id)?.status ?? .open
        }
        ok = check(status == .done, "完成 ticked the task off") && ok
        try await Task.sleep(for: .seconds(1.5))
        let left = await within(.seconds(10)) { await backend.pending() }
        ok = check(left?.isEmpty == true, "nothing left with the system: \(left.map { $0.map { $0.title ?? "" } } ?? ["(no answer)"])") && ok
        _ = await within(.seconds(5)) { await backend.clearDelivered() }

        // A click on a habit's notification opens the habits page.
        await services.reminders.handle(ReminderResponse(taskId: "h1", action: .open, kind: .habit))
        try await Task.sleep(for: .milliseconds(200))
        ok = check(services.reminders.openRequest == .habit("h1"), "a habit notification opens the habits page") && ok
        return ok
    }

    // MARK: Suspension

    private func suspension() async throws -> Bool {
        let system = MemoryReminderBackend(allow: true, asked: true)
        let services = try AppServices.launch(databaseURL: databaseURL, reminderBackend: system, tokens: KeyValueTokenStore(try AppDatabase.inMemory()))
        await services.start(seed: false)
        let repo = services.repo
        let id = try await repo.addTask(title: "后台完成", dueDate: Day.today(), dueTime: 23 * 60 + 59, reminders: [0])
        func writes() async -> Bool {
            (try? await repo.setContent(id, "试写 \(Date().timeIntervalSince1970)")) != nil
        }
        var ok = check(await writes(), "writes in the foreground")
        services.lifecycle.enterBackground() // what appDidEnterBackground does on iOS
        ok = check(!(await writes()), "suspended in the background: a write is refused") && ok
        await system.respond(ReminderResponse(taskId: id, action: .done))
        let status = try await repo.getTask(id)?.status
        ok = check(status == .done, "完成 pressed in the background was written") && ok
        ok = check(!(await writes()), "suspended again afterwards") && ok
        services.lifecycle.enterForeground()
        ok = check(await writes(), "writes again in the foreground") && ok
        return ok
    }

    // MARK: Keychain

    private func keychainServices() throws -> (AppServices, any TokenStore) {
        let services = try AppServices.launch(databaseURL: databaseURL, reminderBackend: MemoryReminderBackend())
        if let k = services.tokens as? KeychainTokenStore {
            say("token store: keychain (\(k.dataProtection ? "data protection" : "login keychain"))")
        } else {
            say("token store: \(type(of: services.tokens))")
        }
        return (services, services.tokens)
    }

    private func signIn(server: String) async throws -> Bool {
        let (services, tokens) = try keychainServices()
        await services.start(seed: false)
        var ok = check(tokens is KeychainTokenStore, "the keychain is used")
        let email = "selftest-\(UUID().uuidString.prefix(8).lowercased())@example.com"
        try await services.sync.signIn(serverUrl: server, email: email, password: "correct horse", register: true)
        ok = check(services.sync.account?.email == email, "signed in as \(email)") && ok
        ok = check(try tokens.token()?.isEmpty == false, "a token in the keychain") && ok
        ok = check(try services.database.getValueNow(Keys.token) == nil, "no token in the database") && ok
        for _ in 0 ..< 50 where services.sync.status.phase != .idle || services.sync.status.lastSyncedAt == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        ok = check(services.sync.status.lastSyncedAt != nil, "first sync done (\(services.sync.status.phase))") && ok
        return ok
    }

    private func signedIn() async throws -> Bool {
        let (services, tokens) = try keychainServices()
        await services.start(seed: false)
        var ok = check(try tokens.token() != nil, "the keychain still has the token")
        ok = check(services.sync.account != nil, "still signed in: \(services.sync.account?.email ?? "-")") && ok
        return ok
    }

    private func signedOut() async throws -> Bool {
        let (services, tokens) = try keychainServices()
        await services.start(seed: false)
        return check(try tokens.token() == nil, "no token in the keychain") && check(services.sync.account == nil, "signed out")
    }

    private func signOut() async throws -> Bool {
        let (services, tokens) = try keychainServices()
        await services.start(seed: false)
        let ok = check(services.sync.account != nil, "signed in before")
        await services.sync.signOut()
        return check(try tokens.token() == nil, "no token left in the keychain") && check(services.sync.account == nil, "signed out") && ok
    }
}

/// `body`'s result, or nil if it takes longer than `limit`. A call that
/// never returns is left behind (a task group would wait for it).
@MainActor
private func within<T: Sendable>(_ limit: Duration, _ body: @escaping @Sendable () async -> T) async -> T? {
    let once = Once<T?>()
    return await withCheckedContinuation { continuation in
        once.set(continuation)
        Task.detached { once.resume(await body()) }
        Task.detached {
            try? await Task.sleep(for: limit)
            once.resume(nil)
        }
    }
}

/// Resumes a continuation once, whoever comes first.
nonisolated private final class Once<T: Sendable>: Sendable {
    private let state = Mutex<(CheckedContinuation<T, Never>?, Bool)>((nil, false))
    func set(_ c: CheckedContinuation<T, Never>) { state.withLock { $0.0 = c } }
    func resume(_ value: T) {
        let c: CheckedContinuation<T, Never>? = state.withLock { s in
            guard !s.1, let c = s.0 else { return nil }
            s.1 = true
            return c
        }
        c?.resume(returning: value)
    }
}

/// Titles of notifications shown, from the delegate's thread.
nonisolated private final class ShownTitles: Sendable {
    private let titles = Mutex<[String]>([])
    func add(_ t: String) { titles.withLock { $0.append(t) } }
    func contains(_ t: String) -> Bool { titles.withLock { $0.contains(t) } }
}
