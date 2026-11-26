// `-OTOpen prefs:<state>` and `-OTOpen account:<state>` (debug builds):
// 设置 and 账号 straight away, on in-memory `LocalSettings`,
// `SyncController` and `ReminderController`, for screenshots. The window
// shows the settings content alone (macOS: at the Settings window's
// width; iOS: as the settings sheet would).
//
//     prefs:general | tasks | notifications | focus | about | account
//     prefs:denied        通知, notifications turned off
//     prefs:unasked       通知, never asked yet
//     prefs:custom        non-default values everywhere (one a newer version set)
//     account:signedOut   the sign-in form            account:register   注册
//     account:error       the form, with the server's message
//     account:signedIn    the account, synced 5 minutes ago, 3 changes waiting
//     account:syncing     the first sync running (iOS/Mac sheet)
//     account:syncError   a network error         account:authError  登录已失效
//     account:signOut     the sign-out confirmation
//     account:sidebar     the Mac sidebar's row, in each state

import OpenTodoData
import OpenTodoDomain
import SwiftUI

enum SettingsDebugState: String, CaseIterable {
    case general, tasks, notifications, focus, about, account, denied, unasked, custom

    var tab: SettingsTab {
        switch self {
        case .general, .custom: .general
        case .tasks: .tasks
        case .notifications, .denied, .unasked: .notifications
        case .focus: .focus
        case .about: .about
        case .account: .account
        }
    }
}

enum AccountDebugState: String, CaseIterable {
    case signedOut, register, error, signedIn, syncing, syncError, authError, signOut, sidebar
}

/// The demo objects a route shows.
@MainActor
struct DebugServices {
    let settings: LocalSettings
    let sync: SyncController
    let reminders: ReminderController

    static let account = Account(serverUrl: defaultServerUrl, token: "t", email: "kada@example.com", userId: "u")

    static func make(allowed: Bool?, custom: Bool = false, sync state: AccountDebugState? = nil) -> DebugServices {
        let db = try! AppDatabase.inMemory()
        let settings = LocalSettings(db)
        if custom {
            settings.set(AppSettings(defaults: TaskDefaults(timedReminders: [-30], allDayReminders: [-900], spanMinutes: 100), snoozeMinutes: 30))
            var cal = settings.calendarPrefs
            cal.showRepeats = false
            settings.setCalendarPrefs(cal)
            settings.setFocusSettings(FocusSettings(pomodoroMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 20, longBreakEvery: 3, autoStartNext: true))
        }
        let backend = MemoryReminderBackend(allow: allowed ?? true, asked: allowed != nil)
        let tokens = KeyValueTokenStore(db)
        let sync = SyncController(db, tokens: tokens)
        let now = Date()
        switch state {
        case nil, .signedOut, .register, .error:
            sync.setPreviewState(account: nil, status: SyncStatus(.signedOut))
        case .signedIn, .signOut, .sidebar:
            sync.setPreviewState(account: account, status: SyncStatus(.idle, lastSyncedAt: now - 5 * 60), pendingChanges: 3)
        case .syncing:
            sync.setPreviewState(account: account, status: SyncStatus(.syncing, lastSyncedAt: nil), progress: SyncReport(pushed: 4, pulled: 128))
        case .syncError:
            sync.setPreviewState(account: account, status: SyncStatus(.error, lastSyncedAt: now - 2 * 3600,
                                 error: networkError(URLError(.notConnectedToInternet))), pendingChanges: 1)
        case .authError:
            sync.setPreviewState(account: account, status: SyncStatus(.error, lastSyncedAt: now - 26 * 3600,
                                 error: SyncError("unauthorized", errorMessages["unauthorized"]!)))
        }
        let reminders = ReminderController(db, repo: TaskRepo(db), backend: backend)
        return DebugServices(settings: settings, sync: sync, reminders: reminders)
    }
}

/// Shows a `prefs:` or `account:` route in place of the window's content.
struct SettingsDebugPresenter: ViewModifier {
    let route: DebugRoute?
    var databaseURL: URL?

    func body(content: Content) -> some View {
        switch route {
        case .prefs(let s)?:
            if let state = SettingsDebugState(rawValue: s) {
                DebugFrame { SettingsDebugScreen(state: state) }
            } else {
                content
            }
        case .selftest(let name)?:
            ServicesSelfTestScreen(name: name, databaseURL: databaseURL)
        case .account(let s)?:
            if let state = AccountDebugState(rawValue: s) {
                DebugFrame { AccountDebugScreen(state: state) }
            } else {
                content
            }
        default:
            content
        }
    }
}

/// macOS: the content at its own size in the middle of the window, on the
/// window's background. iOS: in a navigation stack, as in the sheet.
private struct DebugFrame<C: View>: View {
    @ViewBuilder var content: C

    var body: some View {
        #if os(macOS)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.windowBackground)
        #else
        content
        #endif
    }
}

private struct SettingsDebugScreen: View {
    let state: SettingsDebugState
    @State private var services: DebugServices

    init(state: SettingsDebugState) {
        self.state = state
        let allowed: Bool? = switch state {
        case .denied: false
        case .unasked: nil
        default: true
        }
        _services = State(initialValue: .make(allowed: allowed, custom: state == .custom, sync: state == .account ? .signedIn : nil))
    }

    var body: some View {
        #if os(macOS)
        OpenTodoSettingsView(settings: services.settings, sync: services.sync, reminders: services.reminders, tab: state.tab, paneOnly: true)
        #else
        NavigationStack {
            OpenTodoSettingsView(settings: services.settings, sync: services.sync, reminders: services.reminders,
                                 tab: state == .account ? .account : .general)
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成", systemImage: "checkmark") {} }
                }
        }
        #endif
    }
}

private struct AccountDebugScreen: View {
    let state: AccountDebugState
    @State private var services: DebugServices

    init(state: AccountDebugState) {
        self.state = state
        _services = State(initialValue: .make(allowed: true, sync: state))
    }

    var body: some View {
        switch state {
        case .syncing:
            SignInSheet(sync: services.sync, email: DebugServices.account.email, server: nil, error: nil, signedIn: true)
        case .sidebar:
            sidebarRows
        default:
            #if os(macOS)
            AccountPane(sync: services.sync, confirmingSignOut: state == .signOut, error: formError, register: state == .register)
                .frame(width: 520, height: 420)
            #else
            NavigationStack {
                AccountPane(sync: services.sync, confirmingSignOut: state == .signOut, error: formError, register: state == .register)
                    .navigationBarTitleDisplayMode(.inline)
            }
            #endif
        }
    }

    private var formError: String? {
        state == .error ? errorMessages["invalid_credentials"] : nil
    }

    /// Every state of the sidebar row, stacked as at the bottom of a sidebar.
    private var sidebarRows: some View {
        let now = Date()
        let a = DebugServices.account
        let rows: [(Account?, SyncStatus, SyncReport?)] = [
            (nil, SyncStatus(.signedOut), nil),
            (a, SyncStatus(.idle, lastSyncedAt: now - 300), nil),
            (a, SyncStatus(.syncing), SyncReport(pushed: 0, pulled: 42)),
            (a, SyncStatus(.error, error: networkError(URLError(.notConnectedToInternet))), nil),
            (a, SyncStatus(.error, error: SyncError("unauthorized", errorMessages["unauthorized"]!)), nil),
        ]
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                AccountSidebarRow(account: rows[i].0, status: rows[i].1, progress: rows[i].2, pendingChanges: 2, now: now,
                                  onSignIn: {}, onSyncNow: {}, onSignInAgain: {}, onSignOut: {}, onShowAccount: {})
                Divider()
            }
        }
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
    }
}
