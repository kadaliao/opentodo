// Settings kept on this device (never synced), as JSON in `key_values`, in
// the same shape the Flutter version writes:
//
// - `AppSettings` (`Keys.settings`, from state/settings_providers.dart):
//   `{"defaults":{"timedReminders":[0],"allDayReminders":[],"spanMinutes":60},"snoozeMinutes":15}`
// - `ViewPrefs` per view (`Keys.listPrefs`, from state/providers.dart):
//   `{"list:work":{"layout":"board","sort":"due","group":"tag"},"smart:today":{"layout":"list"}}`;
//   the first version stored just the layout name (`"board"`), still read.
// - `TimelinePrefs` (`Keys.timelinePrefs`, from state/timeline_providers.dart):
//   `{"scale":"week","showDone":false,"trayOpen":true}`.
//
// Readers never fail: missing, unknown or damaged values take the defaults.
// `LocalSettings` holds them all for the UI, with the domain's own:
// `CalendarPrefs`, and the efficiency module's `MatrixPrefs`,
// `FocusSettings` and the running `FocusTimer` (Swift version only).

import Foundation
import Observation
import Synchronization

// MARK: - AppSettings

public struct AppSettings: Sendable, Hashable {
    public var defaults: TaskDefaults
    /// How long 稍后提醒 on a notification puts the reminder off.
    public var snoozeMinutes: Int

    public init(defaults: TaskDefaults = .standard, snoozeMinutes: Int = 15) {
        self.defaults = defaults
        self.snoozeMinutes = snoozeMinutes
    }

    public var json: JSONValue {
        .fields([
            ("defaults", .fields([
                ("timedReminders", .array(defaults.timedReminders.map(JSONValue.int))),
                ("allDayReminders", .array(defaults.allDayReminders.map(JSONValue.int))),
                ("spanMinutes", .int(defaults.spanMinutes)),
            ])),
            ("snoozeMinutes", .int(snoozeMinutes)),
        ])
    }

    /// Unknown or missing values fall back to the defaults.
    public init(json: JSONValue) {
        var defaults = TaskDefaults.standard
        if let d = json["defaults"], d.isObject,
           let decoded = try? JSONDecoder().decode(TaskDefaults.self, from: d.encodedData) {
            defaults = decoded
        }
        let snooze = json["snoozeMinutes"]?.doubleValue
        self.init(defaults: defaults, snoozeMinutes: snooze.flatMap { $0 > 0 ? Int($0) : nil } ?? 15)
    }

    /// The settings as stored (`loadSettings`).
    public static func load(_ db: AppDatabase) throws -> AppSettings {
        guard let raw = try db.getValueNow(Keys.settings), let json = JSONValue.parse(raw), json.isObject else { return AppSettings() }
        return AppSettings(json: json)
    }

    public func save(_ db: AppDatabase) throws {
        try db.setValueNow(Keys.settings, json.encoded())
    }
}

// MARK: - ViewPrefs

/// How a list is laid out on this device. A version that doesn't know a
/// layout shows the list.
public enum ListLayout: String, Sendable, Hashable, CaseIterable {
    case list, board, timeline
}

/// The key a view's `ViewPrefs` are kept under: a list's id (the inbox's
/// too), or the view's name for the rest.
public func viewPrefsKey(_ view: ViewRef) -> String {
    arrangedListId(view) ?? view.description
}

/// How a view shows on this device: a list as a list, a board or a
/// timeline, and how the open tasks are grouped and ordered. A phone may
/// want the list where the computer shows the board.
public struct ViewPrefs: Sendable, Hashable {
    public var layout: ListLayout
    /// Nil: the view's default.
    public var sort: TaskSort?
    public var grouping: TaskGrouping?

    public init(layout: ListLayout = .list, sort: TaskSort? = nil, grouping: TaskGrouping? = nil) {
        self.layout = layout
        self.sort = sort
        self.grouping = grouping
    }

    public var isDefault: Bool { layout == .list && sort == nil && grouping == nil }

    /// The order `view` uses: `sort` if it offers it, else its default.
    public func sortIn(_ view: ViewRef) -> TaskSort? {
        let sorts = sortsFor(view)
        return sort.map(sorts.contains) == true ? sort : sorts.first
    }

    /// The grouping `view` uses: `grouping` if it offers it, else its
    /// default.
    public func groupingIn(_ view: ViewRef) -> TaskGrouping? {
        let groupings = groupingsFor(view)
        return grouping.map(groupings.contains) == true ? grouping : groupings.first
    }

    /// The grouping of `view`'s timeline lanes: `grouping` if the timeline
    /// offers it, else its default (never by date).
    public func timelineGroupingIn(_ view: ViewRef) -> TaskGrouping? {
        let groupings = timelineGroupingsFor(view)
        return grouping.map(groupings.contains) == true ? grouping : groupings.first
    }

    /// What `view` shows as: a board only for a list (the inbox too), a
    /// timeline for any view whose tasks can be arranged (not 已完成 or
    /// 垃圾桶), else a list.
    public func layoutIn(_ view: ViewRef) -> ListLayout {
        switch layout {
        case .board where arrangedListId(view) != nil: .board
        case .timeline where !groupingsFor(view).isEmpty: .timeline
        default: .list
        }
    }

    public var json: JSONValue {
        var pairs: [(String, JSONValue)] = [("layout", .string(layout.rawValue))]
        if let sort { pairs.append(("sort", .string(sort.rawValue))) }
        if let grouping { pairs.append(("group", .string(grouping.rawValue))) }
        return .fields(pairs)
    }

    /// Also reads the bare layout name the first version stored.
    public init(json: JSONValue) {
        if let name = json.stringValue {
            self.init(layout: ListLayout(rawValue: name) ?? .list)
            return
        }
        guard json.isObject else {
            self.init()
            return
        }
        self.init(
            layout: json["layout"]?.stringValue.flatMap(ListLayout.init(rawValue:)) ?? .list,
            sort: json["sort"]?.stringValue.flatMap(TaskSort.init(rawValue:)),
            grouping: json["group"]?.stringValue.flatMap(TaskGrouping.init(rawValue:))
        )
    }

    /// Every view's prefs, by `viewPrefsKey`; nothing when damaged.
    public static func loadAll(_ db: AppDatabase) throws -> [String: ViewPrefs] {
        guard let raw = try db.getValueNow(Keys.listPrefs), let pairs = JSONValue.parse(raw)?.pairs else { return [:] }
        var out: [String: ViewPrefs] = [:]
        for (k, v) in pairs { out[k] = ViewPrefs(json: v) }
        return out
    }

    /// Stores them, the default ones left out, keys in a stable order.
    public static func saveAll(_ all: [String: ViewPrefs], to db: AppDatabase) throws {
        let pairs = all.filter { !$0.value.isDefault }.sorted { $0.key < $1.key }.map { ($0.key, $0.value.json) }
        try db.setValueNow(Keys.listPrefs, JSONValue.fields(pairs).encoded())
    }
}

// MARK: - TimelinePrefs

/// How the timeline looks, the same for every list.
public struct TimelinePrefs: Sendable, Hashable {
    public var scale: TimelineScale
    /// Finished tasks stay on the days they were due, faded.
    public var showDone: Bool
    /// Whether the tasks without a date (无日期) show beside the timeline;
    /// nil until the person chooses: open where there's room.
    public var trayOpen: Bool?

    public init(scale: TimelineScale = .day, showDone: Bool = false, trayOpen: Bool? = nil) {
        self.scale = scale
        self.showDone = showDone
        self.trayOpen = trayOpen
    }

    public var json: JSONValue {
        var pairs: [(String, JSONValue)] = [("scale", .string(scale.rawValue)), ("showDone", .bool(showDone))]
        if let trayOpen { pairs.append(("trayOpen", .bool(trayOpen))) }
        return .fields(pairs)
    }

    /// Unknown or missing values fall back to the defaults.
    public init(json: JSONValue) {
        self.init(
            scale: json["scale"]?.stringValue.flatMap(TimelineScale.init(rawValue:)) ?? .day,
            showDone: json["showDone"]?.boolValue ?? false,
            trayOpen: json["trayOpen"]?.boolValue
        )
    }

    public static func load(_ db: AppDatabase) throws -> TimelinePrefs {
        guard let raw = try db.getValueNow(Keys.timelinePrefs), let json = JSONValue.parse(raw), json.isObject else { return TimelinePrefs() }
        return TimelinePrefs(json: json)
    }

    public func save(_ db: AppDatabase) throws {
        try db.setValueNow(Keys.timelinePrefs, json.encoded())
    }
}

// MARK: - The store

/// The settings for the UI to watch and change: read once when made,
/// written through on every change. `defaultsProvider` hands the current
/// task defaults to `TaskRepo` from any thread.
@MainActor @Observable
public final class LocalSettings {
    public let database: AppDatabase

    public private(set) var settings: AppSettings
    public private(set) var viewPrefs: [String: ViewPrefs]
    public private(set) var timelinePrefs: TimelinePrefs
    public private(set) var calendarPrefs: CalendarPrefs
    public private(set) var matrixPrefs: MatrixPrefs
    public private(set) var focusSettings: FocusSettings
    /// The timer as last saved; read back at launch and `tick(at:)` it to
    /// catch up on what happened while the app was gone.
    public private(set) var focusTimer: FocusTimer?

    /// The last error writing a change (the change still shows).
    public private(set) var saveError: (any Error)?

    @ObservationIgnored private let snapshot: Snapshot

    private final class Snapshot: Sendable {
        let value: Mutex<AppSettings>
        init(_ s: AppSettings) { value = Mutex(s) }
    }

    public init(_ database: AppDatabase) {
        self.database = database
        let settings = (try? AppSettings.load(database)) ?? AppSettings()
        self.settings = settings
        viewPrefs = (try? ViewPrefs.loadAll(database)) ?? [:]
        timelinePrefs = (try? TimelinePrefs.load(database)) ?? TimelinePrefs()
        calendarPrefs = (try? database.getValueNow(CalendarPrefs.storageKey))
            .flatMap { $0 }
            .flatMap { try? JSONDecoder().decode(CalendarPrefs.self, from: Data($0.utf8)) } ?? CalendarPrefs()
        matrixPrefs = MatrixPrefs.decode((try? database.getValueNow(Keys.matrixPrefs)).flatMap { $0 })
        focusSettings = FocusSettings.decode((try? database.getValueNow(Keys.focusSettings)).flatMap { $0 })
        focusTimer = (try? database.getValueNow(Keys.focusTimer)).flatMap { $0 }
            .flatMap { try? JSONDecoder().decode(FocusTimer.self, from: Data($0.utf8)) }
        snapshot = Snapshot(settings)
    }

    /// For `TaskRepo(defaults:)` and the reminder controller.
    public nonisolated var defaultsProvider: @Sendable () -> TaskDefaults {
        let snapshot = self.snapshot
        return { snapshot.value.withLock { $0.defaults } }
    }

    /// The settings now, for `ReminderController(settings:)`.
    public nonisolated var snapshotProvider: @Sendable () -> AppSettings {
        let snapshot = self.snapshot
        return { snapshot.value.withLock { $0 } }
    }

    /// The settings now, from any thread.
    public nonisolated var current: AppSettings { snapshot.value.withLock { $0 } }

    private func save(_ body: () throws -> Void) {
        do {
            try body()
            saveError = nil
        } catch {
            saveError = error
        }
    }

    // MARK: AppSettings

    public func set(_ settings: AppSettings) {
        self.settings = settings
        snapshot.value.withLock { $0 = settings }
        save { try settings.save(database) }
    }

    public func setDefaults(_ defaults: TaskDefaults) {
        var s = settings
        s.defaults = defaults
        set(s)
    }

    public func setSnoozeMinutes(_ minutes: Int) {
        var s = settings
        s.snoozeMinutes = minutes
        set(s)
    }

    // MARK: ViewPrefs

    public func viewPrefs(for view: ViewRef) -> ViewPrefs {
        viewPrefs[viewPrefsKey(view)] ?? ViewPrefs()
    }

    public func setLayout(_ view: ViewRef, _ layout: ListLayout) {
        var p = viewPrefs(for: view)
        p.layout = layout
        setViewPrefs(view, p)
    }

    /// The view's default is stored as no choice, so a later change of
    /// default reaches it.
    public func setSort(_ view: ViewRef, _ sort: TaskSort) {
        var p = viewPrefs(for: view)
        p.sort = sort == sortsFor(view).first ? nil : sort
        setViewPrefs(view, p)
    }

    public func setGrouping(_ view: ViewRef, _ grouping: TaskGrouping) {
        var p = viewPrefs(for: view)
        p.grouping = grouping == groupingsFor(view).first ? nil : grouping
        setViewPrefs(view, p)
    }

    private func setViewPrefs(_ view: ViewRef, _ prefs: ViewPrefs) {
        var all = viewPrefs
        all[viewPrefsKey(view)] = prefs
        all = all.filter { !$0.value.isDefault }
        viewPrefs = all
        save { try ViewPrefs.saveAll(all, to: database) }
    }

    // MARK: Timeline and calendar

    public func setTimelinePrefs(_ prefs: TimelinePrefs) {
        timelinePrefs = prefs
        save { try prefs.save(database) }
    }

    public func setCalendarPrefs(_ prefs: CalendarPrefs) {
        calendarPrefs = prefs
        save {
            let data = try JSONEncoder().encode(prefs)
            try database.setValueNow(CalendarPrefs.storageKey, String(decoding: data, as: UTF8.self))
        }
    }

    // MARK: The efficiency module

    public func setMatrixPrefs(_ prefs: MatrixPrefs) {
        matrixPrefs = prefs
        save { try database.setValueNow(Keys.matrixPrefs, prefs.json) }
    }

    public func setFocusSettings(_ settings: FocusSettings) {
        focusSettings = settings
        save { try database.setValueNow(Keys.focusSettings, settings.json) }
    }

    /// Saves the timer after every change the person makes (start, pause,
    /// a finished stretch); nil forgets it.
    public func setFocusTimer(_ timer: FocusTimer?) {
        focusTimer = timer
        save {
            let text = try timer.map { t -> String in
                let e = JSONEncoder()
                e.outputFormatting = .sortedKeys
                return String(decoding: try e.encode(t), as: UTF8.self)
            }
            try database.setValueNow(Keys.focusTimer, text)
        }
    }
}
