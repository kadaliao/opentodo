// The signed-in account and the sign-in API, ported from
// `app/lib/sync/account.dart`. The token goes through a `TokenStore`
// (the keychain in the app); the server, email and user id stay in
// `key_values`.

import Foundation
import GRDB

/// The hosted sync service. The sign-in screen can point at another one
/// (a local `go run ./cmd/opentodo-server` is http://127.0.0.1:8686).
public let defaultServerUrl = "https://todo.liaoxingyi.com"

public struct Account: Sendable, Hashable {
    public var serverUrl: String
    public var token: String
    public var email: String
    public var userId: String

    public init(serverUrl: String, token: String, email: String, userId: String) {
        self.serverUrl = serverUrl
        self.token = token
        self.email = email
        self.userId = userId
    }

    /// The signed-in account, or nil when there is no token.
    ///
    /// Also nil when the database has no account beside the token (every
    /// sign-in stores the server there, before the token): the keychain
    /// outlives the database, so its token may be from before the database
    /// was cleared (signed out in the Flutter version, which clears
    /// `key_values` but can't reach the keychain) and belong to no one
    /// here.
    public static func load(_ db: AppDatabase, tokens: any TokenStore) async throws -> Account? {
        guard let token = try tokens.token() else { return nil }
        return try await db.writer.read { db in
            guard let server = try db.value(forKey: Keys.server) else { return nil }
            return Account(
                serverUrl: server,
                token: token,
                email: try db.value(forKey: Keys.email) ?? "",
                userId: try db.value(forKey: Keys.userId) ?? ""
            )
        }
    }

    /// Everything but the token, inside a write; see `saveToken`.
    func save(_ db: Database) throws {
        try db.setValue(serverUrl, forKey: Keys.server)
        try db.setValue(email, forKey: Keys.email)
        try db.setValue(userId, forKey: Keys.userId)
    }

    /// The token goes last, after the rest is committed: without it the
    /// device counts as signed out, so a failure in between leaves no
    /// half-signed-in state.
    func saveToken(_ tokens: any TokenStore) throws {
        try tokens.setToken(token)
    }
}

/// An error the person can act on, already in their words.
public struct SyncError: Error, Sendable, Hashable, CustomStringConvertible, LocalizedError {
    public let code: String
    public let message: String

    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }

    public var isAuth: Bool { code == "unauthorized" }
    public var description: String { message }
    public var errorDescription: String? { message }
}

package let errorMessages = [
    "invalid_email": "邮箱格式不对",
    "weak_password": "密码至少 8 位",
    "email_taken": "这个邮箱已经注册过，请直接登录",
    "invalid_credentials": "邮箱或密码不正确",
    "unauthorized": "登录已失效，请重新登录",
    "rate_limited": "尝试太频繁，请一分钟后再试",
]

/// The error a failed response stands for: the server's code if the body
/// has one (`{"error":{"code":…}}`), otherwise `http_<status>`.
public func errorFrom(status: Int, body: Data) -> SyncError {
    var code = "http_\(status)"
    if let c = (JSONValue(parsing: body))?["error"]?["code"]?.stringValue {
        code = c
    }
    return SyncError(code, errorMessages[code] ?? "服务器出错（\(status)），请稍后再试")
}

public func networkError(_ error: any Error) -> SyncError {
    SyncError("network", "连不上服务器，请检查网络或服务器地址（\(error.localizedDescription)）")
}

/// Trims, adds `https://` when there is no scheme, drops trailing slashes;
/// empty means the hosted service.
public func normalizeServerUrl(_ url: String) -> String {
    var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
    if u.isEmpty { return defaultServerUrl }
    if !u.hasPrefix("http://") && !u.hasPrefix("https://") { u = "https://" + u }
    while u.hasSuffix("/") { u.removeLast() }
    return u
}

/// What the server is told this device is (Dart's `Platform.operatingSystem`).
let deviceName: String = {
    #if os(macOS)
    "macos"
    #elseif os(iOS)
    "ios"
    #else
    "unknown"
    #endif
}()

/// Posts JSON and returns the status and body; transport failures become
/// `networkError`.
func post(_ session: URLSession, _ url: String, body: JSONValue?, token: String?, timeout: TimeInterval) async throws -> (Int, Data) {
    guard let u = URL(string: url) else { throw SyncError("network", "服务器地址不对（\(url)）") }
    var request = URLRequest(url: u, timeoutInterval: timeout)
    request.httpMethod = "POST"
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.encodedData
    }
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    do {
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    } catch {
        throw networkError(error)
    }
}

public struct AuthApi: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Signs in (or registers) and returns the account; nothing is stored
    /// until `completeSignIn`.
    public func signIn(serverUrl: String, email: String, password: String, register: Bool) async throws -> Account {
        let server = normalizeServerUrl(serverUrl)
        let body: JSONValue = .fields([
            ("email", .string(email.trimmingCharacters(in: .whitespacesAndNewlines))),
            ("password", .string(password)),
            ("device", .string(deviceName)),
        ])
        let (status, data) = try await post(
            session, "\(server)/v1/auth/\(register ? "register" : "login")", body: body, token: nil, timeout: 20
        )
        guard status == 200 || status == 201 else { throw errorFrom(status: status, body: data) }
        guard let json = JSONValue(parsing: data),
              let token = json["token"]?.stringValue,
              let email = json["user"]?["email"]?.stringValue,
              let userId = json["user"]?["id"]?.stringValue
        else { throw SyncError("bad_response", "服务器出错（\(status)），请稍后再试") }
        return Account(serverUrl: server, token: token, email: email, userId: userId)
    }

    /// Best effort: the local sign-out happens even if the server can't be
    /// reached.
    public func signOut(_ account: Account) async {
        _ = try? await post(session, "\(account.serverUrl)/v1/auth/logout", body: nil, token: account.token, timeout: 10)
    }
}
