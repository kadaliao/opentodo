// The app going to the background and coming back, as far as the data
// layer cares. In the background the database is suspended: iOS kills a
// suspended process that holds a lock on a file in a shared container
// (0xdead10cc). Work that has to happen there anyway — a 完成 or 稍后提醒
// pressed on a notification, which wakes the app in the background — runs
// inside `awake`: the database resumed, the process kept running with a
// background task, and suspended again once it's done (unless the app came
// to the front meanwhile).
//
//     lifecycle.enterBackground()      // scenePhase == .background
//     lifecycle.enterForeground()      // scenePhase == .active
//     try await lifecycle.awake("提醒按钮") { … }

import Foundation
import GRDB
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class AppLifecycle {
    /// How the database is suspended and resumed, and the process kept
    /// running for a while; tests record the calls instead.
    public struct Hooks {
        public var suspendDatabase: @MainActor () -> Void
        public var resumeDatabase: @MainActor () -> Void
        /// Starts a background task named so; returns a token for `endTask`.
        public var beginTask: @MainActor (String) -> Int
        public var endTask: @MainActor (Int) -> Void

        public init(
            suspendDatabase: @escaping @MainActor () -> Void,
            resumeDatabase: @escaping @MainActor () -> Void,
            beginTask: @escaping @MainActor (String) -> Int,
            endTask: @escaping @MainActor (Int) -> Void
        ) {
            self.suspendDatabase = suspendDatabase
            self.resumeDatabase = resumeDatabase
            self.beginTask = beginTask
            self.endTask = endTask
        }

        /// GRDB's suspension notifications (every database opened with
        /// `observesSuspensionNotifications`, as `AppDatabase` opens them)
        /// and, on iOS, `UIApplication`'s background tasks.
        public static var system: Hooks { Hooks(
            suspendDatabase: { NotificationCenter.default.post(name: Database.suspendNotification, object: nil) },
            resumeDatabase: { NotificationCenter.default.post(name: Database.resumeNotification, object: nil) },
            beginTask: { name in
                #if canImport(UIKit)
                var id = UIBackgroundTaskIdentifier.invalid
                id = UIApplication.shared.beginBackgroundTask(withName: name) {
                    // Out of time: let go rather than be killed.
                    UIApplication.shared.endBackgroundTask(id)
                }
                return id.rawValue
                #else
                return 0
                #endif
            },
            endTask: { raw in
                #if canImport(UIKit)
                let id = UIBackgroundTaskIdentifier(rawValue: raw)
                if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
                #endif
            }
        ) }
    }

    private let hooks: Hooks
    /// Whether the app is in the background (the database suspended
    /// whenever no `awake` work is running).
    public private(set) var inBackground = false
    private var awakeCount = 0

    public init(hooks: Hooks = .system) {
        self.hooks = hooks
    }

    public func enterBackground() {
        guard !inBackground else { return }
        inBackground = true
        if awakeCount == 0 { hooks.suspendDatabase() }
    }

    public func enterForeground() {
        guard inBackground else { return }
        inBackground = false
        if awakeCount == 0 { hooks.resumeDatabase() }
    }

    /// Runs `body` with the database usable and the process kept alive,
    /// whatever the app's state; afterwards the database is suspended again
    /// if the app is (still) in the background.
    public func awake<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
        let task = hooks.beginTask(name)
        if awakeCount == 0 && inBackground { hooks.resumeDatabase() }
        awakeCount += 1
        defer {
            awakeCount -= 1
            if awakeCount == 0 && inBackground { hooks.suspendDatabase() }
            hooks.endTask(task)
        }
        return try await body()
    }
}
