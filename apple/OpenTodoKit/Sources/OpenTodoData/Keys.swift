// Keys of the local-only `key_values` table, ported from
// `app/lib/data/keys.dart`. The values are text (often JSON); unreadable or
// unknown contents fall back to defaults where they are read.

public enum Keys {
    public static let server = "account.server"
    /// The Flutter version kept the sign-in token here. The Swift version
    /// keeps it in the keychain (`TokenStore`) and moves it out of the
    /// database on first launch (`moveLegacyToken`).
    public static let token = "account.token"
    public static let email = "account.email"
    public static let userId = "account.userId"
    public static let cursor = "sync.cursor"
    public static let lastSyncedAt = "sync.lastSyncedAt"

    /// Reminders put off with 稍后提醒: task id → epoch milliseconds (JSON).
    public static let snoozes = "reminders.snoozed"

    /// What the notifications the system holds look like; when it changes,
    /// they are all handed over again.
    public static let reminderFormat = "reminders.format"

    /// The person's settings (JSON); see `AppSettings`.
    public static let settings = "settings"

    /// List or board, grouping and order for each view (JSON); see
    /// `ViewPrefs`. (The name is from when it held only lists' layouts.)
    public static let listPrefs = "list.layouts"

    /// Calendar mode and display choices (JSON); see `CalendarPrefs`.
    public static let calendarPrefs = "calendar.prefs"

    /// Timeline scale and display choices (JSON); see `TimelinePrefs`.
    public static let timelinePrefs = "timeline.prefs"

    /// Ids of the welcome items a fresh install creates; dropped on first
    /// sign-in if untouched, so every device doesn't add its own copy.
    public static let seedIds = "seed.ids"

    // MARK: Swift version only

    /// The four quadrants (JSON); see `MatrixPrefs`.
    public static let matrixPrefs = MatrixPrefs.storageKey

    /// Pomodoro lengths and the like (JSON); see `FocusSettings`.
    public static let focusSettings = FocusSettings.storageKey

    /// The focus timer as it stands (JSON of `FocusTimer`), so a run goes on
    /// after the app is killed and opened again; absent while idle with
    /// nothing to remember.
    public static let focusTimer = "focus.timer"

    /// Epoch milliseconds of the first time the Swift version opened this
    /// database. Its absence on a database with tables means the Flutter
    /// version made it, so `AppDatabase` backs it up first. Kept when
    /// signing out clears the table.
    public static let swiftOpenedAt = "swift.openedAt"

    /// What was searched for lately, newest first (JSON array of strings);
    /// see `RecentSearches`.
    public static let recentSearches = "search.recent"
}
