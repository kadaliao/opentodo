// The date dialog's inner pages: the reminder list (with 自定义提醒), the
// repeat list (iOS; macOS uses a pop-up menu) and 自定义重复. Changes apply
// as they're made, the way pages pushed from a form do on Apple's
// platforms; the dialog's own 完成 / 取消 decides what's kept.

import OpenTodoDomain
import SwiftUI

// MARK: - Reminders

struct ReminderPickerView: View {
    @State private var choices: ReminderChoices
    @State private var custom: CustomReminder
    private let onChange: ([Int]) -> Void

    init(_ choices: ReminderChoices, onChange: @escaping ([Int]) -> Void) {
        _choices = State(initialValue: choices)
        _custom = State(initialValue: CustomReminder(allDay: choices.allDay))
        self.onChange = onChange
    }

    var body: some View {
        Form {
            Section {
                CheckRow("无", on: choices.selected.isEmpty) { choices.clear() }
                ForEach(choices.options, id: \.self) { o in
                    CheckRow(choices.label(o), on: choices.isOn(o)) { choices.toggle(o) }
                }
            } footer: {
                Text(choices.allDay ? "全天任务的提醒按当天 0 点算。可以选多个。" : "可以选多个。")
            }
            Section("自定义") {
                CustomReminderRows(custom: $custom)
                Button {
                    if let o = custom.offset { withAnimation { choices.add(o) } }
                } label: {
                    Label("添加“\(custom.label ?? "…")”", systemImage: "plus.circle.fill")
                }
                .disabled(custom.offset == nil)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("提醒")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        #endif
        .onChange(of: choices.reminders) { _, r in onChange(r) }
    }
}

private struct CustomReminderRows: View {
    @Binding var custom: CustomReminder

    private var minuteOfDay: Binding<Date> {
        Binding {
            LocalDateTime(Day(2000, 1, 1), minute: custom.minuteOfDay).date(in: .gmt)
        } set: {
            custom.minuteOfDay = LocalDateTime($0, in: .gmt).minuteOfDay
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("提前")
            TextField("数量", value: $custom.amount, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.center)
                .frame(width: 56)
                #if os(iOS)
                .keyboardType(.numberPad)
                .padding(.vertical, 4)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                #else
                .textFieldStyle(.roundedBorder)
                #endif
            Stepper("数量", value: $custom.amount, in: 0...999).labelsHidden()
            Spacer(minLength: 0)
            if custom.allDay {
                Text("天")
            } else {
                Picker("单位", selection: $custom.unit) {
                    ForEach(CustomReminder.Unit.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        if custom.allDay {
            DatePicker("时间", selection: minuteOfDay, displayedComponents: .hourAndMinute)
                .environment(\.timeZone, .gmt)
        }
    }
}

// MARK: - Repeat (iOS)

#if os(iOS)
struct RepeatPickerView: View {
    @Binding var editor: ScheduleEditor
    let done: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(editor.repeatPresets) { preset in
                    CheckRow(preset.title, on: editor.isChosen(preset)) {
                        editor.choose(preset)
                        done()
                    }
                }
            }
            Section {
                NavigationLink(value: SchedulePage.customRepeat) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义")
                            if editor.isCustomRepeat, let text = editor.repeatText {
                                Text(text).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if editor.isCustomRepeat {
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("重复")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

// MARK: - Custom repeat

struct CustomRepeatView: View {
    @State private var editor: CustomRepeatEditor
    private let onChange: (RepeatRule, RepeatFrom) -> Void

    init(_ editor: CustomRepeatEditor, onChange: @escaping (RepeatRule, RepeatFrom) -> Void) {
        _editor = State(initialValue: editor)
        self.onChange = onChange
    }

    private var untilRange: PartialRangeFrom<Date> { editor.date.start(in: .gmt)... }

    private var until: Binding<Date> {
        Binding { editor.until.start(in: .gmt) } set: { editor.until = Day($0, in: .gmt) }
    }

    private var monthDay: Binding<Int> {
        Binding { editor.monthDay } set: { editor.setMonthDay($0) }
    }

    private var nth: Binding<Int> {
        Binding { editor.nth } set: { editor.setNth($0) }
    }

    private var nthDay: Binding<Int> {
        Binding { editor.nthDay } set: { editor.setNthDay($0) }
    }

    private var lunar: Binding<Bool> {
        Binding { editor.lunar } set: { on in withAnimation(.snappy) { editor.setLunar(on) } }
    }

    private var freqUnit: String {
        CustomRepeatEditor.freqs.first { $0.0 == editor.freq }?.1 ?? ""
    }

    var body: some View {
        Form {
            Section {
                Picker("计算方式", selection: $editor.from.animation(.snappy)) {
                    Text("按到期日期").tag(RepeatFrom.dueDate)
                    Text("按完成日期").tag(RepeatFrom.completion)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                #if os(iOS)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                #endif
            }
            Section {
                Picker("频率", selection: $editor.freq.animation(.snappy)) {
                    Text("每天").tag(Freq.daily)
                    Text("每周").tag(Freq.weekly)
                    Text("每月").tag(Freq.monthly)
                    Text("每年").tag(Freq.yearly)
                }
                LabeledContent("间隔") {
                    HStack(spacing: 8) {
                        Text("每")
                        TextField("间隔", value: $editor.interval, format: .number)
                .labelsHidden()
                            .multilineTextAlignment(.center)
                            .frame(width: 48)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .padding(.vertical, 4)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            #else
                            .textFieldStyle(.roundedBorder)
                            #endif
                        Text(freqUnit).foregroundStyle(.primary)
                        Stepper("间隔", value: $editor.interval, in: 1...999).labelsHidden()
                    }
                }
                if editor.showsWeekdays {
                    WeekdayToggles(editor: $editor)
                    if editor.showsHolidays {
                        Toggle(isOn: $editor.holidays) {
                            Text("按法定节假日调休")
                            Text("放假跳过，调休上班照常")
                        }
                    }
                }
                if editor.showsLunar {
                    Toggle("按农历", isOn: lunar)
                }
                if editor.showsLunarMonthDay {
                    Picker("农历每月", selection: monthDay) {
                        ForEach(CustomRepeatEditor.lunarMonthDays, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                if editor.showsMonthly {
                    Picker("按", selection: $editor.byWeekday.animation(.snappy)) {
                        Text("按日期").tag(false)
                        Text("按星期").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if editor.byWeekday {
                        LabeledContent("每月") {
                            HStack(spacing: 2) {
                                Picker("第几个", selection: nth) {
                                    ForEach(CustomRepeatEditor.nths, id: \.0) { Text($0.1).tag($0.0) }
                                }
                                .labelsHidden().fixedSize()
                                Picker("周几", selection: nthDay) {
                                    ForEach(1...7, id: \.self) { Text("周\(CustomRepeatEditor.weekdayShort[$0 - 1])").tag($0) }
                                }
                                .labelsHidden().fixedSize()
                            }
                        }
                    } else {
                        Picker("每月", selection: monthDay) {
                            ForEach(CustomRepeatEditor.monthDays, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                }
            }
            Section {
                Picker("结束", selection: $editor.end.animation(.snappy)) {
                    ForEach(CustomRepeatEditor.End.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if editor.end == .until {
                    DatePicker("截止日期", selection: until, in: untilRange, displayedComponents: .date)
                        .environment(\.timeZone, .gmt)
                }
                if editor.end == .count {
                    LabeledContent("次数") {
                        HStack(spacing: 8) {
                            TextField("次数", value: $editor.count, format: .number)
                .labelsHidden()
                                .multilineTextAlignment(.center)
                                .frame(width: 48)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                .padding(.vertical, 4)
                                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                #else
                                .textFieldStyle(.roundedBorder)
                                #endif
                            Text("次").foregroundStyle(.primary)
                            Stepper("次数", value: $editor.count, in: 1...999).labelsHidden()
                        }
                    }
                }
            } footer: {
                Text(editor.summary)
                    .font(.callout)
                    .foregroundStyle(editor.rule == nil ? Color.red : Color.accentColor)
                    .contentTransition(.opacity)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("自定义重复")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        #endif
        .onAppear(perform: apply)
        .onChange(of: editor) { apply() }
    }

    /// Opening 自定义 already chooses it, as confirming the Dart dialog unchanged did.
    private func apply() {
        if let rule = editor.rule { onChange(rule, editor.from) }
    }
}

/// 一 … 日 as round toggles, at least one on.
private struct WeekdayToggles: View {
    @Binding var editor: CustomRepeatEditor

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...7, id: \.self) { wd in
                let on = editor.weekdays.contains(wd)
                Button {
                    editor.toggleWeekday(wd)
                } label: {
                    Text(CustomRepeatEditor.weekdayShort[wd - 1])
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(width: 34, height: 34)
                        .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary), in: Circle())
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("周\(CustomRepeatEditor.weekdayShort[wd - 1])")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}

/// A row with a checkmark when on, the whole row tappable.
struct CheckRow: View {
    let title: String
    let on: Bool
    let action: () -> Void

    init(_ title: String, on: Bool, action: @escaping () -> Void) {
        self.title = title
        self.on = on
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Color.primary)
                Spacer()
                if on {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
