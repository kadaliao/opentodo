// Where the sign-in token is kept. The app uses the keychain; tests (and a
// device where the keychain can't be used) keep it in `key_values` under
// `Keys.token`, where the Flutter version kept it. The rest of the account
// (server, email, user id) stays in `key_values` either way.
//
// At start-up the app does
//
//     let tokens = defaultTokenStore(for: db)
//     try moveLegacyToken(from: db, into: tokens)
//
// so a token the Flutter version left in the database goes into the
// keychain and out of the database.

import Foundation
import GRDB
import Security

public protocol TokenStore: Sendable {
    func token() throws -> String?
    /// Stores the token; nil removes it.
    func setToken(_ token: String?) throws
}

/// The token in `key_values` (`Keys.token`).
public struct KeyValueTokenStore: TokenStore {
    public let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func token() throws -> String? {
        try database.getValueNow(Keys.token)
    }

    public func setToken(_ token: String?) throws {
        try database.setValueNow(Keys.token, token)
    }
}

/// The token as a generic password in the keychain (the data-protection
/// keychain on macOS too), readable after the first unlock so a sync in
/// the background can use it.
public struct KeychainTokenStore: TokenStore {
    public let service: String
    public let account: String
    /// A shared access group (for widgets and extensions later); nil uses
    /// the app's own.
    public let accessGroup: String?
    /// The data-protection keychain (iOS's only one; on macOS it needs the
    /// `application-identifier` entitlement, which only a build with a
    /// provisioning profile has). False: macOS's file-based login keychain,
    /// which a sandboxed app can keep its own items in without it.
    public let dataProtection: Bool

    /// `service` defaults to the bundle id, so the debug build keeps its
    /// own token.
    public init(
        service: String = (Bundle.main.bundleIdentifier ?? "com.liaoxingyi.opentodo") + ".sync",
        account: String = "token",
        accessGroup: String? = nil,
        dataProtection: Bool = true
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.dataProtection = dataProtection
    }

    private var query: [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtection,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    public func token() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public func setToken(_ token: String?) throws {
        guard let token else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(token.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, CustomStringConvertible {
    public let status: OSStatus
    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? ""
        return "钥匙串出错（\(status)）\(message)"
    }
}

/// The store the app should use: the keychain; on macOS without the
/// entitlement for the data-protection keychain, the login keychain; the
/// database only where neither can be written (`swift test`, unsigned).
/// A token in the login keychain moves into the data-protection one once
/// a build can use that.
public func defaultTokenStore(for database: AppDatabase, keychain: KeychainTokenStore = KeychainTokenStore()) -> any TokenStore {
    #if os(macOS)
    let login = KeychainTokenStore(service: keychain.service, account: keychain.account, accessGroup: nil, dataProtection: false)
    if keychain.isUsable {
        if login.isUsable, let token = try? login.token(), (try? keychain.token()) == nil {
            try? keychain.setToken(token)
            try? login.setToken(nil)
        }
        return keychain
    }
    return login.isUsable ? login : KeyValueTokenStore(database)
    #else
    return keychain.isUsable ? keychain : KeyValueTokenStore(database)
    #endif
}

extension KeychainTokenStore {
    /// Whether items can be written here. (Without the entitlement a read
    /// still answers "not found"; only a write tells.)
    public var isUsable: Bool {
        let probe = KeychainTokenStore(service: service, account: account + ".probe", accessGroup: accessGroup, dataProtection: dataProtection)
        do {
            try probe.setToken("probe")
            try probe.setToken(nil)
            return true
        } catch {
            return false
        }
    }
}

/// Moves a token the Flutter version left in `key_values` into `store` and
/// deletes it from the database (only once `store` has it, so a failure
/// leaves it where it was). Nothing to do for a store that is the
/// database, or when there is no such token.
///
/// The database's token replaces one already in `store`: it is always the
/// newer sign-in (the Swift version moves its own out at every launch, so
/// one there was written later, by the Flutter version or by a launch
/// without the keychain), and the server, email and user id beside it are
/// that sign-in's. Keeping the keychain's would pair one account's token
/// with another's cursor and data.
public func moveLegacyToken(from database: AppDatabase, into store: any TokenStore) throws {
    guard !(store is KeyValueTokenStore) else { return }
    guard let legacy = try database.getValueNow(Keys.token) else { return }
    if try store.token() != legacy {
        try store.setToken(legacy)
    }
    try database.setValueNow(Keys.token, nil)
}
