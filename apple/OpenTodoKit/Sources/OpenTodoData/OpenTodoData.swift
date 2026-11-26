// The data layer: GRDB (SQLite) database and migrations, `TaskRepo`, local
// settings, sync and reminder scheduling. See docs/apple.md §1 and §3.
//
// Main entry points:
//   AppDatabase            open / openReadOnly (widgets) / inMemory, getValue / setValue,
//                          observe…() for the UI; defaultURL() picks the App Group container
//   TaskRepo               every write (tasks, lists, sections, filters, checklist, seed)
//   EfficiencyRepo         habits, check-ins, focus sessions, countdowns (schema 8)
//   LocalSettings          AppSettings, ViewPrefs, TimelinePrefs, CalendarPrefs, MatrixPrefs,
//                          FocusSettings, the running FocusTimer (@Observable)
//   SyncController         account, sign in / out, when to sync, SyncStatus (@Observable)
//   ReminderController     reminders handed to the system, 完成 / 稍后提醒 (@Observable)
//   SystemReminderBackend  UNUserNotificationCenter; MemoryReminderBackend for tests
//   TokenStore             defaultTokenStore(for:), moveLegacyToken(from:into:)
//   SyncEngine, AuthApi    one sync pass, the sign-in API (used by SyncController)
//   WireRecord             the sync wire format (`model.wire`, `Model(wire:)`)

@_exported import OpenTodoDomain
