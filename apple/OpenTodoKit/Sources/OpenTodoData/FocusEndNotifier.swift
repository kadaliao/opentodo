// The local notification at the end of a pomodoro or a break. The reminder
// scheduler (OpenTodoData) books tasks', habits' and countdowns' reminders
// under numeric ids and leaves other ids alone, so this one has its own
// fixed id: booking again replaces it, nil takes it away.

import Foundation
import UserNotifications

enum FocusEndNotifier {
    static let identifier = "opentodo.focus.end"

    /// Books the notification for `date` (nil cancels it).
    static func schedule(_ date: Date?, _ body: String) {
        // No app bundle (unit tests): no notification center.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let date, date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "专注"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "focus"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if granted { try? await center.add(request) }
        }
    }
}
