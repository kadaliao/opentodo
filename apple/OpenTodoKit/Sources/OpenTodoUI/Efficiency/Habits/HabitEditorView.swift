// New or edited habit: name and icon, colour, goal, how often, part of the
// day, start date and reminders. A sheet with a grouped form.

import OpenTodoDomain
import SwiftUI

struct HabitEditorView: View {
    /// Nil for a new habit.
    var habit: Habit?
    var today: Day
    /// The draft and the habit it edits (nil: new).
    var onSave: (HabitDraft, Habit?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: HabitDraft
    @FocusState private var nameFocused: Bool

    init(habit: Habit?, today: Day, onSave: @escaping (HabitDraft, Habit?) -> Void) {
        self.habit = habit
        self.today = today
        self.onSave = onSave
        _draft = State(initialValue: habit.map(HabitDraft.init) ?? HabitDraft(today: today))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        EmojiPickerButton(emoji: $draft.emoji, color: draft.color, fallback: "leaf.fill")
                        TextField("习惯名称", text: $draft.name, prompt: Text("比如：每天喝水"))
                            .focused($nameFocused)
                            .font(.title3)
                    }
                    ColorDotsPicker(color: $draft.color)
                }

                Section("目标") {
                    Picker("目标", selection: $draft.goalKind) {
                        Text("打卡一次").tag(HabitGoalKind.once)
                        Text("计数").tag(HabitGoalKind.count)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if draft.goalKind == .count {
                        Stepper(value: $draft.goal, in: 1...9999, step: 1) {
                            LabeledContent("每天", value: "\(amountText(draft.goal))\(draft.unit)")
                        }
                        LabeledContent("单位") {
                            TextField("单位", text: $draft.unit, prompt: Text("杯、页、公里"))
                                .multilineTextAlignment(.trailing)
                        }
                        Stepper(value: $draft.step, in: 1...999, step: 1) {
                            LabeledContent("每次记", value: "\(amountText(draft.step))\(draft.unit)")
                        }
                    }
                }

                Section("频率") {
                    Picker("频率", selection: $draft.frequencyKind) {
                        ForEach(FrequencyKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    switch draft.frequencyKind {
                    case .daily:
                        EmptyView()
                    case .weekdays:
                        HabitWeekdayToggles(selection: $draft.weekdays)
                    case .timesPerWeek:
                        Stepper(value: $draft.timesPerWeek, in: 1...6) {
                            LabeledContent("每周", value: "\(draft.timesPerWeek)天")
                        }
                    }
                }

                Section {
                    Picker("时段", selection: $draft.section) {
                        ForEach(HabitSection.displayOrder, id: \.self) { Text($0.name).tag($0) }
                    }
                    DatePicker("开始日期", selection: $draft.startDate.date, displayedComponents: .date)
                }

                Section {
                    ForEach(draft.reminders.indices, id: \.self) { i in
                        HStack {
                            DatePicker("提醒 \(i + 1)", selection: reminder(i).timeOfDay, displayedComponents: .hourAndMinute)
                            Button("删除提醒", systemImage: "minus.circle.fill") {
                                draft.reminders.remove(at: i)
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("添加提醒", systemImage: "bell.badge") {
                        draft.reminders.append(draft.nextReminder)
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("在该打卡的日子按时提醒。")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(habit == nil ? "新建习惯" : "编辑习惯")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(draft, habit)
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                }
            }
            .onAppear { if habit == nil { nameFocused = true } }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 560)
        #endif
    }
}

extension HabitEditorView {
    /// The `i`th reminder, safe while one is being removed.
    fileprivate func reminder(_ i: Int) -> Binding<Int> {
        Binding(
            get: { i < draft.reminders.count ? draft.reminders[i] : 0 },
            set: { if i < draft.reminders.count { draft.reminders[i] = $0 } }
        )
    }
}

/// 一 二 三 四 五 六 日 as round toggles.
struct HabitWeekdayToggles: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { d in
                let on = selection.contains(d)
                Button {
                    if on { selection.remove(d) } else { selection.insert(d) }
                } label: {
                    Text(String(weekdayNames[d - 1].dropFirst()))
                        .font(.subheadline.weight(.medium))
                        .frame(width: 34, height: 34)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: .circle)
                        .foregroundStyle(on ? Color.white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(weekdayNames[d - 1]))
                .accessibilityAddTraits(on ? .isSelected : [])
                if d < 7 { Spacer(minLength: 0) }
            }
        }
        .padding(.vertical, 2)
    }
}
