// Writes from outside the app's windows — a widget's 完成 button, the share
// extension, App Intents (Siri, Shortcuts) — into the shared database,
// through `TaskRepo` like everything else, so the rows are marked for sync
// and the app sends them the next time it syncs. Each write then posts
// `ChangeSignal`, so a running app reads the data again (its own database
// observation can't see another process's commits).
//
//     let writer = try SharedWriter.open()
//     try await writer.complete(taskId)
//     let id = try await writer.add(title: "买牛奶", listId: inboxListId)

import Foundation
import OpenTodoData
import OpenTodoDomain

public final class SharedWriter: Sendable {
    public let database: AppDatabase
    public let repo: TaskRepo

    public init(_ database: AppDatabase) {
        self.database = database
        let defaults = (try? AppSettings.load(database))?.defaults ?? .standard
        repo = TaskRepo(database, defaults: { defaults })
    }

    /// The shared database, once the app has opened it. Not made here: an
    /// extension can't see the app's old database (the Flutter version's,
    /// outside the App Group), and a database it made first would stop the
    /// app from copying that one in (`AppDatabase.moveIntoGroup`).
    public static func open(at url: URL? = nil) throws -> SharedWriter {
        let url = try url ?? AppDatabase.defaultURL()
        guard FileManager.default.fileExists(atPath: url.path) else { throw SharedWriterError.appNotOpenedYet }
        return SharedWriter(try AppDatabase.open(at: url))
    }

    /// Finishes an open task (a repeating one moves on to its next date, as
    /// a tick in the app does). A task that is gone or already done is
    /// left alone.
    public func complete(_ id: String) async throws {
        guard let t = try await repo.getTask(id), isOpen(t) else { return }
        _ = try await repo.setCompleted(id, true)
        ChangeSignal.post()
    }

    /// A new task; with a date it gets the person's default reminders, as
    /// one added in the app does. Returns its id.
    @discardableResult
    public func add(title: String, content: String = "", listId: String = inboxListId,
                    date: Day? = nil, time: Int? = nil) async throws -> String {
        let defaults = (try? AppSettings.load(database))?.defaults ?? .standard
        let lists = try await self.lists()
        let list = listId == inboxListId || lists.contains(where: { $0.id == listId }) ? listId : inboxListId
        let id = try await repo.addTask(
            title: title, listId: list, dueDate: date, dueTime: date == nil ? nil : time,
            reminders: date == nil ? [] : defaults.remindersFor(allDay: time == nil))
        if !content.isEmpty { try await repo.setContent(id, content) }
        ChangeSignal.post()
        return id
    }

    /// The lists to choose from (收集箱 not among them; it is always there).
    public func lists() async throws -> [TaskList] {
        try await database.observeLists().first().filter { $0.id != inboxListId }
    }
}

/// The date and time 添加任务 (Shortcuts, Siri) gives a task: the day of
/// `date`, the clock time of `time`; a time without a date is today's.
/// Both nil: no date.
public func intentDue(date: Date?, time: Date?, now: Date = .now, in timeZone: TimeZone = .current) -> (day: Day?, minute: Int?) {
    let minute = time.map { LocalDateTime($0, in: timeZone).minuteOfDay }
    let day = date.map { Day($0, in: timeZone) } ?? (time == nil ? nil : Day.today(in: timeZone, now: now))
    return (day, minute)
}

/// "Something changed in the shared database": a Darwin notification the
/// app and its extensions post after writing and the app listens for. On
/// macOS the sandbox only lets these through when the name starts with
/// the App Group, so it does.
public enum ChangeSignal {
    public static func name(appGroup: String? = AppDatabase.appGroupFromInfoPlist()) -> String {
        (appGroup ?? "com.liaoxingyi.opentodo") + ".changed"
    }

    public static func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name() as CFString), nil, nil, true)
    }

    /// Calls `handler` (on the main queue) whenever another process posts;
    /// stops when the returned token is released.
    public static func observe(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        Observer(name: name(), handler: handler)
    }

    private final class Observer {
        let name: String
        let handler: @MainActor () -> Void

        init(name: String, handler: @escaping @MainActor () -> Void) {
            self.name = name
            self.handler = handler
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue()
                let handler = me.handler
                DispatchQueue.main.async { MainActor.assumeIsolated { handler() } }
            }, name as CFString, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                               Unmanaged.passUnretained(self).toOpaque(),
                                               CFNotificationName(name as CFString), nil)
        }
    }
}

public enum SharedWriterError: LocalizedError, Equatable {
    /// The app hasn't made the shared database yet.
    case appNotOpenedYet

    public var errorDescription: String? {
        switch self {
        case .appNotOpenedYet: "请先打开一次 OpenTodo，之后就能从这里添加了"
        }
    }
}
