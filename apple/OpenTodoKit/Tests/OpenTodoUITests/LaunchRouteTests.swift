// iOS QA, 2026-11-26: `-OTOpen task:<id>` on a phone showed the views list.
// SystemSync handed the window's model a snapshot of the database while its
// demo data was still being written; the model counted as loaded, ran the
// route, found no task and dropped it.

import Foundation
import OpenTodoData
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

@Suite @MainActor
struct LaunchRouteTests {
    @Test func aSnapshotFromOutsideWaitsUntilTheModelHasSeeded() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchRouteTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("opentodo.sqlite")
        let db = try AppDatabase.open(at: url)
        let repo = TaskRepo(db)
        let seeding = AsyncStream<Void>.makeStream()
        let model = AppModel(repo: repo) {
            // Seeding takes a while; it's done when told.
            for await _ in seeding.stream { break }
            try? await repo.addTask(id: "report", title: "写周报")
        }
        let sync = SystemSync(debounce: .milliseconds(10)) { _ in }
        sync.start(database: db)
        sync.register(model)
        model.applyWhenLoaded(.task("report"))
        let started = Task { await model.start(clock: false) }

        // Something else wrote meanwhile: the model isn't handed the half-seeded data.
        await sync.externalChange()
        #expect(!model.loaded)

        seeding.continuation.yield()
        await started.value
        for _ in 0..<200 where model.selectedTaskId == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.loaded)
        #expect(model.selectedTaskId == "report") // the route ran on the seeded data
    }
}
