// Just a day: the date dialog's shortcuts and month, without time,
// reminders or repeat. For callers that change only the date and keep the
// rest — the batch actions' 选择日期… keeps each task's own time.
//
//     DayPickerView(initial: today, today: today) { day in … } onCancel: { … }

import OpenTodoDomain
import SwiftUI

public struct DayPickerView: View {
    @Environment(\.uiScale) private var s
    @State private var day: Day
    private let today: Day
    private let title: String
    private let onPick: (Day) -> Void
    private let onCancel: () -> Void

    public init(initial: Day, today: Day, title: String = "选择日期",
                onPick: @escaping (Day) -> Void, onCancel: @escaping () -> Void) {
        _day = State(initialValue: initial)
        self.today = today
        self.title = title
        self.onPick = onPick
        self.onCancel = onCancel
    }

    private var quick: some View {
        HStack(spacing: 0) {
            ForEach(QuickDate.all(today: today)) { q in
                let on = day == q.day
                Button {
                    withAnimation(.snappy) { day = q.day }
                } label: {
                    VStack(spacing: 3 * s) {
                        Image(systemName: q.symbol)
                            .uiFont(size: 17)
                            .symbolVariant(on ? .fill : .none)
                            .frame(height: 22 * s)
                        Text(q.title).uiFont(.caption2)
                    }
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44 * s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(q.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    public var body: some View {
        #if os(iOS)
        NavigationStack {
            Form {
                Section {
                    quick.listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    MonthCalendar(selection: $day, today: today)
                        .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 8, trailing: 8))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close, action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button(role: .confirm) { onPick(day) } }
            }
        }
        .environment(\.locale, ScheduleEditorView.locale)
        #else
        VStack(spacing: 0) {
            Text(title).uiFont(.headline).padding(.top, 12 * s).padding(.bottom, 4 * s)
            quick.padding(.horizontal, 6 * s)
            MonthCalendar(selection: $day, today: today)
                .padding(.horizontal, 10 * s).padding(.top, 4 * s).padding(.bottom, 8 * s)
            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("确定") { onPick(day) }.keyboardShortcut(.defaultAction)
            }
            .padding(12 * s)
        }
        .frame(width: 320 * s)
        .environment(\.locale, ScheduleEditorView.locale)
        #endif
    }
}
