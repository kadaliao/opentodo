// The sections of 设置, each a self-contained part of a `Form`: values in,
// changes out through a callback. `SettingsView` (OpenTodoSettingsView.swift)
// puts them on tabs (macOS) or in one grouped list (iOS) and binds them to
// `LocalSettings` and `ReminderController`.

import OpenTodoData
import OpenTodoDomain
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 系统通知 and 稍后提醒.
struct NotificationSettingsSection: View {
    static let snoozeHint = "通知上点“稍后提醒”，过多久再提醒"
    /// Nil while never asked; then whether notifications are allowed.
    let allowed: Bool?
    let snoozeMinutes: Int
    var onOpenSystemSettings: () -> Void
    var onSnoozeMinutes: (Int) -> Void

    var body: some View {
        let status = NotificationStatus(allowed: allowed)
        Section {
            LabeledContent {
                Button(status.button, action: onOpenSystemSettings)
                    #if os(iOS)
                    .buttonStyle(.borderless)
                    #endif
            } label: {
                Label {
                    Text("系统通知")
                    Text(status.text).foregroundStyle(status.warning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                } icon: {
                    Image(systemName: status.warning ? "bell.slash" : "bell.badge")
                        .foregroundStyle(status.warning ? .red : Palette.accent)
                }
            }
            Picker(selection: Binding(get: { snoozeMinutes }, set: { onSnoozeMinutes($0) })) {
                ForEach(SettingsOptions.including(SettingsOptions.snoozes, snoozeMinutes), id: \.self) { m in
                    Text("\(SettingsOptions.minutes(m))后").tag(m)
                }
            } label: {
                Label {
                    Text("稍后提醒")
                    #if os(macOS)
                    Text(Self.snoozeHint)
                    #endif
                } icon: {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Palette.accent)
                }
            }
        } header: {
            Group {
                Text("提醒与通知")
            }
            .uiDefaultFont(.headline)
        } footer: {
            Group {
                #if os(iOS)
                Text(Self.snoozeHint + "。")
                #endif
            }
            .uiDefaultFont(.subheadline)
        }
    }
}

/// 任务默认值: the reminders a task gets when it first has a date or a time,
/// and how long a new span lasts.
struct TaskDefaultsSection: View {
    let defaults: TaskDefaults
    var onChange: (TaskDefaults) -> Void

    var body: some View {
        Section {
            reminderPicker("有时间的任务", allDay: false, value: defaults.timedReminders) { d, r in d.timedReminders = r }
            reminderPicker("全天任务", allDay: true, value: defaults.allDayReminders) { d, r in d.allDayReminders = r }
        } header: {
            Group {
                Text("新任务的默认提醒")
            }
            .uiDefaultFont(.headline)
        } footer: {
            Group {
                Text("快速添加、日期对话框和在日历里拖动时，任务新有了日期或时间，就带上这里的提醒。")
            }
            .uiDefaultFont(.subheadline)
        }
        Section {
            Picker("时间段默认时长", selection: binding(\.spanMinutes)) {
                ForEach(SettingsOptions.including(SettingsOptions.spans, defaults.spanMinutes), id: \.self) { m in
                    Text(SettingsOptions.minutes(m)).tag(m)
                }
            }
        } footer: {
            Group {
                Text("设置只保存在这台设备上。")
            }
            .uiDefaultFont(.subheadline)
        }
    }

    private func reminderPicker(_ title: String, allDay: Bool, value: [Int], set: @escaping (inout TaskDefaults, [Int]) -> Void) -> some View {
        Picker(title, selection: Binding(get: { value }, set: { r in
            var d = defaults
            set(&d, r)
            onChange(d)
        })) {
            ForEach(SettingsOptions.including(SettingsOptions.reminderChoices(allDay: allDay), value), id: \.self) { r in
                Text(SettingsOptions.reminderLabel(r, allDay: allDay)).tag(r)
            }
        }
    }

    private func binding(_ key: WritableKeyPath<TaskDefaults, Int>) -> Binding<Int> {
        Binding(get: { defaults[keyPath: key] }, set: { v in
            var d = defaults
            d[keyPath: key] = v
            onChange(d)
        })
    }
}

/// 日历: what the calendar shows (the same switches as its 显示 menu).
struct CalendarDisplaySection: View {
    let prefs: CalendarPrefs
    var onChange: (CalendarPrefs) -> Void

    var body: some View {
        Section {
            Toggle("显示农历和节假日", isOn: binding(\.showLunar))
            Toggle("显示已完成", isOn: binding(\.showCompleted))
            Toggle("显示重复任务以后的日期", isOn: binding(\.showRepeats))
        } header: {
            Text("日历").uiDefaultFont(.headline)
        }
    }

    private func binding(_ key: WritableKeyPath<CalendarPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { prefs[keyPath: key] }, set: { v in
            var p = prefs
            p[keyPath: key] = v
            onChange(p)
        })
    }
}

/// 专注: the pomodoro and its breaks.
struct FocusSettingsSection: View {
    let settings: FocusSettings
    var onChange: (FocusSettings) -> Void

    var body: some View {
        Section {
            minutesPicker("番茄时长", \.pomodoroMinutes, SettingsOptions.pomodoros)
            minutesPicker("短休息", \.shortBreakMinutes, SettingsOptions.shortBreaks)
            minutesPicker("长休息", \.longBreakMinutes, SettingsOptions.longBreaks)
            Picker("长休息间隔", selection: binding(\.longBreakEvery)) {
                ForEach(SettingsOptions.including(SettingsOptions.longBreakEvery, settings.longBreakEvery), id: \.self) { n in
                    Text("每 \(n) 个番茄").tag(n)
                }
            }
            Toggle(isOn: Binding(get: { settings.autoStartNext }, set: { v in
                var s = settings
                s.autoStartNext = v
                onChange(s)
            })) {
                Text("自动开始下一段")
                Text("番茄结束后直接开始休息，休息结束后直接开始下一个番茄")
            }
        } header: {
            Group {
                Text("专注")
            }
            .uiDefaultFont(.headline)
        }
    }

    private func minutesPicker(_ title: String, _ key: WritableKeyPath<FocusSettings, Int>, _ options: [Int]) -> some View {
        Picker(title, selection: binding(key)) {
            ForEach(SettingsOptions.including(options, settings[keyPath: key]), id: \.self) { m in
                Text(SettingsOptions.minutes(m)).tag(m)
            }
        }
    }

    private func binding(_ key: WritableKeyPath<FocusSettings, Int>) -> Binding<Int> {
        Binding(get: { settings[keyPath: key] }, set: { v in
            var s = settings
            s[keyPath: key] = v
            onChange(s)
        })
    }
}

/// 关于: the version, the licence and where the code is.
struct AboutSection: View {
    let version: String
    /// Off where `AppBadge` already shows it.
    var showsVersion = true

    var body: some View {
        Section {
            if showsVersion { LabeledContent("版本", value: version) }
            LabeledContent("开源协议") {
                Link(AboutInfo.license, destination: URL(string: AboutInfo.licenseURL)!)
            }
            LabeledContent("源代码") {
                Link("github.com/kadaliao/opentodo", destination: URL(string: AboutInfo.repository)!)
            }
        } header: {
            Group {
                if showsVersion { Text("关于") }
            }
            .uiDefaultFont(.headline)
        } footer: {
            Group {
                Text("OpenTodo 是开源软件，按 GNU Affero 通用公共许可证第 3 版发布。")
            }
            .uiDefaultFont(.subheadline)
        }
    }
}

/// The app's icon and name, at the top of 关于 on macOS.
struct AppBadge: View {
    @Environment(\.uiScale) private var s
    let version: String

    var body: some View {
        VStack(spacing: 6 * s) {
            icon
            Text("OpenTodo").uiFont(.title3, weight: .semibold)
            Text("版本 \(version)").uiFont(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6 * s)
    }

    /// The app's own icon on macOS; a drawn stand-in elsewhere.
    @ViewBuilder private var icon: some View {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: 72 * s, height: 72 * s)
            .accessibilityHidden(true)
        #else
        Image(systemName: "checklist")
            .uiFont(size: 30, weight: .semibold)
            .foregroundStyle(.white)
            .frame(width: 64 * s, height: 64 * s)
            .background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
        #endif
    }
}
