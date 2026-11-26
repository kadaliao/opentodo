// How the account and sync read (照 app/lib/ui/account_ui.dart), as plain
// values for the views and the tests.

import Foundation
import OpenTodoData
import OpenTodoDomain

/// The one-line sync state under the email: an SF Symbol, the words, and
/// whether it's a problem.
struct SyncLine: Equatable {
    var symbol: String
    var text: String
    var error: Bool

    init(_ status: SyncStatus, progress: SyncReport? = nil, now: Date, timeZone: TimeZone = .current) {
        switch status.phase {
        case .signedOut:
            self.init(symbol: "icloud.slash", text: "未登录", error: false)
        case .syncing:
            let pulled = progress?.pulled ?? 0
            self.init(symbol: "arrow.triangle.2.circlepath", text: pulled > 0 ? "正在同步…已收到 \(pulled) 条" : "正在同步…", error: false)
        case .error:
            self.init(symbol: "exclamationmark.icloud", text: status.error?.message ?? "同步失败", error: true)
        case .idle:
            self.init(
                symbol: "checkmark.icloud",
                text: status.lastSyncedAt.map { "\(agoText($0, now: now, timeZone: timeZone))同步" } ?? "已登录",
                error: false
            )
        }
    }

    init(symbol: String, text: String, error: Bool) {
        self.symbol = symbol
        self.text = text
        self.error = error
    }
}

/// 刚刚 / 5 分钟前 / 3 小时前 / 昨天 (`AccountTile._ago`).
func agoText(_ at: Date, now: Date, timeZone: TimeZone = .current) -> String {
    let seconds = now.timeIntervalSince(at)
    if seconds < 60 { return "刚刚" }
    if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
    if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
    return dateLabel(Day(at, in: timeZone), today: Day(now, in: timeZone)) + " "
}

/// The sign-out confirmation, worded by what would be lost.
struct SignOutConfirmation: Equatable {
    static let title = "退出登录？"
    static let action = "退出"
    var message: String

    init(pendingChanges: Int) {
        message = pendingChanges == 0
            ? "这台设备上的任务会被清除，重新登录后会从服务器同步回来。"
            : "还有 \(pendingChanges) 条改动没有同步到服务器，退出后会丢失。确定退出吗？"
    }
}

/// What the sign-in form sends.
struct SignInRequest: Equatable, Sendable {
    var email: String
    var password: String
    var server: String
    var register: Bool

    /// The message for a form that can't be sent yet, or nil.
    var problem: String? {
        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty ? "请填写邮箱和密码" : nil
    }

    var submitTitle: String { register ? "注册并登录" : "登录" }
}
