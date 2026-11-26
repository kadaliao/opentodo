// The local-only `key_values` table: account, sync cursor, settings and the
// other JSON blobs named in `Keys`. Never synced. `getValue` / `setValue`
// are `db.dart`'s; setting nil deletes the key.

import GRDB

extension Database {
    /// The text stored under `key`, inside a read or write.
    public func value(forKey key: String) throws -> String? {
        try String.fetchOne(self, sql: "SELECT value FROM key_values WHERE key = ?", arguments: [key])
    }

    /// Stores `value` under `key`, or deletes the key when it is nil.
    public func setValue(_ value: String?, forKey key: String) throws {
        if let value {
            try execute(
                sql: "INSERT INTO key_values (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key, value]
            )
        } else {
            try execute(sql: "DELETE FROM key_values WHERE key = ?", arguments: [key])
        }
    }
}

extension AppDatabase {
    public func getValue(_ key: String) async throws -> String? {
        try await writer.read { try $0.value(forKey: key) }
    }

    public func setValue(_ key: String, _ value: String?) async throws {
        try await writer.write { try $0.setValue(value, forKey: key) }
    }

    /// Blocking forms, for callers that can't await (the keychain-less
    /// token store, app start-up).
    public func getValueNow(_ key: String) throws -> String? {
        try writer.read { try $0.value(forKey: key) }
    }

    public func setValueNow(_ key: String, _ value: String?) throws {
        try writer.write { try $0.setValue(value, forKey: key) }
    }

    /// The value under `key` now and after every change (nil while unset).
    public func observeValue(_ key: String) -> DatabaseObservation<String?> {
        observe { try $0.value(forKey: key) }
    }
}
