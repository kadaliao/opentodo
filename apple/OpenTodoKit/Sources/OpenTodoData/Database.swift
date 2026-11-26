// The app's SQLite database, ported from `AppDatabase` in
// `app/lib/data/db.dart`. Same file, same tables, same `user_version` as
// the Flutter version (docs/apple.md §3); see `Schema.swift` for the tables
// and the upgrade steps.
//
//     let db = try AppDatabase.open()                 // the real file
//     let db = try AppDatabase.open(at: url)          // another file (debug, tests)
//     let db = try AppDatabase.inMemory()             // tests
//
// Opening a file:
// - The first time the Swift version opens a database the Flutter version
//   made, it first copies it to `opentodo.sqlite.before-swift` next to it
//   (never overwriting an earlier copy). "First time" is the absence of
//   `Keys.swiftOpenedAt`, which only the Swift version writes.
// - WAL journal, and a 5-second busy timeout like the Flutter version: a
//   reminder button handled by another process waits for the app's write
//   instead of failing. Several processes (the app, its widgets through
//   `openReadOnly`) can have it open: WAL lets readers go on while one
//   writes, and writers take turns.
// - Where it is: `defaultURL()` (an App Group container when the app has
//   one, else the Flutter version's place).
// - Upgrades from `PRAGMA user_version`: 0 creates the version-7 tables,
//   1–6 run `db.dart`'s `onUpgrade` steps, 7 is used as it is. A version
//   newer than this code knows (a later Swift build) is opened as it is.

import Foundation
import GRDB

public final class AppDatabase: Sendable {
    /// Where everything is read and written. Internal: the UI goes through
    /// the repository and the observations, never SQL.
    let writer: any DatabaseWriter

    /// The file, or nil for an in-memory database.
    public let url: URL?

    init(writer: any DatabaseWriter, url: URL?) {
        self.writer = writer
        self.url = url
    }

    /// The database at `url` (default: `defaultURL()`), created if missing,
    /// backed up first if the Flutter version left it, and upgraded.
    public static func open(at url: URL? = nil) throws -> AppDatabase {
        let url = try url ?? defaultURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backUpIfFromFlutter(url)
        let pool = try DatabasePool(path: url.path, configuration: configuration())
        try prepare(pool)
        return AppDatabase(writer: pool, url: url)
    }

    /// The database at `url` for reading only, as a widget opens it while
    /// the app may be writing: no upgrade, no backup, no writes. Throws if
    /// there is no database there yet. It sees the app's commits (WAL);
    /// a read that meets a write in progress waits, up to 5 seconds.
    public static func openReadOnly(at url: URL? = nil) throws -> AppDatabase {
        let url = try url ?? defaultURL()
        var config = configuration()
        config.readonly = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        return AppDatabase(writer: pool, url: url)
    }

    /// A new, empty database that lives only as long as the value.
    public static func inMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue(configuration: configuration())
        try prepare(queue)
        return AppDatabase(writer: queue, url: nil)
    }

    /// Closes the connections; the value can't be used afterwards.
    /// (Releasing the last reference closes it too.)
    public func close() throws {
        try writer.close()
    }

    /// The copy left beside a Flutter database before the Swift version
    /// first touches it.
    public static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".before-swift")
    }

    // MARK: Location

    public static let fileName = "opentodo.sqlite"

    /// The Info.plist key holding the App Group the app and its widgets
    /// share (`group.com.liaoxingyi.opentodo`, `.dev` for the debug build;
    /// on macOS `$(TeamIdentifierPrefix)group.com.liaoxingyi.opentodo`,
    /// expanded at build time).
    public static let appGroupInfoKey = "OTAppGroup"

    /// The App Group named in the app's Info.plist, if any.
    public static func appGroupFromInfoPlist(_ bundle: Bundle = .main) -> String? {
        (bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Where the database lives: the one place that decides it.
    ///
    /// With an App Group container (`appGroup` given and the app entitled
    /// to it) the database is in the container, where widgets can open it
    /// too; the first time, a database at the old place is copied in
    /// (`moveIntoGroup`). Without one it is where the Flutter version kept
    /// it, through path_provider's `getApplicationSupportDirectory`:
    /// - macOS: `Application Support/<bundle id>/opentodo.sqlite` (inside
    ///   the sandbox container);
    /// - iOS: `Library/Application Support/opentodo.sqlite`.
    /// The debug build has its own bundle id and group, so its own file.
    public static func defaultURL(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroup: String? = appGroupFromInfoPlist(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let legacy = location(applicationSupport: support, bundleIdentifier: bundleIdentifier)
        guard let appGroup, let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return legacy
        }
        return try moveIntoGroup(legacy: legacy, group: groupLocation(container: container))
    }

    /// The database's place in an App Group container.
    public static func groupLocation(container: URL) -> URL {
        container.appendingPathComponent("Library/Application Support", isDirectory: true).appendingPathComponent(fileName)
    }

    /// `group` once there is a database there: if there isn't one yet and
    /// there is one at `legacy` (the Flutter version's, or the Swift
    /// version's from before the App Group), it is checkpointed (so its
    /// WAL is in the main file) and copied in, with any `-wal` / `-shm`
    /// left; the old files stay where they are, as a backup.
    public static func moveIntoGroup(legacy: URL, group: URL) throws -> URL {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: group.path), fm.fileExists(atPath: legacy.path) else { return group }
        try fm.createDirectory(at: group.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let old = try DatabaseQueue(path: legacy.path, configuration: configuration())
            _ = try old.writeWithoutTransaction { try $0.checkpoint(.truncate) }
            try old.close()
        } catch {
            // A file that won't open is still copied: it is the person's data.
        }
        // Into place under temporary names, the main file last, so a crash
        // halfway leaves no database in the group and the next launch
        // starts over.
        let stamp = UUID().uuidString
        var moved: [(URL, URL)] = []
        for suffix in ["-wal", "-shm", ""] {
            let from = URL(fileURLWithPath: legacy.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = URL(fileURLWithPath: group.path + suffix)
            let temp = URL(fileURLWithPath: group.path + suffix + ".copy-" + stamp)
            try fm.copyItem(at: from, to: temp)
            moved.append((temp, to))
        }
        for (temp, to) in moved {
            try? fm.removeItem(at: to)
            try fm.moveItem(at: temp, to: to)
        }
        return group
    }

    /// `defaultURL` without touching the file system.
    public static func location(applicationSupport: URL, bundleIdentifier: String?) -> URL {
        #if os(macOS)
        let dir = applicationSupport.appendingPathComponent(bundleIdentifier ?? "com.liaoxingyi.opentodo", isDirectory: true)
        #else
        let dir = applicationSupport
        #endif
        return dir.appendingPathComponent(fileName)
    }

    // MARK: Opening

    private static func configuration() -> Configuration {
        var config = Configuration()
        config.busyMode = .timeout(5)
        // GRDB gives a pool's readers 10 seconds; the same 5 for all.
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA busy_timeout = 5000") }
        config.label = "OpenTodo"
        // In an App Group container a process suspended while holding a
        // lock on the file is killed (0xdead10cc): the app posts
        // `Database.suspendNotification` when it goes to the background and
        // `Database.resumeNotification` when it comes back.
        config.observesSuspensionNotifications = true
        return config
    }

    /// Creates or upgrades the tables and leaves the Swift version's mark.
    private static func prepare(_ writer: any DatabaseWriter) throws {
        try writer.write { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            if version < Schema.version {
                try Schema.migrate(db, from: version)
            }
            if try db.value(forKey: Keys.swiftOpenedAt) == nil {
                try db.setValue(String(nowMilliseconds()), forKey: Keys.swiftOpenedAt)
            }
        }
    }

    /// Copies a database the Flutter version left (it has tables but not
    /// the Swift version's mark) to `backupURL(for:)`, unless that exists.
    private static func backUpIfFromFlutter(_ url: URL) throws {
        let fm = FileManager.default
        let backup = backupURL(for: url)
        guard fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) else { return }
        let source = try DatabaseQueue(path: url.path, configuration: configuration())
        defer { try? source.close() }
        let needed = try source.read { db -> Bool in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            guard version > 0 else { return false }
            guard try db.tableExists("key_values") else { return true }
            return try db.value(forKey: Keys.swiftOpenedAt) == nil
        }
        guard needed else { return }
        let partial = backup.appendingPathExtension("partial")
        try? fm.removeItem(at: partial)
        do {
            let destination = try DatabaseQueue(path: partial.path)
            try source.backup(to: destination)
            try destination.close()
            try fm.moveItem(at: partial, to: backup)
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
    }
}

func nowMilliseconds(_ date: Date = .now) -> Int {
    Int((date.timeIntervalSince1970 * 1000).rounded(.down))
}
