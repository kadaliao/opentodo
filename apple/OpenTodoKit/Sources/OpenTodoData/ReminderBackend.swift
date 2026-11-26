// The system side of reminders, ported from
// `app/lib/notify/reminder_backend.dart`: the system holds scheduled
// notifications and shows them even when the app isn't running. Each
// carries two buttons, 完成 and 稍后提醒 (`ReminderActions.swift`); a press
// starts the app in the background if need be and reaches it through the
// `start(onResponse:)` callback (no background isolate, unlike Flutter).
//
// `SystemReminderBackend` is the `UNUserNotificationCenter` one (iOS and
// macOS); `MemoryReminderBackend` stands in for the system in tests and
// previews.

import Foundation
import Synchronization

/// What the person did with a reminder: opened it, or pressed a button.
public enum ReminderAction: String, Sendable, Hashable, CaseIterable {
    case open, done, snooze
}

/// A reminder the person responded to.
public struct ReminderResponse: Sendable, Hashable {
    /// The task's id, or the habit's or countdown's for those kinds.
    public let taskId: String
    public let action: ReminderAction
    public let kind: ReminderKind

    public init(taskId: String, action: ReminderAction, kind: ReminderKind = .task) {
        self.taskId = taskId
        self.action = action
        self.kind = kind
    }
}

/// Where the UI should go for a notification the person clicked.
public enum ReminderOpenRequest: Sendable, Hashable {
    case task(String)
    /// The habits page (习惯打卡), that habit.
    case habit(String)
    /// The countdowns page (倒数日), that countdown.
    case countdown(String)

    init(_ r: ReminderResponse) {
        switch r.kind {
        case .task: self = .task(r.taskId)
        case .habit: self = .habit(r.taskId)
        case .countdown: self = .countdown(r.taskId)
        }
    }
}

/// The identifiers of the notification category and its buttons.
public enum ReminderIdentifiers {
    /// Tasks' notifications, with the 完成 and 稍后提醒 buttons.
    public static let category = "reminder"
    /// Habits' and countdowns' notifications: no buttons, a click opens them.
    public static let habitCategory = "reminder.habit"
    public static let countdownCategory = "reminder.countdown"
    public static let thread = "reminders"
    public static let done = "done"
    public static let snooze = "snooze"
    /// The `userInfo` key holding the task id, or the habit's or
    /// countdown's.
    public static let taskId = "taskId"
    /// The `userInfo` key holding the `ReminderKind` (none: a task).
    public static let kind = "kind"
    /// Where flutter_local_notifications put the task id on the Flutter
    /// version's notifications.
    public static let flutterPayload = "payload"

    public static func category(for kind: ReminderKind) -> String {
        switch kind {
        case .task: category
        case .habit: habitCategory
        case .countdown: countdownCategory
        }
    }
}

/// The task and button of a system response (`reminderResponse`): a press
/// on 完成 or 稍后提醒, otherwise a click on the notification itself. Nil if
/// it isn't a reminder (no task id), or the notification was dismissed.
/// `kind` is the `userInfo` kind; habits and countdowns have no buttons, so
/// anything on one of them opens it.
public func reminderResponse(taskId: String?, kind: String? = nil, actionIdentifier: String) -> ReminderResponse? {
    guard let taskId, !taskId.isEmpty else { return nil }
    if actionIdentifier == "com.apple.UNNotificationDismissActionIdentifier" { return nil }
    let kind = kind.flatMap(ReminderKind.init(rawValue:)) ?? .task
    let action: ReminderAction = switch actionIdentifier {
    case ReminderIdentifiers.done where kind == .task: .done
    case ReminderIdentifiers.snooze where kind == .task: .snooze
    default: .open
    }
    return ReminderResponse(taskId: taskId, action: action, kind: kind)
}

/// `reminderResponse` for a notification's `userInfo`: the task id and
/// kind the Swift version puts there, or, on a notification the Flutter
/// version scheduled (the scheduler keeps those while their title and body
/// still match), its `payload`, which is the task id.
public func reminderResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) -> ReminderResponse? {
    let taskId = userInfo[ReminderIdentifiers.taskId] as? String ?? userInfo[ReminderIdentifiers.flutterPayload] as? String
    return reminderResponse(taskId: taskId, kind: userInfo[ReminderIdentifiers.kind] as? String, actionIdentifier: actionIdentifier)
}

/// A notification the system is holding for later.
public struct PendingReminder: Sendable, Hashable {
    public let id: Int
    public let title: String?
    public let body: String?

    public init(id: Int, title: String?, body: String?) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// A reminder as handed to the system: the moment it goes off (an instant;
/// the app reschedules when the clock or time zone changes).
public struct ScheduledReminder: Sendable, Hashable {
    public let id: Int
    /// The task's id, or the habit's or countdown's.
    public let taskId: String
    public let at: Date
    public let title: String
    public let body: String
    public let kind: ReminderKind

    public init(id: Int, taskId: String, at: Date, title: String, body: String, kind: ReminderKind = .task) {
        self.id = id
        self.taskId = taskId
        self.at = at
        self.title = title
        self.body = body
        self.kind = kind
    }
}

/// Whether the app may show notifications.
public enum ReminderPermission: Sendable, Hashable {
    /// Not asked yet.
    case notDetermined
    case denied
    case allowed
}

public protocol ReminderBackend: Sendable {
    /// Sets up the system side (the buttons); `onResponse` gets the
    /// notifications the person clicks or presses a button on, including
    /// the one the app was launched from. It may be called on any thread.
    ///
    /// The system is told the response is handled only when `onResponse`
    /// returns, so it must not return before the work is done: on iOS a
    /// button pressed while the app is in the background is all the app
    /// gets to run for.
    func start(onResponse: @escaping @Sendable (ReminderResponse) async -> Void) async

    /// Asks for permission the first time; later calls just report it.
    func requestPermission() async -> Bool

    /// The permission as it stands, without asking.
    func permission() async -> ReminderPermission

    func pending() async -> [PendingReminder]
    func schedule(_ reminder: ScheduledReminder) async throws
    func cancel(_ id: Int) async

    /// Opens the system's notification settings for the app.
    func openSettings() async
}

/// Stands in for the system: remembers what is pending, in order, and logs
/// the calls (`schedule <title>`, `cancel <title>`).
public final class MemoryReminderBackend: ReminderBackend {
    private struct State {
        var pending: [ScheduledReminder] = []
        var log: [String] = []
        var permissionRequests = 0
        var allow: Bool
        var asked = false
        var onResponse: (@Sendable (ReminderResponse) async -> Void)?
    }

    private let state: Mutex<State>

    /// `asked`: as if permission had been asked for already (and given
    /// `allow` as the answer).
    public init(allow: Bool = true, asked: Bool = false) {
        var s = State(allow: allow)
        s.asked = asked
        state = Mutex(s)
    }

    public var allow: Bool {
        get { state.withLock { $0.allow } }
        set { state.withLock { $0.allow = newValue } }
    }

    public var log: [String] { state.withLock { $0.log } }
    public func clearLog() { state.withLock { $0.log = [] } }
    public var permissionRequests: Int { state.withLock { $0.permissionRequests } }
    public var scheduled: [ScheduledReminder] { state.withLock { $0.pending } }

    /// The person responding to a notification; returns when the app has
    /// handled it, as the system waits for.
    public func respond(_ r: ReminderResponse) async {
        let handler = state.withLock { $0.onResponse }
        await handler?(r)
    }

    public func start(onResponse: @escaping @Sendable (ReminderResponse) async -> Void) async {
        state.withLock { $0.onResponse = onResponse }
    }

    public func requestPermission() async -> Bool {
        state.withLock {
            $0.permissionRequests += 1
            $0.asked = true
            return $0.allow
        }
    }

    public func permission() async -> ReminderPermission {
        state.withLock { !$0.asked ? .notDetermined : $0.allow ? .allowed : .denied }
    }

    public func pending() async -> [PendingReminder] {
        state.withLock { $0.pending.map { PendingReminder(id: $0.id, title: $0.title, body: $0.body) } }
    }

    public func schedule(_ reminder: ScheduledReminder) async throws {
        state.withLock {
            $0.log.append("schedule \(reminder.title)")
            $0.pending.removeAll { $0.id == reminder.id }
            $0.pending.append(reminder)
        }
    }

    public func cancel(_ id: Int) async {
        state.withLock { s in
            s.log.append("cancel \(s.pending.first { $0.id == id }?.title ?? "nil")")
            s.pending.removeAll { $0.id == id }
        }
    }

    public func openSettings() async {}
}
