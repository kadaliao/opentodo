// `SystemSync`: outside writes reach every registered model (the windows'
// and the menu bar / quick-add one), and widgets and Spotlight follow the
// database with no window at all. "Another process" is a second
// connection pool on the same file: its commits are invisible to the
// first pool's observations, exactly like a widget's or the share
// extension's.

import Foundation
import OpenTodoSystem
import Testing
@testable import OpenTodoUI

private func tempDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SystemSyncTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("opentodo.sqlite")
}

/// Waits (up to `seconds`) for `condition`.
private func eventually(_ seconds: Double = 10, _ condition: @MainActor () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@Suite(.serialized) @MainActor
struct SystemSyncTests {
    @Test func outsideWritesReachEveryRegisteredModel() async throws {
        let url = tempDatabaseURL()
        let app = try AppDatabase.open(at: url)
        let other = try AppDatabase.open(at: url) // the widget / share extension
        let sync = SystemSync(debounce: .milliseconds(10)) { _ in }
        sync.start(database: app)
        let window = AppModel(repo: TaskRepo(app))
        let menuBar = AppModel(repo: TaskRepo(app))
        await window.start(clock: false)
        await menuBar.start(clock: false)
        sync.register(window)
        sync.register(menuBar)
        sync.register(window) // twice: once
        #expect(sync.liveModels.count == 2)

        // Written by the other pool without a signal (that's the next test).
        let id = try await TaskRepo(other).addTask(title: "从分享扩展来的")
        // The app's own observation can't see it…
        try await Task.sleep(for: .milliseconds(200))
        #expect(window.task(id) == nil)
        // …the signal (or coming to the foreground) brings it in.
        await sync.externalChange()
        #expect(window.task(id)?.title == "从分享扩展来的")
        #expect(menuBar.task(id)?.title == "从分享扩展来的")
    }

    @Test func theDarwinSignalTriggersTheReread() async throws {
        let url = tempDatabaseURL()
        let app = try AppDatabase.open(at: url)
        let other = try AppDatabase.open(at: url)
        let sync = SystemSync(debounce: .milliseconds(10)) { _ in }
        sync.start(database: app)
        let model = AppModel(repo: TaskRepo(app))
        sync.register(model)
        // `add` posts `ChangeSignal`, as the extensions do.
        let id = try await SharedWriter(other).add(title: "快捷指令加的")
        #expect(await eventually { model.task(id) != nil })
    }

    @Test func widgetsAndSpotlightFollowTheDatabaseWithoutWindows() async throws {
        let url = tempDatabaseURL()
        let app = try AppDatabase.open(at: url)
        let other = try AppDatabase.open(at: url)
        var refreshed: [TaskData] = []
        let sync = SystemSync(debounce: .milliseconds(50)) { refreshed.append($0) }
        sync.start(database: app)
        #expect(sync.liveModels.isEmpty) // no window at all
        #expect(await eventually { refreshed.count == 1 }) // the first snapshot

        // A write in this process (the menu bar's quick add, say).
        let repo = TaskRepo(app)
        let a = try await repo.addTask(title: "一")
        let b = try await repo.addTask(title: "二")
        #expect(await eventually { refreshed.last?.tasks.contains { $0.id == b } == true })
        // Debounced: the two writes made one refresh.
        try await Task.sleep(for: .milliseconds(150))
        let afterTwo = refreshed.count
        #expect(afterTwo == 2)
        #expect(refreshed.last?.tasks.contains { $0.id == a } == true)

        // A write by another process, once it's signalled.
        let c = try await SharedWriter(other).add(title: "三")
        #expect(await eventually { refreshed.last?.tasks.contains { $0.id == c } == true })
        #expect(refreshed.count > afterTwo)
    }

    @Test func modelsAreHeldWeakly() async throws {
        let db = try AppDatabase.inMemory()
        let sync = SystemSync { _ in }
        sync.start(database: db)
        var model: AppModel? = AppModel(repo: TaskRepo(db))
        sync.register(model!)
        #expect(sync.liveModels.count == 1)
        model = nil
        #expect(sync.liveModels.isEmpty)
    }

    @Test func startsOnce() throws {
        let a = try AppDatabase.inMemory(), b = try AppDatabase.inMemory()
        let sync = SystemSync { _ in }
        sync.start(database: a)
        sync.start(database: b)
        #expect(sync.database === a)
    }

    @Test func modelsOnAnotherDatabaseAreLeftAlone() async throws {
        let url = tempDatabaseURL()
        let app = try AppDatabase.open(at: url)
        let other = try AppDatabase.open(at: url)
        let elsewhere = try AppDatabase.inMemory()
        let sync = SystemSync { _ in }
        sync.start(database: app)
        let stranger = AppModel(repo: TaskRepo(elsewhere))
        sync.register(stranger)
        _ = try await TaskRepo(other).addTask(title: "x")
        await sync.externalChange()
        #expect(stranger.data.tasks.isEmpty)
    }
}
