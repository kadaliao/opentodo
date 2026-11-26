// The process's side of the system integration, independent of windows:
// the app shell starts it once (`SystemSync.shared.start(database:)`) and
// it runs until the process ends — with every window closed too (macOS
// keeps running for the menu bar window and the quick-add shortcut).
//
// - Writes by other processes (a widget's 完成, the share extension, an
//   App Intent) can't reach GRDB's observations here, so when one says so
//   (`ChangeSignal`) or the app comes to the foreground, every registered
//   `AppModel` — each window's, and the menu bar window's and quick-add
//   panel's — reads the data again.
// - The widgets and the Spotlight index follow the database itself (one
//   observation per process, not per window), a second after changes
//   settle; an outside write counts as a change too.
//
// Windows register their model through `SystemIntegration`; the accessory
// model registers itself (`SystemServices`).

import Foundation
import OpenTodoSystem
import WidgetKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
public final class SystemSync {
    public static let shared = SystemSync()

    /// How long changes must settle before widgets and Spotlight refresh.
    var debounce: Duration
    /// What a refresh does: reload the widgets, rebuild the Spotlight index.
    var refresh: @MainActor (TaskData) async -> Void

    private(set) var database: AppDatabase?
    private var models: [Weak] = []
    private var latest: TaskData = .empty
    private var signal: AnyObject?
    private var observations: [ObservationHandle] = []
    private var activeObserver: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?

    private struct Weak {
        weak var model: AppModel?
    }

    init(debounce: Duration = .seconds(1), refresh: @escaping @MainActor (TaskData) async -> Void = SystemSync.refreshSystem) {
        self.debounce = debounce
        self.refresh = refresh
    }

    /// Starts watching `database` (the app's, `AppServices.database`), the
    /// signal from other processes, and the app coming to the foreground.
    /// Once; later calls do nothing.
    public func start(database: AppDatabase) {
        guard self.database == nil else { return }
        self.database = database
        observations = [
            database.observeTaskData().start { [weak self] data in
                self?.latest = data
                self?.changed()
            },
            // The widgets also show habits, countdowns and focus.
            database.observeHabits().map(\.count).start { [weak self] _ in self?.changed() },
            database.observeCheckins().map(\.count).start { [weak self] _ in self?.changed() },
            database.observeCountdowns().map { $0.map(\.updatedAt) }.start { [weak self] _ in self?.changed() },
            database.observeFocusSessions().map(\.count).start { [weak self] _ in self?.changed() },
        ]
        signal = ChangeSignal.observe { [weak self] in
            Task { await self?.externalChange() }
        }
        #if os(macOS)
        let active = NSApplication.didBecomeActiveNotification
        #else
        let active = UIApplication.didBecomeActiveNotification
        #endif
        activeObserver = NotificationCenter.default.addObserver(forName: active, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                _ = Task { await SystemSync.shared.externalChange() }
            }
        }
    }

    /// Keeps `model` up to date with outside writes while it lives (held
    /// weakly; registering twice is harmless).
    public func register(_ model: AppModel) {
        models.removeAll { $0.model == nil }
        guard !models.contains(where: { $0.model === model }) else { return }
        models.append(Weak(model: model))
    }

    /// The registered models still alive.
    var liveModels: [AppModel] {
        models.removeAll { $0.model == nil }
        return models.compactMap(\.model)
    }

    /// Another process may have written: read the data once and hand it to
    /// every model on this database that hasn't got it; then refresh.
    func externalChange() async {
        guard let database, let data = try? await database.observeTaskData().first() else { return }
        // A model that has started but not had its first snapshot yet gets
        // it from its own observation (after seeding); handing it one now
        // would mark it loaded early and run its launch route (`task:<id>`)
        // on a database still being filled.
        for model in liveModels where !model.awaitingFirstSnapshot && model.database === database && model.data != data {
            model.receive(data)
        }
        latest = data
        changed()
    }

    private func changed() {
        pending?.cancel()
        let debounce = self.debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            await self.refresh(self.latest)
        }
    }

    /// Reload every widget and index the open tasks for Spotlight.
    static func refreshSystem(_ data: TaskData) async {
        WidgetCenter.shared.reloadAllTimelines()
        await Spotlight.index(spotlightEntries(data.tasks, lists: data.lists, today: Day.today()))
    }
}
