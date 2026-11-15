/// Keys of the local-only [KeyValues] table.
abstract final class Keys {
  static const server = 'account.server';
  static const token = 'account.token';
  static const email = 'account.email';
  static const userId = 'account.userId';
  static const cursor = 'sync.cursor';
  static const lastSyncedAt = 'sync.lastSyncedAt';

  /// Ids of the welcome items a fresh install creates; dropped on first
  /// sign-in if untouched, so every device doesn't add its own copy.
  static const seedIds = 'seed.ids';
}
