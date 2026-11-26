// 账号 (照 app/lib/ui/account_ui.dart): signing in or registering, the
// signed-in account with how syncing is going, and the row at the bottom
// of the Mac sidebar. The parts here take values and report through
// callbacks; `AccountBound.swift` ties them to `SyncController`.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

// MARK: - Sign in

/// The sign-in / register form's fields. The caller sends the request and
/// passes back `busy` and `error`.
struct SignInFields: View {
    @Environment(\.uiScale) private var s
    @Binding var request: SignInRequest
    let busy: Bool
    let error: String?
    var onSubmit: () -> Void

    @FocusState private var focus: Field?
    private enum Field { case email, password, server }

    // A Mac form shows the field's name beside it, an iPhone form only the
    // prompt: there the prompt has to say what the field is.
    #if os(macOS)
    private static let emailPrompt = "name@example.com"
    private var passwordPrompt: String { request.register ? "至少 8 位" : "必填" }
    #else
    private static let emailPrompt = "邮箱"
    private var passwordPrompt: String { request.register ? "密码（至少 8 位）" : "密码" }
    #endif

    var body: some View {
        Section {
            TextField("邮箱", text: $request.email, prompt: Text(Self.emailPrompt))
                .textContentType(.username)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }
            SecureField("密码", text: $request.password, prompt: Text(passwordPrompt))
                .textContentType(request.register ? .newPassword : .password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(onSubmit)
        } header: {
            Picker("", selection: $request.register) {
                Text("登录").tag(false)
                Text("注册").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            .textCase(nil)
            .padding(.bottom, 6 * s)
        } footer: {
            Group {
                VStack(alignment: .leading, spacing: 6 * s) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("出错了：\(error)")
                    }
                    if !request.register {
                        Text("登录后，这台设备上已有的任务会合并进账号。")
                    }
                }
            }
            .uiDefaultFont(.subheadline)
        }
        .disabled(busy)
        Section {
            DisclosureGroup("服务器") {
                TextField("服务器地址", text: $request.server, prompt: Text(defaultServerUrl))
                    .textContentType(.URL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .focused($focus, equals: .server)
            }
        } footer: {
            Group {
                Text("默认是官方的同步服务；自己部署的服务器填它的地址。")
            }
            .uiDefaultFont(.subheadline)
        }
        .disabled(busy)
    }
}

/// The submit button: 登录 / 注册并登录, a spinner while it goes.
struct SignInButton: View {
    let request: SignInRequest
    let busy: Bool
    var onSubmit: () -> Void

    var body: some View {
        Button(action: onSubmit) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Text(request.submitTitle)
            }
        }
        .disabled(busy)
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Signed in

/// The signed-in account: who, how syncing is going, what's waiting, and
/// 立即同步 / 重新登录 / 退出登录 (with the confirmation that says what will be
/// lost).
struct AccountSummary: View {
    @Environment(\.uiScale) private var s
    let account: Account
    let status: SyncStatus
    let progress: SyncReport?
    let pendingChanges: Int
    let now: Date
    var onSyncNow: () -> Void
    var onSignInAgain: () -> Void
    var onSignOut: () -> Void

    @State var confirming = false

    var body: some View {
        Group { sections }
            .confirmationDialog(SignOutConfirmation.title, isPresented: $confirming, titleVisibility: .visible) {
                Button(SignOutConfirmation.action, role: .destructive, action: onSignOut)
                Button("取消", role: .cancel) {}
            } message: {
                Text(SignOutConfirmation(pendingChanges: pendingChanges).message)
            }
    }

    @ViewBuilder private var sections: some View {
        let line = SyncLine(status, progress: progress, now: now)
        Section {
            HStack(spacing: 12 * s) {
                Image(systemName: "person.crop.circle.fill")
                    .uiFont(size: 40)
                    .foregroundStyle(.white, Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(account.email).uiFont(.headline).lineLimit(1).truncationMode(.middle)
                    Text(serverName(account.serverUrl)).uiFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.vertical, 2 * s)
        }
        Section {
            LabeledContent {
                HStack(spacing: 6 * s) {
                    if status.phase == .syncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: line.symbol).foregroundStyle(line.error ? .red : .secondary)
                    }
                    Text(line.text)
                        .foregroundStyle(line.error ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                }
            } label: {
                Text("同步")
            }
            LabeledContent("未同步的改动", value: pendingChanges == 0 ? "没有" : "\(pendingChanges) 条")
            #if os(macOS)
            LabeledContent {
                HStack {
                    if status.error?.isAuth == true { Button("重新登录…", action: onSignInAgain) }
                    Button("立即同步", action: onSyncNow).disabled(status.phase == .syncing)
                }
            } label: {
                Text("改动会在两秒后自动同步，之后每分钟、回到应用时也会同步。")
                    .uiFont(.callout)
                    .foregroundStyle(.secondary)
            }
            #else
            if status.error?.isAuth == true {
                Button("重新登录", action: onSignInAgain)
            }
            Button("立即同步", action: onSyncNow)
                .disabled(status.phase == .syncing)
            #endif
        } footer: {
            Group {
                #if os(macOS)
                HStack {
                    Spacer()
                    Button("退出登录…") { confirming = true }
                }
                .padding(.top, 8 * s)
                #else
                Text("改动会在两秒后自动同步，之后每分钟、回到应用时也会同步。")
                #endif
            }
            .uiDefaultFont(.subheadline)
        }
        #if os(iOS)
        Section {
            Button("退出登录", role: .destructive) { confirming = true }
        }
        #endif
    }

    private func serverName(_ url: String) -> String {
        url == defaultServerUrl ? "官方同步服务" : url
    }
}

// MARK: - The Mac sidebar's row

/// The bottom of the Mac sidebar: 登录以同步, or the account and its sync
/// state. A click signs in or syncs; the menu has the rest.
struct AccountSidebarRow: View {
    @Environment(\.uiScale) private var s
    let account: Account?
    let status: SyncStatus
    let progress: SyncReport?
    let pendingChanges: Int
    let now: Date
    var onSignIn: () -> Void
    var onSyncNow: () -> Void
    var onSignInAgain: () -> Void
    var onSignOut: () -> Void
    var onShowAccount: () -> Void

    @State private var confirming = false

    var body: some View {
        let line = SyncLine(status, progress: progress, now: now)
        HStack(spacing: 8 * s) {
            Button(action: account == nil ? onSignIn : onSyncNow) {
                HStack(spacing: 8 * s) {
                    icon(line)
                        .frame(width: 22 * s)
                    VStack(alignment: .leading, spacing: 1 * s) {
                        Text(account?.email ?? "登录以同步")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(account == nil ? "在手机和电脑之间同步任务" : line.text)
                            .uiFont(.caption)
                            .foregroundStyle(line.error ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(account == nil ? "登录以同步" : "立即同步")
            if account != nil {
                Menu {
                    Button("立即同步", systemImage: "arrow.triangle.2.circlepath", action: onSyncNow)
                    if status.error?.isAuth == true {
                        Button("重新登录", systemImage: "person.badge.key", action: onSignInAgain)
                    }
                    Button("账号设置…", systemImage: "person.crop.circle", action: onShowAccount)
                    Divider()
                    Button("退出登录…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirming = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("账号")
            }
        }
        .padding(.horizontal, 10 * s)
        .padding(.vertical, 8 * s)
        .accessibilityElement(children: .contain)
        .confirmationDialog(SignOutConfirmation.title, isPresented: $confirming, titleVisibility: .visible) {
            Button(SignOutConfirmation.action, role: .destructive, action: onSignOut)
            Button("取消", role: .cancel) {}
        } message: {
            Text(SignOutConfirmation(pendingChanges: pendingChanges).message)
        }
    }

    @ViewBuilder private func icon(_ line: SyncLine) -> some View {
        if account == nil {
            Image(systemName: "icloud.slash").foregroundStyle(.secondary)
        } else if status.phase == .syncing {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: line.symbol).foregroundStyle(line.error ? .red : .secondary)
        }
    }
}

/// The row at the top of the iOS settings: the account, like the Apple
/// Account row of the system Settings.
struct AccountSettingsRow: View {
    @Environment(\.uiScale) private var s
    let account: Account?
    let status: SyncStatus
    let progress: SyncReport?
    let now: Date

    var body: some View {
        let line = SyncLine(status, progress: progress, now: now)
        HStack(spacing: 14 * s) {
            Image(systemName: account == nil ? "person.crop.circle" : "person.crop.circle.fill")
                .uiFont(size: 44)
                .foregroundStyle(account == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.accent))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(account?.email ?? "登录以同步").uiFont(.title3, weight: .semibold).lineLimit(1).truncationMode(.middle)
                Text(account == nil ? "在手机和电脑之间同步任务" : line.text)
                    .uiFont(.subheadline)
                    .foregroundStyle(line.error ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4 * s)
    }
}
