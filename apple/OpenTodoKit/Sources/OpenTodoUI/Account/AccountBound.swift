// The account views tied to `SyncController`: what the settings, the Mac
// sidebar and a sign-in sheet put on screen.
//
//     AccountPane(sync: services.sync)                  // 设置 › 账号
//     AccountSidebarItem(sync: services.sync) { … }     // bottom of the Mac sidebar
//     .sheet(…) { SignInSheet(sync: services.sync) }   // 登录 / 重新登录

import OpenTodoData
import OpenTodoDomain
import SwiftUI

/// Sends `request`; the message to show if it fails, nil if signed in.
@MainActor
func send(_ request: SignInRequest, to sync: SyncController) async -> String? {
    if let problem = request.problem { return problem }
    do {
        try await sync.signIn(serverUrl: request.server, email: request.email, password: request.password, register: request.register)
        return nil
    } catch let e as SyncError {
        return e.message
    } catch {
        return error.localizedDescription
    }
}

/// 设置 › 账号: the sign-in form while signed out, the account once in.
public struct AccountPane: View {
    let sync: SyncController
    @State private var request: SignInRequest
    @State private var busy = false
    @State private var error: String?
    @State private var signingInAgain = false
    private let confirmingSignOut: Bool

    public init(sync: SyncController) {
        self.init(sync: sync, confirmingSignOut: false)
    }

    /// For debug routes: open on the sign-out confirmation, or a form error.
    init(sync: SyncController, confirmingSignOut: Bool, error: String? = nil, register: Bool = false) {
        self.sync = sync
        self.confirmingSignOut = confirmingSignOut
        _request = State(initialValue: SignInRequest(email: error == nil ? "" : "me@example.com", password: "",
                                                     server: defaultServerUrl, register: register))
        _error = State(initialValue: error)
    }

    public var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
            Form {
                if let account = sync.account {
                    AccountSummary(
                        account: account, status: sync.status, progress: sync.progress,
                        pendingChanges: sync.pendingChanges, now: context.date,
                        onSyncNow: { Task { await sync.syncNow() } },
                        onSignInAgain: { signingInAgain = true },
                        onSignOut: { Task { await sync.signOut() } },
                        confirming: confirmingSignOut
                    )
                } else {
                    SignInFields(request: $request, busy: busy, error: error, onSubmit: submit)
                    #if os(macOS)
                    Section {} footer: {
                        HStack {
                            Spacer()
                            SignInButton(request: request, busy: busy, onSubmit: submit)
                        }
                    }
                    #else
                    Section {
                        SignInButton(request: request, busy: busy, onSubmit: submit)
                            .frame(maxWidth: .infinity)
                    }
                    #endif
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("账号")
        .sheet(isPresented: $signingInAgain) {
            SignInSheet(sync: sync, email: sync.account?.email, server: sync.account?.serverUrl)
        }
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            error = await send(request, to: sync)
            busy = false
            if error == nil { request.password = "" }
        }
    }
}

/// Signing in in a sheet (from the sidebar, or 重新登录): the form, then the
/// first sync's progress, then it closes on its own.
public struct SignInSheet: View {
    let sync: SyncController
    @Environment(\.dismiss) private var dismiss
    @State private var request: SignInRequest
    @State private var busy = false
    @State private var error: String?
    @State private var signedIn = false

    public init(sync: SyncController, email: String? = nil, server: String? = nil) {
        self.init(sync: sync, email: email, server: server, error: nil, signedIn: false)
    }

    /// For debug routes: open on an error, or on the first sync.
    init(sync: SyncController, email: String?, server: String?, error: String?, signedIn: Bool, register: Bool = false) {
        self.sync = sync
        _request = State(initialValue: SignInRequest(email: email ?? "", password: error == nil ? "" : "password",
                                                     server: server ?? defaultServerUrl, register: register))
        _error = State(initialValue: error)
        _signedIn = State(initialValue: signedIn)
    }

    public var body: some View {
        NavigationStack {
            Form {
                if signedIn {
                    FirstSyncSection(status: sync.status, progress: sync.progress)
                } else {
                    SignInFields(request: $request, busy: busy, error: error, onSubmit: submit)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(signedIn ? "已登录" : request.register ? "注册账号" : "登录账号")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !signedIn { Button("取消") { dismiss() }.disabled(busy) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if signedIn {
                        Button("完成") { dismiss() }
                    } else {
                        SignInButton(request: request, busy: busy, onSubmit: submit)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: signedIn ? 220 : 400)
        #endif
        .onChange(of: sync.status.phase) { _, phase in
            // The first sync is done: nothing left to watch.
            if signedIn && phase == .idle { dismiss() }
        }
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            error = await send(request, to: sync)
            busy = false
            if error == nil { signedIn = true }
        }
    }
}

/// After signing in: the first sync, which can take a while.
struct FirstSyncSection: View {
    let status: SyncStatus
    let progress: SyncReport?

    var body: some View {
        Section {
            switch status.phase {
            case .error:
                Label(status.error?.message ?? "同步失败", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.red)
            case .idle:
                Label("同步完成", systemImage: "checkmark.icloud")
            default:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(SyncLine(status, progress: progress, now: .now).text)
                }
            }
        } footer: {
            Text("第一次同步会把这台设备上的任务和账号里的合在一起。")
        }
    }
}

/// The bottom of the Mac sidebar, tied to `SyncController`. `onShowAccount`
/// opens 设置 › 账号.
public struct AccountSidebarItem: View {
    let sync: SyncController
    var onShowAccount: () -> Void
    @State private var signingIn = false

    public init(sync: SyncController, onShowAccount: @escaping () -> Void) {
        self.sync = sync
        self.onShowAccount = onShowAccount
    }

    public var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
            AccountSidebarRow(
                account: sync.account, status: sync.status, progress: sync.progress,
                pendingChanges: sync.pendingChanges, now: context.date,
                onSignIn: { signingIn = true },
                onSyncNow: { Task { await sync.syncNow() } },
                onSignInAgain: { signingIn = true },
                onSignOut: { Task { await sync.signOut() } },
                onShowAccount: onShowAccount
            )
        }
        .sheet(isPresented: $signingIn) {
            SignInSheet(sync: sync, email: sync.account?.email, server: sync.account?.serverUrl)
        }
    }
}
