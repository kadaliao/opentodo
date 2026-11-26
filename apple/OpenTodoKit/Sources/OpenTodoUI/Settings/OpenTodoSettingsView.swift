// 设置: on macOS the Settings window's tabs (通用 / 任务 / 通知 / 专注 / 账号 /
// 关于), on iOS one grouped list like the system Settings, the account at
// the top. Bound to the app's `LocalSettings`, `SyncController` and
// `ReminderController`:
//
//     Settings { OpenTodoSettingsView(settings: s.settings, sync: s.sync, reminders: s.reminders) }  // macOS
//     NavigationStack { OpenTodoSettingsView(…) }                                                     // iOS sheet
//
// Without a `sync` there is no 账号, without `reminders` the notification
// row reads "never asked".

import OpenTodoData
import OpenTodoDomain
import SwiftUI

public enum SettingsTab: String, CaseIterable, Hashable, Sendable {
    case general, tasks, notifications, focus, quickAdd, account, about
}

public struct OpenTodoSettingsView: View {
    let settings: LocalSettings
    let sync: SyncController?
    let reminders: ReminderController?
    @State private var tab: SettingsTab
    @State private var showingAccount: Bool
    /// macOS debug routes: just the pane of `tab`, without the tabs (a
    /// `TabView` in an ordinary window draws its tabs differently from the
    /// Settings window's).
    var paneOnly = false

    /// `tab`: the one to open on (macOS), or `.account` to open 账号 (iOS).
    public init(settings: LocalSettings, sync: SyncController?, reminders: ReminderController?, tab: SettingsTab = .general) {
        self.init(settings: settings, sync: sync, reminders: reminders, tab: tab, paneOnly: false)
    }

    init(settings: LocalSettings, sync: SyncController?, reminders: ReminderController?, tab: SettingsTab, paneOnly: Bool) {
        self.paneOnly = paneOnly
        self.settings = settings
        self.sync = sync
        self.reminders = reminders
        _tab = State(initialValue: tab)
        _showingAccount = State(initialValue: tab == .account)
    }

    private var version: String { AboutInfo.version(Bundle.main.infoDictionary) }

    public var body: some View {
        content
            .task { await reminders?.refreshPermission() }
    }

    #if os(macOS)
    @ViewBuilder private var content: some View {
        if paneOnly {
            pane(for: tab)
        } else {
            TabView(selection: $tab) {
                Tab("通用", systemImage: "gearshape", value: .general) { pane(for: .general) }
                Tab("任务", systemImage: "checklist", value: .tasks) { pane(for: .tasks) }
                Tab("通知", systemImage: "bell.badge", value: .notifications) { pane(for: .notifications) }
                Tab("专注", systemImage: "timer", value: .focus) { pane(for: .focus) }
                Tab("快速添加", systemImage: "keyboard", value: .quickAdd) { pane(for: .quickAdd) }
                if sync != nil {
                    Tab("账号", systemImage: "person.crop.circle", value: .account) { pane(for: .account) }
                }
                Tab("关于", systemImage: "info.circle", value: .about) { pane(for: .about) }
            }
        }
    }

    @ViewBuilder private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: pane { calendar }
        case .tasks: pane { defaultsSection }
        case .notifications: pane { notifications }
        case .focus: pane { focus }
        case .quickAdd: IntegrationSettingsPane().frame(width: 520)
        case .account:
            if let sync { AccountPane(sync: sync).frame(width: 520, height: 420) }
        case .about:
            pane {
                Section { AppBadge(version: version) }
                AboutSection(version: version, showsVersion: false)
            }
        }
    }

    private func pane<C: View>(@ViewBuilder _ sections: () -> C) -> some View {
        Form(content: sections)
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 520)
    }
    #else
    private var content: some View {
        Form {
            if let sync {
                Section {
                    NavigationLink {
                        AccountPane(sync: sync)
                    } label: {
                        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
                            AccountSettingsRow(account: sync.account, status: sync.status, progress: sync.progress, now: context.date)
                        }
                    }
                }
            }
            notifications
            defaultsSection
            calendar
            focus
            AboutSection(version: version)
        }
        .navigationDestination(isPresented: $showingAccount) {
            if let sync { AccountPane(sync: sync) }
        }
    }
    #endif

    private var notifications: some View {
        NotificationSettingsSection(
            allowed: reminders?.allowed,
            snoozeMinutes: settings.settings.snoozeMinutes,
            onOpenSystemSettings: { Task { await reminders?.openSettings() } },
            onSnoozeMinutes: { settings.setSnoozeMinutes($0) }
        )
    }

    private var defaultsSection: some View {
        TaskDefaultsSection(defaults: settings.settings.defaults) { settings.setDefaults($0) }
    }

    private var calendar: some View {
        CalendarDisplaySection(prefs: settings.calendarPrefs) { settings.setCalendarPrefs($0) }
    }

    private var focus: some View {
        FocusSettingsSection(settings: settings.focusSettings) { settings.setFocusSettings($0) }
    }
}
