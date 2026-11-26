// Reminders through `UNUserNotificationCenter`, on iOS and macOS alike: a
// notification category with the 完成 and 稍后提醒 buttons (they run in the
// background: the system starts the app without bringing it forward),
// permission asked for when there is a first reminder to show, and the
// delegate that hands clicks and presses to `ReminderController`.
//
// Call `start(onResponse:)` early at launch (the app delegate's
// `didFinishLaunching`, or the `App` initializer): the system delivers the
// response the app was launched from only once a delegate is set.
//
// Notifications can't be tested under `swift test` (there's no app bundle);
// `MemoryReminderBackend` stands in there.

import Foundation
import Synchronization
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public final class SystemReminderBackend: NSObject, ReminderBackend, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let onResponse = Mutex<(@Sendable (ReminderResponse) async -> Void)?>(nil)
    /// Clicks and presses that came before `start` (the one the app was
    /// launched from), handed over when it registers the handler. The
    /// system's call waits on `done` until then (or `earlyWait`).
    private let early = Mutex<[Early]>([])

    private struct Early {
        let id: UUID
        let response: ReminderResponse
        var done: CheckedContinuation<Void, Never>?
    }

    /// How long a response that came before `start` holds the system's call
    /// (iOS gives an app woken in the background about 30 seconds).
    static let earlyWait: Duration = .seconds(25)
    private let provisional: Bool
    private let onPresent: (@Sendable (String) -> Void)?

    /// Looked up when first used: `current()` needs an app bundle.
    private var center: UNUserNotificationCenter { .current() }

    /// `provisional` (debug builds, self-tests): asks for provisional
    /// authorization, which is given without a prompt (notifications go
    /// quietly to the notification centre). `onPresent` hears the title of
    /// each notification shown while the app is in front.
    public init(provisional: Bool = false, onPresent: (@Sendable (String) -> Void)? = nil) {
        self.provisional = provisional
        self.onPresent = onPresent
        super.init()
    }

    /// Becomes the notification centre's delegate now, before the window's
    /// `start`: `AppServices.launch` calls it from the App initializer, so
    /// the response the app was launched from (a click, or 完成 / 稍后提醒
    /// on iOS, where the app may be started in the background without a
    /// window) isn't lost. Responses wait until `start`.
    public func listenEarly() {
        center.delegate = self
    }

    public func start(onResponse handler: @escaping @Sendable (ReminderResponse) async -> Void) async {
        let queued: [Early] = onResponse.withLock { h in
            h = handler
            return early.withLock { q in defer { q.removeAll() }; return q }
        }
        if !queued.isEmpty {
            Task {
                for e in queued {
                    await handler(e.response)
                    e.done?.resume()
                }
            }
        }
        let done = UNNotificationAction(identifier: ReminderIdentifiers.done, title: "完成", options: [])
        let snooze = UNNotificationAction(identifier: ReminderIdentifiers.snooze, title: "稍后提醒", options: [])
        let category = UNNotificationCategory(
            identifier: ReminderIdentifiers.category, actions: [done, snooze], intentIdentifiers: [], options: []
        )
        let habit = UNNotificationCategory(identifier: ReminderIdentifiers.habitCategory, actions: [], intentIdentifiers: [], options: [])
        let countdown = UNNotificationCategory(identifier: ReminderIdentifiers.countdownCategory, actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category, habit, countdown])
        center.delegate = self
    }

    public func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: provisional ? [.alert, .sound, .badge, .provisional] : [.alert, .sound, .badge])) ?? false
    }

    public func permission() async -> ReminderPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    /// Takes the shown notifications out of the notification centre
    /// (self-tests clean up after themselves).
    public func clearDelivered() async {
        center.removeAllDeliveredNotifications()
    }

    /// The notifications shown and still in the notification centre:
    /// their ids and titles.
    public func delivered() async -> [PendingReminder] {
        await center.deliveredNotifications().compactMap { n in
            guard let id = Int(n.request.identifier) else { return nil }
            return PendingReminder(id: id, title: n.request.content.title, body: n.request.content.body)
        }
    }

    public func pending() async -> [PendingReminder] {
        await center.pendingNotificationRequests().compactMap { r in
            guard let id = Int(r.identifier) else { return nil }
            return PendingReminder(id: id, title: r.content.title, body: r.content.body)
        }
    }

    public func schedule(_ reminder: ScheduledReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = ReminderIdentifiers.category(for: reminder.kind)
        content.threadIdentifier = ReminderIdentifiers.thread + (reminder.kind == .task ? "" : "." + reminder.kind.rawValue)
        content.userInfo = [ReminderIdentifiers.taskId: reminder.taskId, ReminderIdentifiers.kind: reminder.kind.rawValue]
        // The moment, not the wall-clock time: with its time zone, the
        // components name one instant.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.at)
        parts.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await center.add(UNNotificationRequest(identifier: String(reminder.id), content: content, trigger: trigger))
    }

    public func cancel(_ id: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [String(id)])
    }

    public func openSettings() async {
        #if canImport(UIKit)
        await MainActor.run {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        #elseif canImport(AppKit)
        let id = Bundle.main.bundleIdentifier ?? "com.liaoxingyi.opentodo"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
        }
        #endif
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shown while the app is in front too.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        onPresent?(notification.request.content.title)
        return [.banner, .list, .sound]
    }

    /// Returns (the system's completion handler) only once the app has
    /// handled the response: written to the database, reminders handed over
    /// again. A response before `start` waits for it, up to `earlyWait`.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let r = reminderResponse(userInfo: info, actionIdentifier: response.actionIdentifier) else { return }
        if let handler = onResponse.withLock({ $0 }) {
            await handler(r)
            return
        }
        let id = UUID()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            // `start` may have come in between: then handle it here.
            let handler: (@Sendable (ReminderResponse) async -> Void)? = onResponse.withLock { h in
                if h == nil { early.withLock { $0.append(Early(id: id, response: r, done: done)) } }
                return h
            }
            if let handler {
                Task {
                    await handler(r)
                    done.resume()
                }
                return
            }
            // Don't hold the system for ever if `start` never comes; the
            // response stays queued for when it does.
            Task { [weak self] in
                try? await Task.sleep(for: Self.earlyWait)
                let late: CheckedContinuation<Void, Never>? = self?.early.withLock { q -> CheckedContinuation<Void, Never>? in
                    guard let i = q.firstIndex(where: { $0.id == id }) else { return nil }
                    defer { q[i].done = nil }
                    return q[i].done
                }
                late?.resume()
            }
        }
    }
}
