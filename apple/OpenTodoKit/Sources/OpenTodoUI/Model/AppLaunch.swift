// Opening the app's data. `launchServices` makes the `AppServices` once for
// the whole app (the App holds it; every window and the Settings window
// share it): the real database with the system's notifications and the
// keychain — or, for a debug launch with `-OTDatabasePath` (screenshots,
// UI tests), that file with notifications kept in memory and the token in
// the database, so no system prompt shows. `forLaunch` makes a window's
// `AppModel` on it; its `start()` starts the services (reminders, the
// welcome list on a fresh install, sync) — or, for `-OTSeed demo`, fills
// the demo instead of the welcome list.
//
// If the database can't be opened the app still comes up, on an empty
// in-memory one, and says so.

import Foundation
import OpenTodoData
import OpenTodoDomain

extension AppModel {
    public static func launchServices(_ debug: DebugLaunch?) -> AppServices {
        if let size = debug?.interfaceSize { InterfacePrefs.overrideForThisRun(size) }
        #if os(macOS)
        if debug?.hiddenWindows == true { DebugHiddenWindows.install() }
        #endif
        do {
            if let url = debug?.databaseURL {
                let db = try AppDatabase.open(at: url)
                return AppServices(database: db, tokens: KeyValueTokenStore(db), reminderBackend: MemoryReminderBackend())
            }
            return try AppServices.launch()
        } catch {
            print("OpenTodo: can't open the database: \(error)")
            let db = try! AppDatabase.inMemory()
            return AppServices(database: db, tokens: KeyValueTokenStore(db), reminderBackend: MemoryReminderBackend())
        }
    }

    /// The model for a window. `debug` is `DebugLaunch.current` in Debug
    /// builds, nil in Release.
    public static func forLaunch(_ debug: DebugLaunch?, services: AppServices? = nil) -> AppModel {
        let services = services ?? launchServices(debug)
        let seed = debug?.seed
        let tz = services.repo.timeZone
        let pinned = debug?.timeOfDay.map { LocalDateTime(Day.today(in: tz), minute: $0) }
        let model = AppModel(repo: services.repo, settings: services.settings, services: services, now: pinned) {
            switch seed {
            case .demo:
                await services.start(seed: false)
                do {
                    try await DemoData.seed(services.repo, now: pinned ?? LocalDateTime.now(in: tz))
                    try await EfficiencyDemo.seed(services.efficiency, today: Day.today(in: services.repo.timeZone))
                } catch {
                    print("OpenTodo: seeding failed: \(error)")
                }
            case nil:
                await services.start()
            }
        }
        model.clockPinned = pinned != nil
        if services.database.url == nil { model.notices.show("打不开数据库，这次的改动不会保存") }
        if let route = debug?.open { model.applyWhenLoaded(route) }
        model.taskList.prefill = debug?.quickAddText
        return model
    }
}
