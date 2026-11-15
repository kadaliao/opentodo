/// Keys of the local-only [KeyValues] table.
abstract final class Keys {
  static const server = 'account.server';
  static const token = 'account.token';
  static const email = 'account.email';
  static const userId = 'account.userId';
  static const cursor = 'sync.cursor';
  static const lastSyncedAt = 'sync.lastSyncedAt';

  /// Reminders put off with 稍后提醒: task id → epoch milliseconds (JSON).
  static const snoozes = 'reminders.snoozed';

  /// What the notifications the system holds look like; when it changes,
  /// they are all handed over again (see `ReminderController`).
  static const reminderFormat = 'reminders.format';

  /// The person's settings (JSON); see `AppSettings`.
  static const settings = 'settings';

  /// List or board, grouping and order for each view (JSON); see
  /// `ViewPrefs`. (The name is from when it held only lists' layouts.)
  static const listPrefs = 'list.layouts';

  /// Calendar mode and display choices (JSON); see `CalendarPrefs`.
  static const calendarPrefs = 'calendar.prefs';

  /// Ids of the welcome items a fresh install creates; dropped on first
  /// sign-in if untouched, so every device doesn't add its own copy.
  static const seedIds = 'seed.ids';
}
