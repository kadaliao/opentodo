// Everything the app runs on, made once at launch in the right order, for
// the UI to take from (AppModel, the settings and account screens):
//
//     let services = try AppServices.launch()              // or launch(databaseURL:) in debug
//     await services.start()                               // at launch (the App's init / first .task)
//     services.appDidBecomeActive()                        // scenePhase == .active
//     services.appDidEnterBackground()                     // scenePhase == .background
//
// `launch` opens the database (backing up a Flutter one, moving into the
// App Group container when there is one), picks the token store (the
// keychain; key_values where the keychain can't be used) and moves a token
// the Flutter version left in the database into it. `start` sets up
// reminders first, so a notification the app was launched from is handled,
// then the welcome list on a fresh install, then sync.

import Foundation
import GRDB
import Observation

@MainActor @Observable
public final class AppServices {
    public let database: AppDatabase
    public let tokens: any TokenStore
    public let settings: LocalSettings
    public let repo: TaskRepo
    public let efficiency: EfficiencyRepo
    /// The one focus timer every window shows (FocusTimerStore.swift).
    public let focusTimer: FocusTimerStore
    public let sync: SyncController
    public let reminders: ReminderController
    /// Background and foreground, for the database's suspension.
    public let lifecycle: AppLifecycle

    @ObservationIgnored private var started = false

    public init(
        database: AppDatabase,
        tokens: any TokenStore,
        reminderBackend: any ReminderBackend,
        session: URLSession = .shared,
        clock: @escaping @Sendable () -> Date = { Date() },
        lifecycleHooks: AppLifecycle.Hooks = .system
    ) {
        self.database = database
        self.tokens = tokens
        let settings = LocalSettings(database)
        self.settings = settings
        repo = TaskRepo(database, clock: clock, defaults: settings.defaultsProvider, tokens: tokens)
        efficiency = EfficiencyRepo(database, clock: clock)
        focusTimer = FocusTimerStore(settings: settings, repo: efficiency, clock: clock)
        sync = SyncController(database, tokens: tokens, session: session)
        let current = settings.snapshotProvider
        let lifecycle = AppLifecycle(hooks: lifecycleHooks)
        self.lifecycle = lifecycle
        reminders = ReminderController(database, repo: repo, backend: reminderBackend, settings: current, clock: clock, lifecycle: lifecycle)
    }

    /// The services on the app's real database (or `databaseURL`), the
    /// system's notifications and the keychain.
    public static func launch(
        databaseURL: URL? = nil,
        reminderBackend: (any ReminderBackend)? = nil,
        tokens: (any TokenStore)? = nil
    ) throws -> AppServices {
        let database = try AppDatabase.open(at: databaseURL)
        let store = tokens ?? defaultTokenStore(for: database)
        // Not a reason to fail the launch (the app would fall back to an
        // empty database): the token stays in the database and moves at
        // the next launch; until then the device shows signed out.
        try? moveLegacyToken(from: database, into: store)
        let backend = reminderBackend ?? {
            let system = SystemReminderBackend()
            system.listenEarly()
            return system
        }()
        return AppServices(database: database, tokens: store, reminderBackend: backend)
    }

    /// Starts reminders, the welcome list (fresh installs, `seed`) and
    /// sync, once.
    public func start(seed: Bool = true) async {
        guard !started else { return }
        started = true
        await reminders.start()
        if seed { try? await repo.seedIfEmpty() }
        await sync.start()
    }

    /// Back in the foreground: the database's locks may be taken again,
    /// the permission and the time may have changed, sync catches up.
    public func appDidBecomeActive() {
        lifecycle.enterForeground()
        reminders.appDidBecomeActive()
        sync.appDidBecomeActive()
    }

    /// In the background a process holding a lock on a database in a shared
    /// container is killed (0xdead10cc); GRDB lets go of it here. Only on
    /// iOS: a Mac window that is hidden or minimized also reports
    /// `.background`, and suspending there would stop every other window,
    /// the menu bar panel, sync and the notification buttons from writing.
    public func appDidEnterBackground() {
        #if os(iOS)
        lifecycle.enterBackground()
        #endif
    }
}
