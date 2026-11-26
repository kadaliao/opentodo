// How the calendar looks, kept on this device (never synced). Ported from
// `CalendarPrefs` in `app/lib/state/calendar_providers.dart`.
//
// Stored as JSON under `CalendarPrefs.storageKey` (`calendar.prefs`) in
// `key_values`, the same JSON the Flutter version writes: `mode` (a
// `CalendarMode` name), `showCompleted`, `showRepeats`, `showLunar`,
// `hiddenLists` (list ids). Decoding never fails: a missing or unusable
// value takes the default, so does an unknown mode, and non-strings in
// `hiddenLists` are dropped.
//
// Keys of the Swift version's own, which the Flutter version ignores (and
// leaves out when it saves): `weeks`, the multi-week view's length;
// `filterId`, the saved filter (过滤器) the calendar shows only the tasks
// of; `taskCard`, a click on a task shows its card rather than the detail.

public struct CalendarPrefs: Sendable, Hashable {
    /// The `key_values` key (`Keys.calendarPrefs` in the Dart version).
    public static let storageKey = "calendar.prefs"

    public var mode: CalendarMode
    public var showCompleted: Bool
    public var showRepeats: Bool
    /// Lunar days, festivals, and 休 / 班 from the holiday schedule.
    public var showLunar: Bool
    public var hiddenLists: Set<String>
    /// How many weeks the multi-week view shows, within `multiWeekRange`.
    public var weeks: Int
    /// Only the tasks of this saved filter (`TaskFilter.id`); nil for all.
    public var filterId: String?
    /// A click on a task shows its card instead of opening the detail.
    public var taskCard: Bool

    public init(
        mode: CalendarMode = .month,
        showCompleted: Bool = true,
        showRepeats: Bool = true,
        showLunar: Bool = true,
        hiddenLists: Set<String> = [],
        weeks: Int = defaultMultiWeeks,
        filterId: String? = nil,
        taskCard: Bool = false
    ) {
        self.mode = mode
        self.showCompleted = showCompleted
        self.showRepeats = showRepeats
        self.showLunar = showLunar
        self.hiddenLists = hiddenLists
        self.weeks = clampWeeks(weeks)
        self.filterId = filterId
        self.taskCard = taskCard
    }

    public static let standard = CalendarPrefs()

    public var filter: CalendarFilter {
        CalendarFilter(showCompleted: showCompleted, showRepeats: showRepeats, hiddenLists: hiddenLists)
    }
}

extension CalendarPrefs: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, showCompleted, showRepeats, showLunar, hiddenLists, weeks, filterId, taskCard
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        func bool(_ key: CodingKeys, _ fallback: Bool) -> Bool { (try? c.decode(Bool.self, forKey: key)) ?? fallback }
        mode = CalendarMode.byName(try? c.decode(String.self, forKey: .mode)) ?? .month
        showCompleted = bool(.showCompleted, true)
        showRepeats = bool(.showRepeats, true)
        showLunar = bool(.showLunar, true)
        let lists = (try? c.decode([LossyString].self, forKey: .hiddenLists)) ?? []
        hiddenLists = Set(lists.compactMap(\.value))
        weeks = clampWeeks((try? c.decode(Int.self, forKey: .weeks)) ?? defaultMultiWeeks)
        filterId = (try? c.decode(String.self, forKey: .filterId)).flatMap { $0.isEmpty ? nil : $0 }
        taskCard = bool(.taskCard, false)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode.rawValue, forKey: .mode)
        try c.encode(showCompleted, forKey: .showCompleted)
        try c.encode(showRepeats, forKey: .showRepeats)
        try c.encode(showLunar, forKey: .showLunar)
        // Sorted, so the same prefs always give the same text.
        try c.encode(hiddenLists.sorted(), forKey: .hiddenLists)
        try c.encode(weeks, forKey: .weeks)
        try c.encodeIfPresent(filterId, forKey: .filterId)
        try c.encode(taskCard, forKey: .taskCard)
    }
}

/// A JSON value that is a string (kept) or anything else (`value` nil).
/// Never fails to decode.
private struct LossyString: Decodable {
    let value: String?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}
