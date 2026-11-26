// The signed-in account and when to sync, for the UI to watch; ported from
// `AccountNotifier` and `SyncController` in `app/lib/state/sync_providers.dart`.
// Signed in, it syncs right away, 2 seconds after local changes settle,
// every minute, when the app comes back to the foreground, and on demand.
//
//     let sync = SyncController(db, tokens: tokens)
//     await sync.start()                          // at launch
//     try await sync.signIn(serverUrl: url, email: e, password: p, register: false)  // throws SyncError
//     sync.account, sync.status.phase, sync.status.lastSyncedAt, sync.status.error?.message
//     sync.appDidBecomeActive()                   // from scenePhase == .active
//     await sync.signOut()                        // clears this account's data from the device

import Foundation
import Observation

public enum SyncPhase: Sendable, Hashable {
    case signedOut, idle, syncing, error
}

public struct SyncStatus: Sendable, Hashable {
    public var phase: SyncPhase
    public var lastSyncedAt: Date?
    /// What went wrong, in the person's words; `isAuth` means sign in again.
    public var error: SyncError?

    public init(_ phase: SyncPhase, lastSyncedAt: Date? = nil, error: SyncError? = nil) {
        self.phase = phase
        self.lastSyncedAt = lastSyncedAt
        self.error = error
    }
}

@MainActor @Observable
public final class SyncController {
    /// The signed-in account, or nil.
    public private(set) var account: Account?
    public private(set) var status = SyncStatus(.signedOut)
    /// Local changes not on the server yet (for 未同步的改动 and the
    /// sign-out warning). Kept up to date whether signed in or not.
    public private(set) var pendingChanges = 0
    /// While a sync runs: what it has pushed and pulled so far.
    public private(set) var progress: SyncReport?

    public let database: AppDatabase
    public let tokens: any TokenStore
    public let session: URLSession
    @ObservationIgnored private let engine: SyncEngine
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let interval: Duration

    @ObservationIgnored private var dirty: ObservationHandle?
    @ObservationIgnored private var counting: ObservationHandle?
    @ObservationIgnored private var periodic: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    /// Bumped on every sign-in and sign-out, so a sync still running for
    /// the previous account doesn't report into the new state.
    @ObservationIgnored private var generation = 0

    public init(
        _ database: AppDatabase,
        tokens: any TokenStore,
        session: URLSession = .shared,
        debounce: Duration = .seconds(2),
        interval: Duration = .seconds(60),
        pageSize: Int = 500
    ) {
        self.database = database
        self.tokens = tokens
        self.session = session
        self.debounce = debounce
        self.interval = interval
        engine = SyncEngine(database, session: session, tokens: tokens, pageSize: pageSize)
    }

    /// Loads the account and, if there is one, starts syncing.
    public func start() async {
        if counting == nil {
            counting = database.observeDirtyCount().start { [weak self] n in self?.pendingChanges = n }
        }
        account = try? await Account.load(database, tokens: tokens)
        if account != nil { await begin() } else { status = SyncStatus(.signedOut) }
    }

    /// Signs in or registers, starting from the account's data (untouched
    /// welcome items dropped), then syncs. Throws `SyncError` with a
    /// message for the person; nothing changes then.
    public func signIn(serverUrl: String, email: String, password: String, register: Bool) async throws {
        let account = try await AuthApi(session: session).signIn(
            serverUrl: serverUrl, email: email, password: password, register: register
        )
        end()
        try await completeSignIn(database, account, tokens: tokens)
        self.account = account
        await begin()
    }

    /// Signs out: tells the server (best effort) and removes this account's
    /// data, settings and token from the device.
    public func signOut() async {
        let account = self.account
        end()
        if let account { await AuthApi(session: session).signOut(account) }
        do {
            try await clearLocalData(database, tokens: tokens)
        } catch {
            status = SyncStatus(.signedOut, error: SyncError("unknown", "退出时清理数据出错：\(error.localizedDescription)"))
        }
        self.account = nil
    }

    /// Back in the foreground.
    public func appDidBecomeActive() {
        guard account != nil else { return }
        Task { await syncNow() }
    }

    public func stop() { end() }

    /// Syncs now, or once more right after the one running.
    public func syncNow() async {
        guard account != nil, status.phase != .signedOut else { return }
        if running {
            again = true
            return
        }
        running = true
        defer { running = false }
        let generation = self.generation
        let last = status.lastSyncedAt
        status = SyncStatus(.syncing, lastSyncedAt: last)
        progress = SyncReport(pushed: 0, pulled: 0)
        defer { progress = nil }
        do {
            repeat {
                again = false
                try await engine.sync { [weak self] report in
                    Task { @MainActor in
                        guard let self, self.generation == generation, self.running else { return }
                        self.progress = report
                    }
                }
            } while again && generation == self.generation
            guard generation == self.generation else { return followNewAccount() }
            status = SyncStatus(.idle, lastSyncedAt: Date())
        } catch {
            guard generation == self.generation else { return followNewAccount() }
            let e = error as? SyncError ?? SyncError("unknown", "同步出错：\(error.localizedDescription)")
            status = SyncStatus(.error, lastSyncedAt: last, error: e)
        }
    }

    // MARK: Private

    /// The account changed while a sync ran: the new one's first sync was
    /// held back by it, so run it now (after this one has let go).
    private func followNewAccount() {
        guard account != nil else { return }
        Task { await syncNow() }
    }

    private func begin() async {
        generation += 1
        let ms = (try? await database.getValue(Keys.lastSyncedAt)).flatMap { $0 }.flatMap { Int($0) }
        status = SyncStatus(.idle, lastSyncedAt: ms.map { Date(timeIntervalSince1970: Double($0) / 1000) })
        dirty = database.observeDirtyCount().start { [weak self] n in
            if n > 0 { self?.syncSoon() }
        }
        periodic = Task { [weak self, interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.syncNow()
            }
        }
        Task { await syncNow() }
    }

    private func end() {
        generation += 1
        dirty?.cancel()
        dirty = nil
        periodic?.cancel()
        periodic = nil
        pending?.cancel()
        pending = nil
        again = false
        status = SyncStatus(.signedOut)
    }

    /// After local changes settle.
    private func syncSoon() {
        pending?.cancel()
        pending = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    // MARK: Previews

    /// Puts the controller in a state without a server, for previews,
    /// screenshots and UI tests (within the package only).
    package func setPreviewState(account: Account?, status: SyncStatus, pendingChanges: Int = 0, progress: SyncReport? = nil) {
        end()
        self.account = account
        self.status = status
        self.pendingChanges = pendingChanges
        self.progress = progress
    }
}
