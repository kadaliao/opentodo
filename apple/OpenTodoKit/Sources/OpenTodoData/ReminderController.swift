// Schedules reminders (tasks', habits', countdowns', in one budget)
// whenever any of them change (after 0.5 s of quiet), when
// the app comes back to the foreground, and every 15 minutes as later
// reminders move into the window the system holds (the soonest 48); carries
// out what the person does with a notification. Ported from
// `ReminderController` in `app/lib/state/reminder_providers.dart`.
//
//     let reminders = ReminderController(db, repo: repo, backend: SystemReminderBackend(),
//                                        settings: { settings.current })
//     await reminders.start()               // at launch, before the first response can arrive
//     reminders.appDidBecomeActive()        // from scenePhase == .active
//     reminders.allowed                     // nil until asked; false: show 去开启
//     reminders.openRequest                 // .task / .habit / .countdown opened from a
//                                           // notification; the UI goes there and sets it to nil

import Foundation
import Observation

@MainActor @Observable
public final class ReminderController {
    /// Bumped when the notifications handed to the system change shape, so
    /// the ones already there are replaced: 2 added the 完成 and 稍后提醒
    /// buttons. (The same number as the Flutter version: its notifications
    /// already have them.)
    public static let reminderFormat = "2"

    /// Whether notifications are allowed (nil until there was a reminder
    /// to ask about).
    public private(set) var allowed: Bool?

    /// What the person opened from a notification (a task, or the habits
    /// or countdowns page at one of them), waiting for the UI to show it.
    /// The UI sets it back to nil.
    public var openRequest: ReminderOpenRequest?

    /// The last thing that went wrong scheduling or carrying out a button.
    public private(set) var lastError: (any Error)?

    public let database: AppDatabase
    public let repo: TaskRepo
    public let backend: any ReminderBackend
    /// Keeps the database usable and the process running while a button
    /// is handled in the background (iOS); nil where that doesn't apply.
    @ObservationIgnored private let lifecycle: AppLifecycle?
    @ObservationIgnored private let scheduler: ReminderScheduler
    @ObservationIgnored private let settings: @Sendable () -> AppSettings
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored public let timeZone: TimeZone
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let refresh: Duration

    @ObservationIgnored private var sources: ReminderSources?
    @ObservationIgnored private var observation: ObservationHandle?
    @ObservationIgnored private var periodic: Task<Void, Never>?
    @ObservationIgnored private var pendingRun: Task<Void, Never>?
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false

    public init(
        _ database: AppDatabase,
        repo: TaskRepo,
        backend: any ReminderBackend,
        settings: @escaping @Sendable () -> AppSettings = { AppSettings() },
        clock: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .autoupdatingCurrent,
        debounce: Duration = .milliseconds(500),
        refresh: Duration = .seconds(15 * 60),
        lifecycle: AppLifecycle? = nil
    ) {
        self.lifecycle = lifecycle
        self.database = database
        self.repo = repo
        self.backend = backend
        self.settings = settings
        self.clock = clock
        self.timeZone = timeZone
        self.debounce = debounce
        self.refresh = refresh
        scheduler = ReminderScheduler(backend, timeZone: timeZone)
    }

    /// Sets up the system side and starts watching the tasks.
    public func start() async {
        guard observation == nil else { return }
        let since = Day(clock(), in: timeZone).startOfWeek - 7
        observation = database.observe { try ReminderSources.fetch($0, since: since) }
            .start(onError: { [weak self] in self?.lastError = $0 }) { [weak self] sources in
                self?.sources = sources
                self?.kick()
            }
        await backend.start { [weak self] r in
            await self?.handle(r)
        }
        periodic = Task { [weak self, refresh] in
            while !Task.isCancelled {
                try? await Task.sleep(for: refresh)
                self?.kick()
            }
        }
        ready = true
        kick()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        periodic?.cancel()
        pendingRun?.cancel()
        ready = false
    }

    /// Back in the foreground: the person may have changed the permission
    /// in Settings, and time has passed.
    public func appDidBecomeActive() {
        Task {
            await scheduler.recheckPermission()
            kick()
        }
    }

    /// Reads the permission as it stands, without asking (for 设置): nil
    /// while never asked, then whether it is allowed.
    public func refreshPermission() async {
        switch await backend.permission() {
        case .notDetermined: allowed = nil
        case .denied: allowed = false
        case .allowed: allowed = true
        }
    }

    /// A notification clicked (the UI shows its task, habit or countdown)
    /// or one of its buttons pressed: carried out, and the system's
    /// reminders brought in line, before this returns. What the backend
    /// calls, and a way in for debug builds and tests.
    public func handle(_ r: ReminderResponse) async {
        if r.action == .open || r.kind != .task {
            openRequest = ReminderOpenRequest(r)
            return
        }
        if let lifecycle {
            await lifecycle.awake("提醒按钮") { await act(r) }
        } else {
            await act(r)
        }
    }

    /// For the 去开启 button: the system settings, where a refusal is undone.
    public func openSettings() async {
        await backend.openSettings()
    }

    /// Schedules after the debounce, once, however many times it is asked.
    func kick() {
        pendingRun?.cancel()
        pendingRun = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    /// 完成 / 稍后提醒: the write, then reminders handed over again from what
    /// is stored now (the app may be suspended as soon as this returns, so
    /// it doesn't wait for the observation or the debounce).
    private func act(_ r: ReminderResponse) async {
        let now = clock()
        do {
            try await applyReminderAction(repo, Snoozes(database), r, now: now, snoozeMinutes: settings().snoozeMinutes)
            let since = Day(now, in: timeZone).startOfWeek - 7
            sources = try await database.writer.read { try ReminderSources.fetch($0, since: since) }
        } catch {
            lastError = error
        }
        while running { try? await Task.sleep(for: .milliseconds(20)) }
        await run(evenBeforeStart: true)
    }

    func run(evenBeforeStart: Bool = false) async {
        guard ready || evenBeforeStart else { return }
        if running {
            again = true
            return
        }
        running = true
        defer { running = false }
        do {
            repeat {
                again = false
                guard let sources else { break }
                let now = clock()
                // Snoozes may also come from a button handled elsewhere.
                let snoozed = try await Snoozes(database).upcoming(now)
                let replaceAll = try await database.getValue(Keys.reminderFormat) != Self.reminderFormat
                try await scheduler.apply(reminderEvents(sources, now: now, snoozed: snoozed, timeZone: timeZone), replaceAll: replaceAll)
                if replaceAll { try await database.setValue(Keys.reminderFormat, Self.reminderFormat) }
                allowed = await scheduler.allowed
            } while again
            lastError = nil
        } catch {
            lastError = error
        }
    }
}
