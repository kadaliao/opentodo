// 专注记录: every session by day, latest first; swipe to delete, + to add
// one by hand. And the focus settings.

import OpenTodoDomain
import SwiftUI
#if os(macOS)
import AppKit
#else
import AudioToolbox
#endif

struct FocusRecordsView: View {
    var sessions: [FocusSession]
    var tasks: [TodoTask]
    var today: Day
    var timeZone: TimeZone
    var onSaveSession: (FocusSession) -> Void
    var clock: () -> Int

    @State private var adding = false

    var body: some View {
        let days = focusRecordDays(sessions, in: timeZone)
        List {
            if days.isEmpty {
                ContentUnavailableView("还没有专注记录", systemImage: "timer", description: Text("开始一个番茄，或者点加号补记一条。"))
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.sessions) { s in
                        FocusSessionRow(session: s, taskTitle: tasks.first { $0.id == s.taskId }?.title, timeZone: timeZone)
                            .swipeActions {
                                Button("删除", systemImage: "trash", role: .destructive) { onSaveSession(deletedSession(s, now: clock())) }
                            }
                            .contextMenu {
                                Button("删除", systemImage: "trash", role: .destructive) { onSaveSession(deletedSession(s, now: clock())) }
                            }
                    }
                } header: {
                    HStack {
                        Text(group.day == today ? "今天" : dayText(group.day, today: today))
                        Spacer()
                        Text(durationText(group.sessions.reduce(0) { $0 + $1.duration }))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("专注记录")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("补记", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            FocusSessionEditor(tasks: tasks, today: today) { day, start, minutes, kind, taskId, note in
                onSaveSession(manualFocusSession(day: day, startMinute: start, minutes: minutes, kind: kind,
                                                 taskId: taskId, note: note, in: timeZone, now: clock()))
            }
        }
    }
}

/// 补记一条专注.
struct FocusSessionEditor: View {
    var tasks: [TodoTask]
    var today: Day
    var onSave: (Day, Int, Int, FocusKind, String?, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var day: Day
    @State private var start = 9 * 60
    @State private var minutes = 25
    @State private var kind = FocusKind.pomodoro
    @State private var taskId: String?
    @State private var note = ""

    init(tasks: [TodoTask], today: Day, onSave: @escaping (Day, Int, Int, FocusKind, String?, String) -> Void) {
        self.tasks = tasks
        self.today = today
        self.onSave = onSave
        _day = State(initialValue: today)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $kind) {
                        Text("番茄").tag(FocusKind.pomodoro)
                        Text("正计时").tag(FocusKind.stopwatch)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    DatePicker("日期", selection: $day.date, in: ...today.start(), displayedComponents: .date)
                    DatePicker("开始", selection: $start.timeOfDay, displayedComponents: .hourAndMinute)
                    Stepper(value: $minutes, in: 1...600, step: 5) {
                        LabeledContent("时长", value: durationText(minutes * 60))
                    }
                }
                Section {
                    Picker("任务", selection: $taskId) {
                        Text("不关联").tag(String?.none)
                        ForEach(tasks.filter { isOpen($0) && $0.deletedAt == nil }) { t in
                            Text(t.title).tag(Optional(t.id))
                        }
                    }
                    TextField("备注", text: $note, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("补记专注")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onSave(day, start, minutes, kind, taskId, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 420)
        #endif
    }
}

// MARK: - Settings

struct FocusSettingsView: View {
    var settings: FocusSettings
    var onChange: (FocusSettings) -> Void

    @State private var draft: FocusSettings

    init(settings: FocusSettings, onChange: @escaping (FocusSettings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        _draft = State(initialValue: settings)
    }

    var body: some View {
        Form {
            Section("时长") {
                Stepper(value: $draft.pomodoroMinutes, in: 5...120, step: 5) {
                    LabeledContent("番茄", value: "\(draft.pomodoroMinutes)分钟")
                }
                Stepper(value: $draft.shortBreakMinutes, in: 1...30) {
                    LabeledContent("短休息", value: "\(draft.shortBreakMinutes)分钟")
                }
                Stepper(value: $draft.longBreakMinutes, in: 5...60, step: 5) {
                    LabeledContent("长休息", value: "\(draft.longBreakMinutes)分钟")
                }
                Stepper(value: $draft.longBreakEvery, in: 2...8) {
                    LabeledContent("长休息间隔", value: "每\(draft.longBreakEvery)个番茄")
                }
            }
            Section {
                Toggle("自动开始下一个", isOn: $draft.autoStartNext)
                Toggle("结束提示音", isOn: $draft.endSound)
            } footer: {
                Text("自动开始：番茄结束后直接开始休息，休息结束后直接开始下一个番茄。不足\(focusMinimumSeconds / 60)分钟的专注不会记录。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("专注设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: draft) { _, new in onChange(new) }
    }
}

/// The sound when a pomodoro or a break ends.
func playFocusEndSound() {
    #if os(macOS)
    (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
    #else
    AudioServicesPlaySystemSound(1005)
    #endif
}
