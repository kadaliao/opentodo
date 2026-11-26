// `-OTOpen schedule:<state>` (debug builds): the date dialog straight away,
// in one of a few states, for screenshots.
//
//     schedule:none     a task without a date
//     schedule:timed    a time, two reminders and a weekly repeat
//     schedule:span     a span across midnight, with a reminder
//     schedule:custom   a custom repeat, its page open
//     schedule:denied   like timed, with notifications turned off
//     schedule:reminders  like timed, the reminder list open
//     schedule:repeats  like timed, the repeat list open
//     schedule:holiday  National Day 2026: festivals, 休 and 班 in the month

import Foundation
import OpenTodoDomain
import SwiftUI

enum ScheduleDebugState: String, CaseIterable {
    case none, timed, span, custom, denied, reminders, repeats, holiday

    func draft(today: Day) -> ScheduleDraft {
        switch self {
        case .none:
            ScheduleDraft(dueDate: nil)
        case .timed, .denied, .reminders, .repeats:
            ScheduleDraft(dueDate: today + 1, dueTime: 10 * 60 + 30, reminders: [-30, 0], repeatRule: .weekly)
        case .span:
            ScheduleDraft(dueDate: today, dueTime: 22 * 60, duration: 3 * 60 + 30, reminders: [0])
        case .holiday:
            ScheduleDraft(dueDate: Day(2026, 10, 1), reminders: [540], repeatRule: .yearly)
        case .custom:
            ScheduleDraft(dueDate: today, dueTime: 9 * 60, reminders: [0],
                          repeatRule: RepeatRule(.weekly, interval: 2, weekdays: [1, 3, 5], count: 10))
        }
    }

    var opening: [SchedulePage] {
        switch self {
        case .custom: [.repeats, .customRepeat]
        case .reminders: [.reminders]
        case .repeats: [.repeats]
        default: []
        }
    }
}

/// Presents the dialog for a `schedule:` route, pointing at the top right
/// of the window where a task's date button would be.
struct ScheduleDebugPresenter: ViewModifier {
    let route: DebugRoute?
    @State private var presented = false

    private var state: ScheduleDebugState? {
        if case .schedule(let s) = route { ScheduleDebugState(rawValue: s) } else { nil }
    }

    /// `-OTSnapshot` draws only the main window, not the popover's own:
    /// then the panel sits in the window, as the popover would show it.
    private var embedded: Bool {
        #if os(macOS)
        ProcessInfo.processInfo.arguments.contains("-OTSnapshot")
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        if let state, embedded {
            content.overlay(alignment: .topTrailing) {
                ScheduleEditorView(
                    state.draft(today: Day.today()), defaults: .standard, now: .now, timeZone: .current,
                    notificationsAllowed: state == .denied ? false : true, openNotificationSettings: {},
                    opening: state.opening, onCommit: { _ in }, onCancel: {}
                )
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                .padding(.top, 60)
                .padding(.trailing, 120)
            }
        } else if let state {
            content.overlay(alignment: .topTrailing) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .padding(.top, 60)
                    .padding(.trailing, 280)
                    .modifier(SchedulePresenter(
                        isPresented: $presented,
                        schedule: state.draft(today: Day.today()),
                        defaults: .standard,
                        notificationsAllowed: state == .denied ? false : true,
                        openNotificationSettings: {},
                        opening: state.opening,
                        onCommit: { print("schedule: \($0)") }
                    ))
                    .task {
                        try? await Task.sleep(for: .milliseconds(300))
                        presented = true
                    }
            }
        } else {
            content
        }
    }
}
