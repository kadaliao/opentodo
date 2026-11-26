// The date dialog (日期对话框): date or span (时间段), time, reminders and
// repeat, for one task or several. Spec: `app/lib/ui/schedule_dialog.dart`;
// the state and its rules are `ScheduleEditor`, this is only the view.
//
// iOS: a form in a navigation stack, meant for a sheet with detents (like
// Reminders' 详细信息 and Calendar's new event): 提醒 and 重复 push their
// lists, 自定义 pushes the custom repeat. macOS: a compact popover panel;
// 重复 is a pop-up menu, and 提醒 and 自定义重复 slide in as pages of the
// same panel with a back button, the way Calendar edits a repeat.
//
// Usage (see also `.scheduleEditor(isPresented:…)`):
//
//     ScheduleEditorView(ScheduleDraft(task: task), defaults: settings.defaults,
//                        notificationsAllowed: reminders.allowed) { draft in
//         repo.setSchedule(task.id, draft)      // draft.isCleared: 清除
//     } onCancel: { … }

import OpenTodoDomain
import SwiftUI

/// The pages inside the dialog.
enum SchedulePage: Hashable {
    case reminders, repeats, customRepeat
}

public struct ScheduleEditorView: View {
    @State private var editor: ScheduleEditor
    private let timeZone: TimeZone
    private let notificationsAllowed: Bool?
    private let openNotificationSettings: (() -> Void)?
    private let onCommit: (ScheduleDraft) -> Void
    private let onCancel: () -> Void
    #if os(iOS)
    @State private var path: [SchedulePage]
    #else
    @State private var page: SchedulePage?
    private let opening: [SchedulePage]
    #endif

    /// - Parameters:
    ///   - initial: the task's schedule now (`ScheduleDraft(task:)`), or an
    ///     empty one (`ScheduleDraft(dueDate: nil)`) for a task without a date.
    ///   - defaults: the person's `TaskDefaults` (settings).
    ///   - now: the current moment; the dialog reads today and the next hour from it.
    ///   - notificationsAllowed: false when the system has turned
    ///     notifications off: with reminders set, the dialog says so and
    ///     offers 去开启 (`openNotificationSettings`). Nil: not known yet.
    ///   - onCommit: 完成 / 确定 with the new schedule, or 清除 with
    ///     `ScheduleDraft.cleared`.
    ///   - onCancel: dismissed without a change.
    public init(
        _ initial: ScheduleDraft,
        defaults: TaskDefaults = .standard,
        now: Date = .now,
        timeZone: TimeZone = .current,
        notificationsAllowed: Bool? = nil,
        openNotificationSettings: (() -> Void)? = nil,
        onCommit: @escaping (ScheduleDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(initial, defaults: defaults, now: now, timeZone: timeZone,
                  notificationsAllowed: notificationsAllowed, openNotificationSettings: openNotificationSettings,
                  opening: [], onCommit: onCommit, onCancel: onCancel)
    }

    /// `opening`: pages to show straight away (debug routes).
    init(
        _ initial: ScheduleDraft,
        defaults: TaskDefaults,
        now: Date,
        timeZone: TimeZone,
        notificationsAllowed: Bool?,
        openNotificationSettings: (() -> Void)?,
        opening: [SchedulePage],
        onCommit: @escaping (ScheduleDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _editor = State(initialValue: ScheduleEditor(initial, defaults: defaults, now: LocalDateTime(now, in: timeZone)))
        self.timeZone = timeZone
        self.notificationsAllowed = notificationsAllowed
        self.openNotificationSettings = openNotificationSettings
        self.onCommit = onCommit
        self.onCancel = onCancel
        #if os(iOS)
        _path = State(initialValue: opening)
        #else
        self.opening = opening
        #endif
    }

    public var body: some View {
        content
            .environment(\.locale, Self.locale)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, timeZone)
    }

    static let locale = Locale(identifier: "zh_Hans_CN")

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Self.locale
        c.timeZone = timeZone
        c.firstWeekday = 2
        return c
    }

    // MARK: Bindings

    private func date(_ t: LocalDateTime) -> Date { t.date(in: timeZone) }
    private func local(_ d: Date) -> LocalDateTime { LocalDateTime(d, in: timeZone) }

    private var day: Binding<Day> {
        Binding { editor.date } set: { editor.setDate($0) }
    }

    private var isSpan: Binding<Bool> {
        Binding { editor.isSpan } set: { on in withAnimation(.snappy) { editor.setSpan(on) } }
    }

    private var hasTime: Binding<Bool> {
        Binding { editor.time != nil } set: { on in
            withAnimation(.snappy) { editor.setTime(on ? ScheduleEditor.defaultPickedTime : nil) }
        }
    }

    private var time: Binding<Date> {
        Binding { date(LocalDateTime(editor.date, minute: editor.time ?? ScheduleEditor.defaultPickedTime)) }
            set: { editor.setTime(local($0).minuteOfDay) }
    }

    private var start: Binding<Date> {
        Binding { date(LocalDateTime(editor.date, minute: editor.time ?? 0)) } set: {
            let t = local($0)
            editor.setStartDay(t.day)
            if !editor.isAllDay { editor.setStartTime(t.minuteOfDay) }
        }
    }

    private var end: Binding<Date> {
        Binding { date(editor.end) } set: {
            let t = local($0)
            editor.setEndDay(t.day)
            if !editor.isAllDay { editor.setEndTime(t.minuteOfDay) }
        }
    }

    private var spanAllDay: Binding<Bool> {
        Binding { editor.isAllDay } set: { on in withAnimation(.snappy) { editor.setSpanAllDay(on) } }
    }

    private var pickerRange: ClosedRange<Date> {
        date(LocalDateTime(Day(2000, 1, 1)))...date(LocalDateTime(Day(2100, 12, 31), minute: minutesPerDay - 1))
    }

    private func commit() {
        if let result = editor.result { onCommit(result) }
    }

    // MARK: Shared pieces

    private var modePicker: some View {
        Picker("类型", selection: isSpan) {
            Text("日期").tag(false)
            Text("时间段").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var quickDates: some View {
        HStack(spacing: 0) {
            ForEach(editor.quickDates) { q in
                let on = editor.date == q.day
                Button {
                    withAnimation(.snappy) { editor.setDate(q.day) }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: q.symbol)
                            .font(.system(size: 17))
                            .symbolVariant(on ? .fill : .none)
                            .frame(height: 22)
                        Text(q.title).font(.caption2)
                    }
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(q.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var monthCalendar: some View {
        MonthCalendar(selection: day, today: editor.today)
    }

    @ViewBuilder private var notificationWarning: some View {
        if !editor.reminders.isEmpty && notificationsAllowed == false {
            HStack(spacing: 8) {
                Image(systemName: "bell.slash.fill").foregroundStyle(.red)
                Text("系统通知已关闭，提醒不会弹出")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let openNotificationSettings {
                    Button("去开启", action: openNotificationSettings)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var spanError: some View {
        Text("结束要晚于开始").font(.footnote).foregroundStyle(.red)
    }

    private var spanComponents: DatePicker<Text>.Components {
        editor.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private var reminderChoices: ReminderChoices {
        ReminderChoices(allDay: editor.isAllDay, selected: editor.reminders)
    }

    private func setReminders(_ r: [Int]) { editor.setReminders(r) }

    private func setCustomRepeat(_ rule: RepeatRule, _ from: RepeatFrom) { editor.setCustomRepeat(rule, from: from) }
}

// MARK: - iOS

#if os(iOS)
extension ScheduleEditorView {
    private var content: some View {
        NavigationStack(path: $path) {
            Form {
                if editor.isSpan {
                    spanSection
                } else {
                    Section {
                        quickDates
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        monthCalendar
                            .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 8, trailing: 8))
                    }
                    Section {
                        HStack {
                            ScheduleRowLabel("时间", symbol: "clock.fill", tint: .blue)
                            Spacer()
                            if editor.time != nil {
                                DatePicker("时间", selection: time, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                            Toggle("时间", isOn: hasTime).labelsHidden()
                        }
                    }
                }
                Section {
                    NavigationLink(value: SchedulePage.reminders) {
                        LabeledContent {
                            Text(editor.remindersText ?? "无")
                                .lineLimit(2)
                        } label: {
                            ScheduleRowLabel("提醒", symbol: "bell.fill", tint: .orange)
                        }
                    }
                    notificationWarning
                    NavigationLink(value: SchedulePage.repeats) {
                        LabeledContent {
                            Text(editor.repeatText ?? "无")
                                .lineLimit(2)
                        } label: {
                            ScheduleRowLabel("重复", symbol: "repeat", tint: .gray)
                        }
                    }
                }
                Section {
                    Button("清除日期", role: .destructive) { onCommit(.cleared) }
                        .frame(maxWidth: .infinity)
                }
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .navigationTitle(editor.isSpan ? "时间段" : "日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close, action: onCancel)
                }
                ToolbarItem(placement: .principal) {
                    modePicker.frame(width: 180)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: commit)
                        .disabled(editor.result == nil)
                }
            }
            .navigationDestination(for: SchedulePage.self) { page in
                switch page {
                case .reminders:
                    ReminderPickerView(reminderChoices, onChange: setReminders)
                case .repeats:
                    RepeatPickerView(editor: $editor) { path.removeLast() }
                case .customRepeat:
                    CustomRepeatView(editor.customRepeatEditor, onChange: setCustomRepeat)
                }
            }
        }
    }

    @ViewBuilder private var spanSection: some View {
        Section {
            DatePicker(selection: start, in: pickerRange, displayedComponents: spanComponents) {
                ScheduleRowLabel("开始", symbol: "calendar", tint: .red)
            }
            DatePicker(selection: end, in: pickerRange, displayedComponents: spanComponents) {
                ScheduleRowLabel("结束", symbol: "calendar.badge.checkmark", tint: .red)
            }
            Toggle(isOn: spanAllDay) {
                ScheduleRowLabel("全天", symbol: "sun.max.fill", tint: .yellow)
            }
        } footer: {
            if !editor.isSpanValid { spanError }
        }
    }
}
#endif

// MARK: - macOS

#if os(macOS)
extension ScheduleEditorView {
    private var content: some View {
        ZStack(alignment: .top) {
            if let page {
                pageView(page)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                main
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 320)
        .clipped()
        .animation(.snappy(duration: 0.3), value: page)
        .task {
            guard let first = opening.last, first != .repeats else { return } // 重复 is a menu here
            try? await Task.sleep(for: .milliseconds(600))
            page = first
        }
    }

    private var main: some View {
        VStack(spacing: 0) {
            modePicker
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            if editor.isSpan {
                spanRows.padding(.horizontal, 14).padding(.vertical, 6)
            } else {
                quickDates.padding(.horizontal, 6)
                monthCalendar.padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
                Divider().padding(.horizontal, 14)
                MacRow(symbol: "clock", tint: editor.time != nil) {
                    Text("时间")
                } trailing: {
                    if editor.time != nil {
                        DatePicker("时间", selection: time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.stepperField)
                    }
                    Toggle("时间", isOn: hasTime).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
            }
            Divider().padding(.horizontal, 14)
            MacRow(symbol: "bell", tint: !editor.reminders.isEmpty) {
                Text("提醒")
            } trailing: {
                Button {
                    page = .reminders
                } label: {
                    HStack(spacing: 4) {
                        Text(editor.remindersText ?? "无").lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(editor.reminders.isEmpty ? Color.secondary : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            notificationWarning.padding(.horizontal, 14).padding(.bottom, 6)
            MacRow(symbol: "repeat", tint: editor.repeatRule != nil) {
                Text("重复")
            } trailing: {
                repeatMenu
            }
            Divider()
            HStack {
                Button("清除") { onCommit(.cleared) }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("确定", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(editor.result == nil)
            }
            .padding(12)
        }
    }

    /// A page pushed inside the panel: a back button to the dialog, the
    /// title, and the page; changes apply as they're made.
    private func pageView(_ p: SchedulePage) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Text(p == .reminders ? "提醒" : "自定义重复").font(.headline)
                HStack {
                    Button {
                        page = nil
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            Divider()
            switch p {
            case .reminders:
                ReminderPickerView(reminderChoices, onChange: setReminders)
            case .customRepeat, .repeats:
                CustomRepeatView(editor.customRepeatEditor, onChange: setCustomRepeat)
            }
        }
    }

    private var repeatMenu: some View {
        Menu {
            ForEach(editor.repeatPresets) { preset in
                Toggle(preset.title, isOn: Binding {
                    editor.isChosen(preset)
                } set: { _ in
                    editor.choose(preset)
                })
            }
            Divider()
            Toggle("自定义…", isOn: Binding { editor.isCustomRepeat } set: { _ in page = .customRepeat })
        } label: {
            Text(editor.repeatText ?? "不重复").lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .tint(editor.repeatRule == nil ? .secondary : .accentColor)
    }

    @ViewBuilder private var spanRows: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("开始").foregroundStyle(.secondary)
                DatePicker("开始", selection: start, in: pickerRange, displayedComponents: spanComponents)
                    .labelsHidden()
            }
            GridRow {
                Text("结束").foregroundStyle(.secondary)
                DatePicker("结束", selection: end, in: pickerRange, displayedComponents: spanComponents)
                    .labelsHidden()
            }
            GridRow {
                Text("全天").foregroundStyle(.secondary)
                Toggle("全天", isOn: spanAllDay).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if !editor.isSpanValid {
            spanError.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
        }
    }
}

/// A line of the macOS panel: icon and title on the left, the control on
/// the right.
private struct MacRow<Title: View, Trailing: View>: View {
    let symbol: String
    let tint: Bool
    @ViewBuilder let title: Title
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            title
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
    }
}
#endif

/// iOS: a title with a coloured symbol tile, as in Settings and Reminders.
struct ScheduleRowLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    init(_ title: String, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}
