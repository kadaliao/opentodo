// Keeps the system's pending notifications in line with the reminders the
// tasks call for, touching only what changed; ported from
// `app/lib/notify/reminder_scheduler.dart`. Delivered notifications are
// left alone: cancelling one would also pull it out of the notification
// centre.

import Foundation

public actor ReminderScheduler {
    public let backend: any ReminderBackend
    public let timeZone: TimeZone
    /// Whether the system lets the app show notifications; nil until there
    /// has been something to ask about.
    public private(set) var allowed: Bool?

    /// `allowed`: already known, so permission isn't asked for.
    public init(_ backend: any ReminderBackend, allowed: Bool? = nil, timeZone: TimeZone = .autoupdatingCurrent) {
        self.backend = backend
        self.allowed = allowed
        self.timeZone = timeZone
    }

    /// Asks again next time (the person may have changed it in Settings).
    public func recheckPermission() {
        if allowed == false { allowed = nil }
    }

    /// `replaceAll` hands every reminder over again, as when the way they
    /// are set up has changed (buttons added, say).
    public func apply(_ events: [ReminderEvent], replaceAll: Bool = false) async throws {
        if !events.isEmpty && allowed == nil {
            allowed = await backend.requestPermission()
        }
        // By id, in the order they first come, the last one winning (a Dart map).
        var order: [Int] = []
        var want: [Int: ReminderEvent] = [:]
        for e in events {
            let id = e.id(in: timeZone)
            if want[id] == nil { order.append(id) }
            want[id] = e
        }
        var keep = Set<Int>()
        for p in await backend.pending() {
            if !replaceAll, let e = want[p.id], e.title == p.title, e.body == p.body {
                keep.insert(p.id)
            } else {
                await backend.cancel(p.id)
            }
        }
        for id in order where !keep.contains(id) {
            let e = want[id]!
            try await backend.schedule(ScheduledReminder(id: id, taskId: e.taskId, at: e.at.date(in: timeZone), title: e.title, body: e.body, kind: e.kind))
        }
    }
}
