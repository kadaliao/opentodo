// What 设置 and 账号 offer and say (Settings/SettingsOptions.swift,
// Account/AccountPresentation.swift).

import Foundation
import OpenTodoData
import Testing
@testable import OpenTodoUI

@Suite struct SettingsPresentationTests {
    @Test("choices and their labels, as the Flutter settings page")
    func options() {
        #expect(SettingsOptions.spans.map(SettingsOptions.minutes) == ["15分钟", "30分钟", "45分钟", "1小时", "1小时30分钟", "2小时", "3小时"])
        #expect(SettingsOptions.reminderChoices(allDay: false) == [[], [0], [-5], [-30], [-60], [-1440]])
        #expect(SettingsOptions.reminderChoices(allDay: true) == [[], [540], [-900], [-2340], [-9540]])
        #expect(SettingsOptions.reminderLabel([], allDay: false) == "无")
        #expect(SettingsOptions.reminderLabel([0], allDay: false) == "准时")
        #expect(SettingsOptions.reminderLabel([540], allDay: true) == "当天 09:00")
        // A value set elsewhere (or by a newer version) is shown and kept.
        #expect(SettingsOptions.including(SettingsOptions.snoozes, 7) == [5, 10, 15, 30, 60, 7])
        #expect(SettingsOptions.including(SettingsOptions.snoozes, 15) == SettingsOptions.snoozes)
        #expect(SettingsOptions.including(SettingsOptions.reminderChoices(allDay: false), [0, -30]).last == [0, -30])
    }

    @Test("the notification row: never asked, allowed, turned off")
    func notifications() {
        #expect(NotificationStatus(allowed: false) == NotificationStatus(text: "已关闭，提醒不会弹出", warning: true, button: "去开启"))
        #expect(NotificationStatus(allowed: true).button == "系统设置")
        #expect(!NotificationStatus(allowed: true).warning)
        #expect(NotificationStatus(allowed: nil).text.contains("第一次"))
    }

    @Test("the version line")
    func version() {
        #expect(AboutInfo.version(["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "7"]) == "0.1.0 (7)")
        #expect(AboutInfo.version(["CFBundleShortVersionString": "1", "CFBundleVersion": "1"]) == "1")
        #expect(AboutInfo.version(nil) == "—")
    }
}

@Suite struct AccountPresentationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("how long ago it synced")
    func ago() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        #expect(agoText(now - 20, now: now, timeZone: tz) == "刚刚")
        #expect(agoText(now - 300, now: now, timeZone: tz) == "5 分钟前")
        #expect(agoText(now - 3 * 3600, now: now, timeZone: tz) == "3 小时前")
        #expect(agoText(now - 26 * 3600, now: now, timeZone: tz) == "昨天 ")
    }

    @Test("the sync line for each phase")
    func line() {
        #expect(SyncLine(SyncStatus(.idle, lastSyncedAt: now - 300), now: now).text == "5 分钟前同步")
        #expect(SyncLine(SyncStatus(.idle), now: now).text == "已登录")
        #expect(SyncLine(SyncStatus(.syncing), now: now).text == "正在同步…")
        #expect(SyncLine(SyncStatus(.syncing), progress: SyncReport(pushed: 1, pulled: 40), now: now).text == "正在同步…已收到 40 条")
        let auth = SyncLine(SyncStatus(.error, error: SyncError("unauthorized", "登录已失效，请重新登录")), now: now)
        #expect(auth.error && auth.text == "登录已失效，请重新登录")
        #expect(SyncLine(SyncStatus(.error), now: now).text == "同步失败")
        #expect(SyncLine(SyncStatus(.signedOut), now: now).text == "未登录")
    }

    @Test("signing out says what would be lost")
    func signOut() {
        #expect(SignOutConfirmation(pendingChanges: 0).message == "这台设备上的任务会被清除，重新登录后会从服务器同步回来。")
        #expect(SignOutConfirmation(pendingChanges: 3).message == "还有 3 条改动没有同步到服务器，退出后会丢失。确定退出吗？")
    }

    @Test("the form needs an email and a password")
    func form() {
        var r = SignInRequest(email: "  ", password: "x", server: "", register: false)
        #expect(r.problem == "请填写邮箱和密码")
        r.email = "a@example.com"
        #expect(r.problem == nil)
        r.password = ""
        #expect(r.problem != nil)
        #expect(r.submitTitle == "登录")
        r.register = true
        #expect(r.submitTitle == "注册并登录")
    }
}
