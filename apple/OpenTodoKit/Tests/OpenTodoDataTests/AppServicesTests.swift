// AppServices: what the app starts with, in order.

import Foundation
import Testing
@testable import OpenTodoData

@Suite @MainActor struct AppServicesTests {
    @Test("launch moves the old token, start seeds a fresh install and reminds with the person's defaults")
    func launch() async throws {
        let dir = try TempDir()
        let url = dir.file()
        // What the Flutter version left: an account in key_values, token
        // and all (its `Account.save` writes the four together).
        let old = try AppDatabase.open(at: url)
        try old.setValueNow(Keys.server, "http://127.0.0.1:1")
        try old.setValueNow(Keys.token, "flutter-token")
        try old.setValueNow(Keys.email, "a@example.com")
        try old.setValueNow(Keys.userId, "u")
        try old.setValueNow(Keys.settings, #"{"snoozeMinutes":7}"#)
        try old.close()

        let keychain = MemoryTokenStore()
        let system = MemoryReminderBackend()
        let services = try AppServices.launch(databaseURL: url, reminderBackend: system, tokens: keychain)
        #expect(try keychain.token() == "flutter-token")
        #expect(try services.database.getValueNow(Keys.token) == nil)
        #expect(services.settings.settings.snoozeMinutes == 7)

        await services.start()
        // Signed in (the token moved over), so no welcome list.
        #expect(services.sync.account == Account(serverUrl: "http://127.0.0.1:1", token: "flutter-token", email: "a@example.com", userId: "u"))
        #expect(try await services.database.observeTasks().first().isEmpty)
        services.sync.stop()
    }

    @Test("a fresh install gets the welcome list; the defaults reach new tasks")
    func fresh() async throws {
        let services = AppServices(database: try AppDatabase.inMemory(), tokens: MemoryTokenStore(), reminderBackend: MemoryReminderBackend())
        await services.start()
        #expect(try await services.database.observeTasks().first().count == 4)
        #expect(services.sync.status.phase == .signedOut)
        services.settings.setDefaults(TaskDefaults(timedReminders: [-5]))
        let id = try await services.repo.addTask(title: "新的")
        try await services.repo.setDue(id, Day(2026, 11, 20), 600)
        #expect(try await services.repo.getTask(id)?.reminders == [-5])
        await services.start() // once only
        #expect(try await services.database.observeTasks().first().count == 5)
        services.appDidEnterBackground()
        services.appDidBecomeActive()
        services.reminders.stop()
    }
}

/// The app runs for days (iOS keeps it in the background) and the device
/// may change time zones meanwhile: "today", repeats and the moments
/// reminders go off follow the device's zone now, as Dart's local
/// `DateTime` does, not the one it had at launch.
@Suite @MainActor struct TimeZoneTests {
    @Test("the services follow the device's time zone, not the one at launch")
    func followsDevice() async throws {
        let services = AppServices(database: try AppDatabase.inMemory(), tokens: MemoryTokenStore(), reminderBackend: MemoryReminderBackend())
        #expect(services.repo.timeZone == .autoupdatingCurrent)
        #expect(services.efficiency.timeZone == .autoupdatingCurrent)
        #expect(services.reminders.timeZone == .autoupdatingCurrent)
        #expect(await ReminderScheduler(MemoryReminderBackend()).timeZone == .autoupdatingCurrent)
    }
}

/// A keychain that can't be read right now (locked, say).
struct FailingTokenStore: TokenStore {
    struct Failure: Error {}
    func token() throws -> String? { throw Failure() }
    func setToken(_ token: String?) throws { throw Failure() }
}

@Suite @MainActor struct LaunchFailureTests {
    @Test("a keychain that fails at launch doesn't stop the app opening its database; the old token stays put for next time")
    func keychainFails() throws {
        let dir = try TempDir()
        let url = dir.file()
        let old = try AppDatabase.open(at: url)
        try old.setValueNow(Keys.server, "http://x")
        try old.setValueNow(Keys.token, "flutter-token")
        try old.writer.write { try TodoTask(id: "a", title: "旧任务").insert($0) }
        try old.close()

        let services = try AppServices.launch(databaseURL: url, reminderBackend: MemoryReminderBackend(), tokens: FailingTokenStore())
        #expect(services.database.url == url)
        #expect(try services.database.getValueNow(Keys.token) == "flutter-token")
    }
}
