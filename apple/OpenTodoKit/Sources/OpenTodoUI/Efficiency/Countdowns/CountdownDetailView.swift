// One countdown: the big number, its dates (lunar too), the age a birthday
// brings, the next few times it comes round, and its reminders. Plus the
// editor.

import OpenTodoDomain
import SwiftUI

struct CountdownDetailView: View {
    @Environment(\.uiScale) private var s
    var countdown: Countdown
    var today: Day
    var format: CountdownFormat
    var onEdit: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void

    @State private var shownFormat: CountdownFormat
    @State private var confirmingDelete = false

    init(countdown: Countdown, today: Day, format: CountdownFormat, onEdit: @escaping () -> Void,
         onPin: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.countdown = countdown
        self.today = today
        self.format = format
        self.onEdit = onEdit
        self.onPin = onPin
        self.onDelete = onDelete
        _shownFormat = State(initialValue: format)
    }

    private var tint: Color { EfficiencyPalette.color(countdown.color) }

    var body: some View {
        let c = countdown
        let t = countdownCardText(c, today: today, format: shownFormat)
        let status = countdownStatus(c, today: today)
        List {
            Section {
                VStack(spacing: 12 * s) {
                    EmojiBadge(emoji: c.emoji, color: c.color, fallback: countdownSymbol(c.kind), size: 56)
                    Text(c.title).uiFont(.title2) { $0.bold() }.multilineTextAlignment(.center)
                    Button {
                        shownFormat = nextFormat(shownFormat)
                    } label: {
                        VStack(spacing: 4 * s) {
                            if let caption = t.caption { Text(caption).uiFont(.subheadline).foregroundStyle(.secondary) }
                            BigNumberText(runs: t.runs, tint: tint, size: 64)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(Text("切换显示方式"))
                    Text(t.date).uiFont(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12 * s)
            }

            Section {
                LabeledContent("类型", value: c.kind.name)
                LabeledContent(c.kind == .anniversary || c.kind == .birthday ? "起始日" : "日期", value: countdownDateText(c, c.date, today: today))
                LabeledContent("重复", value: repeatText(c))
                if c.kind == .birthday, let s = status, let age = countdownAge(c, on: s.target), s.target != c.date {
                    LabeledContent(s.target == today ? "今天" : "下一个生日", value: "\(age)岁")
                }
                if c.kind == .anniversary, c.date <= today, let next = countdownOccurrences(c, from: today + 1, limit: 1).first, c.repeats != .none {
                    LabeledContent("下一个纪念日", value: "\(dayText(next, today: today))，还有\(today.days(to: next))天")
                }
                LabeledContent("显示在“今天”", value: c.showInToday ? "是" : "否")
            }

            let upcoming = c.repeats == .none ? [] : countdownOccurrences(c, from: today, limit: 4)
            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming, id: \.self) { d in
                        LabeledContent {
                            Text(d == today ? "今天" : "\(today.days(to: d))天后").monospacedDigit()
                        } label: {
                            Text(countdownDateText(c, d, today: today))
                        }
                    }
                } header: {
                    Text("接下来").uiDefaultFont(.headline)
                }
            }

            if !c.reminders.isEmpty {
                Section {
                    ForEach(c.reminders.sorted(by: >), id: \.self) { r in
                        Label(countdownReminderText(r), systemImage: "bell")
                    }
                } header: {
                    Text("提醒").uiDefaultFont(.headline)
                }
            }
        }
        .navigationTitle(c.kind.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .moreActions) {
                Button(c.pinnedAt == nil ? "置顶" : "取消置顶", systemImage: c.pinnedAt == nil ? "pin" : "pin.slash", action: onPin)
            }
            ToolbarItem(placement: .moreActions) {
                Button("删除", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("编辑", action: onEdit)
            }
        }
        .confirmationDialog("删除“\(c.title)”？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Editor

struct CountdownEditorView: View {
    @Environment(\.uiScale) private var s
    var countdown: Countdown?
    var today: Day
    var onSave: (CountdownDraft, Countdown?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CountdownDraft
    @FocusState private var titleFocused: Bool

    init(countdown: Countdown?, kind: CountdownKind, today: Day, onSave: @escaping (CountdownDraft, Countdown?) -> Void) {
        self.countdown = countdown
        self.today = today
        self.onSave = onSave
        _draft = State(initialValue: countdown.map(CountdownDraft.init) ?? CountdownDraft(kind: kind, today: today))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: Binding(get: { draft.kind }, set: { draft.setKind($0) })) {
                        ForEach([CountdownKind.anniversary, .countdown, .birthday, .holiday], id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    HStack(spacing: 12 * s) {
                        EmojiPickerButton(emoji: $draft.emoji, color: draft.color, fallback: countdownSymbol(draft.kind))
                        TextField("标题", text: $draft.title, prompt: Text(placeholder))
                            .focused($titleFocused)
                            .uiFont(.title3)
                    }
                    ColorDotsPicker(color: $draft.color)
                }

                Section {
                    DatePicker(draft.kind == .birthday ? "出生日期" : "日期", selection: $draft.date.date, displayedComponents: .date)
                    Toggle("按农历", isOn: $draft.lunar)
                    if draft.lunar {
                        LabeledContent("农历") {
                            if let l = toLunar(draft.date) {
                                Text(l.description)
                            } else {
                                Text("超出农历范围（1900–2100）").foregroundStyle(.red)
                            }
                        }
                    }
                    Picker("重复", selection: $draft.repeats) {
                        Text("不重复").tag(CountdownRepeat.none)
                        Text(draft.lunar ? "农历每年" : "每年").tag(CountdownRepeat.yearly)
                        Text(draft.lunar ? "农历每月" : "每月").tag(CountdownRepeat.monthly)
                    }
                }

                Section {
                    Toggle("显示在“今天”", isOn: $draft.showInToday)
                    Toggle("置顶", isOn: $draft.pinned)
                } footer: {
                    Group {
                        Text("到了那天，在“今天”里显示。")
                    }
                    .uiDefaultFont(.subheadline)
                }

                Section {
                    ForEach(draft.reminders.indices, id: \.self) { i in
                        reminderRow(i)
                    }
                    Button("添加提醒", systemImage: "bell.badge") {
                        draft.reminders.append(countdownReminder(daysBefore: draft.reminders.isEmpty ? 0 : 1, minute: 9 * 60))
                    }
                } header: {
                    Text("提醒").uiDefaultFont(.headline)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(countdown == nil ? "新建\(draft.kind.name)" : "编辑\(draft.kind.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(draft, countdown)
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                }
            }
            .onAppear { if countdown == nil { titleFocused = true } }
        }
        #if os(macOS)
        .frame(minWidth: 440 * s, idealWidth: 480 * s, minHeight: 560 * s)
        #endif
    }

    private var placeholder: String {
        switch draft.kind {
        case .countdown: "比如：考试"
        case .anniversary: "比如：在一起"
        case .birthday: "比如：妈妈的生日"
        case .holiday: "比如：春节"
        }
    }

    private func reminderRow(_ i: Int) -> some View {
        let offset = Binding<Int>(
            get: { i < draft.reminders.count ? draft.reminders[i] : 0 },
            set: { if i < draft.reminders.count { draft.reminders[i] = $0 } }
        )
        let days = Binding<Int>(
            get: { countdownReminderParts(offset.wrappedValue).daysBefore },
            set: { offset.wrappedValue = countdownReminder(daysBefore: $0, minute: countdownReminderParts(offset.wrappedValue).minute) }
        )
        let minute = Binding<Int>(
            get: { countdownReminderParts(offset.wrappedValue).minute },
            set: { offset.wrappedValue = countdownReminder(daysBefore: countdownReminderParts(offset.wrappedValue).daysBefore, minute: $0) }
        )
        return HStack {
            Stepper(value: days, in: 0...30) {
                Text(days.wrappedValue == 0 ? "当天" : "提前\(days.wrappedValue)天")
            }
            DatePicker("时间", selection: minute.timeOfDay, displayedComponents: .hourAndMinute)
                .labelsHidden()
            Button("删除提醒", systemImage: "minus.circle.fill") {
                if i < draft.reminders.count { draft.reminders.remove(at: i) }
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.red)
            .buttonStyle(.borderless)
        }
    }
}
