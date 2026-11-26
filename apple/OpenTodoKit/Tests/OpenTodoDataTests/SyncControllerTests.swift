// SyncController (sync_providers.dart): signing in and out, syncing after
// local changes, errors. Against the real Go server, inside the
// integration suite (which starts it).

import Foundation
import Testing
@testable import OpenTodoData

@MainActor
func controller(_ d: Device) -> SyncController {
    SyncController(d.db, tokens: d.tokens, session: d.session, debounce: .milliseconds(50), interval: .seconds(3600))
}

extension SyncIntegrationTests {
    @Test("the controller: register, sync after a change, the other device sees it, sign out")
    @MainActor
    func controllerFlow() async throws {
        let server = try #require(GoServer.current)
        let email = newEmail()
        let a = controller(phone)
        await a.start()
        #expect(a.account == nil && a.status.phase == .signedOut)
        await a.syncNow() // signed out: nothing happens
        #expect(a.status.phase == .signedOut)

        try await a.signIn(serverUrl: server.url, email: email, password: "correct horse", register: true)
        #expect(a.account?.email == email)
        #expect(await eventually { a.status.phase == .idle && a.status.lastSyncedAt != nil })

        // A local change goes out on its own, shortly after.
        let id = try await phone.repo.addTask(title: "自动同步")
        #expect(await eventually { (try? await phone.dirtyCount()) == 0 })
        #expect(await eventually { a.status.phase == .idle })

        let b = controller(mac)
        try await b.signIn(serverUrl: server.url, email: email, password: "correct horse", register: false)
        #expect(await eventually { (try? await mac.task(id)) != nil })

        // A fresh controller picks the account up again, and its last sync.
        let again = controller(phone)
        await again.start()
        #expect(again.account?.email == email)
        #expect(again.status.lastSyncedAt != nil)
        again.stop()

        await a.signOut()
        #expect(a.account == nil && a.status.phase == .signedOut)
        #expect(try await phone.tasks().isEmpty)
        #expect(try phone.tokens.token() == nil)
        b.stop()
    }

    @Test("the controller: a failed sign-in changes nothing; a bad token is an error to act on")
    @MainActor
    func controllerErrors() async throws {
        let server = try #require(GoServer.current)
        let email = newEmail()
        let c = controller(phone)
        await c.start()
        await #expect(throws: SyncError("invalid_credentials", "邮箱或密码不正确")) {
            try await c.signIn(serverUrl: server.url, email: email, password: "nobody here", register: false)
        }
        #expect(c.account == nil && c.status.phase == .signedOut)

        try await c.signIn(serverUrl: server.url, email: email, password: "correct horse", register: true)
        #expect(await eventually { c.status.phase == .idle && c.status.lastSyncedAt != nil })
        try phone.tokens.setToken("expired")
        await c.syncNow()
        #expect(await eventually { c.status.phase == .error })
        #expect(c.status.error?.isAuth == true)
        #expect(c.status.error?.message == "登录已失效，请重新登录")
        #expect(c.status.lastSyncedAt != nil, "the last good sync is still shown")
        c.stop()
    }
}

@Suite @MainActor struct SyncControllerOfflineTests {
    @Test("signed out until there is a token; a server that isn't there is an error")
    func offline() async throws {
        let db = try AppDatabase.inMemory()
        let tokens = KeyValueTokenStore(db)
        let c = SyncController(db, tokens: tokens, debounce: .milliseconds(20), interval: .seconds(3600))
        await c.start()
        #expect(c.status == SyncStatus(.signedOut))
        // Changes waiting are counted even signed out (the sign-out warning).
        _ = try await TaskRepo(db).addTask(title: "没同步的")
        #expect(await eventually { c.pendingChanges == 1 })

        // Signed in earlier, to a server that is gone now.
        try await completeSignIn(db, Account(serverUrl: "http://127.0.0.1:1", token: "t", email: "a@example.com", userId: "u"), tokens: tokens)
        await c.start()
        #expect(c.account?.email == "a@example.com")
        #expect(await eventually { c.status.phase == .error })
        #expect(c.status.error?.code == "network")
        c.stop()
        #expect(c.status.phase == .signedOut)
    }
}
